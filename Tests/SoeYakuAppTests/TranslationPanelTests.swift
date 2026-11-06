import AppKit
import SoeYakuCore
import Testing
@testable import SoeYakuApp

@Suite(.serialized) @MainActor struct TranslationPanelTests {
    @Test func aNewLiveFrameStartsAtTheTopOfItsTranslation() throws {
        _ = NSApplication.shared
        let panel = TranslationPanel()
        defer { panel.window.orderOut(nil) }
        let document = SourceDocument(fingerprint: "live", title: "live", sentences: (0..<80).map {
            Sentence(id: $0, paragraph: $0, page: 0, text: "A long dialogue line number \($0).")
        })
        let reading = ReadingText(document: document, translations: Array(repeating: "台詞が続きます。次の場面では冒頭から読みます。", count: 80))
        panel.display(reading); panel.show(); panel.window.contentView?.layoutSubtreeIfNeeded()
        let scroll = try #require(panel.window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
        let text = try #require(scroll.documentView as? NSTextView)
        text.layoutManager?.ensureLayout(for: try #require(text.textContainer))
        scroll.contentView.setBoundsOrigin(CGPoint(x: 0, y: 700))
        #expect(scroll.contentView.bounds.minY > 500)
        panel.display(reading, resetScroll: true)
        #expect(scroll.contentView.bounds.minY == 0)
    }

    @Test func mirroredFrameKeepsAspectAndReturningToTextRestoresTheReadingWindow() throws {
        _ = NSApplication.shared
        let translation = TranslationPanel()
        defer { translation.window.orderOut(nil) }
        let visible = try #require(NSScreen.main?.visibleFrame)
        translation.window.setFrameOrigin(CGPoint(x: visible.maxX - 200, y: visible.minY + 40))
        let original = translation.window.frame
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 450,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try #require(bitmap.cgImage)
        translation.displayFrame(image, blocks: [FrameBlock(text: "North", box: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.2))], translations: ["北へ"])
        #expect(translation.window.level == .normal)
        #expect(abs(translation.window.contentAspectRatio.width / translation.window.contentAspectRatio.height - 16.0 / 9) < 0.0001)
        #expect(translation.window.contentView is MirroredFrameView)
        #expect(visible.insetBy(dx: -1, dy: -1).contains(translation.window.frame))
        translation.clear()
        #expect(translation.window.contentAspectRatio == .zero)
        #expect(translation.window.frame == original)
        #expect(translation.window.contentView?.subviews.contains(where: { $0 is NSScrollView }) == true)
    }

    @Test func translationUsesNormalLevelAndAutomaticShowingKeepsFocus() {
        _ = NSApplication.shared
        let controls = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                               styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        let translation = TranslationPanel()
        defer { translation.window.orderOut(nil); controls.orderOut(nil) }
        #expect(translation.window.level == .normal)
        #expect(!translation.window.isFloatingPanel)
        controls.makeKeyAndOrderFront(nil)
        translation.show()
        #expect(translation.window.isVisible)
        #expect(NSApp.keyWindow === controls)
        translation.show(focus: true)
        #expect(NSApp.keyWindow === translation.window)
        controls.makeKeyAndOrderFront(nil)
        translation.show()
        #expect(NSApp.keyWindow === controls)
    }

    @Test func automaticShowingKeepsTheCurrentKeyWindowButExplicitShowingSelectsTheTranslation() {
        _ = NSApplication.shared
        let controls = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                               styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        let translation = TranslationPanel()
        defer { translation.window.orderOut(nil); controls.orderOut(nil) }
        controls.makeKeyAndOrderFront(nil)
        translation.show()
        #expect(NSApp.keyWindow === controls)
        translation.show(focus: true)
        #expect(NSApp.keyWindow === translation.window)
        #expect(translation.window.styleMask.contains(.nonactivatingPanel))
    }

    @Test func returningToTheSameSentenceAfterManualScrollingRevealsItAgain() async throws {
        _ = NSApplication.shared
        let translation = TranslationPanel()
        defer { translation.window.orderOut(nil) }
        let document = SourceDocument(fingerprint: "scroll", title: "T", sentences: (0..<80).map {
            Sentence(id: $0, paragraph: $0, page: 0, text: "Sentence \($0) has enough words to make a full line of readable source text.")
        })
        translation.display(ReadingText(document: document, translations: document.sentences.map { _ in "文章を読みながら訳文を確認できます。長い文もウインドウの幅で折り返します。" }))
        translation.show()
        translation.window.contentView?.layoutSubtreeIfNeeded()
        let scroll = try #require(translation.window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
        let text = try #require(scroll.documentView as? NSTextView)
        text.layoutManager?.ensureLayout(for: try #require(text.textContainer))
        translation.highlight(sentence: 0, source: document.sentences[0].text)
        scroll.contentView.setBoundsOrigin(CGPoint(x: 0, y: 1000))
        scroll.reflectScrolledClipView(scroll.contentView)
        #expect(scroll.contentView.bounds.minY > 500)
        translation.highlight(sentence: 0, source: document.sentences[0].text)
        for _ in 0..<40 where scroll.contentView.bounds.minY >= 500 {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(scroll.contentView.bounds.minY < 500)
    }
}
