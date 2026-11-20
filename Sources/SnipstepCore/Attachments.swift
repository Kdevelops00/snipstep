import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

public struct CaptureManifest: Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let mode: ProcessingMode
    public let fileExtension: String
    public init(id: UUID, createdAt: Date, mode: ProcessingMode, fileExtension: String) {
        self.id = id; self.createdAt = createdAt; self.mode = mode; self.fileExtension = fileExtension
    }
}

public enum ImageFiles {
    public static let maximumBytes = 100_000_000
    public static let maximumPixels = 50_000_000

    public static func inspect(_ data: Data) throws -> String {
        guard data.count <= maximumBytes else { throw SnapError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else { throw SnapError.invalidImage }
        guard width <= maximumPixels / height else { throw SnapError.imageTooLarge }
        switch type as String {
        case UTType.png.identifier: return "png"
        case UTType.jpeg.identifier: return "jpg"
        case UTType.heic.identifier: return "heic"
        default: throw SnapError.invalidImage
        }
    }

    public static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw SnapError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapError.invalidImage }
        return data as Data
    }

    public static func thumbnail(url: URL, pixels: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw SnapError.invalidImage }
        return image
    }
}

public actor AttachmentStore {
    public nonisolated let root: URL
    private let fm = FileManager.default
    private let allowedExtensions: Set<String> = ["png", "jpg", "heic"]

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    public func save(_ data: Data, id: UUID = UUID(), mode: ProcessingMode, createdAt: Date = .now) throws -> CaptureManifest {
        let ext = try ImageFiles.inspect(data)
        let manifest = CaptureManifest(id: id, createdAt: createdAt, mode: mode, fileExtension: ext)
        let staging = root.appendingPathComponent(".staging-" + id.uuidString, isDirectory: true)
        let final = directory(id)
        guard !fm.fileExists(atPath: final.path), !fm.fileExists(atPath: staging.path) else { throw SnapError.storage }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try durableWrite(JSONEncoder().encode(manifest), to: staging.appendingPathComponent("pending.json"))
            try durableWrite(data, to: staging.appendingPathComponent("original." + ext))
            try synchronizeDirectory(staging)
            try fm.moveItem(at: staging, to: final)
            try synchronizeDirectory(root)
            return manifest
        } catch { throw SnapError.storage }
    }

    public func finishCommit(_ id: UUID) throws {
        let folder = try checkedDirectory(id)
        let manifest = folder.appendingPathComponent("pending.json")
        if fm.fileExists(atPath: manifest.path) {
            try fm.removeItem(at: manifest)
            try synchronizeDirectory(folder)
        }
    }

    public func recoverableCaptures() throws -> [CaptureManifest] {
        var results: [CaptureManifest] = []
        let folders = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        for folder in folders {
            let name = folder.lastPathComponent
            let isStaging = name.hasPrefix(".staging-")
            let idText = isStaging ? String(name.dropFirst(".staging-".count)) : name
            guard let id = UUID(uuidString: idText) else { continue }
            let properties = try folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard properties.isSymbolicLink != true, properties.isDirectory == true else { throw SnapError.storage }
            let marker = folder.appendingPathComponent("pending.json")
            guard fm.fileExists(atPath: marker.path) else { continue }
            try rejectSymlink(marker)
            let markerSize = try marker.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard markerSize < 16_384 else { throw SnapError.storage }
            let manifest = try JSONDecoder().decode(CaptureManifest.self, from: Data(contentsOf: marker))
            guard manifest.id == id, allowedExtensions.contains(manifest.fileExtension) else { throw SnapError.storage }
            let original = folder.appendingPathComponent("original." + manifest.fileExtension)
            // An incomplete staging write was never reported saved; keep it for diagnosis, never fabricate a task.
            guard fm.fileExists(atPath: original.path) else {
                if isStaging { continue }
                throw SnapError.storage
            }
            try rejectSymlink(original)
            if isStaging {
                guard !fm.fileExists(atPath: directory(id).path) else { throw SnapError.storage }
                try fm.moveItem(at: folder, to: directory(id))
                try synchronizeDirectory(root)
            }
            results.append(manifest)
        }
        return results
    }

    public func originalURL(id: UUID, fileExtension: String) throws -> URL {
        guard allowedExtensions.contains(fileExtension) else { throw SnapError.storage }
        let url = try checkedDirectory(id).appendingPathComponent("original." + fileExtension)
        try rejectSymlink(url)
        return url
    }

    public func preview(id: UUID, fileExtension: String, pixels: Int) throws -> Data {
        let original = try originalURL(id: id, fileExtension: fileExtension)
        return try ImageFiles.png(ImageFiles.thumbnail(url: original, pixels: pixels))
    }

    public func widgetPreview(id: UUID, fileExtension: String) throws -> Data {
        let original = try originalURL(id: id, fileExtension: fileExtension)
        let image = try ImageFiles.thumbnail(url: original, pixels: 360)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw SnapError.storage }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 100_000 else { throw SnapError.storage }
        return output as Data
    }

    public func cloudImage(id: UUID, fileExtension: String) throws -> Data {
        let original = try originalURL(id: id, fileExtension: fileExtension)
        let data = try Data(contentsOf: original, options: .mappedIfSafe)
        _ = try ImageFiles.inspect(data)
        // Strip metadata while retaining every pixel; the original bytes remain untouched on disk.
        return try ImageFiles.png(ImageFiles.thumbnail(url: original, pixels: ImageFiles.maximumPixels))
    }

    public func remove(_ id: UUID) throws {
        let url = directory(id)
        guard fm.fileExists(atPath: url.path) else { return }
        _ = try checkedDirectory(id)
        try fm.removeItem(at: url)
        try synchronizeDirectory(root)
    }

    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func checkedDirectory(_ id: UUID) throws -> URL {
        let url = directory(id)
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { throw SnapError.storage }
        return url
    }
    private func rejectSymlink(_ url: URL) throws {
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw SnapError.storage }
    }
    private func durableWrite(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
    }
    private func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw SnapError.storage }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw SnapError.storage }
    }
}
