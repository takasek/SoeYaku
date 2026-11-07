import AppKit
import SoeYakuCore
import SoeYakuRuntime
import SoeYakuVision

enum ReadingMode: String, CaseIterable, Identifiable {
    case document = "文書", frameText = "枠1・テキスト", frameImage = "枠2・画像と訳"
    var id: Self { self }
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
    private let capture: @MainActor (FrameRegion) async throws -> CGImage
    private let recognize: @Sendable (CGImage) async throws -> [TextLine]

    init(panel: TranslationPanel, capture: @escaping @MainActor (FrameRegion) async throws -> CGImage = FrameCapture.image,
         recognize: @escaping @Sendable (CGImage) async throws -> [TextLine] = TextRecognizer.lines) {
        self.panel = panel; self.capture = capture; self.recognize = recognize
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

    func start(model: URL?, style: ReadingMode) {
        guard style != .document, !running, !selecting, let region else { return }
        guard let model, FileManager.default.fileExists(atPath: model.path) else {
            status = "翻訳モデル（GGUF）を選んでください。"; return
        }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            status = WindowFollower.Problem.permission.localizedDescription; return
        }
        let id = UUID(); revision = id
        running = true; status = "翻訳モデルを読み込んでいます…"
        panel.clear(); panel.setFooter(status); panel.show()
        task = Task {
            do {
                guard let helper = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
                    .appending(path: "Helpers/start-model"), FileManager.default.isExecutableFile(atPath: helper.path) else {
                    throw AppFailure("配布用の SoeYaku.app から起動してください。")
                }
                let glossary = try Glossary.load(FileManager.default.fileExists(atPath: StoragePaths.commonGlossary.path) ? [StoragePaths.commonGlossary] : [])
                let port = try await server.start(executable: helper, model: model)
                try Task.checkCancellation()
                let engine = FrameTranslator(using: try LocalTranslator(port: port, apiKey: server.apiKey), glossary: glossary)
                guard revision == id else { return }
                try await observe(region: region, style: style, engine: engine)
            } catch is CancellationError {
            } catch {
                if revision == id { status = error.localizedDescription; panel.setFooter(status) }
            }
            guard revision == id else { return }
            server.stop(); running = false; task = nil
        }
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
    func observe(region: FrameRegion, style: ReadingMode, engine: FrameTranslator) async throws {
        let id = revision
        var lastImage: CFData?
        var lastBlocks: [FrameBlock]?
        var lastTranslations: [String] = []
        while revision == id {
            try Task.checkCancellation()
            let image = try await capture(region)
            try Task.checkCancellation()
            guard revision == id else { return }
            let data = image.dataProvider?.data
            if let data, let lastImage, CFEqual(data, lastImage) {
                try await Task.sleep(for: .milliseconds(600)); continue
            }
            let blocks = FrameText.blocks(from: try await recognize(image))
            try Task.checkCancellation()
            guard revision == id else { return }
            if blocks != lastBlocks {
                present(image, blocks: blocks, translations: [], style: style, resetScroll: true)
                status = blocks.isEmpty ? "枠内に英語の文字が見つかりません。" : "枠内の \(blocks.count) 段落を翻訳しています…"
                panel.setFooter(status)
                let translated: [String]
                do { translated = try await engine.translate(blocks) }
                catch is CancellationError { throw CancellationError() }
                catch {
                    guard revision == id else { return }
                    status = "この画面の翻訳に失敗しました。画面が変わると再試行します。 " + error.localizedDescription
                    panel.setFooter(status)
                    lastImage = data; lastBlocks = nil; lastTranslations = []
                    try await Task.sleep(for: .milliseconds(600))
                    continue
                }
                try Task.checkCancellation()
                guard revision == id else { return }
                lastTranslations = translated
            }
            present(image, blocks: blocks, translations: lastTranslations, style: style)
            status = blocks.isEmpty ? "枠内に英語の文字が見つかりません。" : "\(blocks.count) 段落を翻訳しました。画面が変わると更新します。"
            panel.setFooter(status)
            lastImage = data; lastBlocks = blocks
            try await Task.sleep(for: .milliseconds(600))
        }
    }

    private func present(_ image: CGImage, blocks: [FrameBlock], translations: [String], style: ReadingMode, resetScroll: Bool = false) {
        if style == .frameImage { panel.displayFrame(image, blocks: blocks, translations: translations) }
        else {
            let sentences = blocks.enumerated().map {
                Sentence(id: $0.offset, paragraph: $0.offset, page: 0, text: $0.element.text)
            }
            panel.display(ReadingText(sentences: sentences, translations: translations.map(Optional.some)), resetScroll: resetScroll)
        }
    }
}
