import CoreGraphics
import Foundation
import PDFKit
import SoeYakuCore
import SoeYakuTestSupport
import Testing

@testable import SoeYakuCLIKit

private struct FakeTranslator: SentenceTranslator {
    func translate(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) async throws -> String {
        if source == "Results" { throw Failure() }
        return "訳:" + source
    }

    struct Failure: Error {}
}

private func object(_ line: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
}

private func withFixture<T>(_ body: (URL) async throws -> T) async throws -> T {
    let url = try MainFixture.write(rightColumnFirst: false)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    return try await body(url)
}

struct CommandsTests {
    @Test func extractPrintsOneJSONObjectPerSentence() async throws {
        let lines = try await withFixture { try CLI.extractLines(file: $0) }
        #expect(lines.count == 15)
        #expect(lines[0] == #"{"id":0,"paragraph":0,"page":0,"text":"A Study of Document Translation"}"#)
        let last = try object(lines[14])
        #expect(last["id"] as? Int == 14 && last["page"] as? Int == 2 && last["paragraph"] as? Int == 4)
        #expect(last["text"] as? String == "It has only one paragraph with two sentences.")
    }

    @Test func translatePrintsIdEnJaAndNullForAFailedSentence() async throws {
        let memory = FileManager.default.temporaryDirectory.appending(path: "memory-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: memory) }
        let progress = ProgressLog()
        let lines = try await withFixture { url in
            try await CLI.translateLines(
                TranslateOptions(file: url.path, port: 1, memory: memory.path, model: "m"),
                translator: FakeTranslator(), progress: { await progress.add($0) })
        }
        #expect(lines.count == 15)
        #expect(lines[0] == #"{"id":0,"en":"A Study of Document Translation","ja":"訳:A Study of Document Translation"}"#)
        let heading = try object(lines[9])
        #expect(heading["en"] as? String == "Results")
        #expect(heading["ja"] is NSNull)
        #expect(try object(lines[10])["ja"] as? String == "訳:The system translated every sentence in the test document.")
        #expect(await progress.last == TranslationProgress(done: 14, failed: 1, total: 15))
    }

    @Test func aSecondTranslateRunReusesTheSavedMemory() async throws {
        let memory = FileManager.default.temporaryDirectory.appending(path: "memory-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: memory) }
        let url = try MainFixture.write(rightColumnFirst: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let options = TranslateOptions(file: url.path, port: 1, memory: memory.path, model: "m")
        _ = try await CLI.translateLines(options, translator: FakeTranslator(), progress: { _ in })
        let again = try await CLI.translateLines(options, translator: RefusingTranslator(), progress: { _ in })
        // The failed heading is not saved, so only it is asked for again.
        #expect(try object(again[0])["ja"] as? String == "訳:A Study of Document Translation")
        #expect(try object(again[9])["ja"] is NSNull)
    }

    @Test func glossaryFilesDefaultToTheCommonThenTheDocumentOneWhenTheyExist() {
        let common = StoragePaths.commonGlossary, document = StoragePaths.documentGlossary(for: "fp")
        #expect(CLI.glossaryFiles(given: [], fingerprint: "fp", exists: { _ in true }) == [common, document])
        #expect(CLI.glossaryFiles(given: [], fingerprint: "fp", exists: { $0 == document }) == [document])
        #expect(CLI.glossaryFiles(given: [], fingerprint: "fp", exists: { _ in false }).isEmpty)
        #expect(
            CLI.glossaryFiles(given: ["/x/a.txt", "/x/b.txt"], fingerprint: "fp", exists: { _ in true })
                == [URL(fileURLWithPath: "/x/a.txt"), URL(fileURLWithPath: "/x/b.txt")])
    }

    @Test(.timeLimit(.minutes(3)))
    func locatePrintsTheMatchedSentenceForAPointerOnARenderedPage() async throws {
        let pdf = try MainFixture.write(rightColumnFirst: false)
        let png = pdf.deletingLastPathComponent().appending(path: "page.png")
        defer { try? FileManager.default.removeItem(at: pdf.deletingLastPathComponent()) }
        let document = try #require(PDFDocument(url: pdf))
        let page = try #require(document.page(at: 1))
        let image = try PageImage.render(page)
        try PageImage.writePNG(image, to: png)
        let heading = try #require(document.findString("Results", withOptions: []).first?.bounds(for: page))
        // Page space is bottom-left in points; the image is top-left in pixels at 2x.
        let pointer = CGPoint(x: heading.midX * 2, y: (page.bounds(for: .mediaBox).height - heading.midY) * 2)
        let line = try await CLI.locateLine(file: pdf, image: png, pointer: pointer)
        let result = try object(line)
        #expect(result["status"] as? String == "matched")
        #expect(result["sentence"] as? Int == 9)
        #expect(result["text"] as? String == "Results")
        #expect((result["confidence"] as? Double ?? 0) > 0)
    }

    @Test(.timeLimit(.minutes(3)))
    func locatePrintsUnresolvedWhenNothingMatches() async throws {
        let pdf = try MainFixture.write(rightColumnFirst: false)
        let png = pdf.deletingLastPathComponent().appending(path: "blank.png")
        defer { try? FileManager.default.removeItem(at: pdf.deletingLastPathComponent()) }
        let context = try #require(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        try PageImage.writePNG(try #require(context.makeImage()), to: png)
        #expect(try await CLI.locateLine(file: pdf, image: png, pointer: CGPoint(x: 10, y: 10)) == #"{"status":"unresolved"}"#)
    }

    @Test func anUnreadableImageIsAJapaneseError() async throws {
        let pdf = try MainFixture.write(rightColumnFirst: false)
        defer { try? FileManager.default.removeItem(at: pdf.deletingLastPathComponent()) }
        let missing = pdf.deletingLastPathComponent().appending(path: "none.png")
        await #expect(throws: CLIError.self) { try await CLI.locateLine(file: pdf, image: missing, pointer: .zero) }
        #expect(CLIError.unreadableImage(missing.path).errorDescription == "画像を読み込めませんでした: \(missing.path)")
    }
}

private actor ProgressLog {
    private(set) var last: TranslationProgress?
    func add(_ progress: TranslationProgress) { last = progress }
}

private struct RefusingTranslator: SentenceTranslator {
    func translate(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) async throws -> String {
        struct Refused: Error {}
        throw Refused()
    }
}
