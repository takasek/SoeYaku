import Foundation

public struct TranslationProgress: Sendable, Equatable {
    public let done: Int
    public let failed: Int
    public let total: Int

    public init(done: Int, failed: Int, total: Int) {
        self.done = done
        self.failed = failed
        self.total = total
    }
}

/// Translates every sentence of a document in order, reusing and saving translations in a `TranslationMemory` file.
public struct Pretranslation: Sendable {
    private static let saveInterval = 10
    private static let consecutiveFailureLimit = 3
    private static let historyLength = 2

    private let document: SourceDocument
    private let glossary: Glossary
    private let model: String
    private let memoryURL: URL

    public init(document: SourceDocument, glossary: Glossary, model: String, memoryURL: URL) {
        self.document = document
        self.glossary = glossary
        self.model = model
        self.memoryURL = memoryURL
    }

    /// Saved translations only, in sentence id order; `nil` where none is saved.
    public func cached() throws -> [String?] {
        let memory = try TranslationMemory.load(from: memoryURL)
        return sentences.map { memory[key(for: $0)] }
    }

    /// One failed sentence is `nil` in the result; the third consecutive failure throws its error.
    /// Progress is saved every 10 sentences, at the end, and on cancellation, which throws `CancellationError`.
    public func run(using translator: some SentenceTranslator,
                    progress: @Sendable (TranslationProgress) async -> Void) async throws -> [String?] {
        var memory = try TranslationMemory.load(from: memoryURL)
        var results = [String?](repeating: nil, count: sentences.count)
        var history: [TranslationPair] = []
        var done = 0
        var failed = 0
        var consecutiveFailures = 0

        do {
            for (index, sentence) in sentences.enumerated() {
                try Task.checkCancellation()
                let key = key(for: sentence)
                if let saved = memory[key] {
                    results[index] = saved
                    history.append(TranslationPair(source: sentence.text, translation: saved))
                    done += 1
                    consecutiveFailures = 0
                } else {
                    do {
                        let translated = try await translator.translate(
                            sentence.text, context: document.title,
                            history: Array(history.suffix(Self.historyLength)),
                            glossary: Glossary(terms: glossary.matches(in: sentence.text)))
                        memory[key] = translated
                        results[index] = translated
                        history.append(TranslationPair(source: sentence.text, translation: translated))
                        done += 1
                        consecutiveFailures = 0
                    } catch {
                        if error is CancellationError || Task.isCancelled { throw CancellationError() }
                        failed += 1
                        consecutiveFailures += 1
                        if consecutiveFailures >= Self.consecutiveFailureLimit {
                            try memory.save(to: memoryURL)
                            throw error
                        }
                    }
                }
                await progress(TranslationProgress(done: done, failed: failed, total: sentences.count))
                if (index + 1) % Self.saveInterval == 0 { try memory.save(to: memoryURL) }
            }
        } catch is CancellationError {
            try? memory.save(to: memoryURL)
            throw CancellationError()
        }
        try memory.save(to: memoryURL)
        return results
    }

    private var sentences: [Sentence] { document.sentences.sorted { $0.id < $1.id } }

    private func key(for sentence: Sentence) -> String {
        TranslationMemory.key(source: sentence.text, terms: glossary.matches(in: sentence.text), model: model)
    }
}
