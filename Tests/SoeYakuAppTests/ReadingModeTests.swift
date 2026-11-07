import Testing
@testable import SoeYakuApp

struct ReadingModeTests {
    @Test func onlyTheFrameModesHaveAFrameStyle() {
        #expect(ReadingMode.document.frameStyle == nil)
        #expect(ReadingMode.frameText.frameStyle == .text)
        #expect(ReadingMode.frameImage.frameStyle == .image)
    }
}
