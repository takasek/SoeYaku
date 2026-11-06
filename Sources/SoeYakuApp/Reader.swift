import AppKit
import SoeYakuCore
import SoeYakuRuntime
import UniformTypeIdentifiers

/// The app's state: the open document, its saved translations, the translation run and the position following.
@MainActor final class Reader: ObservableObject {
    @Published private(set) var document: SourceDocument?
    @Published private(set) var documentURL: URL?
    @Published private(set) var translations: [String?] = []
    @Published private(set) var progress: TranslationProgress?
    @Published private(set) var translating = false
    @Published private(set) var loading = false
    @Published private(set) var following = false
    @Published private(set) var status = "英語の PDF を開いてください。"
    @Published var model: URL?
    @Published var fontSize = UserDefaults.standard.double(forKey: "fontSize").clampedFont {
        didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize"); panel.fontSize = fontSize }
    }

    let panel = TranslationPanel()
    private let server = ModelServer()
    private var run: Task<Void, Never>?
    private var follower: WindowFollower?
    private(set) var loadingTask: Task<Void, Never>?
    private var loadID = UUID()
    private let loadDocument: @Sendable (URL) async throws -> SourceDocument

    var translatedCount: Int { translations.lazy.compactMap { $0 }.count }

    init(loadDocument: @escaping @Sendable (URL) async throws -> SourceDocument = { url in
        try await Task.detached { try PDFExtractor.extract(url: url) }.value
    }) {
        self.loadDocument = loadDocument
        panel.fontSize = fontSize
        if let path = UserDefaults.standard.string(forKey: "modelPath") {
            model = URL(filePath: path)
        } else {
            // dist/SoeYaku.app sits two levels below the repository, whose local/models holds the GGUF.
            let root = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            let candidate = root.appending(path: "local/models/plamo-3-translate-2b-Q4_K_M.gguf")
            if FileManager.default.fileExists(atPath: candidate.path) { model = candidate }
        }
    }

    // MARK: Document

    func choosePDF() {
        let panel = NSOpenPanel()
        panel.title = "英語の PDF を選択"
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard !translating else { return }
        stopFollowing()
        loadingTask?.cancel()
        let id = UUID()
        loadID = id
        loading = true
        document = nil
        documentURL = nil
        translations = []
        panel.clear()
        status = "本文を読み取っています…"
        loadingTask = Task {
            defer {
                if loadID == id { loading = false; loadingTask = nil }
            }
            do {
                let extracted = try await loadDocument(url)
                try Task.checkCancellation()
                let job = try await pretranslation(for: extracted)
                let saved = try job.cached()
                guard loadID == id, !Task.isCancelled else { return }
                document = extracted
                documentURL = url
                translations = saved
                refreshPanel()
                panel.show()
                status = "\(extracted.sentences.count) 文のうち \(translatedCount) 文が翻訳済みです。"
            } catch {
                guard loadID == id, !Task.isCancelled else { return }
                status = error.localizedDescription
            }
        }
    }

