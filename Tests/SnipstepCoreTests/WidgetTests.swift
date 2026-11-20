import Foundation
import ImageIO
import Testing
@testable import SnipstepCore

@Test func widgetOutboxKeepsNewerClickAndPersistsSnapshot() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WidgetStore(root: root)
    let id = UUID()
    try store.write(.init(tasks: [.init(id: id, title: "Read", summary: "Synthetic summary", completed: false)], remaining: 1))
    #expect(try store.read().tasks.first?.id == id)
    try store.complete(id: id, completed: true)
    let old = try #require(try store.commands().first)
    try store.complete(id: id, completed: false)
    try store.acknowledge(old)
    let newer = try #require(try store.commands().first)
    #expect(!newer.completed)
    try store.acknowledge(newer)
    #expect(try store.commands().isEmpty)
}

@Test func widgetSnapshotRejectsSymlink() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WidgetStore(root: root)
    let target = root.appendingPathComponent("other.json")
    try Data("{}".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("snapshot.json"), withDestinationURL: target)
    #expect(throws: SnapError.storage) { try store.read() }
}

@Test func widgetDeletionSurvivesOlderCompletionAcknowledgement() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WidgetStore(root: root)
    let id = UUID()
    try store.complete(id: id, completed: false)
    let old = try #require(try store.commands().first)
    try store.delete(id: id)
    try store.acknowledge(old)
    let deletion = try #require(try store.commands().first)
    #expect(deletion.deleted == true)
    try store.acknowledge(deletion)
    #expect(try store.commands().isEmpty)
}

@Test func checklistHidesCompletedTasksButRetainsProgressTotals() {
    let unfinished = WidgetTask(id: UUID(), title: "Explore", summary: "", completed: false)
    let done = WidgetTask(id: UUID(), title: "Already finished", summary: "", completed: true)
    let snapshot = WidgetSnapshot(tasks: [done, unfinished], completed: 1, remaining: 1)
    #expect(snapshot.pendingTasks.map(\.id) == [unfinished.id])
    #expect(snapshot.completed == 1)
}

@Test @MainActor func widgetPreviewKeepsWholeScreenshotAspectAndBoundsPayload() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AttachmentStore(root: root)
    let manifest = try await store.save(textFixture(), mode: .ocrOnly)
    let data = try await store.widgetPreview(id: manifest.id, fileExtension: manifest.fileExtension)
    #expect(data.count <= 100_000)
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
    let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
    #expect(width > height)
    #expect(width <= 360)
    #expect(abs(Double(width) / Double(height) - 900.0 / 320.0) < 0.03)
}

@Test func widgetShowsTickBrieflyThenHidesCompletedTask() {
    let now = Date(timeIntervalSince1970: 10000)
    let done = WidgetTask(id: UUID(), title: "Just finished", summary: "", completed: true, completedAt: now)
    let old = WidgetTask(id: UUID(), title: "Old completed task", summary: "", completed: true, completedAt: now.addingTimeInterval(-60))
    let pending = WidgetTask(id: UUID(), title: "Next", summary: "", completed: false)
    let snapshot = WidgetSnapshot(tasks: [pending, old, done], completed: 2, remaining: 1)
    #expect(snapshot.checklistRows(at: now.addingTimeInterval(1)).map(\.id) == [done.id, pending.id])
    #expect(snapshot.checklistRows(at: now.addingTimeInterval(2.1)).map(\.id) == [pending.id])
    #expect(snapshot.pendingTasks.map(\.id) == [pending.id])
}
