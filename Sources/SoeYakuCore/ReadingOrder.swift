import CoreGraphics
import Foundation
import NaturalLanguage

/// One line of text on a PDF page. `bounds` is in PDF page space (origin at the bottom left).
public struct PageLine: Sendable, Equatable {
    public let text: String
    public let bounds: CGRect
    public let page: Int

    public init(text: String, bounds: CGRect, page: Int) {
        self.text = text
        self.bounds = bounds
        self.page = page
    }
}

enum ReadingOrder {
    enum Column {
        case left, right, full
    }

    static func column(of line: PageLine, pageBounds: CGRect) -> Column {
        let mid = pageBounds.midX
        let tolerance = 0.05 * pageBounds.width
        if line.bounds.maxX <= mid + tolerance && line.bounds.minX < mid { return .left }
        if line.bounds.minX >= mid - tolerance { return .right }
        return .full
    }

    /// Only lines at least a quarter of the page wide count, so that the short labels of a figure do not look like columns.
    static func isTwoColumn(_ lines: [PageLine], pageBounds: CGRect) -> Bool {
        let columns = lines.filter { $0.bounds.width >= 0.25 * pageBounds.width }.map { column(of: $0, pageBounds: pageBounds) }
        return columns.filter { $0 == .left }.count >= 3 && columns.filter { $0 == .right }.count >= 3
    }

    /// Orders the lines of one page the way a person reads them.
    static func order(_ lines: [PageLine], pageBounds: CGRect) -> [PageLine] {
        guard isTwoColumn(lines, pageBounds: pageBounds) else { return topToBottom(lines) }
        let columns = lines.map { column(of: $0, pageBounds: pageBounds) }

        let wide = topToBottom(zip(lines, columns).filter { $1 == .full }.map(\.0))
        func band(_ line: PageLine) -> Int {
            wide.filter { $0.bounds.midY > line.bounds.midY }.count
        }
        func columnLines(_ kind: Column, inBand index: Int) -> [PageLine] {
            let members = zip(lines, columns).filter { $1 == kind && band($0) == index }.map(\.0)
            return members.sorted { $0.bounds.maxY > $1.bounds.maxY }
        }

        var result: [PageLine] = []
        for index in 0...wide.count {
            if index > 0 { result.append(wide[index - 1]) }
            result += columnLines(.left, inBand: index)
            result += columnLines(.right, inBand: index)
        }
        return result
    }

    private static let romanNumerals: Set<String> = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii"]

    /// Drops page numbers and running headers or footers from the top and bottom 8% of each page.
    static func removeRunningElements(_ pages: [[PageLine]], pageBounds: [CGRect]) -> [[PageLine]] {
        func inBand(_ line: PageLine, _ bounds: CGRect) -> Bool {
            line.bounds.midY >= bounds.maxY - 0.08 * bounds.height || line.bounds.midY <= bounds.minY + 0.08 * bounds.height
        }
        func isNumber(_ text: String) -> Bool {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return (!trimmed.isEmpty && trimmed.allSatisfy { $0.isASCII && $0.isNumber }) || romanNumerals.contains(trimmed)
        }
        func key(_ text: String) -> String {
            text.lowercased().filter { !$0.isNumber }.trimmingCharacters(in: .whitespaces)
        }

        var pageCount: [String: Int] = [:]
        for (index, lines) in pages.enumerated() {
            let keys = Set(lines.filter { inBand($0, pageBounds[index]) }.map { key($0.text) })
            for key in keys where !key.isEmpty { pageCount[key, default: 0] += 1 }
        }
        let repeated = Set(pageCount.filter { $0.value >= 3 && Double($0.value) >= 0.3 * Double(pages.count) }.keys)

        return pages.enumerated().map { index, lines in
            lines.filter { line in
                !(inBand(line, pageBounds[index]) && (isNumber(line.text) || repeated.contains(key(line.text))))
            }
        }
    }

    private struct ColumnKey: Hashable {
        let page: Int
        let column: Column?
    }

