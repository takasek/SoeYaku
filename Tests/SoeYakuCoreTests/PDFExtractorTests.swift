import Foundation
import Testing

@testable import SoeYakuCore

private typealias Block = FixturePDF.Block

private let leftColumn = CGRect(x: 72, y: 100, width: 220, height: 570)
private let rightColumn = CGRect(x: 320, y: 100, width: 220, height: 570)

private let leftText =
    "Machine translation has improved quickly over the last decade. "
    + "The \u{FB01}rst systems relied on hand written rules and large dictionaries. "
    + "Modern systems learn from parallel text, and the quality of the transla-\n"
    + "tion depends mostly on the amount of data. "
    + "A good reader wants to follow the original text while the"

private let rightText =
    "translation keeps pace with the page. "
    + "Therefore the whole document is translated before reading begins. "
    + "Each sentence is shown beside its source so that the reader can check the meaning quickly. "
    + "The window follows the position of the reader and highlights the sentence that is currently"

private func running(_ pageNumber: Int) -> [Block] {
    [
        Block(text: "Running Header", rect: CGRect(x: 72, y: 745, width: 468, height: 20), fontSize: 10),
        Block(text: "\(pageNumber)", rect: CGRect(x: 290, y: 30, width: 40, height: 20), fontSize: 10),
    ]
}

/// Three pages: a title and two columns (page 1), a sentence continued from page 1 and a heading (page 2), one paragraph (page 3).
/// With `rightColumnFirst` the right column is drawn into the PDF before the left one.
private func mainFixture(rightColumnFirst: Bool, title: String? = "Fixture Title") throws -> URL {
    let titleBlock = Block(text: "A Study of Document Translation", rect: CGRect(x: 72, y: 690, width: 468, height: 40), fontSize: 20)
    let left = Block(text: leftText, rect: leftColumn)
    let right = Block(text: rightText, rect: rightColumn)
    let page1 = running(1) + [titleBlock] + (rightColumnFirst ? [right, left] : [left, right])
    let page2 =
        running(2) + [
            Block(text: "visible in the preview application.", rect: CGRect(x: 72, y: 690, width: 468, height: 20)),
            Block(text: "Results", rect: CGRect(x: 72, y: 650, width: 468, height: 28), fontSize: 16),
            Block(
                text: "The system translated every sentence in the test document. "
                    + "Most sentences were translated correctly with an e\u{FB03}cient model. "
                    + "Nothing was lost between the pages.",
                rect: CGRect(x: 72, y: 520, width: 468, height: 110)),
        ]
    let page3 =
        running(3) + [
            Block(
                text: "This short page closes the example. It has only one paragraph with two sentences.",
                rect: CGRect(x: 72, y: 600, width: 468, height: 100))
        ]
    return try FixturePDF.writeTemporary(pages: [page1, page2, page3], title: title, name: "main")
}

private func rows(_ document: SourceDocument) -> [String] {
    document.sentences.map { "\($0.id)|\($0.paragraph)|\($0.page)|\($0.text)" }
}

@Suite struct PDFExtractorTests {
    @Test func extractsBodySentencesInReadingOrder() throws {
        let url = try mainFixture(rightColumnFirst: true)
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
                "8|2|1|Results",
                "9|3|1|The system translated every sentence in the test document.",
                "10|3|1|Most sentences were translated correctly with an efficient model.",
                "11|3|1|Nothing was lost between the pages.",
                "12|4|2|This short page closes the example.",
                "13|4|2|It has only one paragraph with two sentences.",
            ])
    }

    @Test func drawOrderDoesNotChangeTheResult() throws {
        let rightFirst = try mainFixture(rightColumnFirst: true)
        let leftFirst = try mainFixture(rightColumnFirst: false)
        defer {
            try? FileManager.default.removeItem(at: rightFirst.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: leftFirst.deletingLastPathComponent())
        }
        #expect(try PDFExtractor.extract(url: rightFirst).sentences == PDFExtractor.extract(url: leftFirst).sentences)
    }

    @Test func leftColumnSentencesPrecedeRightColumnSentences() throws {
        let url = try mainFixture(rightColumnFirst: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sentences = try PDFExtractor.extract(url: url).sentences
        func id(containing text: String) throws -> Int {
            try #require(sentences.first { $0.text.contains(text) }).id
        }
        #expect(try id(containing: "decade") < id(containing: "Therefore"))
        #expect(try id(containing: "dictionaries") < id(containing: "Each sentence"))
    }

    @Test func runningHeaderAndPageNumbersAreNotSentences() throws {
        let url = try mainFixture(rightColumnFirst: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let texts = try PDFExtractor.extract(url: url).sentences.map(\.text)
        #expect(!texts.contains { $0.contains("Running Header") })
        #expect(!texts.contains { $0.allSatisfy(\.isNumber) })
    }

    @Test func headingIsItsOwnParagraph() throws {
        let url = try mainFixture(rightColumnFirst: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let sentences = try PDFExtractor.extract(url: url).sentences
        let heading = try #require(sentences.first { $0.text == "Results" })
        #expect(sentences.filter { $0.paragraph == heading.paragraph }.count == 1)
    }

    @Test func sentenceCrossingAColumnAndAPageIsOneSentence() throws {
        let url = try mainFixture(rightColumnFirst: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let texts = try PDFExtractor.extract(url: url).sentences.map(\.text)
        #expect(texts.contains("A good reader wants to follow the original text while the translation keeps pace with the page."))
        #expect(texts.contains { $0.hasSuffix("currently visible in the preview application.") })
    }

    @Test func fingerprintIsTheSHA256OfTheFile() throws {
        let url = try mainFixture(rightColumnFirst: false)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let document = try PDFExtractor.extract(url: url)
        #expect(document.fingerprint == SourceDocument.fingerprint(of: try Data(contentsOf: url)))
    }

    @Test func titleComesFromThePDFAttribute() throws {
        let url = try mainFixture(rightColumnFirst: false, title: "Fixture Title")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(try PDFExtractor.extract(url: url).title == "Fixture Title")
    }

    @Test func titleFallsBackToTheFileNameWithoutExtension() throws {
        let url = try mainFixture(rightColumnFirst: false, title: nil)
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
