import Testing

@testable import SoeYakuCore

struct HyphenationTests {
    @Test(arguments: [
        ("a transla-", "tion", "a translation"),
        ("a well-", "Known author", "a well- Known author"),
        ("pages 3-", "5 apply", "pages 3- 5 apply"),
        ("pages 3-", "five", "pages 3- five"),
        ("a word -", "next", "a word - next"),
        ("a café-", "au lait", "a café- au lait"),
        ("-", "next", "- next"),
        ("a line", "next", "a line next"),
    ])
    func joinFollowsTheCanonicalRule(line: String, next: String, expected: String) {
        #expect(Hyphenation.join(line, next) == expected)
        #expect(Hyphenation.continues(line, into: next) == (expected == String(line.dropLast()) + next))
    }
}
