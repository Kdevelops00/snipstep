import Foundation
import SwiftData

public enum ProcessingMode: String, Codable, Sendable, CaseIterable {
    case ocrOnly, gemini, localAI
    public var label: String { switch self { case .ocrOnly: "Text only"; case .gemini: "LLM API"; case .localAI: "Local AI" } }
}

public enum OCRState: String, Codable, Sendable {
    case notStarted, running, recognized, empty, failed
    public var isFinished: Bool { self == .recognized || self == .empty || self == .failed }
}

public enum ProcessingState: String, Codable, Sendable {
    case saved, recognizing, enriching, ready, fallback
    public var label: String {
        switch self {
        case .saved: "Saved · Waiting"
        case .recognizing: "Reading text locally"
        case .enriching: "Creating summary"
        case .ready: "Ready"
        case .fallback: "Saved locally"
        }
    }
}

public enum TaskField: Int, Sendable {
    case title = 1, details = 2
}

public enum SnapError: Error, Equatable, Sendable, LocalizedError {
    case invalidImage, imageTooLarge, storage, invalidTitle, keyUnavailable, invalidCredentialFile
    case invalidConnection, invalidModelFile
    case serviceBusy, modelUnavailable, localUnavailable, localNoText
    case cloudDisabled, requestTooLarge, responseTooLarge, authentication, quota, unavailable, invalidResponse, cancelled
    public var errorDescription: String? {
        switch self {
        case .invalidImage: "Choose a single PNG, JPEG, or HEIC image."
        case .imageTooLarge: "This image exceeds the 100 MB or 50 megapixel local limit."
        case .storage: "The library could not be saved. Your existing data has not been reset. Check available disk space and try again."
        case .invalidTitle: "Enter a title between 1 and 160 characters."
        case .keyUnavailable: "The API key is missing or Keychain is unavailable. Your task remains saved locally."
        case .invalidCredentialFile: "The selected file or folder must contain exactly one nonempty Gemi_APi_key= entry."
        case .invalidConnection: "Enter a valid HTTPS API endpoint and model ID. No credentials, query parameters, or fragments are allowed in the endpoint."
        case .invalidModelFile: "Choose a single GGUF model file under 4 GB. On this Mac, start with a small Q4 model. Your original file has not been changed."
        case .localUnavailable: "The local model could not finish. Open Ollama and check the selected model. Your screenshot is saved; nothing was sent to a cloud API."
        case .localNoText: "No readable text was found. This local mode summarizes extracted text; the original screenshot is still saved."
        case .cloudDisabled: "Enable LLM API processing in Settings before requesting cloud processing."
        case .requestTooLarge: "This image and text exceed the cloud request limit. The original and local task are preserved."
        case .responseTooLarge, .invalidResponse: "The AI returned an unusable response. The local task is preserved."
        case .authentication: "The LLM API rejected the API key. Update it in Settings to retry."
        case .quota: "The LLM API quota or rate limit was reached. You can retry later."
        case .serviceBusy: "The LLM API is temporarily busy (503). Your screenshot is saved. Try Summarize again shortly."
        case .modelUnavailable: "This API model is unavailable (404). Your screenshot is saved. Check the model ID in API settings."
        case .unavailable: "The LLM API could not finish the request. You can retry later."
        case .cancelled: "AI processing was stopped. The local task is preserved."
        }
    }
}

public struct OCRResult: Sendable, Codable, Equatable {
    public var state: OCRState
    public var text: String
    public init(state: OCRState, text: String = "") {
        self.state = state
        self.text = text
    }
    public var title: String {
        let first = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return first.map { String($0.prefix(160)) } ?? "Explore screenshot"
    }
}

public struct TaskSuggestion: Codable, Sendable, Equatable {
    public let title: String
    public let description: String
    public init(title: String, description: String) {
        self.title = title; self.description = description
    }
    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 160, description.count <= 4_000,
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw SnapError.invalidResponse }
    }
}

public enum SnapSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    public static var models: [any PersistentModel.Type] { [SavedTask.self] }

    @Model public final class SavedTask {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var details: String
        // Retain unused early-development columns so existing local libraries still open.
        var category: String
        var link: String?
        public var createdAt: Date
        public var completedAt: Date?
        public var archivedAt: Date?
        public var attachmentExtension: String?
        public var processingRaw: String
        public var modeRaw: String
        public var ocrStateRaw: String
        public var ocrText: String
        var ocrURLs: [String]
        public var editedFields: Int
        public var origin: String
        public var issue: String?
        public var pendingDeletion: Bool

        public init(id: UUID = UUID(), title: String = "Explore screenshot", createdAt: Date = .now,
                    attachmentExtension: String? = nil, mode: ProcessingMode = .ocrOnly) {
            self.id = id; self.title = title; self.createdAt = createdAt
            self.details = ""; self.category = "Idea"
            self.attachmentExtension = attachmentExtension; self.modeRaw = mode.rawValue
            self.processingRaw = attachmentExtension == nil ? ProcessingState.ready.rawValue : ProcessingState.saved.rawValue
            self.ocrStateRaw = OCRState.notStarted.rawValue; self.ocrText = ""; self.ocrURLs = []
            self.editedFields = attachmentExtension == nil ? TaskField.title.rawValue : 0
            self.origin = attachmentExtension == nil ? "Manual" : "Original screenshot"
            self.pendingDeletion = false
        }
        public var mode: ProcessingMode { ProcessingMode(rawValue: modeRaw) ?? .ocrOnly }
        public var processing: ProcessingState { ProcessingState(rawValue: processingRaw) ?? .ready }
        public var ocr: OCRResult { .init(state: OCRState(rawValue: ocrStateRaw) ?? .notStarted, text: ocrText) }
        public var isCompleted: Bool { completedAt != nil }
        public var isArchived: Bool { archivedAt != nil }
        public func isEdited(_ field: TaskField) -> Bool { editedFields & field.rawValue != 0 }
    }
}

public typealias SavedTask = SnapSchemaV1.SavedTask

public enum SnapMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SnapSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
