import AppIntents
import UniformTypeIdentifiers
import SnipstepCore

struct SaveScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Screenshot to Snipstep"
    static let description = IntentDescription("Save an image as a checklist item and automatically read and summarize it using your selected processing mode.")
    static let openAppWhenRun = false

    @Parameter(title: "Screenshot", supportedContentTypes: [.png, .jpeg, .heic])
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary { Summary("Save \(\.$screenshot) to Snipstep") }

    @MainActor func perform() async throws -> some IntentResult {
        guard let model = AppModel.shared else { throw SnapError.storage }
        // Save before any processing; waiting keeps the background intent alive through enrichment.
        model.start()
        await model.waitForStartup()
        _ = try await model.pipeline.ingest(screenshot.data)
        model.screenshotSaved()
        await model.pipeline.waitUntilIdle()
        return .result()
    }
}
