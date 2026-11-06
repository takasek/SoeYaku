import AppKit
import SoeYakuCore
import Testing
@testable import SoeYakuApp

@Suite(.serialized) @MainActor struct TranslationPanelTests {
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
