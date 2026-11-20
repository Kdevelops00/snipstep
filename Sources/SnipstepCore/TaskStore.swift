import Foundation
import SwiftData

@MainActor public final class TaskStore {
    public let container: ModelContainer
    public let context: ModelContext

    public init(url: URL? = nil, inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: SnapSchemaV1.self)
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, migrationPlan: SnapMigrationPlan.self, configurations: [config])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    public func all(includeDeleted: Bool = false) throws -> [SavedTask] {
        let result = try context.fetch(FetchDescriptor<SavedTask>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        return includeDeleted ? result : result.filter { !$0.pendingDeletion }
    }

    public func task(_ id: UUID, includeDeleted: Bool = false) throws -> SavedTask? {
        let identifier = id
        var request = FetchDescriptor<SavedTask>(predicate: #Predicate { $0.id == identifier })
        request.fetchLimit = 1
        let task = try context.fetch(request).first
        return (includeDeleted || task?.pendingDeletion == false) ? task : nil
    }

    public func commit() throws {
        do { try context.save() }
        catch { context.rollback(); throw SnapError.storage }
    }

    @discardableResult public func addManual(title: String) throws -> SavedTask {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 160 else { throw SnapError.invalidTitle }
        let task = SavedTask(title: title)
        context.insert(task)
        try commit()
        return task
    }

    @discardableResult public func insertCapture(_ manifest: CaptureManifest) throws -> SavedTask {
        if let existing = try task(manifest.id, includeDeleted: true) { return existing }
        let task = SavedTask(id: manifest.id, createdAt: manifest.createdAt,
                             attachmentExtension: manifest.fileExtension, mode: manifest.mode)
        context.insert(task)
        try commit()
        return task
    }

    public func edit(_ task: SavedTask, title: String, details: String) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, cleanTitle.count <= 160 else { throw SnapError.invalidTitle }
        for (field, changed) in [(TaskField.title, task.title != cleanTitle), (.details, task.details != details)] where changed {
            task.editedFields |= field.rawValue
        }
        task.title = cleanTitle; task.details = String(details.prefix(10_000))
        try commit()
    }

    public func toggleCompleted(_ task: SavedTask) throws {
        task.completedAt = task.completedAt == nil ? .now : nil
        try commit()
    }
    public func toggleArchived(_ task: SavedTask) throws {
        task.archivedAt = task.archivedAt == nil ? .now : nil
        try commit()
    }

    public func applyOCR(_ result: OCRResult, to task: SavedTask) throws {
        task.ocrStateRaw = result.state.rawValue; task.ocrText = result.text
        if !task.isEdited(.title) { task.title = result.title }
        if !task.isEdited(.details) { task.details = String(result.text.prefix(4_000)) }
        task.origin = result.text.isEmpty ? "Original screenshot" : "On-device OCR"
        task.processingRaw = ProcessingState.ready.rawValue
        try commit()
    }

    public func applySuggestion(_ suggestion: TaskSuggestion, to task: SavedTask) throws {
        try suggestion.validate()
        if !task.isEdited(.title) { task.title = suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !task.isEdited(.details) { task.details = suggestion.description }
        task.origin = task.mode == .localAI ? "AI suggestion · Local" : "AI suggestion · LLM API"; task.processingRaw = ProcessingState.ready.rawValue; task.issue = nil
        try commit()
    }

    public func fallback(_ task: SavedTask, error: SnapError) throws {
        task.processingRaw = ProcessingState.fallback.rawValue
        task.issue = error.localizedDescription
        try commit()
    }
}
