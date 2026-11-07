import AppKit
import SoeYakuCore

/// The source pixels and translation boxes share one transform, including when resized.
@MainActor final class MirroredFrameView: NSView {
    /// One translation box in image space, with the text rectangle and the font already fitted to it.
    private struct Label {
        let box: CGRect
        let rect: CGRect
        let text: String
        let attributes: [NSAttributedString.Key: Any]
    }

    private var image: CGImage?
    private var labels: [Label] = []
    override var isFlipped: Bool { true }

    func display(_ image: CGImage?, blocks: [FrameBlock] = [], translations: [String] = []) {
        self.image = image
        // The fit is in image space, so it does not depend on the view size and is not redone on every redraw.
        labels = image.map { image in
            let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            return zip(blocks, translations).map { Self.label(for: $0.box, text: $1, in: imageRect) }
        } ?? []
        setAccessibilityElement(true)
        setAccessibilityLabel("枠2の画像と訳文")
        setAccessibilityValue(translations.joined(separator: "\n"))
        needsDisplay = true
    }

    private static func label(for blockBox: CGRect, text translation: String, in imageRect: CGRect) -> Label {
        let box = FrameGeometry.map(blockBox, into: imageRect)
        let rect = box.insetBy(dx: min(4, box.width * 0.03), dy: min(2, box.height * 0.03))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        var fontSize = min(64, max(8, rect.height * 0.8))
        var attributes: [NSAttributedString.Key: Any] = [:]
        while fontSize >= 4 {
            attributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black, .paragraphStyle: style]
            let measured = (translation as NSString).boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            if measured.height <= rect.height { break }
            fontSize -= 1
        }
        return Label(box: box, rect: rect, text: translation, attributes: attributes)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        let size = CGSize(width: image.width, height: image.height)
        let fit = FrameGeometry.aspectFit(size, in: bounds)
        NSImage(cgImage: image, size: size).draw(in: fit, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        context.saveGState()
        context.translateBy(x: fit.minX, y: fit.minY)
        context.scaleBy(x: fit.width / size.width, y: fit.height / size.height)
        for label in labels {
            NSColor.white.withAlphaComponent(0.94).setFill(); label.box.fill()
            context.saveGState(); context.clip(to: label.box)
            (label.text as NSString).draw(with: label.rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: label.attributes)
            context.restoreGState()
        }
        context.restoreGState()
    }
}
