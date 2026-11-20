import Foundation
import Testing
@testable import SnipstepCore

private actor LocalStub: TaskEnriching {
    var calls = 0
    func enrich(image: Data, ocr: OCRResult, apiKey: String) async throws -> TaskSuggestion {
        #expect(apiKey.isEmpty)
        #expect(image.isEmpty)
        calls += 1
        return .init(title: "Explore locally", description: "A local summary.")
    }
}
@Test @MainActor func localModeNeverUsesGeminiAndReusesOCR() async throws {
    let cloud = StubAI(), local = LocalStub(), ocr = StubOCR()
    let h = try Harness(ocr: ocr, ai: cloud); defer { h.cleanup() }
    h.pipeline.setLocalEnricher(local)
    let id = try await h.pipeline.ingest(testImage())
    await h.pipeline.waitUntilIdle()
    #expect(try h.store.task(id)?.mode == .localAI)
    #expect(try h.store.task(id)?.origin == "AI suggestion · Local")
    try h.pipeline.retryAI(id)
    await h.pipeline.waitUntilIdle()
    #expect(await ocr.calls == 1)
    #expect(await cloud.calls == 0)
    #expect(await local.calls == 2)
    h.pipeline.setLocalEnricher(nil)
    #expect(throws: SnapError.cloudDisabled) { try h.pipeline.retryAI(id) }
}
@Test func localCloudModelTagsAreExcluded() throws {
    let cloud = try JSONDecoder().decode(LocalAIClient.InstalledModel.self,
        from: Data(#"{"name":"remote:cloud","size":0,"remote_host":"https://example.com"}"#.utf8))
    #expect(!cloud.isLocal)
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPLATER_LOCAL_SMOKE"] == "1"))
func localInstalledModelSummarizesSyntheticText() async throws {
    let client = LocalAIClient(model: "qwen3.5:2b-q4_K_M")
    let suggestion = try await client.enrich(image: Data(), ocr: .init(state: .recognized,
        text: "Products Developers Pricing\nDietrichGebert / Ponytail\nPonytail helps AI coding agents write simpler code with less unnecessary work."), apiKey: "")
    #expect(suggestion.title.localizedCaseInsensitiveContains("Ponytail"))
    try suggestion.validate()
    print("Local synthetic result: \(suggestion.title) — \(suggestion.description)")
}

@Test @MainActor func disablingLocalModeBlocksQueuedJobsAndLateResults() async throws {
    let local = StubAI(deferred: true), cloud = StubAI()
    let h = try Harness(ai: cloud); defer { h.cleanup() }
    h.pipeline.setLocalEnricher(local)
    let first = try await h.pipeline.ingest(testImage())
    try await local.waitForRequest()
    let second = try await h.pipeline.ingest(testImage())
    h.pipeline.setLocalEnricher(nil)
    await local.release()
    await h.pipeline.waitUntilIdle()
    #expect(await local.calls == 1)
    #expect(await cloud.calls == 0)
    #expect(try h.store.task(first)?.processing == .fallback)
    #expect(try h.store.task(second)?.processing == .fallback)
}
