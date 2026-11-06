import CoreGraphics
import Foundation

/// One OCR text line. `box` is normalized (0...1) to the captured image with a top-left origin.
public struct TextLine: Sendable, Equatable {
    public let text: String
    public let box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

public enum LocateResult: Sendable, Equatable {
    case matched(sentence: Int, confidence: Double)
    case unresolved
}

/// The document as one token stream, with a table from token 3-grams to where they occur.
public struct DocumentIndex: Sendable {
    /// 3-grams that occur more often than this carry no position information and are left out.
    static let maxOccurrences = 64

    let tokenCount: Int
    let sentenceOfToken: [Int]
    let occurrences: [String: [Int]]

    public init(_ document: SourceDocument) {
        var tokens: [String] = []
        var sentenceOfToken: [Int] = []
        for sentence in document.sentences {
            for token in TextNormalizer.tokens(sentence.text) {
                tokens.append(token)
                sentenceOfToken.append(sentence.id)
            }
        }
        var occurrences: [String: [Int]] = [:]
        if tokens.count >= 3 {
            for position in 0..<(tokens.count - 2) {
                occurrences[Self.gram(tokens, position), default: []].append(position)
            }
        }
        self.tokenCount = tokens.count
        self.sentenceOfToken = sentenceOfToken
        self.occurrences = occurrences.filter { $0.value.count <= Self.maxOccurrences }
    }

    static func gram(_ tokens: [String], _ position: Int) -> String {
        tokens[position] + " " + tokens[position + 1] + " " + tokens[position + 2]
    }
}

/// Finds the document sentence under the pointer from the OCR lines of a viewer window.
public struct Locator: Sendable {
    private let index: DocumentIndex
    public private(set) var lastSentence: Int?

    public init(index: DocumentIndex) {
        self.index = index
    }

    public mutating func locate(lines: [TextLine], pointer: CGPoint) -> LocateResult {
        guard let (sentence, confidence) = resolve(lines: lines, pointer: pointer) else {
            return .unresolved
        }
        lastSentence = sentence
        return .matched(sentence: sentence, confidence: confidence)
    }

    private struct Candidate {
        let id: Int
        let line: TextLine
        var tokens: [String]
    }

    private func resolve(lines: [TextLine], pointer: CGPoint) -> (Int, Double)? {
        let candidates = lines.enumerated().compactMap { id, line -> Candidate? in
            let tokens = TextNormalizer.tokens(line.text)
            return tokens.isEmpty || line.box.height <= 0 || line.box.width <= 0
                ? nil : Candidate(id: id, line: line, tokens: tokens)
        }
        guard let anchor = anchorLine(in: candidates, pointer: pointer) else { return nil }

        var column = contextLines(around: anchor, in: candidates)
        let anchorPosition = column.firstIndex { $0.id == anchor.id } ?? 0
        joinHyphenatedWords(&column)
        var query: [String] = []
        var anchorRange = 0..<0
        for (offset, entry) in column.enumerated() {
            let start = query.count
            query.append(contentsOf: entry.tokens)
            if offset == anchorPosition { anchorRange = start..<query.count }
        }
        guard !anchorRange.isEmpty else { return nil }

        let gramCount = query.count - 2
        guard gramCount > 0 else { return nil }
        var votes: [Int: Int] = [:]
        for q in 0..<gramCount {
            for p in index.occurrences[DocumentIndex.gram(query, q)] ?? [] {
                votes[p - q, default: 0] += 1
            }
        }
        var scores: [Int: Int] = [:]
        for d in votes.keys {
            scores[d] = (-3...3).reduce(0) { $0 + (votes[d + $1] ?? 0) }
        }
        guard let best = scores.max(by: { ($0.value, -$0.key) < ($1.value, -$1.key) }) else { return nil }
        guard best.value >= 2, Double(best.value) >= 0.25 * Double(gramCount) else { return nil }

        let target = anchorRange.lowerBound + tokenOffset(
            in: column[anchorPosition], fraction: pointer.x)
        let rivals = scores.filter {
            abs($0.key - best.key) > 30 && Double($0.value) >= 0.75 * Double(best.value)
        }.map(\.key)
        var chosen = best.key
        if !rivals.isEmpty {
            guard let last = lastSentence else { return nil }
            let sentenceFor = { (shift: Int) -> Int? in
                let position = shift + target
                return (0..<index.tokenCount).contains(position) ? index.sentenceOfToken[position] : nil
            }
            let options = ([best.key] + rivals.sorted()).compactMap { shift in
                sentenceFor(shift).map { (shift: shift, distance: abs($0 - last)) }
            }
            guard let nearest = options.min(by: { $0.distance < $1.distance }) else { return nil }
            chosen = nearest.shift
        }
        let position = chosen + target
        guard (0..<index.tokenCount).contains(position) else { return nil }
        return (index.sentenceOfToken[position], min(1, Double(best.value) / Double(gramCount)))
    }

