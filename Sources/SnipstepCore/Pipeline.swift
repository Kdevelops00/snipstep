import Foundation

@MainActor public final class CapturePipeline {
    private let store: TaskStore
    private let attachments: AttachmentStore
    private let ocr: any OCRRecognizing
    private var localEnricher: (any TaskEnriching)?
    private var enricher: any TaskEnriching
    private var credential: @MainActor () throws -> String
    private var queue: [UUID] = []
    private var worker: Task<Void, Never>?
    private var activeID: UUID?
    private var activeJob: Task<Void, Never>?
    private var activeCloud: Task<TaskSuggestion, Error>?
    private var consentGeneration = 0
    public private(set) var cloudEnabled = false
    public var onChange: @MainActor () -> Void = {}
    public var onError: @MainActor (SnapError) -> Void = { _ in }

    public init(store: TaskStore, attachments: AttachmentStore, ocr: any OCRRecognizing = VisionOCR(),
                enricher: any TaskEnriching = GeminiClient(), credential: @escaping @MainActor () throws -> String) {
        self.store = store; self.attachments = attachments; self.ocr = ocr; self.enricher = enricher; self.credential = credential
    }

    public func setCloudEnricher(_ provider: any TaskEnriching, credential: @escaping @MainActor () throws -> String) throws {
        setCloudEnabled(false)
        consentGeneration += 1
        activeCloud?.cancel()
        // Old queued captures must not be sent to a newly selected endpoint.
        for id in queue + (activeID.map { [$0] } ?? []) {
            if let task = try store.task(id), task.mode == .gemini { task.modeRaw = ProcessingMode.ocrOnly.rawValue }
        }
        try store.commit()
        enricher = provider
        self.credential = credential
    }

    public func setCloudEnabled(_ enabled: Bool) {
        if enabled && localEnricher != nil {
            localEnricher = nil
            consentGeneration += 1
            activeCloud?.cancel()
        }
        guard cloudEnabled != enabled else { return }
        cloudEnabled = enabled
        consentGeneration += 1
        if !enabled { activeCloud?.cancel() }
    }

    public func setLocalEnricher(_ provider: (any TaskEnriching)?) {
        if provider != nil { setCloudEnabled(false) }
        localEnricher = provider
        consentGeneration += 1
        activeCloud?.cancel()
    }

    @discardableResult public func ingest(_ data: Data, localOnly: Bool = false) async throws -> UUID {
        let generation = consentGeneration
        let mode: ProcessingMode = localEnricher != nil ? .localAI : cloudEnabled && !localOnly ? .gemini : .ocrOnly
        let manifest = try await attachments.save(data, mode: mode)
        try store.insertCapture(manifest)
        // A leftover journal is harmless: recovery checks the durable ID before inserting.
        do { try await attachments.finishCommit(manifest.id) } catch { onError(.storage) }
        if mode == .gemini && generation != consentGeneration {
            guard let task = try store.task(manifest.id) else { return manifest.id }
            task.modeRaw = ProcessingMode.ocrOnly.rawValue
            try store.commit()
        }
        enqueue(manifest.id)
        onChange()
        return manifest.id
    }

    public func recover() async throws {
        for task in try store.all(includeDeleted: true) where task.pendingDeletion {
            try await finishDeletion(task.id)
        }
        for manifest in try await attachments.recoverableCaptures() {
            _ = try store.insertCapture(manifest)
            try await attachments.finishCommit(manifest.id)
        }
        for task in try store.all() where task.attachmentExtension != nil {
            if task.processing == .enriching {
                // The previous request may already have reached the provider; never resend automatically after a crash.
                try store.fallback(task, error: .cancelled)
            } else if task.processing == .saved || task.processing == .recognizing {
                // No persisted destination binding exists on legacy pending captures; require explicit AI retry.
                if task.mode == .gemini { task.modeRaw = ProcessingMode.ocrOnly.rawValue; try store.commit() }
                enqueue(task.id)
            }
        }
        onChange()
    }

