import Foundation

/// The continuous text of the translation window: paragraphs in reading order, one line each, with the range of every sentence.
public struct ReadingText: Equatable, Sendable {
    public struct Run: Equatable, Sendable {
        public let sentence: Int
        /// UTF-16 range in `string`, as used by TextKit.
        public let range: NSRange
        /// `false` when the run shows the source text because no translation exists yet.
        public let translated: Bool
    }

    public let string: String
    /// One run per sentence, indexed by sentence id.
    public let runs: [Run]

    public init(document: SourceDocument, translations: [String?]) {
        var string = ""
        var runs: [Run] = []
        var paragraph: Int?
        for sentence in document.sentences {
            let translation = sentence.id < translations.count ? translations[sentence.id] : nil
            let text = translation ?? sentence.text
            if let paragraph, paragraph != sentence.paragraph {
                string += "\n"
            } else if let last = string.unicodeScalars.last, !Self.isFullWidth(last), paragraph != nil {
                string += " "
            }
            paragraph = sentence.paragraph
            let start = string.utf16.count
            string += text
            runs.append(Run(sentence: sentence.id, range: NSRange(location: start, length: text.utf16.count),
                            translated: translation != nil))
        }
        self.string = string
        self.runs = runs
    }

    // Japanese text needs no space between sentences; Latin text does.
    private static func isFullWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x2FFFF: true
        default: false
        }
    }
}
