import CoreGraphics
import Foundation
import Testing
import SoeYakuTestSupport

struct PageImageTests {
    @Test func whiteCanvasIsAnOpaqueWhiteImageOfTheRequestedSize() throws {
        let image = try #require(try PageImage.whiteCanvas(width: 7, height: 3).makeImage())
        #expect(image.width == 7 && image.height == 3)
        let bytes = [UInt8](try #require(image.dataProvider?.data) as Data)
        #expect(bytes.count >= 7 * 4)
        #expect(bytes.prefix(7 * 4).allSatisfy { $0 == 255 })
    }
}
