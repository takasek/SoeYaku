import CryptoKit
import Foundation

/// Saved translations keyed by source text, the glossary terms that apply to it and the model.
public struct TranslationMemory: Codable, Sendable, Equatable {
    private var version = 1
    private var entries: [String: String] = [:]

    public init() {}

    public static func key(source: String, terms: [GlossaryTerm], model: String) -> String {
        let normalized = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let parts = [normalized] + terms.map { "\($0.source)\u{1F}\($0.target)" } + [model]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1E}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public subscript(key: String) -> String? {
        get { entries[key] }
        set { entries[key] = newValue }
    }

    /// A missing file is an empty memory.
    public static func load(from url: URL) throws -> TranslationMemory {
        guard FileManager.default.fileExists(atPath: url.path) else { return TranslationMemory() }
        return try JSONDecoder().decode(TranslationMemory.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
