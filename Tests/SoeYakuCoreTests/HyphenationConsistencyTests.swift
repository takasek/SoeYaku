import CoreGraphics
import Testing

@testable import SoeYakuCore

/// The PDF paragraph, the frame paragraph and the locator's OCR query must tokenize a two-line text alike,
/// because the PDF index is built from the ReadingOrder text and the other two are matched against it.
struct HyphenationConsistencyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let first: String
        let second: String
        var testDescription: String { "\(first.debugDescription) / \(second.debugDescription)" }
    }

    static let cases: [Case] = ["a transla", "pages 3", "a café", "a word ", "a word"].flatMap { ending in
        ["", "-"].flatMap { hyphen in
            ["tion of text", "Known author", "5 apply", "(see below)"].map { Case(first: ending + hyphen, second: $0) }
        }
    }

    /// The tokens of the two lines as one ReadingOrder paragraph; fails unless they do form exactly one paragraph.
    private func readingOrderTokens(_ c: Case) -> [String] {
        let flow = [
            line(c.first, x: 72, top: 700, width: 468),
            line(c.second, x: 72, top: 686, width: 468),
        ]
        let paragraphs = ReadingOrder.paragraphs(flow, pageBounds: [letter]).map(\.text)
        #expect(paragraphs.count == 1, "the two lines must form one paragraph")
        return TextNormalizer.tokens(paragraphs.first ?? "")
    }

    @Test(arguments: cases)
    func frameParagraphTokenizesLikeReadingOrder(_ c: Case) {
        let blocks = FrameText.blocks(from: [
            TextLine(text: c.first, box: CGRect(x: 0.1, y: 0.1, width: 0.65, height: 0.05)),
            TextLine(text: c.second, box: CGRect(x: 0.1, y: 0.16, width: 0.65, height: 0.05)),
        ])
        #expect(blocks.count == 1, "the two lines must form one block")
        #expect(TextNormalizer.tokens(blocks.first?.text ?? "") == readingOrderTokens(c))
    }

    @Test(arguments: cases)
    func locatorQueryTokenizesLikeReadingOrder(_ c: Case) {
        let lines = [c.first, c.second].map { (text: $0, tokens: TextNormalizer.tokens($0)) }
        #expect(Locator.joinedQuery(lines).0 == readingOrderTokens(c))
    }
}
