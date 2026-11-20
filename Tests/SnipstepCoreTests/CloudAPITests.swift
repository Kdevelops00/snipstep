import Foundation
import Testing
@testable import SnipstepCore

@Test func cloudConnectionRejectsUnsafeDestinationsAndBindsConsent() throws {
    let base = CloudConnection(format: .chatCompletions, endpoint: "https://example.test/v1/chat/completions", model: "vision-model")
    try base.validate()
    #expect(base.credentialService != CloudConnection.google.credentialService)
    for endpoint in ["http://example.test/v1/chat/completions", "https://key@example.test/v1", "https://example.test/v1?key=value", "https://example.test/v1#secret", "https://example.test/\n"] {
        var value = base; value.endpoint = endpoint
        #expect(throws: SnapError.invalidConnection) { try value.validate() }
    }
    var changed = base; changed.endpoint = "https://other.test/v1/chat/completions"
    #expect(changed.credentialService != base.credentialService)
    #expect(changed.consentBinding != base.consentBinding)
    changed = base; changed.sendsImage = false
    #expect(changed.credentialService == base.credentialService)
    #expect(changed.consentBinding != base.consentBinding)
    changed = base; changed.model = "other-model"
    #expect(changed.consentBinding != base.consentBinding)
    var google = CloudConnection.google; google.endpoint = "https://unrelated.test/v1"
    #expect(throws: SnapError.invalidConnection) { try google.validate() }
}

@Test func compatibleRequestsRespectPayloadChoiceAndKeepKeyInHeader() throws {
    var connection = CloudConnection(format: .chatCompletions, endpoint: "https://example.test/v1/chat/completions", model: "test-model")
    let image = Data("synthetic-image".utf8)
    for sendImage in [false, true] {
        connection.sendsImage = sendImage
        let request = try CloudAPIClient.request(connection: connection, image: image, ocr: .init(state: .recognized, text: "Fictional reference"), apiKey: "placeholder-only")
        #expect(request.url?.absoluteString == connection.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer placeholder-only")
        let root = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let messages = try #require(root["messages"] as? [[String: Any]])
        let parts = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(parts.contains { $0["type"] as? String == "image_url" } == sendImage)
        #expect(!String(data: request.httpBody!, encoding: .utf8)!.contains("placeholder-only"))
    }
    connection = .google; connection.sendsImage = false
    let request = try CloudAPIClient.request(connection: connection, image: image, ocr: .init(state: .recognized, text: "Text only"), apiKey: "placeholder-only")
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "placeholder-only")
    #expect(!String(data: request.httpBody!, encoding: .utf8)!.contains("inlineData"))
}

@Test func compatibleResponsesRequireCompleteValidatedTaskJSON() throws {
    func response(finish: String = "stop", content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": content]]]])
    }
    let valid = #"{"title":"Explore a useful idea","description":"Review the saved fictional reference."}"#
    let result = try CloudAPIClient.decode(response(content: valid), format: .chatCompletions)
    #expect(result.title == "Explore a useful idea")
    for (finish, text) in [("length", valid), ("stop", "not JSON"), ("stop", #"{"title":"","description":"No title"}"#)] {
        #expect(throws: SnapError.invalidResponse) { try CloudAPIClient.decode(response(finish: finish, content: text), format: .chatCompletions) }
    }
}
