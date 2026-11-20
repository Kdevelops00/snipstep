import AppKit
import Observation
import SnipstepCore
import WidgetKit
import UserNotifications
import UniformTypeIdentifiers

@MainActor @Observable final class AppModel {
    static let shared: AppModel? = try? AppModel()
    let store: TaskStore
    let attachments: AttachmentStore
    let pipeline: CapturePipeline
    var credentials: KeychainCredentialStore
    var cloudConnection: CloudConnection
    let preferences: UserDefaults
    let isTesting: Bool
    var tasks: [SavedTask] = []
    var selectedID: UUID?
    var requestedDetailID: UUID?
    var requestedNewTask = false
    var errorMessage: String?
    var mode: ProcessingMode
    var keyConfigured: Bool
    var localModelName = ""
    var localModels: [LocalAIClient.InstalledModel] = []
    var localStatus: String?
    var widgetSyncStatus = "Open the app to sync widgets."
    var loadingLocalModels = false
    var importingLocalModel = false
    var localModelSource: String?
    var isCapturing = false
    var captureShortcutAvailable = false
    var shortcutLabel = "⌃⌥X"
    var settingsRequested = false
    var settingsPage = "Basics"
    var notificationsEnabled = false
    @ObservationIgnored private var widgetDeletions = Set<UUID>()
    var isImporting = false
    var lastSaveMessage: String?
    var feedbackID = UUID()
    @ObservationIgnored var openLibrary: () -> Void = {}
    @ObservationIgnored private var started = false
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private let widgetStore: WidgetStore?
    @ObservationIgnored private var widgetPublish: Task<Void, Never>?
    @ObservationIgnored private let thumbnails = NSCache<NSString, NSImage>()
    @ObservationIgnored private lazy var captureController = CaptureController()
    @ObservationIgnored private let captureHotKey = CaptureHotKey()

