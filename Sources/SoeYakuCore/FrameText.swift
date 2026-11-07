import CoreGraphics
import Foundation

/// One paragraph from a live frame, in top-left normalized image coordinates.
public struct FrameBlock: Sendable, Equatable {
    public let text: String
    public let box: CGRect
    public init(text: String, box: CGRect) { self.text = text; self.box = box }
}

public enum FrameText {
    public static func blocks(from input: some Sequence<TextLine>) -> [FrameBlock] {
        let lines = input.compactMap { line -> PageLine? in
            let text = line.text.precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let b = line.box
            guard !text.isEmpty, [b.minX, b.minY, b.width, b.height].allSatisfy(\.isFinite), b.width > 0, b.height > 0 else { return nil }
            let clipped = b.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
            return PageLine(text: text, bounds: ScreenGeometry.topLeft(fromVision: clipped), page: 0)
        }
        let flow = ReadingOrder.order(lines, pageBounds: CGRect(x: 0, y: 0, width: 1, height: 1))
        var result: [FrameBlock] = []
        var previous: CGRect?
        for line in flow {
            let box = ScreenGeometry.topLeft(fromVision: line.bounds)
            if let p = previous, let last = result.last,
               box.minY > p.minY + p.height * 0.3,
               box.minY - p.maxY < max(p.height, box.height) * 0.9,
               abs(box.height - p.height) < p.height * 0.35,
               min(box.maxX, p.maxX) - max(box.minX, p.minX) >= min(box.width, p.width) * 0.5 {
                let text = last.text.hasSuffix("-") && line.text.first?.isLowercase == true
                    ? String(last.text.dropLast()) + line.text : last.text + " " + line.text
                result[result.count - 1] = FrameBlock(text: text, box: last.box.union(box))
            } else {
                result.append(FrameBlock(text: line.text, box: box))
            }
            previous = box
        }
        return result
    }
}

public enum FrameGeometry {
    /// Cocoa-global selection constrained to the screen where the drag began.
    public static func selection(from start: CGPoint, to end: CGPoint, in screen: CGRect) -> CGRect? {
        guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else { return nil }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(start.x - end.x), height: abs(start.y - end.y)).intersection(screen)
        return !rect.isNull && rect.width >= 32 && rect.height >= 24 ? rect : nil
    }

    public static func aspectFit(_ source: CGSize, in bounds: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    public static func map(_ normalized: CGRect, into image: CGRect) -> CGRect {
        CGRect(x: image.minX + normalized.minX * image.width, y: image.minY + normalized.minY * image.height,
               width: normalized.width * image.width, height: normalized.height * image.height)
    }
}

/// Translations live only for the current frame session. Nothing is written to disk.
public actor FrameTranslator {
    private let translator: any SentenceTranslator
    private let glossary: Glossary
    private var cache: [String: String] = [:]

    public init(using translator: any SentenceTranslator, glossary: Glossary) {
        self.translator = translator; self.glossary = glossary
    }

    public func translate(_ blocks: [FrameBlock]) async throws -> [String] {
        var result: [String] = []
        for block in blocks {
            try Task.checkCancellation()
            if let saved = cache[block.text] { result.append(saved); continue }
            var translated: [String] = []
            for part in Self.parts(block.text) {
                try Task.checkCancellation()
                translated.append(try await translator.translate(part, context: "", history: [], glossary: glossary))
            }
            let text = translated.joined()
            try Task.checkCancellation()
            if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
            cache[block.text] = text
            result.append(text)
        }
        try Task.checkCancellation()
        return result
    }

    private static let maxPartLength = 400

    private static func parts(_ text: String) -> [String] {
        var result: [String] = [], current = ""
        for sentence in ReadingOrder.sentences(text) {
            if sentence.count <= Self.maxPartLength {
                if !current.isEmpty, current.count + sentence.count + 1 > Self.maxPartLength { result.append(current); current = "" }
                current += (current.isEmpty ? "" : " ") + sentence
            } else {
                if !current.isEmpty { result.append(current); current = "" }
                for word in sentence.split(whereSeparator: \.isWhitespace).map(String.init) {
                    if !current.isEmpty, current.count + word.count + 1 > Self.maxPartLength { result.append(current); current = "" }
                    var remaining = word[...]
                    while remaining.count > Self.maxPartLength {
                        result.append(String(remaining.prefix(Self.maxPartLength))); remaining = remaining.dropFirst(Self.maxPartLength)
                    }
                    current += (current.isEmpty ? "" : " ") + remaining
                }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
