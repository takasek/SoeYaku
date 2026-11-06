import Foundation
import Testing
@testable import SoeYakuCore

private func temporaryFile(_ name: String = "memory.json") -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: name)
}

struct TranslationMemoryTests {
    @Test func keyIsSHA256OfNormalizedSourceTermsAndModel() {
        let key = TranslationMemory.key(source: "  a \n\t b ", terms: [GlossaryTerm("x", "y")], model: "m")
        #expect(key == "348a84823b0b6a954979b3b1fb5efc60b80ff3d9c6dc5a71af65187a16835d6f")
    }

    @Test func keyChangesWithTermsAndModel() {
        let base = TranslationMemory.key(source: "a", terms: [], model: "m")
        #expect(base != TranslationMemory.key(source: "a", terms: [GlossaryTerm("x", "y")], model: "m"))
        #expect(base != TranslationMemory.key(source: "a", terms: [], model: "n"))
        #expect(base == TranslationMemory.key(source: "a", terms: [], model: "m"))
    }

    @Test func savesVersionedJSONAndRoundTripsCreatingParentDirectories() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var memory = TranslationMemory()
        memory["k"] = "訳"
        try memory.save(to: url)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary
        #expect(object == ["version": 1, "entries": ["k": "訳"]] as NSDictionary)
        #expect(try TranslationMemory.load(from: url) == memory)
    }

    @Test func loadingAMissingFileGivesAnEmptyMemory() throws {
        #expect(try TranslationMemory.load(from: temporaryFile()) == TranslationMemory())
    }
}
