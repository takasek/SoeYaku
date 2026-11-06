import Foundation
import Testing
@testable import SoeYakuCore

struct ReadingTextTests {
    private let document = SourceDocument(fingerprint: "f", title: "T", sentences: [
        Sentence(id: 0, paragraph: 0, page: 0, text: "First."),
        Sentence(id: 1, paragraph: 0, page: 0, text: "Second."),
        Sentence(id: 2, paragraph: 1, page: 0, text: "Third."),
        Sentence(id: 3, paragraph: 1, page: 1, text: "Fourth.")
    ])

    @Test func joinsJapaneseSentencesWithoutSpaceAndParagraphsWithNewline() {
        let text = ReadingText(document: document, translations: ["一。", "二。", "三。", "四。"])
        #expect(text.string == "一。二。\n三。四。")
        #expect(text.runs.map(\.range) == [NSRange(location: 0, length: 2), NSRange(location: 2, length: 2),
                                         NSRange(location: 5, length: 2), NSRange(location: 7, length: 2)])
        #expect(text.runs.map(\.translated) == [true, true, true, true])
    }

    @Test func showsSourceForUntranslatedSentencesSeparatedBySpace() {
        let text = ReadingText(document: document, translations: ["一。", nil, nil, "四。"])
        #expect(text.string == "一。Second.\nThird. 四。")
        #expect(text.runs.map(\.translated) == [true, false, false, true])
        #expect(text.runs[2].range == NSRange(location: 10, length: 6))
        #expect(text.runs[3].range == NSRange(location: 17, length: 2))
    }

    @Test func rangesUseUTF16OffsetsForTextKit() {
        let single = SourceDocument(fingerprint: "f", title: "T", sentences: [
            Sentence(id: 0, paragraph: 0, page: 0, text: "A."), Sentence(id: 1, paragraph: 0, page: 0, text: "B.")
        ])
        let text = ReadingText(document: single, translations: ["𠮷野家。", "次。"])
        #expect(text.runs[1].range == NSRange(location: 5, length: 2))
    }

    @Test func missingTranslationArrayEntriesCountAsUntranslated() {
        let text = ReadingText(document: document, translations: [])
        #expect(text.string == "First. Second.\nThird. Fourth.")
    }
}