    public func retryAI(_ id: UUID) throws {
        guard cloudEnabled || localEnricher != nil else { throw SnapError.cloudDisabled }
        guard activeID != id, !queue.contains(id), let task = try store.task(id), task.attachmentExtension != nil else { return }
        guard task.ocr.state.isFinished else { enqueue(id); return }
        task.modeRaw = (localEnricher != nil ? ProcessingMode.localAI : .gemini).rawValue
        task.processingRaw = ProcessingState.saved.rawValue
        task.issue = nil
        try store.commit()
        enqueue(id)
        onChange()
    }

    public func delete(_ id: UUID) async throws {
        guard let task = try store.task(id, includeDeleted: true) else { return }
        task.pendingDeletion = true
        try store.commit()
        queue.removeAll { $0 == id }
        if activeID == id { activeJob?.cancel(); activeCloud?.cancel() }
        onChange()
        try await finishDeletion(id)
        onChange()
    }

    private func finishDeletion(_ id: UUID) async throws {
        try await attachments.remove(id)
        if let task = try store.task(id, includeDeleted: true) {
            store.context.delete(task)
            try store.commit()
        }
    }

    public func waitUntilIdle() async { await worker?.value }

    private func enqueue(_ id: UUID) {
        guard activeID != id, !queue.contains(id) else { return }
        queue.append(id)
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !queue.isEmpty {
                let id = queue.removeFirst()
                activeID = id
                let job = Task { await self.process(id) }
                activeJob = job
                await job.value
                activeID = nil; activeJob = nil; activeCloud = nil
            }
            worker = nil
        }
    }

    private func process(_ id: UUID) async {
        do {
            guard let initial = try store.task(id), let ext = initial.attachmentExtension else { return }
            if !initial.ocr.state.isFinished {
                initial.processingRaw = ProcessingState.recognizing.rawValue
                initial.ocrStateRaw = OCRState.running.rawValue
                try store.commit(); onChange()
                let result: OCRResult
                do {
                    let original = try await attachments.originalURL(id: id, fileExtension: ext)
                    result = try await ocr.recognize(url: original)
                } catch is CancellationError { return }
                catch { result = OCRResult(state: .failed) }
                try Task.checkCancellation()
                guard let task = try store.task(id) else { return }
                try store.applyOCR(result, to: task)
                onChange()
            }
            guard let task = try store.task(id) else { return }
            guard task.mode != .ocrOnly else {
                task.processingRaw = ProcessingState.ready.rawValue
                try store.commit(); onChange(); return
            }
            let local = task.mode == .localAI
            guard let provider: any TaskEnriching = local ? localEnricher : (cloudEnabled ? enricher : nil) else {
                try store.fallback(task, error: .cancelled); onChange(); return
            }
            let generation = consentGeneration
            let cachedOCR = task.ocr
            let key = local ? "" : try credential()
            let image = !local && provider.needsImage ? try await attachments.cloudImage(id: id, fileExtension: ext) : Data()
            try Task.checkCancellation()
            guard let current = try store.task(id) else { return }
            guard generation == consentGeneration else {
                try store.fallback(current, error: .cancelled); onChange(); return
            }
            current.processingRaw = ProcessingState.enriching.rawValue
            try store.commit(); onChange()
            let request = Task { try await provider.enrich(image: image, ocr: cachedOCR, apiKey: key) }
            activeCloud = request
            let suggestion = try await withTaskCancellationHandler {
                try await request.value
            } onCancel: { request.cancel() }
            try Task.checkCancellation()
            guard let current = try store.task(id) else { return }
            guard generation == consentGeneration else {
                try store.fallback(current, error: .cancelled); onChange(); return
            }
            try store.applySuggestion(suggestion, to: current)
            onChange()
        } catch {
            do {
                guard let task = try store.task(id) else { return }
                let safe = (error as? SnapError) ?? (error is CancellationError ? .cancelled : task.mode == .localAI ? .localUnavailable : .unavailable)
                try store.fallback(task, error: safe)
                onChange()
            } catch { onError(.storage) }
        }
    }
}
