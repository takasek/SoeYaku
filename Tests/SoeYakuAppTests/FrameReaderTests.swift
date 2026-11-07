import AppKit
import SoeYakuCore
import Testing
@testable import SoeYakuApp

@Suite(.serialized) @MainActor struct FrameReaderTests {
    @Test func failedFrameDoesNotStopTheNextDialogueUpdate() async throws {
        _ = NSApplication.shared
        let panel = TranslationPanel()
        let first = try bitmap(), second = try bitmap(width: 81)
        var captures = 0
        let reader = FrameReader(panel: panel, capture: { _ in captures += 1; return captures == 1 ? first : second }, recognize: { image in
            [TextLine(text: image.width == 80 ? "Old dialogue." : "Next dialogue.", box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.1))]
        })
        let engine = FrameTranslator(using: FailingFrameTranslator(), glossary: Glossary())
        let work = Task { try await reader.observe(region: region, style: .text, engine: engine) }
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline, !displayedText(panel).contains("次の台詞") {
            try await Task.sleep(for: .milliseconds(20))
        }
        reader.stop()
        #expect(displayedText(panel) == "次の台詞。")
        do { try await work.value } catch is CancellationError { }
    }

    @Test func stoppedCaptureCannotPaintALateFrame() async throws {
        _ = NSApplication.shared
        let panel = TranslationPanel()
        let gate = FrameGate()
        let image = try bitmap()
        let reader = FrameReader(panel: panel, capture: { _ in await gate.wait(); return image }, recognize: { _ in [] })
        let engine = FrameTranslator(using: GatedFrameTranslator(gate: nil), glossary: Glossary())
        let work = Task { try await reader.observe(region: region, style: .text, engine: engine) }
        await entered(gate)
        reader.stop(); panel.setFooter("keep after stop")
        await gate.release()
        try await work.value
        #expect(footer(panel) == "keep after stop")
    }

    @Test func stoppedInferenceCannotPaintALateTranslation() async throws {
        _ = NSApplication.shared
        let panel = TranslationPanel()
        let gate = FrameGate()
        let image = try bitmap()
        let reader = FrameReader(panel: panel, capture: { _ in image }, recognize: { _ in
            [TextLine(text: "Cross the bridge.", box: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.1))]
        })
        let engine = FrameTranslator(using: GatedFrameTranslator(gate: gate), glossary: Glossary())
        let work = Task { try await reader.observe(region: region, style: .text, engine: engine) }
        await entered(gate)
        reader.stop(); panel.setFooter("keep after stop")
        await gate.release()
        try await work.value
        #expect(footer(panel) == "keep after stop")
        let scroll = try #require(panel.window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first)
        #expect((scroll.documentView as? NSTextView)?.string == "Cross the bridge.")
    }

    private var region: FrameRegion { FrameRegion(displayID: 1, normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), size: CGSize(width: 400, height: 200)) }
    private func displayedText(_ panel: TranslationPanel) -> String {
        let scroll = panel.window.contentView?.subviews.compactMap { $0 as? NSScrollView }.first
        return (scroll?.documentView as? NSTextView)?.string ?? ""
    }
    private func bitmap(width: Int = 80) throws -> CGImage {
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 40, bitsPerSample: 8,
                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try #require(image.cgImage)
    }
    private func entered(_ gate: FrameGate) async {
        while !(await gate.entered) { await Task.yield() }
    }
    private func footer(_ panel: TranslationPanel) -> String? {
        panel.window.contentView?.subviews.compactMap { $0 as? NSTextField }.first?.stringValue
    }
}

private struct FailingFrameTranslator: SentenceTranslator {
    struct Failure: Error { }
    func translate(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) async throws -> String {
        if source == "Old dialogue." { throw Failure() }
        return "次の台詞。"
    }
}

private actor FrameGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

private actor GatedFrameTranslator: SentenceTranslator {
    let gate: FrameGate?
    init(gate: FrameGate?) { self.gate = gate }
    func translate(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) async throws -> String {
        await gate?.wait()
        return "橋を渡る。"
    }
}
