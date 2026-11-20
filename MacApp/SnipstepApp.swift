import SwiftUI
import SnipstepCore

@main struct SnipstepApp: App {
    @NSApplicationDelegateAdaptor(DesktopAppDelegate.self) private var delegate
    @State private var model: AppModel?
    init() {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        _model = State(initialValue: testing ? try? AppModel(testing: true) : AppModel.shared)
        #else
        _model = State(initialValue: AppModel.shared)
        #endif
    }
    var body: some Scene {
        WindowGroup("Snipstep", id: "library") {
            if let model {
                LibraryView(model: model)
                    .frame(minWidth: 460, minHeight: 400)
                    .onOpenURL { url in
                        guard let destination = TaskLink(url: url) else { return }
                        Task {
                            model.start(); await model.waitForStartup()
                            switch destination {
                            case .newTask: model.requestedNewTask = true
                            case .detail(let id): model.requestedDetailID = id
                            }
                        }
                    }
            } else {
                ContentUnavailableView("Your library couldn’t be opened", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your existing data has not been reset. Check disk space and file access, then reopen Snipstep."))
                    .frame(width: 620, height: 360)
            }
        }
        .defaultSize(width: 620, height: 600)
        .defaultLaunchBehavior(.presented)
        .commands { if let model { SnapCommands(model: model) } }


        MenuBarExtra("Snipstep", systemImage: "square.stack.3d.up") {
            if let model { MenuContent(model: model) }
        }
    }
}

@MainActor final class DesktopAppDelegate: NSObject, NSApplicationDelegate {
    private var library: NSWindow?
    private var model: AppModel? {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--uitesting") else { return nil }
        #endif
        return AppModel.shared
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let model else { return }
        model.openLibrary = { [weak self] in
            guard let self else { return }
            if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("library") == true }) {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            if library == nil {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
                window.title = "Snipstep Library"
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: LibraryView(model: model))
                window.center()
                library = window
            }
            library?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        model.start()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            Task { @MainActor in AppModel.shared?.reload() }
        }, "org.snaplater.widget.changed" as CFString, nil, .deliverImmediately)
    }
    func applicationDidBecomeActive(_ notification: Notification) { model?.reload() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.openLibrary()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct SnapCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.settingsRequested = true; model.openLibrary() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("Capture Screenshot") { model.capture() }
            Button("Capture Locally Only") { model.capture(localOnly: true) }
            Button("Import Image…") { model.importImage() }.keyboardShortcut("i", modifiers: .command)
        }
        CommandMenu("Snipstep Widgets") {
            Text("Add To-Do and Progress through macOS Edit Widgets.")
        }
    }
}

private struct MenuContent: View {
    let model: AppModel
    var body: some View {
        Text("Processing: \(model.mode.label)")
        if model.captureShortcutAvailable { Text("Capture: " + model.shortcutLabel) }
        Divider()
        Button("Capture Screenshot") { model.capture() }
        Button("Capture Locally Only") { model.capture(localOnly: true) }
        Button("Import Image…") { model.importImage() }
        Divider()
        Button("Open Library") { model.openLibrary() }
        Button("Settings…") { model.settingsRequested = true; model.openLibrary() }
        Divider()
        Button("Quit Snipstep") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
