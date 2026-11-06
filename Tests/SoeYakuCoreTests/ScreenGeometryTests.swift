import CoreGraphics
import Testing
@testable import SoeYakuCore

struct ScreenGeometryTests {
    @Test func visionBoxFlipsToTopLeftOrigin() {
        let vision = CGRect(x: 0.1, y: 0.7, width: 0.5, height: 0.02)
        let topLeft = ScreenGeometry.topLeft(fromVision: vision)
        #expect(abs(topLeft.minX - 0.1) < 1e-9)
        #expect(abs(topLeft.minY - 0.28) < 1e-9)
        #expect(abs(topLeft.width - 0.5) < 1e-9)
        #expect(abs(topLeft.height - 0.02) < 1e-9)
    }

    @Test func pointerInsideWindowBecomesNormalizedFromTopLeft() {
        let pointer = ScreenGeometry.normalizedPointer(
            mouse: CGPoint(x: 150, y: 700),
            primaryScreenHeight: 1000,
            windowFrame: CGRect(x: 100, y: 200, width: 400, height: 200))
        #expect(pointer == CGPoint(x: 0.125, y: 0.5))
    }

    @Test func pointerOutsideWindowIsNil() {
        let frame = CGRect(x: 100, y: 200, width: 400, height: 200)
        #expect(ScreenGeometry.normalizedPointer(
            mouse: CGPoint(x: 50, y: 700), primaryScreenHeight: 1000, windowFrame: frame) == nil)
        #expect(ScreenGeometry.normalizedPointer(
            mouse: CGPoint(x: 150, y: 100), primaryScreenHeight: 1000, windowFrame: frame) == nil)
        #expect(ScreenGeometry.normalizedPointer(
            mouse: CGPoint(x: 150, y: 900), primaryScreenHeight: 1000, windowFrame: frame) == nil)
    }
}
