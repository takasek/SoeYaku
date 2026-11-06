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
