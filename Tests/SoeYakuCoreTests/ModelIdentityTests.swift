import Foundation
import Testing
@testable import SoeYakuCore

struct ModelIdentityTests {
    @Test func identityFollowsContentsAcrossSameNamesMovesAndReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "model-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "a/model.gguf"), second = directory.appending(path: "b/model.gguf")
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let original = try ModelIdentity.forFile(first)
        #expect(original != (try ModelIdentity.forFile(second)))
        try Data("first".utf8).write(to: second)
        #expect(original == (try ModelIdentity.forFile(second)))
        try Data("third".utf8).write(to: first)
        #expect(original != (try ModelIdentity.forFile(first)))
    }

    @Test func identityIsTheLowercaseSHA256HexOfTheContents() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "golden-\(UUID().uuidString).gguf")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        #expect(try ModelIdentity.forFile(url)
            == "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    private func temporaryModel(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "cache-\(UUID().uuidString).gguf")
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// A whole-second date survives the round trip through `Date` exactly, unlike a file system timestamp read back.
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test func cacheReturnsTheOldIdentityWhenPathSizeAndDateAreUnchanged() async throws {
        let url = try temporaryModel("abc")
        defer { try? FileManager.default.removeItem(at: url) }
        try setModificationDate(fixedDate, of: url)
        let cache = ModelIdentityCache()
        let first = try await cache.identity(for: url)
        #expect(first == (try ModelIdentity.forFile(url)))
        try Data("xyz".utf8).write(to: url)
        try setModificationDate(fixedDate, of: url)
        #expect(try await cache.identity(for: url) == first)
    }

    @Test func cacheRecomputesWhenTheModificationDateChanges() async throws {
        let url = try temporaryModel("abc")
        defer { try? FileManager.default.removeItem(at: url) }
        try setModificationDate(fixedDate, of: url)
        let cache = ModelIdentityCache()
        let first = try await cache.identity(for: url)
        try Data("xyz".utf8).write(to: url)
        try setModificationDate(fixedDate.addingTimeInterval(3600), of: url)
        let second = try await cache.identity(for: url)
        #expect(second != first)
        #expect(second == (try ModelIdentity.forFile(url)))
    }

    @Test func cacheNeverCachesAFailure() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).gguf")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = ModelIdentityCache()
        await #expect(throws: (any Error).self) { try await cache.identity(for: url) }
        await #expect(throws: (any Error).self) { try await cache.identity(for: url) }
        try Data("abc".utf8).write(to: url)
        #expect(try await cache.identity(for: url) == (try ModelIdentity.forFile(url)))
    }
}
