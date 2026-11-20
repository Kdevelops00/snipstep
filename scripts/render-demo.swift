import AppKit
import SwiftUI
import WidgetKit
import SnipstepCore

// Render actual views with an isolated in-memory library; never capture the desktop.
@main struct DemoRenderer {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let model = try AppModel(testing: true)
        model.start(); await model.waitForStartup()
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let second = try model.store.addManual(title: "Pick a small PR for the test")
        let id = try await model.pipeline.ingest(data, localOnly: true)
        await model.pipeline.waitUntilIdle()
        guard let first = try model.store.task(id), let fileExtension = first.attachmentExtension else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try model.store.edit(first, title: "Try Ponytail on a small PR", details: "Read the README and try the review workflow on the next small change.")
        model.reload()
        func snapshot<V: View>(_ view: V, name: String, width: CGFloat = 860, height: CGFloat = 620, scale: CGFloat = 1) async throws {
            let content = view.environment(\.colorScheme, .dark)
                .frame(width: width, height: height)
                .background(name.hasPrefix("widget") ? Color.clear : Color(red: 0.10, green: 0.12, blue: 0.17))
                .scaleEffect(scale)
                .frame(width: width * scale, height: height * scale)
            let host = NSHostingView(rootView: content)
            host.frame = NSRect(x: 0, y: 0, width: width * scale, height: height * scale)
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(450))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: output.appendingPathComponent(name + ".png"))
        }
        try await snapshot(LibraryView(model: model), name: "library")
        try await snapshot(VStack(alignment: .leading) { Text("Snipstep").font(.title2.bold()).padding(); TaskDetail(task: first, model: model) }, name: "detail")
        let thumbnail = try await model.attachments.widgetPreview(id: first.id, fileExtension: fileExtension)
        let date = Date()
        let capture = WidgetTask(id: first.id, title: first.title, summary: first.details, completed: false, thumbnail: thumbnail)
        let manual = WidgetTask(id: second.id, title: second.title, summary: second.details, completed: false, thumbnail: nil)
        let entry = Entry(date: date, snapshot: .init(tasks: [capture, manual], completed: 0, remaining: 2))
        try await snapshot(Checklist(entry: entry).padding(16), name: "widget", width: 360, height: 164, scale: 2)
        let checked = WidgetTask(id: first.id, title: first.title, summary: first.details, completed: true,
                                 thumbnail: thumbnail, completedAt: date)
        let done = Entry(date: date, snapshot: .init(tasks: [checked, manual], completed: 1, remaining: 1))
        try await snapshot(Checklist(entry: done).padding(16), name: "widget-done", width: 360, height: 164, scale: 2)
        // Testing mode disables shared widgets, hotkeys, existing credentials and network enrichment.
        precondition(model.isTesting && model.mode == .ocrOnly && !model.keyConfigured)
        print("Rendered isolated app and widget views with the supplied fixture.")
    }
}
