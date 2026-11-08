import CoreGraphics
import Testing
import SoeYakuTestSupport
@testable import SoeYakuVision

struct CapturedPixelsTests {
    /// A white image, with a black square where `mark` says.
    private func image(mark: CGRect? = nil) throws -> CGImage {
        let context = try PageImage.whiteCanvas(width: 40, height: 20)
        if let mark {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(mark)
        }
        return try #require(context.makeImage())
    }

    @Test func separateCapturesWithTheSamePixelsMatch() throws {
        #expect(CapturedPixels(try image()).matches(CapturedPixels(try image())))
    }

    @Test func capturesWithDifferentPixelsDoNotMatch() throws {
        let changed = try image(mark: CGRect(x: 10, y: 5, width: 4, height: 4))
        #expect(!CapturedPixels(changed).matches(CapturedPixels(try image())))
    }

    @Test func aFirstCaptureHasNothingToMatch() throws {
        #expect(!CapturedPixels(try image()).matches(nil))
    }
}
