import CoreGraphics
import CoreText
import Foundation
import Testing
import SoeYakuCore
import SoeYakuTestSupport
@testable import SoeYakuVision

struct TextRecognizerTests {
    /// White image with black Helvetica lines; `y` is measured from the top of the image in pixels.
    private func image(width: Int, height: Int, lines: [(text: String, x: CGFloat, y: CGFloat)]) throws -> CGImage {
        let context = try PageImage.whiteCanvas(width: width, height: height)
        let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        for line in lines {
            let text = NSAttributedString(string: line.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: line.x, y: CGFloat(height) - line.y)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }
        return try #require(context.makeImage())
    }

    @Test(.timeLimit(.minutes(3)))
    func returnsLinesWithTopLeftNormalizedBoxes() async throws {
        let picture = try image(width: 1000, height: 400, lines: [
            ("The quick brown fox jumps", 40, 80), ("over the lazy sleeping dog", 520, 320)
        ])
        let lines = try await TextRecognizer.lines(in: picture)
        let top = try #require(lines.first { $0.text.contains("quick") })
        let bottom = try #require(lines.first { $0.text.contains("lazy") })
        #expect(top.text == "The quick brown fox jumps")
        #expect(top.box.minY < 0.25 && top.box.minX < 0.1)
        #expect(bottom.box.minY > 0.65 && bottom.box.minX > 0.5)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        #expect(lines.filter { !unit.contains($0.box) }.isEmpty)
    }

    @Test(.timeLimit(.minutes(3)))
    func blankImageHasNoLines() async throws {
        let lines = try await TextRecognizer.lines(in: try image(width: 200, height: 100, lines: []))
        #expect(lines.isEmpty)
    }
}
