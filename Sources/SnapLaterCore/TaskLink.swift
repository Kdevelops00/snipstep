import Foundation

/// The legacy URL scheme stays stable for existing widgets and installations.
public enum TaskLink: Equatable, Sendable {
    case newTask
    case detail(UUID)

    public init?(url: URL) {
        guard url.scheme == "snaplater", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        if url.host == "new-task", url.path.isEmpty || url.path == "/" {
            self = .newTask
        } else if url.host == "task", url.pathComponents.count == 2,
                  let id = UUID(uuidString: url.lastPathComponent) {
            self = .detail(id)
        } else { return nil }
    }

    public var url: URL {
        switch self {
        case .newTask: URL(string: "snaplater://new-task")!
        case .detail(let id): URL(string: "snaplater://task/\(id.uuidString)")!
        }
    }
}
