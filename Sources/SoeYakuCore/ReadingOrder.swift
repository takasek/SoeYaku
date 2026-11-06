import CoreGraphics
import Foundation

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

    static func isTwoColumn(_ columns: [Column]) -> Bool {
        columns.filter { $0 == .left }.count >= 3 && columns.filter { $0 == .right }.count >= 3
    }

    /// Orders the lines of one page the way a person reads them.
    static func order(_ lines: [PageLine], pageBounds: CGRect) -> [PageLine] {
        let columns = lines.map { column(of: $0, pageBounds: pageBounds) }
        guard isTwoColumn(columns) else { return topToBottom(lines) }

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
