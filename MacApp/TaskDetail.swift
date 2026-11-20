import SwiftUI
import SnipstepCore

struct TaskDetail: View {
    let task: SavedTask
    let model: AppModel
    @State private var title: String
    @State private var details: String
    @State private var showScreenshot = false
    @State private var showDelete = false
    @State private var preview: NSImage?
    @State private var saveError: String?

    init(task: SavedTask, model: AppModel) {
        self.task = task; self.model = model
        _title = State(initialValue: task.title)
        _details = State(initialValue: task.details)
    }

    private var hasChanges: Bool {
        title != task.title || details != task.details
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label(task.origin, systemImage: task.origin.hasPrefix("AI") ? "sparkles" : "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(task.processing.label).font(.caption).foregroundStyle(.secondary)
                }
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title2.weight(.semibold)).textFieldStyle(.plain).accessibilityIdentifier("detailTitle")
                HStack {
                    Spacer()
                    Button(task.isCompleted ? "Reopen" : "Mark Done", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                        model.complete(task)
                    }.accessibilityIdentifier("detailComplete")
                }
                if task.attachmentExtension != nil {
                    Button { showScreenshot = true } label: {
                        ZStack(alignment: .bottomTrailing) {
                            RoundedRectangle(cornerRadius: 14).fill(.quaternary)
                            if let preview { Image(nsImage: preview).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity).padding(8) }
                            else { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
                            Image(systemName: "arrow.up.left.and.arrow.down.right").padding(9).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(10)
                        }.frame(height: 215).clipShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).help("View original screenshot").accessibilityLabel("View screenshot").accessibilityIdentifier("showScreenshot")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.origin.hasPrefix("AI") ? "SUMMARY" : task.attachmentExtension != nil && !task.isEdited(.details) ? "EXTRACTED TEXT" : "NOTES")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if task.attachmentExtension != nil && !task.origin.hasPrefix("AI") && !task.isEdited(.details) {
                        Text("Text read from your screenshot. An AI summary has not been generated.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("What would you like to explore?", text: $details, axis: .vertical)
                        .lineLimit(5...16).textFieldStyle(.plain).accessibilityIdentifier("detailNotes")
                }
                if let issue = task.issue {
                    Label(issue, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                HStack {
                    Button("Save Changes") { save() }.buttonStyle(.borderedProminent).tint(.primary)
                        .disabled(!hasChanges).accessibilityIdentifier("saveChanges")
                    if task.attachmentExtension != nil {
                        if model.mode != .ocrOnly {
                            Button(task.origin.hasPrefix("AI") ? "Retry AI" : "Summarize", systemImage: "sparkles") { model.retry(task) }
                                .disabled(task.processing == .enriching || task.processing == .recognizing)
                                .help(model.mode == .localAI ? "Summarize cached text with your local model" : model.cloudConnection.sendsImage ? "Send this screenshot and cached text to \(model.cloudConnection.host)" : "Send cached text only to \(model.cloudConnection.host)")
                        } else {
                            Button("Enable AI summaries…") { model.settingsPage = "AI summaries"; model.settingsRequested = true }
                        }
                    }
                    Spacer()
                }
                if task.attachmentExtension != nil {
                    DisclosureGroup("Cached screenshot text") {
                        Text(task.ocrText.isEmpty ? "No readable text was extracted. The original is still saved." : task.ocrText)
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }.font(.callout)
                }
                Divider()
                HStack {
                    Button(task.isArchived ? "Restore from Archive" : "Archive", systemImage: task.isArchived ? "tray.and.arrow.up" : "archivebox") { model.archive(task) }
                    Spacer()
                    Button("Delete…", systemImage: "trash", role: .destructive) { showDelete = true }.accessibilityIdentifier("deleteTask")
                }
            }.padding(28)
        }
        .task(id: task.id) { preview = await model.thumbnail(for: task) }
        .onChange(of: task.title) { old, new in if title == old { title = new } }
        .onChange(of: task.details) { old, new in if details == old { details = new } }
        .confirmationDialog("Delete this task and its screenshot?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) { model.delete(task) }
        } message: { Text("The local original, cached text, and task will be removed. This cannot retract previous cloud submissions or system backups.") }
        .alert("Changes weren’t saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .sheet(isPresented: $showScreenshot) { ScreenshotView(task: task, model: model) }
    }
    private func save() {
        do { try model.store.edit(task, title: title, details: details); model.reload() }
        catch { saveError = ((error as? SnapError) ?? .storage).localizedDescription }
    }
}

private struct ScreenshotView: View {
    let task: SavedTask
    let model: AppModel
    @State private var image: NSImage?
    @State private var unavailable = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Original screenshot").font(.headline); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(16)
            Divider()
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(20).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if unavailable { ContentUnavailableView("Preview unavailable", systemImage: "photo.badge.exclamationmark") }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.frame(minWidth: 650, idealWidth: 900, minHeight: 450, idealHeight: 650)
        .task {
            guard let ext = task.attachmentExtension else { unavailable = true; return }
            if let data = try? await model.attachments.preview(id: task.id, fileExtension: ext, pixels: 2_400) { image = NSImage(data: data) }
            unavailable = image == nil
        }
    }
}
