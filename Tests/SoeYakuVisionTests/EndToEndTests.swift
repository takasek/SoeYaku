import CoreGraphics
import CoreText
import Foundation
import PDFKit
import SoeYakuCore
import SoeYakuTestSupport
import Testing

@testable import SoeYakuVision

/// A rendered PDF page cropped like a viewer window, with a toolbar strip on top, plus the page geometry needed to point at text.
private struct Window {
    static let scale: CGFloat = 2
    static let toolbarHeight = 60

    let document: PDFDocument
    let sentences: [Sentence]
    let index: DocumentIndex
    let page: PDFPage
    /// The crop of the page in image pixels, top-left origin.
    let crop: CGRect
    let image: CGImage

    init(url: URL, pageIndex: Int, crop: CGRect) throws {
        document = try #require(PDFDocument(url: url))
        let extracted = try PDFExtractor.extract(url: url)
        sentences = extracted.sentences
        index = DocumentIndex(extracted)
        page = try #require(document.page(at: pageIndex))
        self.crop = crop
        let pageImage = try PageImage.render(page, scale: Self.scale)
        let cropped = try #require(pageImage.cropping(to: crop))
        let height = cropped.height + Self.toolbarHeight
        let context = try #require(CGContext(data: nil, width: cropped.width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: cropped.width, height: height))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        let toolbar = NSAttributedString(string: "File Edit View Go Tools Window Help",
                                         attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        context.textPosition = CGPoint(x: 20, y: CGFloat(height - Self.toolbarHeight) + 18)
        CTLineDraw(CTLineCreateWithAttributedString(toolbar), context)
        image = try #require(context.makeImage())
    }

    /// The pointer, normalized to the window image, for a point in PDF page space (points, bottom-left origin).
    func pointer(atPageX x: CGFloat, y: CGFloat) -> CGPoint {
        let pageHeight = page.bounds(for: .mediaBox).height
        let pixelX = x * Self.scale - crop.minX
        let pixelY = (pageHeight - y) * Self.scale - crop.minY + CGFloat(Self.toolbarHeight)
        return CGPoint(x: pixelX / CGFloat(image.width), y: pixelY / CGFloat(image.height))
    }

    /// The pointer over the middle of the first occurrence of `phrase`.
    func pointer(over phrase: String) throws -> CGPoint {
        let rect = try bounds(of: phrase)
        return pointer(atPageX: rect.midX, y: rect.midY)
    }

    func bounds(of phrase: String) throws -> CGRect {
        let selection = try #require(document.findString(phrase, withOptions: []).first { $0.pages.contains(page) })
        return selection.bounds(for: page)
    }

    func sentence(containing text: String) throws -> Int {
        try #require(sentences.first { $0.text.contains(text) }).id
    }

    func locate(at pointer: CGPoint) async throws -> LocateResult {
        let lines = try await TextRecognizer.lines(in: image)
        var locator = Locator(index: index)
        return locator.locate(lines: lines, pointer: pointer)
    }
}

private func fixtureURL() throws -> URL { try MainFixture.write(rightColumnFirst: false) }

private func removeFixture(_ url: URL) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

private func id(_ result: LocateResult) -> Int? {
    if case .matched(let sentence, _) = result { sentence } else { nil }
}

struct EndToEndTests {
    private let fullPage1 = CGRect(x: 0, y: 60, width: 1224, height: 1400)

    @Test(.timeLimit(.minutes(3)))
    func aSentenceInTheLeftColumnIsFound() async throws {
        let url = try fixtureURL()
        defer { removeFixture(url) }
        let window = try Window(url: url, pageIndex: 0, crop: fullPage1)
        let result = try await window.locate(at: window.pointer(over: "Modern systems learn"))
        #expect(id(result) == (try window.sentence(containing: "Modern systems learn")))
    }

    @Test(.timeLimit(.minutes(3)))
    func theRightColumnPartOfASentenceThatCrossesColumnsIsFound() async throws {
        let url = try fixtureURL()
        defer { removeFixture(url) }
        let window = try Window(url: url, pageIndex: 0, crop: fullPage1)
        let result = try await window.locate(at: window.pointer(over: "translation keeps"))
        let crossing = try window.sentence(containing: "A good reader wants to follow")
        #expect(crossing == 4)
        #expect(id(result) == crossing)
    }

    @Test(.timeLimit(.minutes(3)))
    func aHeadingWithBodyLinesBelowIsFound() async throws {
        let url = try fixtureURL()
        defer { removeFixture(url) }
        let window = try Window(url: url, pageIndex: 1, crop: CGRect(x: 0, y: 160, width: 1224, height: 700))
        let result = try await window.locate(at: window.pointer(over: "Results"))
        #expect(id(result) == (try window.sentence(containing: "Results")))
    }

    @Test(.timeLimit(.minutes(3)))
    func aLineCutInHalfAtTheTopEdgeDoesNotMislead() async throws {
        let url = try fixtureURL()
        defer { removeFixture(url) }
        let document = try #require(PDFDocument(url: url))
        let page = try #require(document.page(at: 0))
        // Left column lines from top to bottom: cut the third (the end of the second sentence) in half and point at the fourth (the start of the third sentence).
        let lines = try #require(page.selection(for: CGRect(x: 72, y: 100, width: 220, height: 570)))
            .selectionsByLine().map { $0.bounds(for: page) }.sorted { $0.midY > $1.midY }
        let cut = lines[2], next = lines[3]
        let pageHeight = page.bounds(for: .mediaBox).height
        let top = (pageHeight - cut.midY) * Window.scale
        let window = try Window(url: url, pageIndex: 0, crop: CGRect(x: 0, y: top, width: 1224, height: 1500 - top))
        let pointer = window.pointer(atPageX: next.minX + 0.1 * next.width, y: next.midY)
        let result = try await window.locate(at: pointer)
        let expected = try window.sentence(containing: "Modern systems learn")
        #expect(id(result) == expected)
    }

    @Test(.timeLimit(.minutes(3)))
    func aPointerOnTheToolbarIsUnresolved() async throws {
        let url = try fixtureURL()
        defer { removeFixture(url) }
        let window = try Window(url: url, pageIndex: 0, crop: fullPage1)
        let toolbarPointer = CGPoint(x: 0.15, y: CGFloat(Window.toolbarHeight) / 2 / CGFloat(window.image.height))
        #expect(try await window.locate(at: toolbarPointer) == .unresolved)
    }
}
