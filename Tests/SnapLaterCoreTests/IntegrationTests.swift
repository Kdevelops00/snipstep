import AppKit
import Foundation
import Testing
@testable import SnapLaterCore

@MainActor func textFixture() throws -> Data {
    let image = NSImage(size: NSSize(width: 900, height: 320))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 900, height: 320).fill()
    ("Explore Swift\nhttps://swift.org/documentation" as NSString).draw(at: NSPoint(x: 40, y: 140),
        withAttributes: [.font: NSFont.systemFont(ofSize: 32), .foregroundColor: NSColor.black])
    image.unlockFocus()
    let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    return try ImageFiles.png(cg)
}

@Test @MainActor func realVisionRecognizesSyntheticScreenshot() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("SnapLaterVision-" + UUID().uuidString)
    let attachments = try AttachmentStore(root: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let manifest = try await attachments.save(textFixture(), mode: .ocrOnly)
    let url = try await attachments.originalURL(id: manifest.id, fileExtension: manifest.fileExtension)
    let result = try await VisionOCR().recognize(url: url)
    #expect(result.state == .recognized)
    #expect(result.text.localizedCaseInsensitiveContains("Swift"))
}

@Test @MainActor func keychainRoundTripUsesAnIsolatedSyntheticCredential() throws {
    let keychain = KeychainCredentialStore(service: "org.snaplater.tests." + UUID().uuidString)
    defer { try? keychain.remove() }
    try keychain.save("synthetic-placeholder-one")
    #expect(try keychain.read() == "synthetic-placeholder-one")
    try keychain.save("synthetic-placeholder-two")
    #expect(try keychain.read() == "synthetic-placeholder-two")
    try keychain.remove()
    #expect(throws: SnapError.keyUnavailable) { try keychain.read() }
}

@Test @MainActor func failedAttachmentWriteDoesNotClaimSaved() async throws {
    let h = try Harness(); defer { h.cleanup() }
    try FileManager.default.removeItem(at: h.attachments.root)
    try Data().write(to: h.attachments.root)
    await #expect(throws: SnapError.storage) { try await h.pipeline.ingest(testImage()) }
    #expect(try h.store.all().isEmpty)
}

@Test @MainActor func deletingASymlinkCannotDeleteItsTargetAndRecoveryFinishesDeletion() async throws {
    let h = try Harness(); defer { h.cleanup() }
    let id = try await h.pipeline.ingest(testImage())
    await h.pipeline.waitUntilIdle()
    let folder = h.attachments.root.appendingPathComponent(id.uuidString)
    let outside = h.root.appendingPathComponent("preserved-original")
    try FileManager.default.moveItem(at: folder, to: outside)
    try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
    await #expect(throws: SnapError.storage) { try await h.pipeline.delete(id) }
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("original.png").path))
    #expect(try h.store.task(id, includeDeleted: true)?.pendingDeletion == true)
    try FileManager.default.removeItem(at: folder)
    try FileManager.default.moveItem(at: outside, to: folder)
    try await h.pipeline.recover()
    #expect(try h.store.all(includeDeleted: true).isEmpty)
}

@Test @MainActor func revokingConsentAlsoStopsQueuedUploads() async throws {
    let ai = StubAI(deferred: true)
    let h = try Harness(ai: ai); defer { h.cleanup() }
    h.pipeline.setCloudEnabled(true)
    _ = try await h.pipeline.ingest(testImage())
    try await ai.waitForRequest()
    let second = try await h.pipeline.ingest(testImage())
    h.pipeline.setCloudEnabled(false)
    await ai.release()
    await h.pipeline.waitUntilIdle()
    #expect(await ai.calls == 1)
    #expect(try h.store.task(second)?.processing == .fallback)
    #expect(try h.store.task(second)?.ocr.state == .recognized)
}

@Test @MainActor func interruptedAIIsNotAutomaticallyResent() async throws {
    let ai = StubAI()
    let h = try Harness(ai: ai); defer { h.cleanup() }
    let manifest = try await h.attachments.save(testImage(), mode: .gemini)
    let task = try h.store.insertCapture(manifest)
    try h.store.applyOCR(.init(state: .recognized, text: "Cached text"), to: task)
    task.processingRaw = ProcessingState.enriching.rawValue
    try h.store.commit()
    h.pipeline.setCloudEnabled(true)
    try await h.pipeline.recover()
    await h.pipeline.waitUntilIdle()
    #expect(await ai.calls == 0)
    #expect(task.processing == .fallback)
    #expect(task.ocrText == "Cached text")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPLATER_GEMINI_KEY_SOURCE"] != nil))
@MainActor func liveGeminiSyntheticSmokeTest() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SNAPLATER_GEMINI_KEY_SOURCE"])
    let key = try DevelopmentCredential.read(from: URL(fileURLWithPath: path))
    // The only live payload is this generated public-documentation fixture. Never use real captures in this test.
    let result = try await GeminiClient().enrich(image: textFixture(),
        ocr: .init(state: .recognized, text: "Explore Swift\nhttps://swift.org/documentation"), apiKey: key)
    try result.validate()
    #expect(!result.title.isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPLATER_GEMINI_KEY_SOURCE"] != nil))
@MainActor func liveGeminiIdentifiesSubjectInFullScreenFixture() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SNAPLATER_GEMINI_KEY_SOURCE"])
    let key = try DevelopmentCredential.read(from: URL(fileURLWithPath: path))
    // Synthetic public text only; no user screenshots are uploaded by this test.
    let image = NSImage(size: NSSize(width: 2940, height: 1912))
    image.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 2940, height: 1912).fill()
    let navigation = "Products    Developers    Businesses    Resources    Pricing"
    let subject = "DietrichGebert / ponytail\n\nPonytail\nMakes your AI agent think like the laziest senior dev in the room.\nThe best code is the code you never wrote.\nAgent skills for simpler code with less unnecessary work."
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 38), .foregroundColor: NSColor.black]
    (navigation as NSString).draw(at: NSPoint(x: 70, y: 1750), withAttributes: attributes)
    (subject as NSString).draw(in: NSRect(x: 170, y: 500, width: 2400, height: 1000), withAttributes: attributes)
    image.unlockFocus()
    let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let result = try await GeminiClient().enrich(image: ImageFiles.png(cg),
        ocr: .init(state: .recognized, text: navigation + "\n" + subject), apiKey: key)
    try result.validate()
    #expect(result.title.localizedCaseInsensitiveContains("ponytail"))
    #expect(!result.description.hasPrefix(navigation))
    #expect(result.description.count < 1000)
    print("Synthetic subject test: \(result.title) — \(result.description)")
}
