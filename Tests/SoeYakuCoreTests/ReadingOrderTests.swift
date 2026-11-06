import CoreGraphics
import Testing

@testable import SoeYakuCore

let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

/// `top` is the y of the line's upper edge in page space.
func line(_ text: String, x: CGFloat, top: CGFloat, width: CGFloat = 200, height: CGFloat = 11, page: Int = 0) -> PageLine {
    PageLine(text: text, bounds: CGRect(x: x, y: top - height, width: width, height: height), page: page)
}

@Suite struct OrderTests {
    @Test func singleColumnReadsTopToBottom() {
        let lines = [
            line("c", x: 72, top: 500, width: 468),
            line("a", x: 72, top: 700, width: 468),
            line("b", x: 72, top: 600, width: 468),
        ]
        #expect(ReadingOrder.order(lines, pageBounds: letter).map(\.text) == ["a", "b", "c"])
    }

    @Test func sameHeightReadsLeftToRight() {
        let lines = [
            line("right", x: 400, top: 600, width: 100),
            line("left", x: 72, top: 600, width: 100),
        ]
        #expect(ReadingOrder.order(lines, pageBounds: letter).map(\.text) == ["left", "right"])
    }

    @Test func twoColumnsReadLeftThenRight() {
        let left = (0..<4).map { line("L\($0)", x: 72, top: 700 - CGFloat($0) * 14) }
        let right = (0..<4).map { line("R\($0)", x: 320, top: 700 - CGFloat($0) * 14) }
        let shuffled = [right[1], left[2], right[0], left[0], right[3], left[3], left[1], right[2]]
        let ordered = ReadingOrder.order(shuffled, pageBounds: letter).map(\.text)
        #expect(ordered == ["L0", "L1", "L2", "L3", "R0", "R1", "R2", "R3"])
    }

    @Test func fullWidthLinesSplitTwoColumnBands() {
        let title = line("TITLE", x: 72, top: 740, width: 468)
        let left1 = (0..<3).map { line("A-L\($0)", x: 72, top: 700 - CGFloat($0) * 14) }
        let right1 = (0..<3).map { line("A-R\($0)", x: 320, top: 700 - CGFloat($0) * 14) }
        let wide = line("WIDE", x: 72, top: 600, width: 468)
        let left2 = (0..<3).map { line("B-L\($0)", x: 72, top: 560 - CGFloat($0) * 14) }
        let right2 = (0..<3).map { line("B-R\($0)", x: 320, top: 560 - CGFloat($0) * 14) }
        let all = right2 + [wide] + right1 + left2 + [title] + left1
        let ordered = ReadingOrder.order(all, pageBounds: letter).map(\.text)
        #expect(
            ordered == [
                "TITLE", "A-L0", "A-L1", "A-L2", "A-R0", "A-R1", "A-R2",
                "WIDE", "B-L0", "B-L1", "B-L2", "B-R0", "B-R1", "B-R2",
            ])
    }

    @Test func fewerThanThreeLinesPerColumnIsNotTwoColumn() {
        let lines = [
            line("R0", x: 320, top: 700), line("L0", x: 72, top: 700),
            line("R1", x: 320, top: 686), line("L1", x: 72, top: 686),
        ]
        #expect(ReadingOrder.order(lines, pageBounds: letter).map(\.text) == ["L0", "R0", "L1", "R1"])
    }
}

@Suite struct RunningElementTests {
    /// A page with a header line at the top, a body line in the middle and a footer line at the bottom.
    func page(_ index: Int, header: String? = nil, body: String = "body", footer: String? = nil) -> [PageLine] {
        var lines = [line(body, x: 72, top: 400, width: 468, page: index)]
        if let header { lines.append(line(header, x: 72, top: 770, page: index)) }
        if let footer { lines.append(line(footer, x: 280, top: 40, width: 20, page: index)) }
        return lines
    }

    func texts(_ pages: [[PageLine]]) -> [[String]] { pages.map { $0.map(\.text) } }

    func run(_ pages: [[PageLine]]) -> [[String]] {
        texts(ReadingOrder.removeRunningElements(pages, pageBounds: Array(repeating: letter, count: pages.count)))
    }

    @Test func removesRepeatedHeaderAndPageNumbers() {
        let pages = (0..<3).map { page($0, header: "Running Header", footer: "\($0 + 1)") }
        #expect(run(pages) == [["body"], ["body"], ["body"]])
    }

    @Test func removesHeadersThatDifferOnlyInDigits() {
        let pages = (0..<3).map { page($0, header: "Page \($0 + 1) of 3") }
        #expect(run(pages) == [["body"], ["body"], ["body"]])
    }

    @Test func removesLowercaseRomanNumeralsInTheBand() {
        let pages = [page(0, footer: "iv"), page(1, footer: "xii"), page(2, footer: "xiii")]
        #expect(run(pages) == [["body"], ["body"], ["body", "xiii"]])
    }

    @Test func keepsNumbersOutsideTheBands() {
        #expect(run([page(0, body: "42")]) == [["42"]])
    }

    @Test func keepsRepeatsOnFewerThanThreePages() {
        let pages = [page(0, header: "Chapter"), page(1, header: "Chapter")]
        #expect(run(pages) == [["body", "Chapter"], ["body", "Chapter"]])
    }

    @Test func keepsRepeatsBelowThirtyPercentOfPages() {
        // 3 of 11 pages is 27%; 3 of 10 pages is 30%.
        func remaining(pageCount: Int) -> Int {
            let pages = (0..<pageCount).map { page($0, header: $0 < 3 ? "Chapter" : nil) }
            return run(pages).flatMap { $0 }.filter { $0 == "Chapter" }.count
        }
        #expect(remaining(pageCount: 11) == 3)
        #expect(remaining(pageCount: 10) == 0)
    }
}
