import CryptoKit
import Foundation

/// One source sentence in reading order. `id` is its index in `SourceDocument.sentences`.
public struct Sentence: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    /// 0-based paragraph index; consecutive sentences with the same value form one paragraph.
    public let paragraph: Int
    /// 0-based PDF page on which the sentence starts; HTML uses 0.
    public let page: Int
    public let text: String

    public init(id: Int, paragraph: Int, page: Int, text: String) {
        self.id = id
        self.paragraph = paragraph
        self.page = page
        self.text = text
    }
}

/// The body text of one file, split into sentences in reading order.
public struct SourceDocument: Codable, Sendable, Equatable {
    /// Lowercase SHA-256 hex of the file bytes. Saved translations are keyed by it.
    public let fingerprint: String
    public let title: String
    public let sentences: [Sentence]

    public init(fingerprint: String, title: String, sentences: [Sentence]) {
        self.fingerprint = fingerprint
        self.title = title
        self.sentences = sentences
    }

    public static func fingerprint(of data: Data) -> String {
        SHA256.hash(data: data).lowercaseHex
    }
}
