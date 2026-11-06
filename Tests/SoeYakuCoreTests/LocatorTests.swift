import CoreGraphics
import Testing
@testable import SoeYakuCore

struct LocatorTests {
    // Sentence ids are the array indices. "Results" followed by an identical sentence occurs twice (4/5 and 9/10),
    // with more than 30 tokens between the occurrences.
    static let texts = [
        "Introduction",
        "Neural machine translation has changed how people read foreign documents.",
        "Readers still need a quick way to check a hard sentence while they scroll.",
        "In this paper we describe a small tool that translates sentences in place.",
        "Results",
        "We report the main findings below.",
        "The first experiment used a small sample of short articles.",
        "Eleven readers finished every task without any help from the authors.",
        "Median lookup time fell sharply once the translations were cached on disk.",
        "Results",
        "We report the main findings below.",
        "The second experiment used a large sample of long articles.",
        "Forty readers finished every task and most of them kept using the tool.",
        "Median lookup time stayed low even when the documents were very long.",
        "Discussion",
        "The tool was fast enough for interactive reading on a laptop.",
        "Participants preferred translations that appeared next to the original text.",
        "Several limitations remain and we list them in the final section."
    ]

    static let document = SourceDocument(
        fingerprint: "f", title: "T",
        sentences: texts.enumerated().map { Sentence(id: $0.offset, paragraph: $0.offset, page: 0, text: $0.element) })

    static let lineHeight = 0.02
    static let lineSpacing = 0.025
    static let charWidth = 0.011

    static func makeLocator() -> Locator {
        Locator(index: DocumentIndex(document))
    }

    /// Lines laid out like a page: left-aligned, one every 0.025, 0.02 high, 0.011 wide per character.
    static func page(_ lines: [String], top: Double = 0.2, x: Double = 0.1) -> [TextLine] {
        lines.enumerated().map { offset, text in
            TextLine(text: text, box: CGRect(
                x: x, y: top + Double(offset) * lineSpacing,
                width: Double(text.count) * charWidth, height: lineHeight))
        }
    }

    /// A pointer on `line`, `fraction` of the way across it, at its vertical center plus `dy`.
    static func pointer(on line: TextLine, at fraction: Double, dy: Double = 0) -> CGPoint {
        CGPoint(x: line.box.minX + line.box.width * fraction, y: line.box.midY + dy)
    }

    static let pageA = [
        "Neural machine translation has changed how",
        "people read foreign documents. Readers still",
        "need a quick way to check a hard sentence",
        "while they scroll. In this paper we describe a",
        "small tool that translates sentences in place."
    ]

    static func matchedSentence(_ result: LocateResult) -> Int? {
        if case .matched(let sentence, _) = result { return sentence }
        return nil
    }

    @Test func returnsTheSentenceOfTheWordUnderThePointer() {
        var locator = Self.makeLocator()
        let noise = [TextLine(text: "File Edit View", box: CGRect(x: 0.1, y: 0.02, width: 0.2, height: 0.02)),
                     TextLine(text: "Page 3 of 12", box: CGRect(x: 0.4, y: 0.95, width: 0.15, height: 0.02))]
        let lines = noise + Self.page(Self.pageA)
        let body = Array(lines[2...])
        let result = locator.locate(lines: lines, pointer: Self.pointer(on: body[2], at: 0.05))
        #expect(Self.matchedSentence(result) == 2)
        guard case .matched(_, let confidence) = result else { return }
        #expect(confidence > 0.5 && confidence <= 1)
        #expect(locator.lastSentence == 2)
    }

    @Test func choosesTheTokenByHorizontalPositionAcrossSentenceBoundaries() {
        let lines = Self.page(Self.pageA)
        var locator = Self.makeLocator()
        #expect(Self.matchedSentence(locator.locate(lines: lines, pointer: Self.pointer(on: lines[1], at: 0.05))) == 1)
        #expect(Self.matchedSentence(locator.locate(lines: lines, pointer: Self.pointer(on: lines[1], at: 0.95))) == 2)
        #expect(Self.matchedSentence(locator.locate(lines: lines, pointer: Self.pointer(on: lines[3], at: 0.02))) == 2)
        #expect(Self.matchedSentence(locator.locate(lines: lines, pointer: Self.pointer(on: lines[3], at: 0.97))) == 3)
    }

    @Test func staysUnresolvedAndKeepsLastSentenceForLinesNotInTheDocument() {
        var locator = Self.makeLocator()
        let lines = Self.page(Self.pageA)
        _ = locator.locate(lines: lines, pointer: Self.pointer(on: lines[2], at: 0.1))
        #expect(locator.lastSentence == 2)
        let chrome = Self.page(["File Edit View", "Page 3 of 12"])
        let result = locator.locate(lines: chrome, pointer: Self.pointer(on: chrome[0], at: 0.5))
        #expect(result == .unresolved)
        #expect(locator.lastSentence == 2)
    }

    @Test func resolvesALineCutOffAtTheTopOfTheWindow() {
        var lines = Self.page([
            "ple read foreign documents. Readers still",
            "need a quick way to check a hard sentence",
            "while they scroll. In this paper we describe a",
            "small tool that translates sentences in place."
        ], top: 0.0)
        lines[0] = TextLine(text: lines[0].text, box: CGRect(
            x: 0.1, y: 0, width: lines[0].box.width, height: 0.012))
        var locator = Self.makeLocator()
        let result = locator.locate(lines: lines, pointer: Self.pointer(on: lines[0], at: 0.35))
        #expect(Self.matchedSentence(result) == 1)
    }

