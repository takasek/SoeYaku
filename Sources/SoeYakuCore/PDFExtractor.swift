import Foundation
import PDFKit

public enum PDFExtractionError: Error, Equatable, LocalizedError {
    case unreadable
    case noText

    public var errorDescription: String? {
        switch self {
        case .unreadable: "PDF を開けませんでした。"
        case .noText: "この PDF には文字情報がありません。"
        }
    }
}

public enum PDFExtractor {
    /// Reads the body text of the PDF at `url` as sentences in reading order.
    public static func extract(url: URL) throws -> SourceDocument {
        let data = try Data(contentsOf: url)
        guard let pdf = PDFDocument(data: data) else { throw PDFExtractionError.unreadable }

        var bounds: [CGRect] = []
        var pages: [[PageLine]] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)
            let selections = page.selection(for: pageBounds)?.selectionsByLine() ?? []
            let lines = selections.compactMap { selection -> PageLine? in
                let text = (selection.string ?? "").precomposedStringWithCompatibilityMapping
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return PageLine(text: text, bounds: selection.bounds(for: page), page: index)
            }
            bounds.append(pageBounds)
            pages.append(lines)
        }

        let body = ReadingOrder.removeRunningElements(pages, pageBounds: bounds)
        let flow = body.enumerated().flatMap { ReadingOrder.order($1, pageBounds: bounds[$0]) }
        var sentences: [Sentence] = []
        var paragraphIndex = 0
        for paragraph in ReadingOrder.paragraphs(flow, pageBounds: bounds) {
            let parts = ReadingOrder.sentences(paragraph.text)
            guard !parts.isEmpty else { continue }
            for part in parts {
                sentences.append(Sentence(id: sentences.count, paragraph: paragraphIndex, page: paragraph.page, text: part))
            }
            paragraphIndex += 1
        }
        guard !sentences.isEmpty else { throw PDFExtractionError.noText }

        let attributeTitle = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = attributeTitle.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        return SourceDocument(fingerprint: SourceDocument.fingerprint(of: data), title: title, sentences: sentences)
    }
}
