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
}
