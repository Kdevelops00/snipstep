import SwiftUI
import Charts
import SnipstepCore

private enum LibrarySection: String, CaseIterable, Identifiable {
    case inbox = "To-Do", completed = "Completed", analytics = "Analytics", archive = "Archive"
    var id: String { rawValue }
}

struct LibraryView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: LibrarySection = .inbox
    @State private var newTitle = ""
    @FocusState private var newTaskFocused: Bool
    @Namespace private var tabIndicator
    @State private var chartVisible = false
    @State private var detailTask: SavedTask?
    @State private var deleting: SavedTask?
    private var filtered: [SavedTask] {
        model.tasks.filter { task in
            switch section {
            case .inbox: !task.isArchived && !task.isCompleted
            case .completed: !task.isArchived && task.isCompleted
            case .archive: task.isArchived
            case .analytics: false
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            if model.settingsRequested {
                SettingsView(model: model)
            } else if let task = detailTask {
                HStack { Button("Back to list", systemImage: "arrow.left") { detailTask = nil }; Spacer() }.padding(.horizontal, 24)
                TaskDetail(task: task, model: model)
            } else {
                tabs
                if section == .analytics { analytics }
                else {
                    if filtered.isEmpty {
                        VStack(spacing: 24) {
                            BrandMark().frame(width: 72, height: 72)
                            VStack(spacing: 8) {
                                Text(section == .inbox ? "Good ideas don’t wait." : "Nothing here yet.")
                                    .font(.system(size: 23, weight: .medium))
                                Text(section == .inbox ? "Press \(model.shortcutLabel) to save a moment. Keep it for your next move." : "Your tasks will appear here.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(filtered, id: \.id) { task in
                                    LibraryRow(task: task, model: model, open: { detailTask = task }, delete: { deleting = task })
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                        .padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.08)))
                                        .contextMenu { Button(task.isArchived ? "Restore" : "Archive") { model.archive(task) } }
                                }
                            }.padding(.horizontal, 22).padding(.bottom, 12)
                        }.accessibilityIdentifier("taskList")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "plus").foregroundStyle(.primary)
                        TextField("Add a task…", text: $newTitle).textFieldStyle(.plain)
                            .accessibilityIdentifier("newTaskTitle").focused($newTaskFocused).onSubmit(addTask)
                        Button(action: addTask) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                            .buttonStyle(.plain).disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Add task").accessibilityIdentifier("addTask")
                    }.padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(22)
                }
            }
            if let message = model.lastSaveMessage {
                Label(message, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.primary)
                    .padding(10).accessibilityLabel(message)
                    .task(id: model.feedbackID) {
                        let id = model.feedbackID
                        try? await Task.sleep(for: .seconds(4))
                        if model.feedbackID == id { model.lastSaveMessage = nil }
                    }
            }
        }
        .background(DesktopMaterial())
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: section)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.settingsRequested)
        .confirmationDialog("Delete this task and its screenshot?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete permanently", role: .destructive) { if let deleting { model.delete(deleting) }; deleting = nil }
        } message: { Text("This removes the local task, screenshot, and extracted text.") }
        .alert("Snipstep", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onAppear { model.start() }
        .task(id: model.requestedNewTask) {
            guard model.requestedNewTask else { return }
            model.settingsRequested = false
            detailTask = nil
            section = .inbox
            await Task.yield()
            newTaskFocused = true
            model.requestedNewTask = false
        }
        .onChange(of: model.requestedDetailID) { _, id in
            if let task = model.tasks.first(where: { $0.id == id }) {
                model.settingsRequested = false
                detailTask = task
                model.requestedDetailID = nil
            }
        }
        .onChange(of: model.tasks.count) { _, _ in
            dismissDeletedDetail()
        }
    }
    private var tabs: some View {
        HStack(spacing: 6) {
                    ForEach(LibrarySection.allCases) { tab in
                        Button { section = tab } label: {
                            Text(tab.rawValue).font(.callout.weight(section == tab ? .semibold : .regular))
                                .padding(.horizontal, 13).padding(.vertical, 9)
                                .background { if section == tab { Capsule().fill(.primary.opacity(0.10)).matchedGeometryEffect(id: "mainTab", in: tabIndicator) } }
                        }.buttonStyle(.plain).accessibilityAddTraits(section == tab ? [.isSelected] : [])
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 22).padding(.bottom, 16)
    }
    private var header: some View {
        HStack(spacing: 12) {
                BrandMark()
                    .frame(width: 42, height: 42)
                    .phaseAnimator([1.0, 1.18, 1.0], trigger: model.feedbackID) { view, scale in
                        view.scaleEffect(reduceMotion ? 1 : scale)
                    } animation: { _ in reduceMotion ? .linear(duration: 0) : .spring(duration: 0.3) }
                    .background(.clear)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Snipstep").font(.title2.weight(.semibold))
                    Text("Save the spark. Make your move.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { detailTask = nil; model.settingsRequested.toggle() } label: {
                    Label(model.settingsRequested ? "Back" : "Settings", systemImage: model.settingsRequested ? "arrow.left" : "gearshape")
                        .padding(.horizontal, 12).padding(.vertical, 9)
                }.buttonStyle(.plain).background(.ultraThinMaterial, in: Capsule()).help("Settings · ⌘,")
            }.padding(22)
    }
    private var analytics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Your momentum").font(.title2.bold())
                HStack(spacing: 12) {
                    metric("To explore", model.remaining.count)
                    metric("Completed", model.completedCount)
                    metric("Saved", model.tasks.filter { !$0.isArchived }.count)
                }
                Text("Completed · last 7 days").font(.headline)
                Chart(0..<7, id: \.self) { offset in
                    let day = Calendar.current.date(byAdding: .day, value: offset - 6, to: Date())!
                    let count = model.tasks.filter { task in !task.isArchived && (task.completedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false) }.count
                    BarMark(x: .value("Day", day, unit: .day), y: .value("Completed", count)).foregroundStyle(.gray.gradient).cornerRadius(5)
                }.chartYScale(domain: 0...max(1, model.completedCount)).frame(height: 190)
                    .mask(alignment: .bottom) { Rectangle().scaleEffect(x: 1, y: chartVisible || reduceMotion ? 1 : 0, anchor: .bottom) }
                    .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) { chartVisible = true } }
                    .onDisappear { chartVisible = false }
                Text("Based on tasks currently saved on this Mac. Deleted tasks are excluded. No analytics leave your device.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }
    }
    private func metric(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(count, format: .number).font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    private func dismissDeletedDetail() {
        guard let id = detailTask?.id else { return }
        if !model.tasks.contains(where: { $0.id == id }) { detailTask = nil }
    }
    private func addTask() {
        guard !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.addManual(newTitle)
        if model.errorMessage == nil { newTitle = ""; section = .inbox }
    }
}

