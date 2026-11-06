import AppKit
import SoeYakuCore

/// The source pixels and translation boxes share one transform, including when resized.
@MainActor final class MirroredFrameView: NSView {
    private var image: CGImage?
    private var blocks: [FrameBlock] = []
    private var translations: [String] = []
    override var isFlipped: Bool { true }

    func display(_ image: CGImage?, blocks: [FrameBlock] = [], translations: [String] = []) {
        self.image = image; self.blocks = blocks; self.translations = translations
        setAccessibilityElement(true)
        setAccessibilityLabel("枠2の画像と訳文")
        setAccessibilityValue(translations.joined(separator: "\n"))
        needsDisplay = true
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
        for (block, translation) in zip(blocks, translations) {
            let box = FrameGeometry.map(block.box, into: CGRect(origin: .zero, size: size))
            NSColor.white.withAlphaComponent(0.94).setFill(); box.fill()
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
            context.saveGState(); context.clip(to: box)
            (translation as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
            context.restoreGState()
        }
        context.restoreGState()
    }
}
