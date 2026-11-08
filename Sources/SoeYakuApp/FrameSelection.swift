import AppKit
import SoeYakuCore

struct FrameRegion: Sendable, Equatable {
    let displayID: CGDirectDisplayID
    let normalized: CGRect
    let size: CGSize
}

@MainActor final class FrameSelection {
    private var windows: [NSWindow] = []
    private var completion: ((FrameRegion?) -> Void)?

    func choose(completion: @escaping (FrameRegion?) -> Void) {
        cancel()
        self.completion = completion
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in
                let region = rect.map { FrameRegion(displayID: id, normalized: CGRect(x: $0.minX / screen.frame.width,
                        y: 1 - $0.maxY / screen.frame.height, width: $0.width / screen.frame.width, height: $0.height / screen.frame.height), size: $0.size) }
                self?.finish(region)
            }
            window.contentView = view
            windows.append(window)
            window.orderFront(nil)
        }
        windows.first?.makeKey()
        NSApp.activate()
        if windows.isEmpty { finish(nil) }
    }

    func cancel() { finish(nil) }

    private func finish(_ region: FrameRegion?) {
        let callback = completion
        completion = nil
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        callback?(region)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection: CGRect?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
        setAccessibilityElement(true)
        setAccessibilityLabel("翻訳する範囲をドラッグ。Escapeでキャンセル。")
    }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil); selection = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = FrameGeometry.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        onFinish?(FrameGeometry.selection(from: start, to: convert(event.locationInWindow, from: nil), in: bounds))
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect: bounds)
        if let selection { shade.appendRect(selection) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill(); shade.fill()
        if let selection {
            NSColor.systemYellow.setStroke()
            let border = NSBezierPath(rect: selection); border.lineWidth = 2; border.stroke()
        }
        let message = "翻訳する範囲をドラッグしてください　Escでキャンセル"
        (message as NSString).draw(at: CGPoint(x: 32, y: bounds.height - 64), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ])
    }
}