private struct DesktopMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = MaterialView()
        view.material = .sidebar; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    private final class MaterialView: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.isOpaque = false; window?.backgroundColor = .clear
        }
    }
}

struct TaskThumbnail: View {
    let task: SavedTask
    let model: AppModel
    var size: CGFloat = 48
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(.quaternary)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(systemName: task.attachmentExtension == nil ? "text.alignleft" : "photo").foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
        .task(id: task.id) { image = await model.thumbnail(for: task) }
    }
}

private struct LibraryRow: View {
    let task: SavedTask
    let model: AppModel
    let open: () -> Void
    let delete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ticking = false
    var body: some View {
        HStack(spacing: 12) {
            Button {
                guard !ticking else { return }
                let id = task.id
                let wasCompleted = task.isCompleted
                ticking = true
                Task {
                    try? await Task.sleep(for: .milliseconds(1100))
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) {
                        if let current = model.tasks.first(where: { $0.id == id }), current.isCompleted == wasCompleted { model.complete(current) }
                        ticking = false
                    }
                }
            } label: {
                ZStack {
                    Circle().strokeBorder(.primary.opacity(0.55), lineWidth: 1.5)
                    if ticking ? !task.isCompleted : task.isCompleted {
                        Circle().fill(.white.opacity(0.16))
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    }
                }.frame(width: 26, height: 26).padding(4)
            }.buttonStyle(.plain).disabled(ticking).accessibilityLabel(task.isCompleted ? "Reopen \(task.title)" : "Complete \(task.title)")
            Button(action: open) {
                HStack(spacing: 12) {
                    if task.attachmentExtension != nil { TaskThumbnail(task: task, model: model) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title).font(.body.weight(.medium)).lineLimit(2)
                        if !task.details.isEmpty {
                            Text(task.details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if task.processing == .recognizing || task.processing == .enriching || task.processing == .saved {
                            Text(task.processing.label).font(.caption2).foregroundStyle(.primary)
                        }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open \(task.title)")
            Button(action: delete) { Image(systemName: "trash").frame(width: 32, height: 32) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete task").accessibilityLabel("Delete \(task.title)")
        }
    }
}
