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

    let tokens: [String]
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
        self.tokens = tokens
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

    private enum Resolution {
        case located(Int, Double)
        case insufficientContext
        case rejected

        var match: (Int, Double)? {
            if case .located(let sentence, let confidence) = self { return (sentence, confidence) }
            return nil
        }
    }

    private func resolve(lines: [TextLine], pointer: CGPoint) -> (Int, Double)? {
        let candidates = lines.enumerated().compactMap { id, line -> Candidate? in
            let tokens = TextNormalizer.tokens(line.text)
            return tokens.isEmpty || line.box.height <= 0 || line.box.width <= 0
                ? nil : Candidate(id: id, line: line, tokens: tokens)
        }
        guard let anchor = anchorLine(in: candidates, pointer: pointer) else { return nil }

        let column = contextLines(around: anchor, in: candidates)
        let anchorPosition = column.firstIndex { $0.id == anchor.id } ?? 0
        let contextual = resolve(column: column, anchorPosition: anchorPosition, pointer: pointer)
        if case .insufficientContext = contextual {
            return resolve(column: [anchor], anchorPosition: 0, pointer: pointer).match
        }
        return contextual.match
    }

    private func resolve(column: [Candidate], anchorPosition: Int, pointer: CGPoint) -> Resolution {
        let (query, positions) = joinedQuery(column)
        let anchorPositions = positions[anchorPosition]

        let gramCount = query.count - 2
        guard gramCount > 0 else { return .insufficientContext }
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
        guard let best = scores.max(by: {
            ($0.value, votes[$0.key] ?? 0, -$0.key) < ($1.value, votes[$1.key] ?? 0, -$1.key)
        }) else { return .insufficientContext }
        guard best.value >= 2, Double(best.value) >= 0.25 * Double(gramCount) else { return .insufficientContext }

        let target = anchorPositions[tokenOffset(in: column[anchorPosition], fraction: pointer.x)]
        let rivals = scores.filter {
            abs($0.key - best.key) > 30 && Double($0.value) >= 0.75 * Double(best.value)
        }.map(\.key)
        var chosen = best.key
        if !rivals.isEmpty {
            guard let last = lastSentence else { return .rejected }
            let sentenceFor = { (shift: Int) -> Int? in
                let position = shift + target
                return index.tokens.indices.contains(position) ? index.sentenceOfToken[position] : nil
            }
            let options = ([best.key] + rivals.sorted()).compactMap { shift in
                sentenceFor(shift).map { (shift: shift, distance: abs($0 - last)) }
            }
            guard let nearest = options.min(by: { $0.distance < $1.distance }) else { return .rejected }
            chosen = nearest.shift
        }
        // Context may omit a wrapped heading or contain an extra OCR token. Align the physical anchor within the smoothed vote band.
        let aligned = (-3...3).compactMap { adjustment -> (shift: Int, matches: Int)? in
            let shift = chosen + adjustment
            let position = shift + target
            guard index.tokens.indices.contains(position), query[target] == index.tokens[position] else { return nil }
            let matches = anchorPositions.filter { q in
                let p = shift + q
                return index.tokens.indices.contains(p) && query[q] == index.tokens[p]
            }.count
            return matches * 2 >= anchorPositions.count ? (shift, matches) : nil
        }.max {
            ($0.matches, votes[$0.shift] ?? 0, -abs($0.shift - chosen))
                < ($1.matches, votes[$1.shift] ?? 0, -abs($1.shift - chosen))
        }
        guard let aligned else { return .rejected }
        let position = aligned.shift + target
        return .located(index.sentenceOfToken[position], min(1, Double(best.value) / Double(gramCount)))
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
    private func joinedQuery(_ column: [Candidate]) -> ([String], [[Int]]) {
        var query: [String] = []
        var positions: [[Int]] = []
        for (k, entry) in column.enumerated() {
            let previous = k > 0 ? column[k - 1].line.text.trimmingCharacters(in: .whitespaces) : ""
            let joins = previous.hasSuffix("-") && previous.dropLast().last?.isLetter == true && !query.isEmpty
            var linePositions: [Int] = []
            for (offset, token) in entry.tokens.enumerated() {
                if offset == 0 && joins {
                    query[query.count - 1] += token
                } else {
                    query.append(token)
                }
                linePositions.append(query.count - 1)
            }
            positions.append(linePositions)
        }
        return (query, positions)
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
