import Foundation

struct TranslationError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

public struct GlossaryTerm: Sendable, Equatable {
    public let source: String
    public let target: String

    public init(_ source: String, _ target: String) {
        self.source = source
        self.target = target
    }

    /// English words inside longer words (e.g. "app" in "happens") must not match.
    public func occurs(in text: String) -> Bool {
        let literal = NSRegularExpression.escapedPattern(for: source)
        let pattern = #"(?<![\p{L}\p{N}_])"# + literal + #"(?![\p{L}\p{N}_])"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

public struct Glossary: Sendable, Equatable {
    public private(set) var terms: [GlossaryTerm] = []

    public init() {}

    init(terms: [GlossaryTerm]) { self.terms = terms }

    /// Lines are `source<TAB>target` or `source = target`; blank lines and `#` comments are ignored.
    public static func parse(_ text: String, name: String) throws -> Glossary {
        var glossary = Glossary()
        for (index, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.isEmpty || clean.hasPrefix("#") { continue }
            let fields: [String]
            if line.contains("\t") {
                fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(trimmed)
            } else {
                fields = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(trimmed)
            }
            guard fields.count == 2, !fields[0].isEmpty, !fields[1].isEmpty else {
                throw TranslationError("\(name) の \(index + 1) 行目を「原語・タブ・訳語」または「原語 = 訳語」の形式にしてください。")
            }
            glossary.add(GlossaryTerm(fields[0], fields[1]))
        }
        return glossary
    }

    /// Later terms replace earlier ones with the same source (case-insensitive) and take the later position.
    public mutating func overlay(_ other: Glossary) {
        for term in other.terms { add(term) }
    }

    public static func load(_ files: [URL]) throws -> Glossary {
        var glossary = Glossary()
        for file in files {
            guard file.isFileURL else { throw TranslationError("用語集にはローカルファイルを指定してください。") }
            let content = try String(contentsOf: file, encoding: .utf8)
            glossary.overlay(try parse(content, name: file.lastPathComponent))
        }
        return glossary
    }

    public func matches(in text: String) -> [GlossaryTerm] {
        terms.filter { $0.occurs(in: text) }
    }

    /// One `source = target` line per term that occurs in any of `texts`, in glossary order.
    public func kikiyakuText(appliedTo texts: [String]) -> String {
        terms.filter { term in texts.contains { term.occurs(in: $0) } }
            .map { "\($0.source) = \($0.target)\n" }
            .joined()
    }

    private mutating func add(_ term: GlossaryTerm) {
        terms.removeAll { $0.source.caseInsensitiveCompare(term.source) == .orderedSame }
        terms.append(term)
    }

    private static func trimmed(_ field: Substring) -> String { field.trimmingCharacters(in: .whitespaces) }
}
