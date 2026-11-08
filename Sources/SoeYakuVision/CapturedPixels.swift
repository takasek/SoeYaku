import CoreGraphics
import Foundation

/// The pixels of one screen capture, kept to tell whether the next capture shows anything new before recognizing its text.
public struct CapturedPixels {
    private let data: CFData?

    public init(_ image: CGImage) {
        data = image.dataProvider?.data
    }

    /// Whether `earlier` has exactly these pixels. A capture whose pixels cannot be read never matches, so its text is always recognized.
    public func matches(_ earlier: CapturedPixels?) -> Bool {
        guard let data, let other = earlier?.data else { return false }
        return CFEqual(data, other)
    }
}
