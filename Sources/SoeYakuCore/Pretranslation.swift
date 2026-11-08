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

    private struct Entry: Sendable {
        let sentence: Sentence
        let terms: [GlossaryTerm]
        let key: String
    }

    private let title: String
    private let entries: [Entry]
    private let memoryURL: URL

    public init(document: SourceDocument, glossary: Glossary, model: String, memoryURL: URL) {
        self.title = document.title
        self.entries = document.sentences.sorted { $0.id < $1.id }.map { sentence in
            let terms = glossary.matches(in: sentence.text)
            return Entry(sentence: sentence, terms: terms,
                         key: TranslationMemory.key(source: sentence.text, terms: terms, model: model))
        }
        self.memoryURL = memoryURL
    }

    /// Saved translations only, in sentence id order; `nil` where none is saved.
    public func cached() throws -> [String?] {
        let memory = try TranslationMemory.load(from: memoryURL)
        return entries.map { memory[$0.key] }
    }

    /// One failed sentence is `nil` in the result; the third consecutive failure throws its error.
    /// Progress is saved every 10 sentences, at the end, and on cancellation, which throws `CancellationError`.
    public func run(using translator: some SentenceTranslator,
                    progress: @Sendable (TranslationProgress) async -> Void) async throws -> [String?] {
        var memory = try TranslationMemory.load(from: memoryURL)
        var results = [String?](repeating: nil, count: entries.count)
        var history: [TranslationPair] = []
        var done = 0
        var failed = 0
        var consecutiveFailures = 0

        do {
            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation()
                let sentence = entry.sentence
                let translation: String?
                if let saved = memory[entry.key] {
                    translation = saved
                } else {
                    do {
                        let translated = try await translator.translate(
                            sentence.text, context: title,
                            history: Array(history.suffix(Self.historyLength)),
                            glossary: Glossary(terms: entry.terms))
                        memory[entry.key] = translated
                        translation = translated
                    } catch {
                        if error is CancellationError || Task.isCancelled { throw CancellationError() }
                        failed += 1
                        consecutiveFailures += 1
                        if consecutiveFailures >= Self.consecutiveFailureLimit {
                            try memory.save(to: memoryURL)
                            throw error
                        }
                        translation = nil
                    }
                }
                if let translation {
                    results[index] = translation
                    history.append(TranslationPair(source: sentence.text, translation: translation))
                    done += 1
                    consecutiveFailures = 0
                }
                await progress(TranslationProgress(done: done, failed: failed, total: entries.count))
                if (index + 1) % Self.saveInterval == 0 { try memory.save(to: memoryURL) }
            }
        } catch is CancellationError {
            try? memory.save(to: memoryURL)
            throw CancellationError()
        }
        try memory.save(to: memoryURL)
        return results
    }
}
