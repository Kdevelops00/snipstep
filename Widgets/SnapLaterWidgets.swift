import SwiftUI
import WidgetKit
import AppIntents
import SnapLaterCore

private struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var problem: String? = nil
}
private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        .init(date: .now, snapshot: .init(tasks: [
            .init(id: UUID(), title: "An idea worth exploring", summary: "Your saved screenshots become simple tasks.", completed: false),
            .init(id: UUID(), title: "Come back to it later", summary: "Only unfinished tasks appear here.", completed: false)
        ], completed: 2, remaining: 2))
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(context.isPreview ? placeholder(in: context) : current()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = current()
        var entries = [entry]
        if let expiry = entry.snapshot.tasks.compactMap(\.completedAt).map({ $0.addingTimeInterval(2.05) }).filter({ $0 > entry.date }).max() {
            entries.append(Entry(date: expiry, snapshot: entry.snapshot, problem: entry.problem))
        }
        completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(900))))
    }
    private func current() -> Entry {
        guard let store = WidgetStore.configured() else {
            return .init(date: .now, snapshot: .init(), problem: "Connect this widget to Snipstep.")
        }
        var snapshot: WidgetSnapshot
        do { snapshot = try store.read() }
        catch { return .init(date: .now, snapshot: .init(), problem: "Your tasks couldn’t be refreshed.") }
        guard snapshot.updatedAt != nil else {
            return .init(date: .now, snapshot: snapshot, problem: "Open Snipstep once to sync your tasks.")
        }
        // Reflect durable clicks immediately, even when the app is not running.
        for command in (try? store.commands()) ?? [] {
            if command.deleted == true {
                if let task = snapshot.tasks.first(where: { $0.id == command.id }) {
                    snapshot.tasks.removeAll { $0.id == command.id }
                    if task.completed { snapshot.completed -= 1 } else { snapshot.remaining -= 1 }
                }
                continue
            }
            if let i = snapshot.tasks.firstIndex(where: { $0.id == command.id }) {
                if snapshot.tasks[i].completed != command.completed {
                    snapshot.tasks[i].completed = command.completed
                    snapshot.completed += command.completed ? 1 : -1
                    snapshot.remaining += command.completed ? -1 : 1
                }
                snapshot.tasks[i].completedAt = command.completed ? command.createdAt : nil
            }
        }
        return .init(date: .now, snapshot: snapshot)
    }
}

struct RefreshWidget: AppIntent {
    static let title: LocalizedStringResource = "Refresh Snipstep Widget"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("org.snaplater.widget.changed" as CFString), nil, nil, true)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct CompleteWidgetTask: AppIntent {
    static let title: LocalizedStringResource = "Update Snipstep Task"
    @Parameter(title: "Task") var taskID: String
    @Parameter(title: "Completed") var completed: Bool
    init() {}
    init(id: UUID, completed: Bool) { taskID = id.uuidString; self.completed = completed }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID), let store = WidgetStore.configured() else { throw SnapError.storage }
        try store.complete(id: id, completed: completed)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("org.snaplater.widget.changed" as CFString), nil, nil, true)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct DeleteWidgetTask: AppIntent {
    static let openAppWhenRun = true
    static let title: LocalizedStringResource = "Delete Snipstep Task"
    @Parameter(title: "Task") var taskID: String
    init() {}
    init(id: UUID) { taskID = id.uuidString }
    func perform() async throws -> some IntentResult {
        try await requestConfirmation(dialog: "Delete this task and its saved screenshot?")
        guard let id = UUID(uuidString: taskID), let store = WidgetStore.configured() else { throw SnapError.storage }
        try store.delete(id: id)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("org.snaplater.widget.changed" as CFString), nil, nil, true)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

private struct RoundTaskToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack {
                Circle().strokeBorder(.primary.opacity(0.6), lineWidth: 1.5)
                if configuration.isOn {
                    Circle().fill(.white.opacity(0.18))
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                }
            }.frame(width: 25, height: 25).padding(3).contentShape(Circle())
        }.buttonStyle(.plain)
    }
}