    private static let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]", "}", "\u{00BB}"]

    private static func endsSentence(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: .whitespaces).reversed().drop { closers.contains($0) }
        guard let last = stripped.first else { return false }
        return ".?!:".contains(last)
    }

    /// Splits lines in reading order (all pages) into paragraphs, labelled with the page of their first line.
    ///
    /// A line change that crosses a column or a page, or that changes the line height, is judged by the
    /// sentence-end rule instead of the vertical-gap and indent rules, which only make sense inside one column.
    static func paragraphs(_ flow: [PageLine], pageBounds: [CGRect]) -> [Paragraph] {
        // A column is a left or right column of a two-column page, or the whole page otherwise.
        var keys: [ColumnKey] = []
        var widest: [ColumnKey: CGFloat] = [:]
        var leftEdge: [ColumnKey: CGFloat] = [:]
        let pages = Dictionary(grouping: flow, by: \.page)
        let twoColumnPages = Set(
            pages.filter { page, lines in isTwoColumn(lines, pageBounds: pageBounds[page]) }.keys)
        for line in flow {
            let kind = twoColumnPages.contains(line.page) ? column(of: line, pageBounds: pageBounds[line.page]) : nil
            let key = ColumnKey(page: line.page, column: kind)
            keys.append(key)
            widest[key] = max(widest[key] ?? 0, line.bounds.width)
            leftEdge[key] = min(leftEdge[key] ?? .infinity, line.bounds.minX)
        }

        // Full-width lines on a two-column page are measured against the whole text block, not against each other.
        for key in widest.keys where key.column == .full {
            let lines = pages[key.page] ?? []
            widest[key] = (lines.map(\.bounds.maxX).max() ?? 0) - (lines.map(\.bounds.minX).min() ?? 0)
        }

        var result: [Paragraph] = []
        var firstLine = flow.first
        for (index, line) in flow.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            if index > 0, let firstLine, let current = result.last,
                !endsNumberedHeading(current.text, firstLine: firstLine, previous: flow[index - 1], next: line),
                !startsParagraph(
                    line, after: flow[index - 1], key: keys[index], previousKey: keys[index - 1], widest: widest, leftEdge: leftEdge)
            {
                var paragraph = result[result.count - 1]
                paragraph.text = Hyphenation.join(paragraph.text, text)
                paragraph.lineStarts.append((paragraph.text.count - text.count, line.page))
                result[result.count - 1] = paragraph
            } else {
                result.append(Paragraph(text: text, lineStarts: [(0, line.page)]))
                firstLine = line
            }
        }
        return result
    }

    /// A paragraph so far that is one row like "1.2.4 Decrypting a file" ends when a new row starts with a capital letter.
    private static func endsNumberedHeading(_ text: String, firstLine: PageLine, previous: PageLine, next: PageLine) -> Bool {
        guard text.range(of: #"^\d+(\.\d+)*\.?\s+\p{Lu}"#, options: .regularExpression) != nil, !endsSentence(text),
              sameRow(firstLine, previous), !sameRow(previous, next) else { return false }
        return next.text.first?.isUppercase == true
    }

    private static func sameRow(_ a: PageLine, _ b: PageLine) -> Bool {
        min(a.bounds.maxY, b.bounds.maxY) - max(a.bounds.minY, b.bounds.minY) > 0.5 * min(a.bounds.height, b.bounds.height)
    }

    /// Text of one paragraph with the page of every line in it.
    struct Paragraph {
        var text: String
        /// Character offset in `text` at which each line starts, with the page of that line; never empty.
        var lineStarts: [(offset: Int, page: Int)]

        /// The page on which the paragraph starts.
        var page: Int { lineStarts[0].page }

        /// The page of the line that contains the character at `offset`.
        func page(atOffset offset: Int) -> Int {
            lineStarts.last { $0.offset <= offset }?.page ?? page
        }
    }

    private static func startsParagraph(
        _ line: PageLine, after previous: PageLine, key: ColumnKey, previousKey: ColumnKey,
        widest: [ColumnKey: CGFloat], leftEdge: [ColumnKey: CGFloat]
    ) -> Bool {
        // A table-of-contents entry ends in a dot leader and a page number; each entry is its own paragraph.
        if endsInLeader(previous.text) { return true }
        let height = previous.bounds.height
        let endsLine = endsSentence(previous.text) || previous.bounds.width < 0.8 * (widest[previousKey] ?? 0)
        // A taller or smaller line inside a sentence (superscript, inline math) must not split it.
        if abs(line.bounds.height - height) > 0.25 * height && endsLine { return true }
        if key == previousKey {
            // A section number and its title are separate lines on one row.
            if sameRow(previous, line) { return false }
            if previous.bounds.minY - line.bounds.maxY > 0.8 * height { return true }
            // A heading's short last line has no punctuation and may sit as close to the body as a normal line.
            if previous.bounds.width < 0.6 * (widest[key] ?? 0), endsInWord(previous.text),
               line.text.first?.isUppercase == true { return true }
            return endsSentence(previous.text) && line.bounds.minX - (leftEdge[key] ?? line.bounds.minX) > 0.5 * height
        }
        return endsSentence(previous.text) && previous.bounds.width < 0.8 * (widest[previousKey] ?? 0)
    }

    private static func endsInWord(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return last.isLetter || last.isNumber
    }

    private static func endsInLeader(_ text: String) -> Bool {
        text.range(of: #"(?:[.…·․]\s*){4,}\s*(?:\d+|[ivxlcdm]+)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func sentences(_ paragraph: String) -> [String] {
        sentenceSpans(paragraph).map(\.text)
    }

    /// Sentences with the character offset at which each one (after trimming) starts in `paragraph`.
    static func sentenceSpans(_ paragraph: String) -> [(text: String, offset: Int)] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        var result: [(text: String, offset: Int)] = []
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            let raw = paragraph[range]
            let sentence = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                let start = raw.firstIndex { !$0.isWhitespace } ?? range.lowerBound
                result.append((sentence, paragraph.distance(from: paragraph.startIndex, to: start)))
            }
            return true
        }
        return result
    }

    /// Top to bottom; lines at the same height read left to right.
    private static func topToBottom(_ lines: [PageLine]) -> [PageLine] {
        var rows: [[PageLine]] = []
        for line in lines.sorted(by: { $0.bounds.maxY > $1.bounds.maxY }) {
            if let first = rows.last?.first,
                abs(line.bounds.midY - first.bounds.midY) <= 0.5 * min(line.bounds.height, first.bounds.height)
            {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }
}
