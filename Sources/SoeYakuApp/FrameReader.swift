import AppKit
import SoeYakuCore
import SoeYakuRuntime
import SoeYakuVision

enum ReadingMode: String, CaseIterable, Identifiable {
    case document = "文書", frameText = "枠1・テキスト", frameImage = "枠2・画像と訳"
    var id: Self { self }

    /// How a frame mode shows its translation; the document mode has none.
    var frameStyle: FrameStyle? {
        switch self {
        case .document: nil
        case .frameText: .text
        case .frameImage: .image
        }
    }

    /// Whether the translation is shown as text sized by the font size setting; the image frame fits its text to each block.
    var usesFontSize: Bool { frameStyle != .image }
}

/// How the translation of a screen region is shown: as continuous text, or over a copy of the region's image.
enum FrameStyle {
    case text, image
}

@MainActor final class FrameReader: ObservableObject {
    @Published private(set) var region: FrameRegion?
    @Published private(set) var selecting = false
    @Published private(set) var running = false
    @Published private(set) var status = "画面から翻訳したい範囲を選んでください。"
    private let panel: TranslationPanel
    private let selection = FrameSelection()
    private let server = ModelServer()
    private var task: Task<Void, Never>?
    private var revision = UUID()
    private let makeCapture: @MainActor () -> @MainActor (FrameRegion) async throws -> CGImage
    private let recognize: @Sendable (CGImage) async throws -> [TextLine]

    /// Without `capture`, each `observe` session captures through its own `FrameCapture`.
    init(panel: TranslationPanel, capture: (@MainActor (FrameRegion) async throws -> CGImage)? = nil,
         recognize: @escaping @Sendable (CGImage) async throws -> [TextLine] = TextRecognizer.lines) {
        self.panel = panel; self.recognize = recognize
        if let capture {
            makeCapture = { capture }
        } else {
            makeCapture = {
                let session = FrameCapture()
                return { try await session.image(in: $0) }
            }
        }
    }

    func chooseRegion() {
        stop()
        selecting = true
        selection.choose { [weak self] region in
            guard let self else { return }
            selecting = false
            if let region {
                self.region = region
                status = "\(Int(region.size.width)) × \(Int(region.size.height)) の枠を選びました。翻訳を開始できます。"
            } else { status = "枠の選択をキャンセルしました。" }
        }
    }

    func start(model: URL?, style: FrameStyle) {
        guard !running, !selecting, let region else { return }
        guard let model, FileManager.default.fileExists(atPath: model.path) else {
            status = "翻訳モデル（GGUF）を選んでください。"; return
        }
        do { try ScreenRecording.requestAccess() }
        catch { status = error.localizedDescription; return }
        let id = UUID(); revision = id
        running = true; status = "翻訳モデルを読み込んでいます…"
        panel.clear(); panel.setFooter(status); panel.show()
        task = Task {
            do {
                let helper = try BundledHelper.modelStarter(missingMessage: "配布用の SoeYaku.app から起動してください。")
                let glossary = try Glossary.loadExisting([StoragePaths.commonGlossary])
                let port = try await server.start(executable: helper, model: model)
                try Task.checkCancellation()
                let engine = FrameTranslator(using: try LocalTranslator(port: port, apiKey: server.apiKey), glossary: glossary)
                guard revision == id else { return }
                try await observe(region: region, style: style, engine: engine)
            } catch is CancellationError {
            } catch {
                if revision == id { report(error.localizedDescription) }
            }
            guard revision == id else { return }
            server.stop(); running = false; task = nil
        }
    }

    private static let emptyFrameMessage = "枠内に英語の文字が見つかりません。"

    private func report(_ text: String) {
        status = text
        panel.setFooter(text)
    }

    func stop() {
        revision = UUID()
        task?.cancel(); task = nil
        server.stop()
        if selecting { selection.cancel(); selecting = false }
        if running { status = "枠の翻訳を止めました。" }
        running = false
    }

    /// Serialized snapshots: a translated batch always remains paired with its captured image.
    func observe(region: FrameRegion, style: FrameStyle, engine: FrameTranslator) async throws {
        let id = revision
        let capture = makeCapture()
        var lastPixels: CapturedPixels?
        var lastBlocks: [FrameBlock]?
        var lastTranslations: [String] = []
        while revision == id {
            try Task.checkCancellation()
            let image = try await capture(region)
            try Task.checkCancellation()
            guard revision == id else { return }
            let pixels = CapturedPixels(image)
            if pixels.matches(lastPixels) {
                try await Task.sleep(for: .milliseconds(600)); continue
            }
            let blocks = FrameText.blocks(from: try await recognize(image))
            try Task.checkCancellation()
            guard revision == id else { return }
            if blocks != lastBlocks {
                present(image, blocks: blocks, translations: [], style: style, resetScroll: true)
                report(blocks.isEmpty ? Self.emptyFrameMessage : "枠内の \(blocks.count) 段落を翻訳しています…")
                let translated: [String]
                do { translated = try await engine.translate(blocks) }
                catch is CancellationError { throw CancellationError() }
                catch {
                    guard revision == id else { return }
                    report("この画面の翻訳に失敗しました。画面が変わると再試行します。 " + error.localizedDescription)
                    lastPixels = pixels; lastBlocks = nil; lastTranslations = []
                    try await Task.sleep(for: .milliseconds(600))
                    continue
                }
                try Task.checkCancellation()
                guard revision == id else { return }
                lastTranslations = translated
            }
            present(image, blocks: blocks, translations: lastTranslations, style: style)
            report(blocks.isEmpty ? Self.emptyFrameMessage : "\(blocks.count) 段落を翻訳しました。画面が変わると更新します。")
            lastPixels = pixels; lastBlocks = blocks
            try await Task.sleep(for: .milliseconds(600))
        }
    }

    private func present(_ image: CGImage, blocks: [FrameBlock], translations: [String], style: FrameStyle, resetScroll: Bool = false) {
        switch style {
        case .image:
            panel.displayFrame(image, blocks: blocks, translations: translations)
        case .text:
            let sentences = blocks.enumerated().map {
                Sentence(id: $0.offset, paragraph: $0.offset, page: 0, text: $0.element.text)
            }
            panel.display(ReadingText(sentences: sentences, translations: translations.map(Optional.some)), resetScroll: resetScroll)
        }
    }
}
