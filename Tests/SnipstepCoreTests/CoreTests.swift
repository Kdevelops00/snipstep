import Foundation
import Testing
import CoreGraphics
@testable import SnipstepCore

func testImage() throws -> Data {
    let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
    return try ImageFiles.png(context.makeImage()!)
}

actor StubOCR: OCRRecognizing {
    var calls = 0
    let result: OCRResult
    let shouldFail: Bool
    init(result: OCRResult = .init(state: .recognized, text: "Read Swift documentation\nhttps://swift.org"), shouldFail: Bool = false) {
        self.result = result; self.shouldFail = shouldFail
    }
    func recognize(url: URL) async throws -> OCRResult {
        calls += 1
        if shouldFail { throw SnapError.invalidImage }
        return result
    }
}

actor StubAI: TaskEnriching {
    var calls = 0
    var receivedImage = false
    var failure: SnapError?
    var continuation: CheckedContinuation<TaskSuggestion, Error>?
    let deferred: Bool
    let needsImage: Bool
    init(failure: SnapError? = nil, deferred: Bool = false, needsImage: Bool = true) {
        self.failure = failure; self.deferred = deferred; self.needsImage = needsImage
    }
    func enrich(image: Data, ocr: OCRResult, apiKey: String) async throws -> TaskSuggestion {
        calls += 1
        receivedImage = !image.isEmpty
        if let failure { throw failure }
        if deferred { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return suggestion
    }
    var suggestion: TaskSuggestion { .init(title: "Explore Swift", description: "Read the language guide.") }
    func succeed() { failure = nil }
    func release() { continuation?.resume(returning: suggestion); continuation = nil }
    func waitForRequest() async throws {
        for _ in 0..<500 {
            if continuation != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SnapError.unavailable
    }
}

@MainActor struct Harness {
    let root: URL
    let store: TaskStore
    let attachments: AttachmentStore
    let pipeline: CapturePipeline
    init(ocr: any OCRRecognizing = StubOCR(), ai: any TaskEnriching = StubAI(), persistent: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SnipstepTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try TaskStore(url: persistent ? root.appendingPathComponent("Library.store") : nil, inMemory: !persistent)
        attachments = try AttachmentStore(root: root.appendingPathComponent("Attachments"))
        pipeline = CapturePipeline(store: store, attachments: attachments, ocr: ocr, enricher: ai, credential: { "synthetic-test-credential" })
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

@Test @MainActor func fallbackAndRetryUseOneOCRAndOneTask() async throws {
    let ocr = StubOCR(), ai = StubAI(failure: .quota)
    let h = try Harness(ocr: ocr, ai: ai); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    let id = try await h.pipeline.ingest(testImage())
    await h.pipeline.waitUntilIdle()
    #expect(try h.store.task(id)?.processing == .fallback)
    #expect(await ocr.calls == 1)
    await ai.succeed()
    try h.pipeline.retryAI(id)
    try h.pipeline.retryAI(id)
    await h.pipeline.waitUntilIdle()
    #expect(await ocr.calls == 1)
    #expect(await ai.calls == 2)
    #expect(try h.store.all().count == 1)
    #expect(try h.store.task(id)?.title == "Explore Swift")
}

@Test @MainActor func failedOCRStillCreatesGenericTaskAndCachesFailure() async throws {
    let ocr = StubOCR(shouldFail: true), ai = StubAI(failure: .unavailable)
    let h = try Harness(ocr: ocr, ai: ai); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    let id = try await h.pipeline.ingest(testImage())
    await h.pipeline.waitUntilIdle()
    #expect(try h.store.task(id)?.title == "Explore screenshot")
    #expect(try h.store.task(id)?.ocr.state == .failed)
    try h.pipeline.retryAI(id)
    await h.pipeline.waitUntilIdle()
    #expect(await ocr.calls == 1)
}

@Test @MainActor func localOnlyNeverUsesCloud() async throws {
    let ai = StubAI()
    let h = try Harness(ai: ai); defer { h.cleanup() }
    _ = try await h.pipeline.ingest(testImage())
    await h.pipeline.waitUntilIdle()
    h.pipeline.setCloudEnabled(true)
    _ = try await h.pipeline.ingest(testImage(), localOnly: true)
    await h.pipeline.waitUntilIdle()
    #expect(await ai.calls == 0)
    #expect(try h.store.all().allSatisfy { $0.processing == .ready })
}

@Test @MainActor func delayedEnrichmentPreservesEditsAndLifecycle() async throws {
    let ai = StubAI(deferred: true)
    let h = try Harness(ai: ai); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    let id = try await h.pipeline.ingest(testImage())
    try await ai.waitForRequest()
    let task = try #require(try h.store.task(id))
    try h.store.edit(task, title: "My own title", details: "My notes")
    try h.store.toggleCompleted(task)
    try h.store.toggleArchived(task)
    await ai.release()
    await h.pipeline.waitUntilIdle()
    #expect(task.title == "My own title")
    #expect(task.details == "My notes")
    #expect(task.isCompleted && task.isArchived)
    try h.store.toggleArchived(task)
    #expect(task.isCompleted && !task.isArchived)
}

@Test @MainActor func deleteDuringEnrichmentCannotResurrectTask() async throws {
    let ai = StubAI(deferred: true)
    let h = try Harness(ai: ai); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    let id = try await h.pipeline.ingest(testImage())
    try await ai.waitForRequest()
    try await h.pipeline.delete(id)
    await ai.release()
    await h.pipeline.waitUntilIdle()
    #expect(try h.store.all(includeDeleted: true).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: h.attachments.root.appendingPathComponent(id.uuidString).path))
}

@Test @MainActor func revokingConsentIgnoresLateResponse() async throws {
    let ai = StubAI(deferred: true)
    let h = try Harness(ai: ai); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    let id = try await h.pipeline.ingest(testImage())
    try await ai.waitForRequest()
    h.pipeline.setCloudEnabled(false)
    await ai.release()
    await h.pipeline.waitUntilIdle()
    let task = try #require(try h.store.task(id))
    #expect(task.origin == "On-device OCR")
    #expect(task.processing == .fallback)
}

@Test @MainActor func journalRecoversMissingRecordWithoutDuplicates() async throws {
    let h = try Harness(); defer { h.cleanup() }
    let manifest = try await h.attachments.save(testImage(), mode: .ocrOnly)
    #expect(try h.store.all().isEmpty)
    try await h.pipeline.recover()
    await h.pipeline.waitUntilIdle()
    try await h.pipeline.recover()
    #expect(try h.store.all().count == 1)
    #expect(try h.store.task(manifest.id)?.ocr.state == .recognized)
    #expect(try await h.attachments.recoverableCaptures().isEmpty)
}

@Test @MainActor func persistentTaskSurvivesNewStore() throws {
    let h = try Harness(persistent: true); defer { h.cleanup() }
    let task = try h.store.addManual(title: "Read this later")
    try h.store.toggleCompleted(task)
    let reopened = try TaskStore(url: h.root.appendingPathComponent("Library.store"))
    #expect(try reopened.task(task.id)?.isCompleted == true)
}

@Test func rejectsUntrustedAIFields() throws {
    #expect(throws: SnapError.invalidResponse) { try TaskSuggestion(title: "", description: "").validate() }
    #expect(throws: SnapError.invalidResponse) { try TaskSuggestion(title: "Read", description: String(repeating: "x", count: 4_001)).validate() }
    #expect(throws: SnapError.invalidResponse) { try TaskSuggestion(title: "Read\nsecret", description: "").validate() }
    let result = #"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"{\"title\":\"Read Swift\",\"description\":\"\"}"}]}}]}"#
    #expect(try GeminiClient.decode(Data(result.utf8)).title == "Read Swift")
    #expect(throws: SnapError.invalidResponse) { try GeminiClient.decode(Data("{}".utf8)) }
    #expect(throws: SnapError.invalidResponse) { try GeminiClient.decode(Data(result.replacingOccurrences(of: "STOP", with: "MAX_TOKENS").utf8)) }
}

@Test func cloudRequestHasSafeEndpointHeaderAndBothInputs() throws {
    let request = try GeminiClient.request(image: testImage(), ocr: .init(state: .recognized, text: "Synthetic OCR"), apiKey: "test-placeholder")
    #expect(request.url?.host == "generativelanguage.googleapis.com")
    #expect(request.url?.query == nil)
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-placeholder")
    let body = try #require(request.httpBody)
    let string = try #require(String(data: body, encoding: .utf8))
    #expect(string.contains("Synthetic OCR") && string.contains("inlineData"))
    #expect(!string.contains("test-placeholder"))
    #expect(throws: SnapError.requestTooLarge) {
        try GeminiClient.request(image: Data(count: GeminiClient.maximumRequestBytes), ocr: .init(state: .empty), apiKey: "test-placeholder")
    }
}

@Test func rejectsInvalidImageWithoutCreatingAttachment() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let attachments = try AttachmentStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }
    await #expect(throws: SnapError.invalidImage) { try await attachments.save(Data("not an image".utf8), mode: .ocrOnly) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@Test @MainActor func changingCloudConnectionDisablesUploadsAndIgnoresOldResult() async throws {
    let old = StubAI(deferred: true), replacement = StubAI()
    let h = try Harness(ai: old); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    let id = try await h.pipeline.ingest(testImage())
    try await old.waitForRequest()
    try h.pipeline.setCloudEnricher(replacement, credential: { "replacement-placeholder" })
    #expect(!h.pipeline.cloudEnabled)
    await old.release()
    await h.pipeline.waitUntilIdle()
    #expect(try h.store.task(id)?.origin == "On-device OCR")
    #expect(await replacement.calls == 0)
    h.pipeline.setCloudEnabled(true)
    try h.pipeline.retryAI(id)
    await h.pipeline.waitUntilIdle()
    #expect(await replacement.calls == 1)
    #expect(try h.store.all().count == 1)
}


@Test @MainActor func queuedCapturesNeverMoveToNewEndpointAutomatically() async throws {
    let old = StubAI(deferred: true), replacement = StubAI()
    let h = try Harness(ai: old); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    _ = try await h.pipeline.ingest(testImage())
    try await old.waitForRequest()
    let queued = try await h.pipeline.ingest(testImage())
    try h.pipeline.setCloudEnricher(replacement, credential: { "replacement-placeholder" })
    h.pipeline.setCloudEnabled(true)
    await old.release()
    await h.pipeline.waitUntilIdle()
    #expect(await replacement.calls == 0)
    #expect(try h.store.task(queued)?.mode == .ocrOnly)
    try h.pipeline.retryAI(queued)
    await h.pipeline.waitUntilIdle()
    #expect(await replacement.calls == 1)
}


@Test @MainActor func recoveredPendingCaptureDoesNotUploadToCurrentConnection() async throws {
    let ai = StubAI()
    let h = try Harness(ai: ai); defer { h.cleanup() }
    _ = try await h.attachments.save(testImage(), mode: .gemini)
    h.pipeline.setCloudEnabled(true)
    try await h.pipeline.recover()
    await h.pipeline.waitUntilIdle()
    #expect(await ai.calls == 0)
    let task = try #require(h.store.all().first)
    #expect(task.mode == .ocrOnly && task.ocr.state.isFinished)
    try h.pipeline.retryAI(task.id)
    await h.pipeline.waitUntilIdle()
    #expect(await ai.calls == 1)
}

@Test @MainActor func changingConnectionDuringSaveNotificationKeepsCaptureLocal() async throws {
    let replacement = StubAI()
    let h = try Harness(); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    var changed = false
    h.pipeline.onChange = {
        guard !changed else { return }
        changed = true
        do {
            try h.pipeline.setCloudEnricher(replacement, credential: { "replacement-placeholder" })
            h.pipeline.setCloudEnabled(true)
        } catch { Issue.record(error) }
    }
    defer { h.pipeline.onChange = {} }
    let id = try await h.pipeline.ingest(testImage())
    await h.pipeline.waitUntilIdle()
    #expect(changed)
    #expect(try h.store.task(id)?.mode == .ocrOnly)
    #expect(await replacement.calls == 0)
}

@Test @MainActor func textOnlyRetryUsesCachedOCRWithoutOpeningOriginal() async throws {
    let ai = StubAI(needsImage: false)
    let h = try Harness(ai: ai); defer { h.cleanup() }
    let id = try await h.pipeline.ingest(testImage())
    await h.pipeline.waitUntilIdle()
    try await h.attachments.remove(id)
    h.pipeline.setCloudEnabled(true)
    try h.pipeline.retryAI(id)
    await h.pipeline.waitUntilIdle()
    #expect(await ai.calls == 1)
    #expect(await !ai.receivedImage)
    #expect(try h.store.task(id)?.title == "Explore Swift")
}
