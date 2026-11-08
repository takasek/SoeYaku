import Testing
@testable import SoeYakuCore

struct TextNormalizerTests {
    @Test func lowercasesAndSplitsOnNonAlphanumerics() {
        #expect(TextNormalizer.tokens("Hello, World! 42-x") == ["hello", "world", "42", "x"])
    }

    @Test func removesApostrophesInsteadOfSplitting() {
        #expect(TextNormalizer.tokens("don't won’t") == ["dont", "wont"])
    }

    @Test func foldsCompatibilityCharactersByNFKC() {
        #expect(TextNormalizer.tokens("ﬁne ＡＢＣ") == ["fine", "abc"])
    }

    @Test func returnsNoTokensForPunctuationOnly() {
        #expect(TextNormalizer.tokens(" — … ").isEmpty)
    }

    @Test func collapsingWhitespaceFoldsCompatibilityCharactersAndCollapsesRuns() {
        #expect(TextNormalizer.collapsingWhitespace("  ＡＢＣ \t ﬁne\n\n x  ") == "ABC fine x")
        #expect(TextNormalizer.collapsingWhitespace(" \n\t ") == "")
    }
}
