import AppKit
import SoeYakuCore

/// A normal-level translation window. Automatic updates keep the reader's window order and focus.
@MainActor final class TranslationPanel {
    private let panel: NSPanel
    private let scrollView = NSScrollView()
    private let textView = NSTextView(usingTextLayoutManager: false)
    private let footer = NSTextField(wrappingLabelWithString: "")
    private var reading: ReadingText?
    private var highlighted: Int?
    var window: NSWindow { panel }
    var fontSize: CGFloat = 18 { didSet { if oldValue != fontSize, let reading { display(reading) } } }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.title = "SoeYaku 訳文"
        panel.level = .normal
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 260, height: 200)
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.isExcludedFromWindowsMenu = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        footer.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footer.textColor = .secondaryLabelColor
        footer.maximumNumberOfLines = 2
        footer.lineBreakMode = .byTruncatingTail

        let content = NSView()
        for view in [scrollView, footer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])
        panel.contentView = content
        panel.setFrameAutosaveName("SoeYakuTranslation")
        if !panel.setFrameUsingName("SoeYakuTranslation"), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - panel.frame.width - 24, y: screen.maxY - panel.frame.height - 24))
        }
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
    }

    func show(focus: Bool = false) {
        if focus { panel.makeKeyAndOrderFront(nil) }
        else if !panel.isVisible { panel.orderBack(nil) }
    }

    func clear() {
        reading = nil
        highlighted = nil
        textView.string = ""
        footer.stringValue = ""
    }

    /// Replaces the whole text, keeping the highlighted sentence and the scroll position.
    func display(_ reading: ReadingText) {
        let origin = scrollView.contentView.bounds.origin
        self.reading = reading
        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize * 0.3
        style.paragraphSpacing = fontSize * 0.9
        let storage = NSMutableAttributedString(string: reading.string, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor, .paragraphStyle: style
        ])
        for run in reading.runs where !run.translated {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: run.range)
        }
        textView.textStorage?.setAttributedString(storage)
        if let highlighted { paint(highlighted) }
        scrollView.contentView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func highlight(sentence: Int, source: String) {
        footer.stringValue = "原文: " + source
        guard let reading, reading.runs.indices.contains(sentence) else { return }
        if sentence != highlighted {
            if let highlighted, reading.runs.indices.contains(highlighted) {
                textView.textStorage?.removeAttribute(.backgroundColor, range: reading.runs[highlighted].range)
            }
            highlighted = sentence
            paint(sentence)
        }
        reveal(reading.runs[sentence].range)
    }

    func setFooter(_ text: String) { footer.stringValue = text }

    private func paint(_ sentence: Int) {
        guard let reading, reading.runs.indices.contains(sentence) else { return }
        textView.textStorage?.addAttribute(.backgroundColor, value: NSColor.findHighlightColor.withAlphaComponent(0.45),
                                           range: reading.runs[sentence].range)
    }

    // Scroll only when the sentence leaves the middle of the view, so pointer moves within a paragraph do not shake the text.
    private func reveal(_ range: NSRange) {
        guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
        layout.ensureLayout(for: container)
        var rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
        rect.origin.y += textView.textContainerInset.height
        let clip = scrollView.contentView
        let visible = clip.bounds
        let band = visible.insetBy(dx: 0, dy: visible.height * 0.2)
        guard rect.minY < band.minY || rect.maxY > band.maxY else { return }
        let maxY = max(0, textView.frame.height - visible.height)
        let y = min(max(0, rect.midY - visible.height / 2), maxY)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
        }
        scrollView.reflectScrolledClipView(clip)
    }
}
