import CoreGraphics

/// Coordinate conversions between Vision, Cocoa and Core Graphics screen spaces.
public enum ScreenGeometry {
    /// Vision boxes are normalized with a bottom-left origin; the locator works with a top-left origin.
    public static func topLeft(fromVision box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// `mouse` is in Cocoa global coordinates (origin at the bottom-left of the primary screen).
    /// `windowFrame` is in CG global coordinates (origin at the top-left of the primary screen).
    /// Returns the pointer as a 0...1 fraction of the window from its top-left, or nil outside the window.
    public static func normalizedPointer(
        mouse: CGPoint, primaryScreenHeight: CGFloat, windowFrame: CGRect
    ) -> CGPoint? {
        let y = primaryScreenHeight - mouse.y
        guard windowFrame.width > 0, windowFrame.height > 0,
              mouse.x >= windowFrame.minX, mouse.x <= windowFrame.maxX,
              y >= windowFrame.minY, y <= windowFrame.maxY
        else { return nil }
        return CGPoint(
            x: (mouse.x - windowFrame.minX) / windowFrame.width,
            y: (y - windowFrame.minY) / windowFrame.height)
    }
}
