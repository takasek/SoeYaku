/// The rule for a word broken across lines with a hyphen.
/// PDF paragraphs, frame paragraphs and the locator's OCR query share this one rule so their texts tokenize alike.
enum Hyphenation {
    /// True when `line` ends in an ASCII letter and "-", and `next` starts with a lowercase letter.
    static func continues(_ line: some StringProtocol, into next: some StringProtocol) -> Bool {
        guard line.hasSuffix("-"), let before = line.dropLast().last, before.isASCII, before.isLetter,
            let first = next.first, first.isLowercase
        else { return false }
        return true
    }

    /// `line` and `next` as one text; `next` is always appended unchanged at the end.
    static func join(_ line: String, _ next: String) -> String {
        continues(line, into: next) ? String(line.dropLast()) + next : line + " " + next
    }
}