    init(testing: Bool = false) throws {
        isTesting = testing
        widgetStore = testing ? nil : WidgetStore.configured()
        let root: URL
        if testing {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("SnipstepUITests-" + UUID().uuidString)
            preferences = UserDefaults(suiteName: "SnipstepUITests-" + UUID().uuidString)!
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SnapLater", isDirectory: true)
            preferences = .standard
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        store = try TaskStore(url: testing ? nil : root.appendingPathComponent("Library.store"), inMemory: testing)
        attachments = try AttachmentStore(root: root.appendingPathComponent("Attachments", isDirectory: true))
        let savedData = preferences.data(forKey: "cloudConnection")
        let savedConnection = savedData.flatMap { try? JSONDecoder().decode(CloudConnection.self, from: $0) }
        let validConnection = savedConnection.flatMap { value in (try? value.validate()).map { value } }
        let connection = validConnection ?? .google
        let configurationValid = savedData == nil || validConnection != nil
        cloudConnection = connection
        if !configurationValid {
            preferences.removeObject(forKey: "cloudConsentBinding")
            preferences.set(0, forKey: "cloudConsentVersion")
        }
        let keychain = KeychainCredentialStore(service: testing ? "org.snaplater.uitests." + UUID().uuidString : connection.credentialService)
        credentials = keychain
        if !testing && savedData == nil && preferences.integer(forKey: "cloudConsentVersion") == 1 {
            preferences.set(connection.consentBinding, forKey: "cloudConsentBinding")
        }
        pipeline = CapturePipeline(store: store, attachments: attachments, enricher: CloudAPIClient(connection: connection), credential: { try keychain.read() })
        let hasKey = !testing && (try? keychain.read()) != nil
        keyConfigured = hasKey
        let savedLocalModel = preferences.string(forKey: "localModelName") ?? ""
        localModelSource = preferences.string(forKey: "localModelSource")
        localModelName = savedLocalModel
        mode = preferences.string(forKey: "processingMode") == ProcessingMode.localAI.rawValue && !savedLocalModel.isEmpty ? .localAI : configurationValid && hasKey && preferences.string(forKey: "cloudConsentBinding") == connection.consentBinding && preferences.string(forKey: "processingMode") == ProcessingMode.gemini.rawValue
            ? .gemini : .ocrOnly
        notificationsEnabled = preferences.bool(forKey: "captureNotifications")
        thumbnails.totalCostLimit = 32 * 1_024 * 1_024
        pipeline.setCloudEnabled(mode == .gemini && !testing)
        if mode == .localAI && !testing { pipeline.setLocalEnricher(LocalAIClient(model: localModelName)) }
        pipeline.onChange = { [weak self] in self?.reload() }
        pipeline.onError = { [weak self] error in self?.report(error) }
    }

    func start() {
        guard !started else { return }
        started = true
        startup = Task {
            do { try await pipeline.recover(); reload() }
            catch { report(.storage) }
        }
        if !isTesting {
            shortcutLabel = preferences.string(forKey: "captureShortcutLabel") ?? "⌃⌥X"
            captureShortcutAvailable = captureHotKey.register(
                keyCode: UInt32(exactly: preferences.object(forKey: "captureKeyCode") as? Int ?? 7) ?? 7,
                modifiers: UInt32(exactly: preferences.object(forKey: "captureModifiers") as? Int ?? 6144) ?? 6144)
        }
    }

    func waitForStartup() async { await startup?.value }

    func reload() {
        do {
            if let widgetStore {
                for command in try widgetStore.commands() {
                    if command.deleted == true {
                        if widgetDeletions.insert(command.id).inserted {
                            Task {
                                defer { widgetDeletions.remove(command.id) }
                                do {
                                    try await pipeline.delete(command.id)
                                    try widgetStore.acknowledge(command)
                                    reload()
                                } catch { report(.storage) }
                            }
                        }
                        continue
                    }
                    if let task = try store.task(command.id) {
                        if command.completed && task.completedAt == nil { task.completedAt = command.createdAt ?? .now }
                        if !command.completed { task.completedAt = nil }
                        try store.commit()
                    }
                    try widgetStore.acknowledge(command)
                }
            }
            tasks = try store.all()
            publishWidgets()
        }
        catch { report(.storage) }
    }
    private func publishWidgets() {
        guard let widgetStore else { widgetSyncStatus = "Widget connection unavailable. Reopen the installed Snipstep app."; return }
        widgetPublish?.cancel()
        let values = tasks.filter { !$0.isArchived }
        let completed = values.filter(\.isCompleted).count
        let now = Date()
        let ordered = values.sorted { left, right in
            let leftRecent = left.completedAt.map { now.timeIntervalSince($0) < 2 } ?? false
            let rightRecent = right.completedAt.map { now.timeIntervalSince($0) < 2 } ?? false
            if leftRecent != rightRecent { return leftRecent }
            return !left.isCompleted && right.isCompleted
        }
        let rows = Array(ordered.prefix(12)).map {
            (id: $0.id, title: $0.title, summary: String($0.details.prefix(300)), completed: $0.isCompleted, completedAt: $0.completedAt, ext: $0.attachmentExtension)
        }
        widgetPublish = Task {
            var items: [WidgetTask] = []
            for row in rows {
                let thumbnail: Data?
                if let ext = row.ext { thumbnail = try? await attachments.widgetPreview(id: row.id, fileExtension: ext) }
                else { thumbnail = nil }
                if Task.isCancelled { return }
                items.append(.init(id: row.id, title: row.title, summary: row.summary, completed: row.completed, thumbnail: thumbnail, completedAt: row.completedAt))
            }
            do {
                try widgetStore.write(.init(tasks: items, completed: completed, remaining: values.count - completed))
                widgetSyncStatus = "Synced · \(values.count - completed) unfinished tasks"
                WidgetCenter.shared.reloadAllTimelines()
            } catch { widgetSyncStatus = "Widget sync failed. Your library remains saved."; report(.storage) }
        }
    }
    func report(_ error: SnapError) { errorMessage = error.localizedDescription }
    func perform(_ action: () throws -> Void) {
        do { try action(); reload() }
        catch { report((error as? SnapError) ?? .storage) }
    }
    var remaining: [SavedTask] { tasks.filter { !$0.isArchived && !$0.isCompleted } }
    var completedCount: Int { tasks.filter { !$0.isArchived && $0.isCompleted }.count }

    func addManual(_ title: String) {
        perform { selectedID = try store.addManual(title: title).id }
    }
    func complete(_ task: SavedTask) { perform { try store.toggleCompleted(task) } }
    func archive(_ task: SavedTask) { perform { try store.toggleArchived(task) } }
    func delete(_ task: SavedTask) {
        let id = task.id
        Task {
            do {
                try await pipeline.delete(id)
                thumbnails.removeObject(forKey: id.uuidString as NSString)
                if selectedID == id { selectedID = nil }
                reload()
            } catch { report(.storage) }
        }
    }
    func retry(_ task: SavedTask) { perform { try pipeline.retryAI(task.id) } }

    func capture(localOnly: Bool = false) {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let data = try await captureController.capture()
                let id = try await pipeline.ingest(data, localOnly: localOnly)
                selectedID = id
                screenshotSaved()
            } catch let error as CaptureFailure {
                errorMessage = error.message
            } catch { report((error as? SnapError) ?? .storage) }
        }
    }

    func screenshotSaved() {
        feedbackID = UUID()
        lastSaveMessage = "Screenshot saved"
        // Confirm the durable save, not merely a keypress or completed AI request.
        NSSound(named: NSSound.Name("Glass"))?.play()
        if notificationsEnabled {
            let content = UNMutableNotificationContent()
            content.title = "Screenshot saved"
            content.body = "Open Snipstep to see your task."
            Task {
                try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }

    func importImage() {
        guard !isImporting else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.message = "Snipstep keeps a private copy. Your original file is unchanged."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= ImageFiles.maximumBytes else {
                        throw SnapError.imageTooLarge
                    }
                    return try Data(contentsOf: url, options: .mappedIfSafe)
                }.value
                selectedID = try await pipeline.ingest(data)
                lastSaveMessage = "Image saved"
            } catch { report((error as? SnapError) ?? .invalidImage) }
        }
    }

    func setNotifications(_ enabled: Bool) {
        if !enabled {
            notificationsEnabled = false
            preferences.set(false, forKey: "captureNotifications")
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        Task {
            let allowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
            notificationsEnabled = allowed
            preferences.set(allowed, forKey: "captureNotifications")
            if !allowed { errorMessage = "Notifications are off in macOS. You can enable Snipstep in System Settings → Notifications. The capture sound still works." }
        }
    }

    func changeShortcut(keyCode: UInt32, modifiers: UInt32, label: String) {
        guard captureHotKey.register(keyCode: keyCode, modifiers: modifiers) else {
            errorMessage = "Those keys are already in use. Your previous shortcut is still active. Choose another combination."
            return
        }
        captureShortcutAvailable = true
        shortcutLabel = label
        preferences.set(Int(keyCode), forKey: "captureKeyCode")
        preferences.set(Int(modifiers), forKey: "captureModifiers")
        preferences.set(label, forKey: "captureShortcutLabel")
        feedbackID = UUID()
        lastSaveMessage = "Shortcut updated to " + label
    }

    func loadLocalModelFile() {
        guard !importingLocalModel else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a small GGUF text model (under 4 GB). Ollama keeps a runtime copy; your original file stays where it is."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importingLocalModel = true
        localStatus = "Importing into Ollama… This may take a few minutes."
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; importingLocalModel = false }
            do {
                let name = try await LocalAIClient(model: "").importGGUF(from: url)
                try await LocalAIClient(model: name).verifyModel()
                localModelName = name
                localModelSource = url.path
                preferences.set(name, forKey: "localModelName")
                preferences.set(url.path, forKey: "localModelSource")
                setMode(.localAI)
                localStatus = "Model ready. The source file is unchanged. Ollama stores the runtime copy."
                refreshLocalModels()
            } catch { localStatus = (error as? SnapError)?.localizedDescription ?? "Ollama couldn’t import this model. Check that Ollama is running and supports this GGUF architecture. The source is unchanged." }
        }
    }

    func refreshLocalModels() {
        guard !loadingLocalModels else { return }
        loadingLocalModels = true
        Task {
            defer { loadingLocalModels = false }
            do {
                localModels = try await LocalAIClient(model: "").installedModels()
                localStatus = localModels.isEmpty ? "No installed local models. Add one in Ollama, then refresh." : "Choose a model. It loads only when needed and unloads after each summary."
            } catch { localStatus = "Open Ollama on this Mac, then click Refresh. No model will be downloaded automatically." }
        }
    }
    func useLocalModel(_ name: String) {
        Task {
            do {
                try await LocalAIClient(model: name).verifyModel()
                localModelName = name
                preferences.set(name, forKey: "localModelName")
                setMode(.localAI)
                localStatus = "Local AI selected. Screenshots and text are not sent to a cloud API."
            } catch { localStatus = SnapError.localUnavailable.localizedDescription }
        }
    }

    var hasCloudConsent: Bool { preferences.string(forKey: "cloudConsentBinding") == cloudConnection.consentBinding }

    func saveCloudConnection(_ value: CloudConnection) throws {
        try value.validate()
        let encoded = try JSONEncoder().encode(value)
        guard value != cloudConnection else { return }
        setMode(.ocrOnly)
        let keychain = KeychainCredentialStore(service: isTesting ? "org.snaplater.uitests." + UUID().uuidString : value.credentialService)
        try pipeline.setCloudEnricher(CloudAPIClient(connection: value), credential: { try keychain.read() })
        cloudConnection = value
        credentials = keychain
        preferences.set(encoded, forKey: "cloudConnection")
        preferences.removeObject(forKey: "cloudConsentBinding")
        preferences.set(0, forKey: "cloudConsentVersion")
        keyConfigured = !isTesting && (try? credentials.read()) != nil
    }

    func setMode(_ value: ProcessingMode) {
        guard value != .gemini || keyConfigured else { return }
        guard value != .localAI || !localModelName.isEmpty else { return }
        pipeline.setLocalEnricher(nil)
        mode = value
        preferences.set(value.rawValue, forKey: "processingMode")
        if value == .gemini {
            preferences.set(1, forKey: "cloudConsentVersion")
            preferences.set(cloudConnection.consentBinding, forKey: "cloudConsentBinding")
        }
        pipeline.setCloudEnabled(value == .gemini && !isTesting)
        if value == .localAI && !isTesting { pipeline.setLocalEnricher(LocalAIClient(model: localModelName)) }
    }

    func saveKey(_ value: String) throws {
        try credentials.save(value)
        keyConfigured = true
        preferences.set(true, forKey: "geminiKeyConfigured")
    }
    func removeKey() throws {
        if mode == .gemini { setMode(.ocrOnly) }
        try credentials.remove()
        keyConfigured = false
        preferences.set(false, forKey: "geminiKeyConfigured")
    }

    #if DEBUG
    func importDevelopmentKey() throws -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Read only the exact Gemi_APi_key= entry into Keychain. The source is never changed."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard cloudConnection.format == .gemini else { throw SnapError.invalidConnection }
        try saveKey(DevelopmentCredential.read(from: url))
        return true
    }
    #endif

    func thumbnail(for task: SavedTask) async -> NSImage? {
        let key = task.id.uuidString as NSString
        if let image = thumbnails.object(forKey: key) { return image }
        guard let ext = task.attachmentExtension,
              let data = try? await attachments.preview(id: task.id, fileExtension: ext, pixels: 320),
              let image = NSImage(data: data), !task.pendingDeletion else { return nil }
        thumbnails.setObject(image, forKey: key, cost: 320 * 320 * 4)
        return image
    }

    func reveal(_ id: UUID) {
        selectedID = id
        openLibrary()
        NSApp.activate(ignoringOtherApps: true)
    }

    #if DEBUG
    func addSyntheticCapture() {
        guard isTesting else { return }
        let image = NSImage(size: NSSize(width: 800, height: 300))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 800, height: 300).fill()
        ("Explore Swift\nhttps://swift.org/documentation" as NSString).draw(at: NSPoint(x: 40, y: 130),
            withAttributes: [.font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black])
        image.unlockFocus()
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let data = try? ImageFiles.png(cg) else { return }
        Task {
            do { selectedID = try await pipeline.ingest(data, localOnly: true) }
            catch { report(.storage) }
        }
    }
    #endif
}
