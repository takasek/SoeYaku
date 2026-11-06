import CoreGraphics
import Foundation
import ImageIO
import SoeYakuCore
import SoeYakuVision

public enum CLIError: Error, LocalizedError, Equatable {
    case unreadableImage(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let path): "画像を読み込めませんでした: \(path)"
        }
    }
}

/// What each `soeyaku-cli` command prints, as lines of JSON.
public enum CLI {
    public static let defaultModel = "plamo-3-translate-2b-Q4_K_M.gguf"

    public static func extractLines(file: URL) throws -> [String] {
        try PDFExtractor.extract(url: file).sentences.map {
            jsonLine([("id", $0.id), ("paragraph", $0.paragraph), ("page", $0.page), ("text", $0.text)])
        }
    }

    /// The glossary files to load: exactly `given` when it is not empty, otherwise the common and the document glossary that exist.
    static func glossaryFiles(given: [String], fingerprint: String, exists: (URL) -> Bool) -> [URL] {
        if !given.isEmpty { return given.map { URL(fileURLWithPath: $0) } }
        return [StoragePaths.commonGlossary, StoragePaths.documentGlossary(for: fingerprint)].filter(exists)
    }

    /// Translates the whole document, reusing and saving translations in the memory file, and returns `{"id","en","ja"}` per sentence.
    /// `ja` is `null` for a sentence that failed.
    public static func translateLines(
        _ options: TranslateOptions, translator: some SentenceTranslator,
        progress: @Sendable (TranslationProgress) async -> Void
    ) async throws -> [String] {
        let document = try PDFExtractor.extract(url: URL(fileURLWithPath: options.file))
        let files = glossaryFiles(given: options.glossaries, fingerprint: document.fingerprint) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        let memory = options.memory.map { URL(fileURLWithPath: $0) } ?? StoragePaths.memory(for: document.fingerprint)
        let pretranslation = Pretranslation(
            document: document, glossary: try Glossary.load(files), model: try modelIdentity(options), memoryURL: memory)
        let results = try await pretranslation.run(using: translator, progress: progress)
        return zip(document.sentences.sorted { $0.id < $1.id }, results).map { sentence, ja in
            jsonLine([("id", sentence.id), ("en", sentence.text), ("ja", ja.map { $0 as Any } ?? NSNull())])
        }
    }

    private static func modelIdentity(_ options: TranslateOptions) throws -> String {
        if let version = options.model { return version }
        let file = URL(fileURLWithPath: options.modelFile ?? "local/models/\(defaultModel)")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw UsageError("モデルを識別できません。--model-file でサーバーが使う GGUF、または --model で固有のバージョンを指定してください。")
        }
        return try ModelIdentity.forFile(file)
    }

    /// Recognizes the text in `image`, finds the sentence under `pointer` (image pixels, top-left origin) and returns one JSON line.
    public static func locateLine(file: URL, image: URL, pointer: CGPoint) async throws -> String {
        let document = try PDFExtractor.extract(url: file)
        guard let source = CGImageSourceCreateWithURL(image as CFURL, nil),
              let picture = CGImageSourceCreateImageAtIndex(source, 0, nil), picture.width > 0, picture.height > 0
        else { throw CLIError.unreadableImage(image.path) }
        let lines = try await TextRecognizer.lines(in: picture)
        var locator = Locator(index: DocumentIndex(document))
        let normalized = CGPoint(x: pointer.x / CGFloat(picture.width), y: pointer.y / CGFloat(picture.height))
        switch locator.locate(lines: lines, pointer: normalized) {
        case .matched(let id, let confidence):
            let text = document.sentences.first { $0.id == id }?.text ?? ""
            return jsonLine([("status", "matched"), ("sentence", id), ("text", text), ("confidence", confidence)])
        case .unresolved:
            return jsonLine([("status", "unresolved")])
        }
    }

    /// One JSON object on one line with the keys in the order given.
    static func jsonLine(_ fields: [(String, Any)]) -> String {
        let options: JSONSerialization.WritingOptions = [.fragmentsAllowed, .withoutEscapingSlashes]
        let members = fields.map { key, value -> String in
            let encode = { (value: Any) -> String in
                String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: options)) ?? Data("null".utf8), as: UTF8.self)
            }
            return encode(key) + ":" + encode(value)
        }
        return "{" + members.joined(separator: ",") + "}"
    }
}
