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

    var translatedCount: Int { translations.lazy.compactMap { $0 }.count }

    init() {
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
        status = "本文を読み取っています…"
        Task {
            do {
                let extracted = try await Task.detached { try PDFExtractor.extract(url: url) }.value
                document = extracted
                documentURL = url
                translations = try pretranslation(for: extracted).cached()
                refreshPanel()
                panel.show()
                status = "\(extracted.sentences.count) 文のうち \(translatedCount) 文が翻訳済みです。"
            } catch {
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
        let panel = NSOpenPanel()
        panel.title = "PLaMo 3 Translate の GGUF を選択"
        if panel.runModal() == .OK, let url = panel.url {
            model = url
            UserDefaults.standard.set(url.path, forKey: "modelPath")
        }
    }

    func translateAll() {
        guard !translating, let document else { return }
        guard let model, FileManager.default.fileExists(atPath: model.path) else {
            status = "翻訳モデル（GGUF）を選んでください。"
            return
        }
        translating = true
        progress = TranslationProgress(done: translatedCount, failed: 0, total: document.sentences.count)
        status = "翻訳モデルを読み込んでいます…"
        run = Task {
            do {
                let job = try pretranslation(for: document)
                guard let helper = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
                    .appending(path: "Helpers/start-model"), FileManager.default.isExecutableFile(atPath: helper.path) else {
                    throw AppFailure("アプリ内の翻訳ヘルパーが見つかりません。Scripts/build-app.sh で作った SoeYaku.app から起動してください。")
                }
                let port = try await server.start(executable: helper, model: model)
                let translator = try LocalTranslator(port: port, apiKey: server.apiKey)
                status = "全文を翻訳しています。訳した文から順に保存します。"
                let result = try await job.run(using: translator) { [weak self] step in
                    await self?.advance(step, job: job)
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
            if let refreshed = try? pretranslation(for: document).cached() { translations = refreshed }
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

    private func pretranslation(for document: SourceDocument) throws -> Pretranslation {
        Pretranslation(document: document, glossary: try glossary(for: document), model: model?.lastPathComponent ?? "",
                       memoryURL: Storage.memory(for: document.fingerprint))
    }

    // MARK: Glossary

    private func glossary(for document: SourceDocument) throws -> Glossary {
        let files = [Storage.commonGlossary, Storage.documentGlossary(for: document.fingerprint)]
        return try Glossary.load(files.filter { FileManager.default.fileExists(atPath: $0.path) })
    }

    func openCommonGlossary() { edit(Storage.commonGlossary, scope: "共通") }

    func openDocumentGlossary() {
        guard let document else { return }
        edit(Storage.documentGlossary(for: document.fingerprint), scope: "「\(document.title)」")
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
        guard let document else { return }
        let follower = WindowFollower(document: document)
        follower.onResult = { [weak self] result in self?.show(result) }
        follower.onProblem = { [weak self] message in self?.panel.setFooter(message) }
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
            panel.highlight(sentence: sentence, source: document.sentences[sentence].text)
        case .unresolved:
            panel.setFooter("現在地を特定できません。本文の行にポインターを置いてください。")
        }
    }

    func showPanel() { panel.show() }

    private func refreshPanel() {
        guard let document else { return }
        panel.display(ReadingText(document: document, translations: translations))
    }

    func shutdown() {
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
