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
