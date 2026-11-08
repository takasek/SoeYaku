import AppKit
import SoeYakuCore
import SoeYakuTestSupport
import Testing
import WebKit
@testable import SoeYakuVision

@Suite(.serialized) @MainActor struct HTMLReadingTests {
    @Test(.timeLimit(.minutes(3))) func renderedColumnsAndRepeatedHeadingsMatchTheHTMLDocument() async throws {
        let page = HTMLPage()
        try await page.load(HTMLFixture.html)
        let document = try HTMLExtractor.extract(data: Data(HTMLFixture.html.utf8), fallbackTitle: "fixture")
        let image = try await page.snapshot()
        let lines = try await TextRecognizer.lines(in: image)
        let expected = ["left": 2, "right": 5, "firstResults": 7, "secondResults": 9]
        for (element, sentence) in expected {
            let rect = try #require(try await page.rectangles(element).first)
            let pointer = CGPoint(x: rect.midX / page.view.frame.width, y: rect.midY / page.view.frame.height)
            var locator = Locator(index: DocumentIndex(document))
            let result = locator.locate(lines: lines, pointer: pointer)
            guard case .matched(let actual, _) = result else { Issue.record("\(element) was unresolved"); continue }
            #expect(actual == sentence, "\(element): \(document.sentences[actual].text)")
        }
    }

    @Test(.timeLimit(.minutes(3))) func clippedHTMLSentenceUsesTheCompletePretranslatedSource() async throws {
        let page = HTMLPage()
        try await page.load(HTMLFixture.html)
        let document = try HTMLExtractor.extract(data: Data(HTMLFixture.html.utf8), fallbackTitle: "fixture")
        let full = try await page.snapshot()
        let boxes = try await page.rectangles("left")
        #expect(boxes.count > 2)
        let first = try #require(boxes.first)
        let scale = CGFloat(full.width) / page.view.frame.width
        let cut = first.midY * scale
        let image = try #require(full.cropping(to: CGRect(x: 0, y: cut, width: CGFloat(full.width), height: CGFloat(full.height)-cut)))
        let next = boxes[1]
        let pointer = CGPoint(x: next.midX / page.view.frame.width, y: (next.midY*scale-cut) / CGFloat(image.height))
        let lines = try await TextRecognizer.lines(in: image)
        var locator = Locator(index: DocumentIndex(document))
        guard case .matched(let actual, _) = locator.locate(lines: lines, pointer: pointer) else {
            Issue.record("Clipped HTML sentence was unresolved"); return
        }
        #expect(actual == 2)
        #expect(document.sentences[actual].text.hasPrefix("Maple Observatory records"))
    }
}

@MainActor private final class HTMLPage: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 740, height: 940), configuration: {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }())
    private var loading: CheckedContinuation<Void, any Error>?

    func load(_ html: String) async throws {
        _ = NSApplication.shared
        view.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading?.resume(); loading = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { loading?.resume(throwing: error); loading = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { loading?.resume(throwing: error); loading = nil }

    func snapshot() async throws -> CGImage {
        let image = try await view.takeSnapshot(configuration: nil)
        return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func rectangles(_ id: String) async throws -> [CGRect] {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: id, options: .fragmentsAllowed), as: UTF8.self)
        let result = try await view.evaluateJavaScript("""
            (() => { const r = document.createRange(); r.selectNodeContents(document.getElementById(\(json)));
              return Array.from(r.getClientRects()).map(b => ({x:b.x,y:b.y,width:b.width,height:b.height})); })()
            """)
        let values = try #require(result as? [[String: Double]])
        return values.map { CGRect(x: $0["x"]!, y: $0["y"]!, width: $0["width"]!, height: $0["height"]!) }
    }
}
