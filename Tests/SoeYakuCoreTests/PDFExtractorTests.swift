import Foundation
import Testing
import SoeYakuTestSupport
@testable import SoeYakuCore

private func rows(_ document: SourceDocument) -> [String] {
    document.sentences.map { "\($0.id)|\($0.paragraph)|\($0.page)|\($0.text)" }
}

@Suite struct PDFExtractorTests {
    @Test func extractsBodySentencesInReadingOrder() throws {
        let url = try MainFixture.write(rightColumnFirst: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try PDFExtractor.extract(url: url)
        #expect(
            rows(document) == [
                "0|0|0|A Study of Document Translation",
                "1|1|0|Machine translation has improved quickly over the last decade.",
                "2|1|0|The first systems relied on hand written rules and large dictionaries.",
                "3|1|0|Modern systems learn from parallel text, and the quality of the translation depends mostly on the amount of data.",
                "4|1|0|A good reader wants to follow the original text while the translation keeps pace with the page.",
                "5|1|0|Therefore the whole document is translated before reading begins.",
                "6|1|0|Each sentence is shown beside its source so that the reader can check the meaning quickly.",
                "7|1|0|The window follows the position of the reader and highlights the sentence that is currently visible in the preview application.",
                "8|1|1|Scrolling the document moves the highlight.",
                "9|2|1|Results",
                "10|3|1|The system translated every sentence in the test document.",
                "11|3|1|Most sentences were translated correctly with an efficient model.",
                "12|3|1|Nothing was lost between the pages.",
                "13|4|2|This short page closes the example.",
                "14|4|2|It has only one paragraph with two sentences.",
            ])
    }

    @Test func drawOrderDoesNotChangeTheResult() throws {
        let rightFirst = try MainFixture.write(rightColumnFirst: true)
        let leftFirst = try MainFixture.write(rightColumnFirst: false)
        defer {
            try? FileManager.default.removeItem(at: rightFirst.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: leftFirst.deletingLastPathComponent())
        }
        #expect(try PDFExtractor.extract(url: rightFirst).sentences == PDFExtractor.extract(url: leftFirst).sentences)
    }

    @Test func leftColumnSentencesPrecedeRightColumnSentences() throws {
        let url = try MainFixture.write(rightColumnFirst: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sentences = try PDFExtractor.extract(url: url).sentences
        func id(containing text: String) throws -> Int {
            try #require(sentences.first { $0.text.contains(text) }).id
        }
        #expect(try id(containing: "decade") < id(containing: "Therefore"))
        #expect(try id(containing: "dictionaries") < id(containing: "Each sentence"))
    }

    @Test func runningHeaderAndPageNumbersAreNotSentences() throws {
        let url = try MainFixture.write(rightColumnFirst: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let texts = try PDFExtractor.extract(url: url).sentences.map(\.text)
        #expect(!texts.contains { $0.contains("Running Header") })
        #expect(!texts.contains { $0.allSatisfy(\.isNumber) })
    }

    @Test func headingIsItsOwnParagraph() throws {
        let url = try MainFixture.write(rightColumnFirst: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sentences = try PDFExtractor.extract(url: url).sentences
        let heading = try #require(sentences.first { $0.text == "Results" })
        #expect(sentences.filter { $0.paragraph == heading.paragraph }.count == 1)
    }

    @Test func sentenceCrossingAColumnAndAPageIsOneSentence() throws {
        let url = try MainFixture.write(rightColumnFirst: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let texts = try PDFExtractor.extract(url: url).sentences.map(\.text)
        #expect(texts.contains("A good reader wants to follow the original text while the translation keeps pace with the page."))
        #expect(texts.contains { $0.hasSuffix("currently visible in the preview application.") })
    }

    @Test func fingerprintIsTheSHA256OfTheFile() throws {
        let url = try MainFixture.write(rightColumnFirst: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try PDFExtractor.extract(url: url)
        #expect(document.fingerprint == SourceDocument.fingerprint(of: try Data(contentsOf: url)))
    }

    @Test func titleComesFromThePDFAttribute() throws {
        let url = try MainFixture.write(rightColumnFirst: false, title: "Fixture Title")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try PDFExtractor.extract(url: url).title == "Fixture Title")
    }

    @Test func titleFallsBackToTheFileNameWithoutExtension() throws {
        let url = try MainFixture.write(rightColumnFirst: false, title: nil)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try PDFExtractor.extract(url: url).title == "main")
    }

    @Test func aPDFWithoutTextFailsWithAJapaneseMessage() throws {
        let url = try FixturePDF.writeTemporary(pages: [[]], name: "blank")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(throws: PDFExtractionError.noText) { try PDFExtractor.extract(url: url) }
        #expect(PDFExtractionError.noText.errorDescription == "この PDF には文字情報がありません。")
    }

    @Test func aFileThatIsNotAPDFFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.pdf")
        try Data("plain text".utf8).write(to: url)
        #expect(throws: PDFExtractionError.unreadable) { try PDFExtractor.extract(url: url) }
    }
}
