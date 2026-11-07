import AppKit
import SoeYakuCore
import Testing
@testable import SoeYakuApp

@Suite(.serialized) @MainActor struct ReaderTests {
    private func reader(_ loader: DocumentLoader) -> Reader {
        _ = NSApplication.shared
        return Reader(loadDocument: { try await loader.load($0) })
    }

    @Test func aStalePDFCompletionCannotReplaceTheNewerDocument() async throws {
        let loader = DocumentLoader()
        let reader = reader(loader)
        let first = URL(filePath: "/tmp/first.pdf"), second = URL(filePath: "/tmp/second.pdf")
        reader.open(first)
        let firstTask = try #require(reader.loadingTask)
        await loader.waitUntilStarted(first)
        reader.open(second)
        let secondTask = try #require(reader.loadingTask)
        await loader.waitUntilStarted(second)
        await loader.finish(second)
        await secondTask.value
        await loader.finish(first)
        await firstTask.value
        #expect(reader.documentURL == second)
        #expect(reader.document?.title == "second")
        #expect(!reader.loading)
        reader.shutdown()
    }

    @Test func replacingAPDFClearsTheOldSessionAndBlocksItsActions() async throws {
        let loader = DocumentLoader()
        let reader = reader(loader)
        let first = URL(filePath: "/tmp/first.pdf"), second = URL(filePath: "/tmp/second.pdf")
        reader.open(first)
        let firstTask = try #require(reader.loadingTask)
        await loader.waitUntilStarted(first)
        await loader.finish(first)
        await firstTask.value
        reader.open(second)
        let secondTask = try #require(reader.loadingTask)
        await loader.waitUntilStarted(second)
        #expect(reader.loading)
        #expect(reader.document == nil && reader.documentURL == nil && reader.translations.isEmpty)
        reader.translateAll()
        reader.toggleFollowing()
        #expect(!reader.translating && !reader.following)
        await loader.finish(second)
        await secondTask.value
        #expect(reader.documentURL == second)
        reader.shutdown()
    }

    @Test func aMissingPreviouslySelectedModelDoesNotPreventReadingAPDF() async throws {
        let loader = DocumentLoader()
        let reader = reader(loader)
        reader.model = URL(filePath: "/tmp/missing-model-\(UUID().uuidString).gguf")
        let pdf = URL(filePath: "/tmp/document.pdf")
        reader.open(pdf)
        let task = try #require(reader.loadingTask)
        await loader.waitUntilStarted(pdf)
        await loader.finish(pdf)
        await task.value
        #expect(reader.documentURL == pdf)
        #expect(reader.document?.sentences.count == 1)
        reader.translateAll()
        #expect(!reader.translating)
        reader.shutdown()
    }

    @Test func aReportedTranslationReplacesOnlyItsSentence() async throws {
        let loader = DocumentLoader()
        let reader = reader(loader)
        let pdf = URL(filePath: "/tmp/document.pdf")
        reader.open(pdf)
        let task = try #require(reader.loadingTask)
        await loader.waitUntilStarted(pdf)
        await loader.finish(pdf)
        await task.value
        #expect(reader.translations == [nil])
        reader.record("訳", at: 0)
        reader.record("範囲外", at: 1)
        #expect(reader.translations == ["訳"])
        reader.shutdown()
    }

    @Test func opensStaticHTMLThroughTheSharedDocumentLoaderAndChoosesBrowserFollowing() async throws {
        _ = NSApplication.shared
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("soeyaku-html-\(UUID().uuidString).html")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("<html><title>Article</title><main><p>The first paragraph.</p><p>The second paragraph.</p></main></html>".utf8).write(to: file)
        let reader = Reader()
        reader.model = nil
        reader.open(file)
        let task = try #require(reader.loadingTask)
        await task.value
        #expect(reader.document?.title == "Article")
        #expect(reader.document?.sentences.map(\.text) == ["The first paragraph.", "The second paragraph."])
        #expect(reader.isHTML)
        #expect(reader.viewer == .browser(bundleID: reader.browserBundleID, titles: ["Article", file.lastPathComponent, file.absoluteString]))
        #expect(reader.documentURL == file)
        #expect(reader.translations == [nil, nil])
        reader.shutdown()
    }
}

private actor DocumentLoader {
    private var pending: [URL: CheckedContinuation<SourceDocument, any Error>] = [:]
    private var waiters: [URL: CheckedContinuation<Void, Never>] = [:]

    func load(_ url: URL) async throws -> SourceDocument {
        try await withCheckedThrowingContinuation { continuation in
            pending[url] = continuation
            waiters.removeValue(forKey: url)?.resume()
        }
    }

    func waitUntilStarted(_ url: URL) async {
        if pending[url] != nil { return }
        await withCheckedContinuation { waiters[url] = $0 }
    }

    func finish(_ url: URL) {
        pending.removeValue(forKey: url)?.resume(returning: SourceDocument(
            fingerprint: UUID().uuidString, title: url.deletingPathExtension().lastPathComponent,
            sentences: [Sentence(id: 0, paragraph: 0, page: 0, text: "A sample document.")]))
    }
}