    /// The line under the pointer, or failing that the nearest line within two line heights.
    private func anchorLine(in candidates: [Candidate], pointer: CGPoint) -> Candidate? {
        let sideMargin: CGFloat = 0.02
        let horizontal = candidates.filter {
            pointer.x >= $0.line.box.minX - sideMargin && pointer.x <= $0.line.box.maxX + sideMargin
        }
        let covering = horizontal.filter {
            let box = $0.line.box
            return pointer.y >= box.minY - box.height / 2 && pointer.y <= box.maxY + box.height / 2
        }
        if let nearest = covering.min(by: { abs($0.line.box.midY - pointer.y) < abs($1.line.box.midY - pointer.y) }) {
            return nearest
        }
        let near = horizontal.filter { verticalDistance(from: pointer.y, to: $0.line.box) <= 2 * $0.line.box.height }
        return near.min { verticalDistance(from: pointer.y, to: $0.line.box) < verticalDistance(from: pointer.y, to: $1.line.box) }
    }

    private func verticalDistance(from y: CGFloat, to box: CGRect) -> CGFloat {
        max(box.minY - y, y - box.maxY, 0)
    }

    /// The anchor plus up to two lines above and two below among lines that share most of its horizontal extent.
    private func contextLines(around anchor: Candidate, in candidates: [Candidate]) -> [Candidate] {
        let anchorBox = anchor.line.box
        let sameColumn = candidates.filter { other in
            if other.id == anchor.id { return true }
            let overlap = min(anchorBox.maxX, other.line.box.maxX) - max(anchorBox.minX, other.line.box.minX)
            let narrower = min(anchorBox.width, other.line.box.width)
            return overlap >= 0.5 * narrower
        }.sorted { $0.line.box.midY < $1.line.box.midY }
        let anchorIndex = sameColumn.firstIndex { $0.id == anchor.id } ?? 0
        let lower = max(0, anchorIndex - 2)
        let upper = min(sameColumn.count - 1, anchorIndex + 2)
        return Array(sameColumn[lower...upper])
    }

    /// A line ending in a letter and "-" continues with the first token of the next line.
    private func joinHyphenatedWords(_ column: inout [Candidate]) {
        guard column.count > 1 else { return }
        for k in 0..<(column.count - 1) {
            let trimmed = column[k].line.text.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasSuffix("-"),
                  let beforeHyphen = trimmed.dropLast().last, beforeHyphen.isLetter,
                  !column[k].tokens.isEmpty, !column[k + 1].tokens.isEmpty
            else { continue }
            column[k].tokens[column[k].tokens.count - 1] += column[k + 1].tokens.removeFirst()
        }
    }

    /// The token of `entry` at the pointer's horizontal position, by character offset.
    private func tokenOffset(in entry: Candidate, fraction pointerX: CGFloat) -> Int {
        let box = entry.line.box
        let fraction = min(1, max(0, (pointerX - box.minX) / box.width))
        let total = entry.tokens.reduce(0) { $0 + $1.count } + entry.tokens.count - 1
        let offset = fraction * CGFloat(total)
        var start = 0
        for (i, token) in entry.tokens.enumerated() {
            if offset < CGFloat(start + token.count + 1) { return i }
            start += token.count + 1
        }
        return entry.tokens.count - 1
    }
}
