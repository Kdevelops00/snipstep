import AppKit
import SnipstepCore

@main struct APISettingsCheck {
    @MainActor static func main() throws {
        let model = try AppModel(testing: true)
        precondition(model.mode == .ocrOnly && !model.keyConfigured)
        model.keyConfigured = true // Simulate presence without storing or reading any real key.
        model.setMode(.gemini)
        precondition(model.hasCloudConsent)
        let custom = CloudConnection(format: .chatCompletions, endpoint: "https://example.test/v1/chat/completions", model: "synthetic-model", sendsImage: false)
        try model.saveCloudConnection(custom)
        precondition(model.mode == .ocrOnly && !model.keyConfigured && !model.hasCloudConsent)
        precondition(!model.pipeline.cloudEnabled)
        model.keyConfigured = true
        model.setMode(.gemini)
        precondition(model.hasCloudConsent)
        let previous = model.cloudConnection
        do {
            try model.saveCloudConnection(.init(format: .chatCompletions, endpoint: "http://unsafe.test", model: "synthetic-model"))
            preconditionFailure("Invalid configuration accepted")
        } catch SnapError.invalidConnection { }
        precondition(model.cloudConnection == previous && model.hasCloudConsent)
        var changed = custom; changed.sendsImage = true
        try model.saveCloudConnection(changed)
        precondition(model.mode == .ocrOnly && !model.hasCloudConsent && !model.pipeline.cloudEnabled)
        print("PASS: settings isolate keys, bind consent to configuration, reject invalid changes and disable cloud on reconfiguration. No network requests or key writes.")
    }
}
