import CoreGraphics
import CoreText
import Foundation

/// Builds small PDFs with CoreText for tests. Lives in the shared test-support target.
public enum FixturePDF {
    /// Text laid out in `rect` (PDF page space, origin at the bottom left), wrapped by CoreText.
    /// A `\n` in `text` forces a line break.
    public struct Block {
        public let text: String
        public let rect: CGRect
        public var fontSize: CGFloat

        public init(text: String, rect: CGRect, fontSize: CGFloat = 11) {
            self.text = text
            self.rect = rect
            self.fontSize = fontSize
        }
    }

    public struct BuildError: Error {}

    /// Writes a PDF with one entry of `pages` per page, drawing blocks in the order given.
    public static func write(pages: [[Block]], title: String? = nil, to url: URL, pageSize: CGSize = CGSize(width: 612, height: 792)) throws {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        var info: [CFString: Any] = [:]
        if let title { info[kCGPDFContextTitle] = title }
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, info as CFDictionary) else { throw BuildError() }
        for blocks in pages {
            context.beginPDFPage(nil)
            for block in blocks {
                let font = CTFontCreateWithName("Helvetica" as CFString, block.fontSize, nil)
                let text = NSAttributedString(string: block.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                let framesetter = CTFramesetterCreateWithAttributedString(text)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: block.rect, transform: nil), nil)
                CTFrameDraw(frame, context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    /// Writes into a fresh temporary file. The caller removes it.
    public static func writeTemporary(pages: [[Block]], title: String? = nil, name: String = "fixture") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).pdf")
        try write(pages: pages, title: title, to: url)
        return url
    }
}
