import Foundation
import Testing
@testable import SnipstepCore

@Test func modelImportRejectsWrongFormatAndSymlinksWithoutChangingOriginal() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("model.gguf")
    let data = Data("GGUF".utf8) + Data(repeating: 0, count: 24)
    try data.write(to: file)
    let hash = try GGUFImport.digest(of: file)
    #expect(hash.size == 28)
    #expect(hash.digest.hasPrefix("sha256:"))
    #expect(hash.digest.count == 71)
    #expect(try Data(contentsOf: file) == data)
    let symlink = root.appendingPathComponent("link.gguf")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
    #expect(throws: SnapError.invalidModelFile) { try GGUFImport.digest(of: symlink) }
    try Data(repeating: 1, count: 28).write(to: file)
    #expect(throws: SnapError.invalidModelFile) { try GGUFImport.digest(of: file) }
}

@Test func missingWidgetSnapshotIsDifferentFromAnEmptySyncedLibrary() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try WidgetStore(root: root)
    #expect(try store.read().updatedAt == nil)
    try store.write(.init())
    #expect(try store.read().updatedAt != nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SNAPLATER_IMPORT_SMOKE_SOURCE"] != nil))
func importExistingGGUFThroughLocalOllama() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["SNAPLATER_IMPORT_SMOKE_SOURCE"])
    let client = LocalAIClient(model: "")
    let name = try await client.importGGUF(from: URL(fileURLWithPath: path))
    try await LocalAIClient(model: name).verifyModel()
    #expect(name.hasPrefix("snaplater-"))
    print("Local GGUF import and model registration verified.")
}

private final class ImportProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        #expect(request.url?.host == "127.0.0.1")
        var status = 200
        var body = Data()
        if request.httpMethod == "HEAD" { status = 404 }
        else if request.url!.path.contains("/blobs/") {
            let stream = request.httpBodyStream!
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 16)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            #expect(data == Data("GGUF".utf8) + Data(repeating: 0, count: 24))
            status = 201
        } else { body = Data(#"{"status":"success"}"#.utf8) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@Test func selectedGGUFIsStreamedOnlyToLoopbackAndRegistered() async throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
    defer { try? FileManager.default.removeItem(at: file) }
    try (Data("GGUF".utf8) + Data(repeating: 0, count: 24)).write(to: file)
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ImportProtocol.self]
    let client = LocalAIClient(model: "", session: URLSession(configuration: config))
    let name = try await client.importGGUF(from: file)
    #expect(name.hasPrefix("snaplater-"))
    #expect(try Data(contentsOf: file).count == 28)
}
