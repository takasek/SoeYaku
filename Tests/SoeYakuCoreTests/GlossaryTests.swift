import Foundation
import Testing
@testable import SoeYakuCore

struct GlossaryTests {
    private func load(_ files: [String]) throws -> Glossary {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = try files.enumerated().map { index, contents in
            let url = folder.appending(path: "\(index).tsv")
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }
        return try Glossary.load(urls)
    }

    @Test func parsesTSVAndEqualsLinesIgnoringCommentsAndLaterLinesOverride() throws {
        let glossary = try Glossary.parse("agent\tエージェント\nspeech recognition = 音声認識\n# c\n\nAgent = 代理人", name: "g.txt")
        #expect(glossary.terms == [GlossaryTerm("speech recognition", "音声認識"), GlossaryTerm("Agent", "代理人")])
    }

    @Test func splitsEqualsLinesAtTheFirstEquals() throws {
        let glossary = try Glossary.parse("a = b = c", name: "g.txt")
        #expect(glossary.terms == [GlossaryTerm("a", "b = c")])
    }

    @Test func malformedLineNamesTheFileAndLineNumber() {
        for text in ["x =", "= y", "x\t", "missing separator"] {
            do {
                _ = try Glossary.parse("# note\n\n" + text, name: "g.txt")
                Issue.record("Malformed glossary was accepted: \(text)")
            } catch {
                #expect(error.localizedDescription.contains("g.txt"))
                #expect(error.localizedDescription.contains("3"))
            }
        }
    }

    @Test func overlayReplacesCaseInsensitivelyAndMovesTheTermToTheEnd() throws {
        var base = try Glossary.parse("App = アプリ\nSwift = 鳥", name: "a")
        base.overlay(try Glossary.parse("swift = スウィフト", name: "b"))
        #expect(base.terms == [GlossaryTerm("App", "アプリ"), GlossaryTerm("swift", "スウィフト")])
    }

    @Test func loadOverlaysFilesInOrderAndRejectsRemoteURLs() throws {
        let glossary = try load(["App\tアプリ\nSwift\t鳥", "swift\tスウィフト"])
        #expect(glossary.terms == [GlossaryTerm("App", "アプリ"), GlossaryTerm("swift", "スウィフト")])
        #expect(throws: (any Error).self) { try Glossary.load([URL(string: "https://example.com/g.tsv")!]) }
    }

    @Test func termsMatchOnWordBoundariesIgnoringCase() {
        let term = GlossaryTerm("app", "アプリ")
        #expect(term.occurs(in: "An App runs."))
        #expect(!term.occurs(in: "It happens."))
        #expect(GlossaryTerm("C++", "シープラプラ").occurs(in: "Use C++ here"))
    }

    @Test func kikiyakuTextListsOnlyOccurringTermsInGlossaryOrder() throws {
        let glossary = try Glossary.parse("agent\tエージェント\nspeech recognition = 音声認識\nAgent = 代理人", name: "g.txt")
        #expect(glossary.kikiyakuText(appliedTo: ["The agent runs."]) == "Agent = 代理人\n")
        #expect(glossary.kikiyakuText(appliedTo: ["Speech recognition and the agent.", "x"])
            == "speech recognition = 音声認識\nAgent = 代理人\n")
        #expect(glossary.kikiyakuText(appliedTo: ["nothing"]) == "")
        #expect(glossary.matches(in: "agent").map(\.target) == ["代理人"])
    }

    @Test func kikiyakuTextDoesNotMatchATermSplitAcrossTwoTexts() throws {
        let glossary = try Glossary.parse("speech recognition = 音声認識", name: "g.txt")
        #expect(glossary.kikiyakuText(appliedTo: ["speech", "recognition"]) == "")
    }
}
