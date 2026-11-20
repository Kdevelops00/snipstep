import Foundation
import Testing
@testable import SnipstepCore

private final class StubResponse: @unchecked Sendable {
    static let shared = StubResponse()
    private let lock = NSLock()
    private var value: (Int, Data, URLError.Code?) = (200, Data(), nil)
    private var nextStatus: Int?
    private var requestCount = 0
    func count() -> Int { lock.lock(); defer { lock.unlock() }; return requestCount }
    func set(status: Int = 200, body: Data = Data(), error: URLError.Code? = nil, then statusAfterFirst: Int? = nil) {
        lock.lock(); defer { lock.unlock() }; value = (status, body, error); nextStatus = statusAfterFirst; requestCount = 0
    }
    func get() -> (Int, Data, URLError.Code?) {
        lock.lock(); defer { lock.unlock() }
        requestCount += 1
        let response = value
        if let nextStatus { value.0 = nextStatus; self.nextStatus = nil }
        return response
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data, error) = StubResponse.shared.get()
        if let error { client?.urlProtocol(self, didFailWithError: URLError(error)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json", "Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct NetworkTests {
    private func client() -> GeminiClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.urlCache = nil
        return GeminiClient(session: URLSession(configuration: config))
    }
    @Test func statusCodesAreSanitized() async throws {
        for (code, expected) in [(401, SnapError.authentication), (403, .authentication), (404, .modelUnavailable), (429, .quota), (500, .unavailable), (302, .unavailable)] {
            StubResponse.shared.set(status: code, body: Data("private upstream diagnostics".utf8))
            await #expect(throws: expected) { try await client().enrich(image: testImage(), ocr: .init(state: .empty), apiKey: "test-placeholder") }
            #expect(StubResponse.shared.count() == 1)
        }
    }
    @Test func timeoutAndOfflineBecomeRecoverableFailure() async throws {
        for code in [URLError.Code.timedOut, .notConnectedToInternet] {
            StubResponse.shared.set(error: code)
            await #expect(throws: SnapError.unavailable) { try await client().enrich(image: testImage(), ocr: .init(state: .empty), apiKey: "test-placeholder") }
        }
    }
    @Test func serviceBusyRetriesOnceAndThenPreservesFailure() async throws {
        StubResponse.shared.set(status: 503)
        await #expect(throws: SnapError.serviceBusy) {
            try await client().enrich(image: testImage(), ocr: .init(state: .empty), apiKey: "test-placeholder")
        }
        #expect(StubResponse.shared.count() == 2)
    }
    @Test func temporaryServiceFailureRecoversOnOneRetry() async throws {
        let body = Data(#"{"candidates":[{"content":{"parts":[{"text":"{\"title\":\"Explore a tool\",\"description\":\"Review this tool later.\"}"}]},"finishReason":"STOP"}]}"#.utf8)
        StubResponse.shared.set(status: 503, body: body, then: 200)
        let result = try await client().enrich(image: testImage(), ocr: .init(state: .empty), apiKey: "test-placeholder")
        #expect(result.title == "Explore a tool")
        #expect(StubResponse.shared.count() == 2)
    }
    @Test func oversizedResponseIsRejected() async throws {
        StubResponse.shared.set(body: Data(count: GeminiClient.maximumResponseBytes + 1))
        await #expect(throws: SnapError.responseTooLarge) { try await client().enrich(image: testImage(), ocr: .init(state: .empty), apiKey: "test-placeholder") }
    }
    @Test func malformedResponseIsRejected() async throws {
        StubResponse.shared.set(body: Data("{not valid JSON}".utf8))
        await #expect(throws: SnapError.invalidResponse) { try await client().enrich(image: testImage(), ocr: .init(state: .empty), apiKey: "test-placeholder") }
    }
    @Test func compatibleHTTPFailuresAreSanitized() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let connection = CloudConnection(format: .chatCompletions, endpoint: "https://example.test/v1/chat/completions", model: "synthetic-model")
        let api = CloudAPIClient(connection: connection, session: URLSession(configuration: config))
        for (status, expected) in [(401, SnapError.authentication), (403, .authentication), (404, .modelUnavailable), (429, .quota), (503, .serviceBusy), (302, .unavailable)] {
            StubResponse.shared.set(status: status, body: Data("private provider diagnostics".utf8))
            await #expect(throws: expected) { try await api.enrich(image: testImage(), ocr: .init(state: .empty), apiKey: "placeholder-only") }
            #expect(StubResponse.shared.count() == 1)
        }
        StubResponse.shared.set(body: Data(count: GeminiClient.maximumResponseBytes + 1))
        await #expect(throws: SnapError.responseTooLarge) { try await api.enrich(image: testImage(), ocr: .init(state: .empty), apiKey: "placeholder-only") }
    }

}
