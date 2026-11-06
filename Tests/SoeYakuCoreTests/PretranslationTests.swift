import Foundation
import Testing
@testable import SoeYakuCore

private func temporaryFile(_ name: String = "memory.json") -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: name)
}

struct TranslationMemoryTests {
    @Test func keyIsSHA256OfNormalizedSourceTermsAndModel() {
        let key = TranslationMemory.key(source: "  a \n\t b ", terms: [GlossaryTerm("x", "y")], model: "m")
        #expect(key == "348a84823b0b6a954979b3b1fb5efc60b80ff3d9c6dc5a71af65187a16835d6f")
    }

    @Test func keyChangesWithTermsAndModel() {
        let base = TranslationMemory.key(source: "a", terms: [], model: "m")
        #expect(base != TranslationMemory.key(source: "a", terms: [GlossaryTerm("x", "y")], model: "m"))
        #expect(base != TranslationMemory.key(source: "a", terms: [], model: "n"))
        #expect(base == TranslationMemory.key(source: "a", terms: [], model: "m"))
    }

    @Test func savesVersionedJSONAndRoundTripsCreatingParentDirectories() throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var memory = TranslationMemory()
        memory["k"] = "訳"
        try memory.save(to: url)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary
        #expect(object == ["version": 1, "entries": ["k": "訳"]] as NSDictionary)
        #expect(try TranslationMemory.load(from: url) == memory)
    }

    @Test func loadingAMissingFileGivesAnEmptyMemory() throws {
        #expect(try TranslationMemory.load(from: temporaryFile()) == TranslationMemory())
    }
}

private actor Recorder {
    struct Call: Equatable {
        let source: String
        let context: String
        let history: [TranslationPair]
        let terms: [GlossaryTerm]
    }
    private(set) var calls: [Call] = []
    func record(_ call: Call) -> Int {
        calls.append(call)
        return calls.count
    }
}

private struct Failure: Error, Equatable { let label: String }

private struct FakeTranslator: SentenceTranslator {
    let recorder = Recorder()
    var behavior: @Sendable (String, Int) async throws -> String = { source, _ in "訳:" + source }

    func translate(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) async throws -> String {
        let count = await recorder.record(.init(source: source, context: context, history: history, terms: glossary.terms))
        return try await behavior(source, count)
    }
}

private actor ProgressLog {
    private(set) var values: [TranslationProgress] = []
    func add(_ value: TranslationProgress) { values.append(value) }
}

private func document(_ texts: [String], paragraphs: [Int]? = nil, title: String = "Title") -> SourceDocument {
    SourceDocument(fingerprint: "f", title: title, sentences: texts.enumerated().map { index, text in
        Sentence(id: index, paragraph: paragraphs?[index] ?? 0, page: 0, text: text)
    })
}

struct PretranslationTests {
    private let memoryURL = temporaryFile()

