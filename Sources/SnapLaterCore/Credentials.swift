import Foundation
import Security

public struct KeychainCredentialStore: Sendable {
    private let service: String
    public init(service: String = "org.snaplater.local.gemini") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "user-api-key",
         kSecAttrSynchronizable as String: false]
    }
    public func read() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw SnapError.keyUnavailable
        }
        return key
    }
    public func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512,
              key.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }) else {
            throw SnapError.keyUnavailable
        }
        let changes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query.merging(changes) { _, new in new }
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw SnapError.keyUnavailable }
        } else if status != errSecSuccess { throw SnapError.keyUnavailable }
    }
    public func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw SnapError.keyUnavailable }
    }
}

public enum DevelopmentCredential {
    public static func read(from source: URL) throws -> String {
        let properties = try source.resourceValues(forKeys: [.isDirectoryKey])
        let files = properties.isDirectory == true
            ? try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            : [source]
        var values: [String] = []
        for file in files {
            guard let attrs = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]),
                  attrs.isRegularFile == true, attrs.isSymbolicLink != true, (attrs.fileSize ?? Int.max) <= 2_000_000,
                  let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: .newlines) where line.hasPrefix("Gemi_APi_key=") {
                let value = String(line.dropFirst("Gemi_APi_key=".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !value.isEmpty { values.append(value) }
            }
        }
        guard values.count == 1 else { throw SnapError.invalidCredentialFile }
        return values[0]
    }
}
