import CoreFoundation
import Foundation
import SwiftSoup

public enum HTMLExtractionError: Error, Equatable, LocalizedError {
    case unreadable
    case noText

    public var errorDescription: String? {
        switch self {
        case .unreadable: "HTML の文字を読み取れませんでした。文字コードを確認してください。"
        case .noText: "この HTML には読み取れる本文がありません。JavaScript で作られるページは、本文を含む HTML として保存してください。"
        }
    }
}

/// Extracts static HTML without executing scripts or loading linked resources.
public enum HTMLExtractor {
    public static func extract(data: Data, fallbackTitle: String, textEncodingName: String? = nil) throws -> SourceDocument {
        let html = try decode(data, encodingName: textEncodingName)
        let dom = try SwiftSoup.parseHTML(html)
        let title = TextNormalizer.collapsingWhitespace(try dom.title())
        try dom.select("head, script, style, template, noscript, nav, aside, form, button, input, select, textarea, svg, canvas, [hidden], [inert]").remove()
        for element in try dom.select("[aria-hidden], [style]") {
            if try element.attr("aria-hidden").lowercased() == "true" || hiddenStyle(element.attr("style")) {
                try element.remove()
            }
        }
        guard let body = dom.body() else { throw HTMLExtractionError.noText }
        let articles = try body.select("article")
        let root = try body.select("main, [role=main]").first() ?? (articles.size() == 1 ? articles.first() : nil) ?? body
        var paragraphs: [String] = []
        var text = ""
        func flush() {
            let paragraph = TextNormalizer.collapsingWhitespace(text)
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
            text = ""
        }
        // Iterative traversal also handles deeply nested markup without recursion.
        var pending: [(Node, Bool)] = [(root, false)]
        while let (node, closing) = pending.popLast() {
            if let leaf = node as? TextNode {
                if !closing { text += leaf.getWholeText() }
                continue
            }
            guard let element = node as? Element else { continue }
            let tag = element.tagNameNormal()
            let boundary = blockTags.contains(tag)
            if boundary { flush() }
            if closing {
                if tag == "td" || tag == "th" { text += " " }
            } else {
                if tag == "br" { text += " " }
                pending.append((element, true))
                pending.append(contentsOf: element.getChildNodes().reversed().map { ($0, false) })
            }
        }
        flush()
        let sentences = paragraphs.enumerated().reduce(into: [Sentence]()) { result, entry in
            for span in ReadingOrder.sentenceSpans(entry.element) {
                result.append(Sentence(id: result.count, paragraph: entry.offset, page: 0, text: span.text))
            }
        }
        guard !sentences.isEmpty else { throw HTMLExtractionError.noText }
        return SourceDocument(fingerprint: SourceDocument.fingerprint(of: data),
                              title: title.isEmpty ? fallbackTitle : title, sentences: sentences)
    }

    private static let blockTags: Set<String> = [
        "html", "body", "main", "article", "section", "div", "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "li", "dt", "dd", "tr", "pre", "blockquote", "figcaption", "address", "ul", "ol", "dl", "table", "header", "footer"
    ]

    private static func hiddenStyle(_ style: String) -> Bool {
        style.lowercased().split(separator: ";").contains { declaration in
            let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard pair.count == 2 else { return false }
            let value = pair[1].replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces)
            return pair[0] == "display" && value == "none" || pair[0] == "visibility" && value == "hidden"
        }
    }

    private static func decode(_ data: Data, encodingName: String?) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: data, encoding: .utf16) else { throw HTMLExtractionError.unreadable }
            return text
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data, encoding: .utf8) { return text }
        var declared = encodingName
        if declared == nil {
            let prefix = String(decoding: data.prefix(16_384), as: UTF8.self)
            if let range = prefix.range(of: #"(?is)^\s*<\?xml\b.*?\?>"#, options: .regularExpression) {
                declared = capture(in: String(prefix[range]), pattern: #"(?i)\bencoding\s*=\s*["']\s*([\w.-]+)"#)
            }
            if declared == nil {
                let head = try SwiftSoup.parseHTML(prefix)
                declared = try head.select("meta[charset]").first()?.attr("charset")
                if declared == nil, let content = try head.select("meta[http-equiv=content-type]").first()?.attr("content") {
                    declared = capture(in: content, pattern: #"(?i)\bcharset\s*=\s*["']?\s*([\w.-]+)"#)
                }
            }
        }
        if let declared, !declared.trimmingCharacters(in: .whitespaces).isEmpty {
            let label = declared.trimmingCharacters(in: .whitespaces).lowercased()
            let encoding: String.Encoding
            if windows1252Labels.contains(label) { encoding = .windowsCP1252 }
            else {
                let value = CFStringConvertIANACharSetNameToEncoding(label as CFString)
                guard value != kCFStringEncodingInvalidId else { throw HTMLExtractionError.unreadable }
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(value))
            }
            guard let text = String(data: data, encoding: encoding) else { throw HTMLExtractionError.unreadable }
            return text
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            throw HTMLExtractionError.unreadable
        }
        return text
    }

    // HTML's Latin1/ASCII labels decode as Windows-1252, unlike Foundation's IANA mappings.
    // https://encoding.spec.whatwg.org/encodings.json
    private static let windows1252Labels: Set<String> = [
        "ansi_x3.4-1968", "ascii", "cp1252", "cp819", "csisolatin1", "ibm819", "iso-8859-1", "iso-ir-100",
        "iso8859-1", "iso88591", "iso_8859-1", "iso_8859-1:1987", "l1", "latin1", "us-ascii", "windows-1252", "x-cp1252"
    ]

    private static func capture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
