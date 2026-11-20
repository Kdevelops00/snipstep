import Foundation
import Darwin

public struct WidgetTask: Codable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var summary: String
    public var completed: Bool
    public var completedAt: Date?
    public var thumbnail: Data?
    public init(id: UUID, title: String, summary: String, completed: Bool, thumbnail: Data? = nil, completedAt: Date? = nil) {
        self.id = id; self.title = title; self.summary = summary; self.completed = completed; self.thumbnail = thumbnail; self.completedAt = completedAt
    }
}

public struct WidgetSnapshot: Codable, Sendable {
    public var pendingTasks: [WidgetTask] { tasks.filter { !$0.completed } }
    public func checklistRows(at date: Date) -> [WidgetTask] {
        tasks.filter { !$0.completed || ($0.completedAt.map { date.timeIntervalSince($0) >= 0 && date.timeIntervalSince($0) < 2 } ?? false) }
            .sorted { $0.completed && !$1.completed }
    }
    public var updatedAt: Date?
    public var tasks: [WidgetTask]
    public var completed: Int
    public var remaining: Int
    public init(tasks: [WidgetTask] = [], completed: Int = 0, remaining: Int = 0, updatedAt: Date? = .now) {
        self.updatedAt = updatedAt
        self.tasks = tasks; self.completed = completed; self.remaining = remaining
    }
}

public struct WidgetCommand: Codable, Sendable {
    public let id: UUID
    public let completed: Bool
    public let deleted: Bool?
    public let createdAt: Date?
}

/// A minimal view of the library and a durable completion outbox; never shares OCR or credentials.
public struct WidgetStore: Sendable {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public static func configured() -> WidgetStore? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "SnipstepAppGroup") as? String,
              !group.hasPrefix("."),
              let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return try? WidgetStore(root: url.appendingPathComponent("Widget", isDirectory: true))
    }
    public func read() throws -> WidgetSnapshot {
        let url = root.appendingPathComponent("snapshot.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .init(updatedAt: nil) }
        return try JSONDecoder().decode(WidgetSnapshot.self, from: boundedRead(url, limit: 2_000_000))
    }
    public func write(_ snapshot: WidgetSnapshot) throws {
        try writePrivate(JSONEncoder().encode(snapshot), to: root.appendingPathComponent("snapshot.json"))
    }
    public func complete(id: UUID, completed: Bool) throws {
        try locked {
            let command = WidgetCommand(id: id, completed: completed, deleted: nil, createdAt: .now)
            try writePrivate(JSONEncoder().encode(command), to: commandURL(id))
        }
    }
    public func delete(id: UUID) throws {
        try locked {
            try writePrivate(JSONEncoder().encode(WidgetCommand(id: id, completed: false, deleted: true, createdAt: .now)), to: commandURL(id))
        }
    }
    public func commands() throws -> [WidgetCommand] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url in
            guard url.lastPathComponent.hasPrefix("completion-"), url.pathExtension == "json" else { return nil }
            let value = try JSONDecoder().decode(WidgetCommand.self, from: boundedRead(url, limit: 1024))
            guard url.lastPathComponent == commandURL(value.id).lastPathComponent else { throw SnapError.storage }
            return value
        }
    }
    public func acknowledge(_ command: WidgetCommand) throws {
        try locked {
        // Keep a newer click if it arrived while the previous state was being committed.
        let url = commandURL(command.id)
        let current = try JSONDecoder().decode(WidgetCommand.self, from: boundedRead(url, limit: 1024))
        if current.completed == command.completed, current.deleted == command.deleted, current.createdAt == command.createdAt { try FileManager.default.removeItem(at: url) }
        }
    }
    private func commandURL(_ id: UUID) -> URL { root.appendingPathComponent("completion-" + id.uuidString + ".json") }
    private func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let attrs = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey, .isRegularFileKey])
        guard attrs.isSymbolicLink != true, attrs.isRegularFile == true, (attrs.fileSize ?? Int.max) <= limit else { throw SnapError.storage }
        return try Data(contentsOf: url)
    }
    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        let fd = open(root.appendingPathComponent("outbox.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SnapError.storage }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw SnapError.storage }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
