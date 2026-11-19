import Foundation
import CryptoKit

public enum GGUFImport {
    public static let maximumBytes = 4_000_000_000
    /// Bounded-memory fingerprinting; the chosen source is never changed or copied by SnapLater.
    public static func digest(of url: URL) throws -> (digest: String, size: Int) {
        let attrs = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attrs.isRegularFile == true, attrs.isSymbolicLink != true,
              let size = attrs.fileSize, size >= 24, size <= maximumBytes else { throw SnapError.invalidModelFile }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard try file.read(upToCount: 4) == Data("GGUF".utf8) else { throw SnapError.invalidModelFile }
        try file.seek(toOffset: 0)
        var hash = SHA256()
        var total = 0
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            total += chunk.count
            guard total <= maximumBytes else { throw SnapError.invalidModelFile }
            hash.update(data: chunk)
        }
        guard total == size else { throw SnapError.invalidModelFile }
        return ("sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined(), size)
    }
}