    func openInPreview() {
        guard let documentURL,
              let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: WindowFollower.previewBundleID) else { return }
        NSWorkspace.shared.open([documentURL], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Translation

    func chooseModel() {
        guard !translating, !loading else { return }
        let panel = NSOpenPanel()
        panel.title = "PLaMo 3 Translate の GGUF を選択"
        if panel.runModal() == .OK, let url = panel.url {
            model = url
            UserDefaults.standard.set(url.path, forKey: "modelPath")
            if let documentURL { open(documentURL) }
        }
    }

    func translateAll() {
        guard !translating, !loading, let document else { return }
        guard let model, FileManager.default.fileExists(atPath: model.path) else {
            status = "翻訳モデル（GGUF）を選んでください。"
            return
        }
        translating = true
        progress = TranslationProgress(done: translatedCount, failed: 0, total: document.sentences.count)
        status = "翻訳モデルを読み込んでいます…"
        run = Task {
            var job: Pretranslation?
            do {
                let prepared = try await pretranslation(for: document, requireModel: true)
                job = prepared
                try Task.checkCancellation()
                guard let helper = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
                    .appending(path: "Helpers/start-model"), FileManager.default.isExecutableFile(atPath: helper.path) else {
                    throw AppFailure("アプリ内の翻訳ヘルパーが見つかりません。Scripts/build-app.sh で作った SoeYaku.app から起動してください。")
                }
                let port = try await server.start(executable: helper, model: model)
                let translator = try LocalTranslator(port: port, apiKey: server.apiKey)
                status = "全文を翻訳しています。訳した文から順に保存します。"
                let result = try await prepared.run(using: translator) { [weak self] step in
                    await self?.advance(step, job: prepared)
                }
                translations = result
                let failed = result.filter { $0 == nil }.count
                status = failed == 0 ? "全 \(result.count) 文の翻訳が終わりました。"
                    : "\(result.count) 文のうち \(failed) 文を翻訳できませんでした。もう一度「全文を翻訳」を押すと未訳の文だけを訳します。"
            } catch is CancellationError {
                status = "翻訳を中断しました。訳し終えた文は保存してあり、次回は続きから訳します。"
            } catch {
                status = error.localizedDescription + " 訳し終えた文は保存してあります。"
            }
            if let refreshed = try? job?.cached() { translations = refreshed }
            refreshPanel()
            server.stop()
            translating = false
            progress = nil
            run = nil
        }
    }

    func cancelTranslation() { run?.cancel() }

    private func advance(_ step: TranslationProgress, job: Pretranslation) {
        progress = step
        // The run saves every 10 sentences; show what has been saved so far.
        if step.done % 10 == 0, let saved = try? job.cached() {
            translations = saved
            refreshPanel()
        }
    }

    private func pretranslation(for document: SourceDocument, requireModel: Bool = false) async throws -> Pretranslation {
        let selectedModel = model
        let identity = try await Task.detached {
            guard let selectedModel else { return "" }
            do { return try ModelIdentity.forFile(selectedModel) }
            catch {
                if requireModel { throw error }
                // Reading and locating remain available when an old model path is no longer accessible.
                return ""
            }
        }.value
        return Pretranslation(document: document, glossary: try glossary(for: document), model: identity,
                       memoryURL: StoragePaths.memory(for: document.fingerprint))
    }

    // MARK: Glossary

    private func glossary(for document: SourceDocument) throws -> Glossary {
        let files = [StoragePaths.commonGlossary, StoragePaths.documentGlossary(for: document.fingerprint)]
        return try Glossary.load(files.filter { FileManager.default.fileExists(atPath: $0.path) })
    }

    func openCommonGlossary() { edit(StoragePaths.commonGlossary, scope: "共通") }

    func openDocumentGlossary() {
        guard let document else { return }
        edit(StoragePaths.documentGlossary(for: document.fingerprint), scope: "「\(document.title)」")
    }

    private func edit(_ url: URL, scope: String) {
        do {
            try Storage.ensureGlossary(at: url, scope: scope)
            NSWorkspace.shared.open(url)
            status = "用語集を保存したら「全文を翻訳」で、その用語を含む文だけを訳し直します。"
        } catch {
            status = error.localizedDescription
        }
    }

    func copyGlossaryForKikiyaku() {
        guard let document else { return }
        do {
            let text = try glossary(for: document).kikiyakuText(appliedTo: document.sentences.map(\.text))
            guard !text.isEmpty else {
                status = "この文書に出てくる用語は用語集にありません。"
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let count = text.split(separator: "\n").count
            status = "この文書で使う \(count) 語を「原語 = 訳語」の形でコピーしました。Kikiyaku の用語集欄に貼り付けられます。"
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: Following

    func toggleFollowing() { following ? stopFollowing() : startFollowing() }

    private func startFollowing() {
        guard !loading, let document else { return }
        let id = loadID
        let follower = WindowFollower(document: document, excludedWindows: [panel.window], documentName: documentURL?.lastPathComponent)
        follower.onResult = { [weak self] result in
            guard let self, self.loadID == id else { return }
            self.show(result)
        }
        follower.onProblem = { [weak self] message in
            guard let self, self.loadID == id else { return }
            self.panel.setFooter(message)
        }
        do {
            try follower.start()
            self.follower = follower
            following = true
            panel.show()
            panel.setFooter("プレビューで読みたい文にポインターを置いてください。")
            status = "プレビューの表示に追従しています。ポインターの下の文の訳を強調します。"
        } catch {
            status = error.localizedDescription
        }
    }

    func stopFollowing() {
        follower?.stop()
        follower = nil
        if following { status = "追従を止めました。" }
        following = false
    }

    private func show(_ result: LocateResult) {
        guard let document else { return }
        switch result {
        case .matched(let sentence, _):
            guard document.sentences.indices.contains(sentence) else { return }
            panel.highlight(sentence: sentence, source: document.sentences[sentence].text)
        case .unresolved:
            panel.setFooter("現在地を特定できません。本文の行にポインターを置いてください。")
        }
    }

    func showPanel() { panel.show(focus: true) }

    private func refreshPanel() {
        guard let document else { return }
        panel.display(ReadingText(document: document, translations: translations))
    }

    func shutdown() {
        loadID = UUID()
        loadingTask?.cancel()
        run?.cancel()
        follower?.stop()
        server.stop()
    }
}

struct AppFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private extension Double {
    var clampedFont: Double { (12...40).contains(self) ? self : 18 }
}