    @Test func usesOnlyTheColumnUnderThePointerWhenColumnsShareTheSameHeight() {
        let left = [
            "Neural machine translation has changed",
            "how people read foreign documents.",
            "Readers still need a quick way to check",
            "a hard sentence while they scroll."
        ]
        let right = [
            "The tool was fast enough for interactive",
            "reading on a laptop. Participants",
            "preferred translations that appeared next",
            "to the original text. Several limitations"
        ]
        let leftLines = Self.page(left, x: 0.04)
        let rightLines = Self.page(right, x: 0.52)
        let lines = zip(leftLines, rightLines).flatMap { [$0, $1] }
        var locator = Self.makeLocator()
        #expect(Self.matchedSentence(locator.locate(
            lines: lines, pointer: Self.pointer(on: rightLines[0], at: 0.5))) == 15)
        #expect(Self.matchedSentence(locator.locate(
            lines: lines, pointer: Self.pointer(on: leftLines[2], at: 0.1))) == 2)
        #expect(Self.matchedSentence(locator.locate(
            lines: lines, pointer: Self.pointer(on: rightLines[2], at: 0.1))) == 16)
    }

    @Test func joinsAWordHyphenatedAtTheEndOfALineWithTheNextLine() {
        let lines = Self.page([
            "In this paper we describe a small tool that transla-",
            "tes sentences in place."
        ])
        var locator = Self.makeLocator()
        let result = locator.locate(lines: lines, pointer: Self.pointer(on: lines[0], at: 0.5))
        #expect(result == .matched(sentence: 3, confidence: 1))
    }

    @Test func aHeadingLineAloneIsUnresolved() {
        let lines = Self.page(["Results"])
        var locator = Self.makeLocator()
        #expect(locator.locate(lines: lines, pointer: Self.pointer(on: lines[0], at: 0.5)) == .unresolved)
    }

    @Test func aHeadingWithItsFollowingBodyLinesAsContextResolvesToTheSecondOccurrence() {
        let lines = Self.page([
            "Results",
            "We report the main findings below.",
            "The second experiment used a large sample of long articles."
        ])
        var locator = Self.makeLocator()
        let result = locator.locate(lines: lines, pointer: Self.pointer(on: lines[0], at: 0.5))
        #expect(Self.matchedSentence(result) == 9)
    }

    @Test func anIdenticalHeadingAndSentenceAreResolvedByTheLastPositionOrElseUnresolved() {
        let ambiguous = Self.page(["Results", "We report the main findings below."])
        let first = Self.page([
            "Results",
            "We report the main findings below.",
            "The first experiment used a small sample of short articles."
        ])
        var locator = Self.makeLocator()
        #expect(locator.locate(lines: ambiguous, pointer: Self.pointer(on: ambiguous[0], at: 0.5)) == .unresolved)
        #expect(Self.matchedSentence(locator.locate(lines: first, pointer: Self.pointer(on: first[0], at: 0.5))) == 4)
        #expect(Self.matchedSentence(locator.locate(
            lines: ambiguous, pointer: Self.pointer(on: ambiguous[0], at: 0.5))) == 4)
        #expect(Self.matchedSentence(locator.locate(
            lines: ambiguous, pointer: Self.pointer(on: ambiguous[1], at: 0.5))) == 5)
    }

    @Test func prefersTheAnchorLineWhoseCenterIsNearestWhenSeveralLinesQualify() {
        let lines = Self.page(Self.pageA)
        var locator = Self.makeLocator()
        // Between lines[1] (y 0.225...0.245) and lines[2] (0.25...0.27): both margins cover y = 0.2475.
        let nearUpper = CGPoint(x: lines[1].box.minX + 0.02, y: 0.2455)
        let nearLower = CGPoint(x: lines[2].box.minX + 0.02, y: 0.2495)
        #expect(Self.matchedSentence(locator.locate(lines: lines, pointer: nearUpper)) == 1)
        #expect(Self.matchedSentence(locator.locate(lines: lines, pointer: nearLower)) == 2)
    }

    @Test func fallsBackToTheNearestLineWithinTwoLineHeightsAndNoFurther() {
        let lines = Self.page(Self.pageA)
        var locator = Self.makeLocator()
        let below = lines[4].box
        let near = CGPoint(x: below.minX + 0.02, y: below.maxY + 0.03)
        let far = CGPoint(x: below.minX + 0.02, y: below.maxY + 0.05)
        #expect(Self.matchedSentence(locator.locate(lines: lines, pointer: near)) == 3)
        #expect(locator.locate(lines: lines, pointer: far) == .unresolved)
        let leftOfAll = CGPoint(x: 0.01, y: lines[2].box.midY)
        #expect(locator.locate(lines: lines, pointer: leftOfAll) == .unresolved)
    }

    @Test func locatesLinesGivenInVisionCoordinatesAfterConversion() {
        let topLeftLines = Self.page(Self.pageA)
        let visionLines = topLeftLines.map {
            TextLine(text: $0.text, box: CGRect(
                x: $0.box.minX, y: 1 - $0.box.maxY, width: $0.box.width, height: $0.box.height))
        }
        let converted = visionLines.map {
            TextLine(text: $0.text, box: ScreenGeometry.topLeft(fromVision: $0.box))
        }
        var locator = Self.makeLocator()
        let result = locator.locate(lines: converted, pointer: Self.pointer(on: converted[2], at: 0.05))
        #expect(Self.matchedSentence(result) == 2)
    }
}