    private func pretranslation(_ texts: [String], paragraphs: [Int]? = nil, glossary: Glossary = Glossary()) -> Pretranslation {
        Pretranslation(document: document(texts, paragraphs: paragraphs), glossary: glossary, model: "m", memoryURL: memoryURL)
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: memoryURL.deletingLastPathComponent()) }

    @Test func identicalSourcesAreTranslatedOnceAndASecondRunCallsNothing() async throws {
        defer { cleanUp() }
        let job = pretranslation(["Hello.", "Other.", "Hello."])
        let translator = FakeTranslator()
        let first = try await job.run(using: translator) { _ in }
        #expect(first == ["訳:Hello.", "訳:Other.", "訳:Hello."])
        #expect(await translator.recorder.calls.map(\.source) == ["Hello.", "Other."])

        let second = FakeTranslator()
        #expect(try await job.run(using: second) { _ in } == first)
        #expect(await second.recorder.calls.isEmpty)
    }

    @Test func passesTitleTwoPreviousTranslationsAcrossParagraphsAndOnlyOccurringTerms() async throws {
        defer { cleanUp() }
        let glossary = try Glossary.parse("agent = エージェント\nspeech recognition = 音声認識", name: "g")
        let job = pretranslation(["One.", "Two.", "Three.", "The agent runs."], paragraphs: [0, 0, 1, 1], glossary: glossary)
        let translator = FakeTranslator()
        _ = try await job.run(using: translator) { _ in }
        let calls = await translator.recorder.calls
        #expect(calls.allSatisfy { $0.context == "Title" })
        #expect(calls[0].history == [])
        #expect(calls[1].history == [.init(source: "One.", translation: "訳:One.")])
        #expect(calls[3].history == [.init(source: "Two.", translation: "訳:Two."), .init(source: "Three.", translation: "訳:Three.")])
        #expect(calls[2].terms == [])
        #expect(calls[3].terms == [GlossaryTerm("agent", "エージェント")])
    }

    @Test func aFailedSentenceBecomesNilAndTheRunContinues() async throws {
        defer { cleanUp() }
        let job = pretranslation(["A.", "B.", "C."])
        var translator = FakeTranslator()
        translator.behavior = { source, _ in
            if source == "B." { throw Failure(label: "B") }
            return "訳:" + source
        }
        let progress = ProgressLog()
        let result = try await job.run(using: translator) { await progress.add($0) }
        #expect(result == ["訳:A.", nil, "訳:C."])
        #expect(await progress.values == [
            TranslationProgress(done: 1, failed: 0, total: 3),
            TranslationProgress(done: 1, failed: 1, total: 3),
            TranslationProgress(done: 2, failed: 1, total: 3)
        ])
        let history = await translator.recorder.calls[2].history
        #expect(history == [.init(source: "A.", translation: "訳:A.")])
    }

    @Test func threeConsecutiveFailuresThrowTheLastErrorAfterSavingEarlierTranslations() async throws {
        defer { cleanUp() }
        let job = pretranslation(["A.", "B.", "C.", "D.", "E."])
        var translator = FakeTranslator()
        translator.behavior = { source, _ in
            if source == "A." { return "訳:A." }
            throw Failure(label: source)
        }
        await #expect(throws: Failure(label: "D.")) { _ = try await job.run(using: translator) { _ in } }
        #expect(await translator.recorder.calls.count == 4)
        #expect(try job.cached() == ["訳:A.", nil, nil, nil, nil])
    }

    @Test func aSuccessResetsTheConsecutiveFailureCount() async throws {
        defer { cleanUp() }
        let job = pretranslation(["A.", "B.", "C.", "D.", "E.", "F."])
        var translator = FakeTranslator()
        translator.behavior = { source, _ in
            if ["C.", "F."].contains(source) { return "訳:" + source }
            throw Failure(label: source)
        }
        let result = try await job.run(using: translator) { _ in }
        #expect(result == [nil, nil, "訳:C.", nil, nil, "訳:F."])
    }

    @Test func savesEveryTenSentencesWhileRunning() async throws {
        defer { cleanUp() }
        let texts = (0..<12).map { "S\($0)." }
        let job = pretranslation(texts)
        let url = memoryURL
        var translator = FakeTranslator()
        translator.behavior = { source, count in
            if count == 11 {
                let saved = try TranslationMemory.load(from: url)
                let keys = texts.map { TranslationMemory.key(source: $0, terms: [], model: "m") }
                #expect(keys.prefix(10).allSatisfy { saved[$0] != nil })
                #expect(saved[keys[10]] == nil)
            }
            return "訳:" + source
        }
        _ = try await job.run(using: translator) { _ in }
    }

    @Test func cancellationSavesAndThrowsCancellationError() async throws {
        defer { cleanUp() }
        let job = pretranslation(["A.", "B.", "C."])
        var translator = FakeTranslator()
        translator.behavior = { source, _ in
            if source == "B." { throw CancellationError() }
            return "訳:" + source
        }
        await #expect(throws: CancellationError.self) { _ = try await job.run(using: translator) { _ in } }
        #expect(try job.cached() == ["訳:A.", nil, nil])
    }

    @Test func cachedReturnsOnlySavedTranslationsWithoutATranslator() throws {
        defer { cleanUp() }
        let job = pretranslation(["A.", "B."])
        #expect(try job.cached() == [nil, nil])
        var memory = TranslationMemory()
        memory[TranslationMemory.key(source: "B.", terms: [], model: "m")] = "保存済み"
        try memory.save(to: memoryURL)
        #expect(try job.cached() == [nil, "保存済み"])
    }

    @Test func changedGlossaryTermsInvalidateOnlyTheAffectedSentences() async throws {
        defer { cleanUp() }
        let texts = ["The agent runs.", "Plain."]
        let first = pretranslation(texts, glossary: try Glossary.parse("agent = エージェント", name: "g"))
        _ = try await first.run(using: FakeTranslator()) { _ in }
        let second = pretranslation(texts, glossary: try Glossary.parse("agent = 代理人", name: "g"))
        #expect(try second.cached() == [nil, "訳:Plain."])
    }
}
