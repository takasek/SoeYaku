import Foundation

/// Turns running text into comparable tokens so that OCR output and extracted PDF text can be matched.
public enum TextNormalizer {
    /// NFKC, lowercased, apostrophes removed, every non-alphanumeric character a separator.
    public static func tokens(_ text: String) -> [String] {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        var tokens: [String] = []
        var current = ""
        for character in folded {
            if character == "'" || character == "\u{2019}" {
                continue
            }
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    /// NFKC with every run of whitespace collapsed to one space and the ends trimmed.
    public static func collapsingWhitespace(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