private struct Checklist: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family
    private var remaining: [WidgetTask] { entry.snapshot.checklistRows(at: entry.date) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Your next moves", systemImage: "sparkles").font(.headline)
                Spacer()
                Text("\(entry.snapshot.remaining)").font(.caption).foregroundStyle(.secondary)
                Link(destination: TaskLink.newTask.url) {
                    Label("Add task", systemImage: "plus.circle.fill").font(.caption.weight(.medium))
                }.accessibilityLabel("Add a task without a screenshot")
            }
            if let problem = entry.problem {
                Text(problem).font(.callout).foregroundStyle(.secondary)
                Button(intent: RefreshWidget()) { Label("Open & refresh", systemImage: "arrow.clockwise") }.buttonStyle(.plain)
            } else if remaining.isEmpty {
                Text(entry.snapshot.remaining == 0 ? "Nothing pending. Go do your thing." : "Open Snipstep to refresh your tasks.").font(.callout).foregroundStyle(.secondary)
                Text("Catch your next idea with Snipstep.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(remaining.prefix(family == .systemLarge ? 4 : 2))) { task in
                HStack(spacing: 9) {
                    Toggle(isOn: task.completed, intent: CompleteWidgetTask(id: task.id, completed: !task.completed)) {
                        Text(task.title)
                    }.toggleStyle(RoundTaskToggleStyle())
                        .accessibilityLabel(task.completed ? "Reopen task" : "Complete task")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(.callout.weight(.medium)).lineLimit(family == .systemLarge ? 2 : 1)
                        if !task.summary.isEmpty { Text(task.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let data = task.thumbnail, let image = NSImage(data: data) {
                        Link(destination: URL(string: "snaplater://task/\(task.id.uuidString)")!) {
                            Image(nsImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
                                .frame(width: family == .systemLarge ? 86 : 72, height: family == .systemLarge ? 54 : 40)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }.accessibilityLabel("Open screenshot for \(task.title)")
                    }
                    Button(intent: DeleteWidgetTask(id: task.id)) {
                        Image(systemName: "trash").font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("Delete task")
                }.padding(.vertical, 3).privacySensitive()
            }
            Spacer(minLength: 0)

        }.containerBackground(for: .widget) { Color.clear }
    }
}

private struct Progress: View {
    let entry: Entry
    private var fraction: Double {
        Double(entry.snapshot.completed) / Double(max(1, entry.snapshot.completed + entry.snapshot.remaining))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Look at you go", systemImage: "sparkles").font(.callout.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            if let problem = entry.problem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
                Button(intent: RefreshWidget()) { Label("Open & refresh", systemImage: "arrow.clockwise") }.buttonStyle(.plain)
            } else {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(.gray.opacity(0.15), lineWidth: 6)
                    Circle().trim(from: 0, to: fraction).stroke(.gray.gradient, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(fraction, format: .percent.precision(.fractionLength(0))).font(.caption.bold()).monospacedDigit()
                }.frame(width: 58, height: 58).accessibilityLabel("Completion \(Int(fraction * 100)) percent")
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(entry.snapshot.remaining)").font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("up next").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("\(entry.snapshot.completed) completed").font(.caption).foregroundStyle(.secondary)
            }
        }.privacySensitive().containerBackground(for: .widget) { Color.clear }
    }
}

struct ToDoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SnapLater.ToDo", provider: Provider()) { Checklist(entry: $0) }
            .configurationDisplayName("Snipstep To-Do").description("Saved screenshots and a simple interactive checklist.")
            .containerBackgroundRemovable(true)
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SnapLater.Progress", provider: Provider()) { Progress(entry: $0) }
            .configurationDisplayName("Snipstep Progress").description("Completed and remaining tasks, separate from your checklist.")
            .containerBackgroundRemovable(true)
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
@main struct SnapLaterWidgetBundle: WidgetBundle {
    var body: some Widget { ToDoWidget(); ProgressWidget() }
}
