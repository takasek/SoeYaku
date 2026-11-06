import CoreGraphics
import Testing
@testable import SoeYakuCore

struct FrameTextTests {
    @Test func wrappedLinesJoinButSeparateDialogueStaysSeparate() {
        let blocks = FrameText.blocks(from: [
            TextLine(text: "We should cross the", box: CGRect(x: 0.1, y: 0.1, width: 0.65, height: 0.05)),
            TextLine(text: "bridge before sunset.", box: CGRect(x: 0.1, y: 0.16, width: 0.6, height: 0.05)),
            TextLine(text: "Take the northern path.", box: CGRect(x: 0.1, y: 0.5, width: 0.7, height: 0.05))
        ].reversed())
        #expect(blocks.map(\.text) == ["We should cross the bridge before sunset.", "Take the northern path."])
        #expect(abs(blocks[0].box.height - 0.11) < 0.0001)
    }

    @Test func narrowColumnsReadLeftThenRightWithoutJoiningAcrossColumns() {
        let lines = (0..<3).flatMap { row in [
            TextLine(text: "Left \(row)", box: CGRect(x: 0.05, y: 0.1 + Double(row) * 0.08, width: 0.4, height: 0.05)),
            TextLine(text: "Right \(row)", box: CGRect(x: 0.55, y: 0.1 + Double(row) * 0.08, width: 0.4, height: 0.05))
        ] }
        #expect(FrameText.blocks(from: lines).map(\.text) == ["Left 0 Left 1 Left 2", "Right 0 Right 1 Right 2"])
    }

    @Test func selectionClipsToOneScreenAndRejectsTinyOrInvalidRectangles() {
        let bounds = CGRect(x: -100, y: 200, width: 800, height: 600)
        #expect(FrameGeometry.selection(from: CGPoint(x: 900, y: 900), to: CGPoint(x: 100, y: 300), in: bounds)
                == CGRect(x: 100, y: 300, width: 600, height: 500))
        #expect(FrameGeometry.selection(from: .zero, to: CGPoint(x: 10, y: 10), in: bounds) == nil)
        #expect(FrameGeometry.selection(from: CGPoint(x: CGFloat.nan, y: 0), to: CGPoint(x: 100, y: 100), in: bounds) == nil)
    }

    @Test func mirroredImageAndTextUseTheSameAspectFitTransformAtEverySize() {
        let source = CGSize(width: 1600, height: 900)
        let box = CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2)
        for size in [CGSize(width: 800, height: 450), CGSize(width: 400, height: 600)] {
            let image = FrameGeometry.aspectFit(source, in: CGRect(origin: .zero, size: size))
            let text = FrameGeometry.map(box, into: image)
            #expect(abs(image.width / image.height - 16.0 / 9) < 0.0001)
            #expect(abs((text.minX - image.minX) / image.width - box.minX) < 0.0001)
            #expect(abs((text.minY - image.minY) / image.height - box.minY) < 0.0001)
            #expect(abs(text.width / image.width - box.width) < 0.0001)
        }
    }

    @Test func liveTranslationsReuseOnlySessionMemoryAndPassGlossary() async throws {
        let translator = FrameTestTranslator()
        let glossary = try Glossary.parse("bridge = 橋梁", name: "test")
        let live = FrameTranslator(using: translator, glossary: glossary)
        let a = FrameBlock(text: "Cross the bridge.", box: .zero)
        let b = FrameBlock(text: "Take the northern path.", box: .zero)
        #expect(try await live.translate([a]) == ["訳:Cross the bridge."])
        #expect(try await live.translate([a, b]) == ["訳:Cross the bridge.", "訳:Take the northern path."])
        let calls = await translator.calls
        #expect(calls.map(\.0) == [a.text, b.text])
        #expect(calls[0].1 == glossary)
    }

    @Test func cancelledSnapshotDoesNotReturnATranslation() async throws {
        let live = FrameTranslator(using: FrameTestTranslator(), glossary: Glossary())
        let job = Task { try await live.translate([FrameBlock(text: "Stop", box: .zero)]) }
        job.cancel()
        await #expect(throws: CancellationError.self) { try await job.value }
    }

    @Test func longLiveParagraphsAreTranslatedInBoundedParts() async throws {
        let translator = FrameTestTranslator()
        let live = FrameTranslator(using: translator, glossary: Glossary())
        let text = Array(repeating: "The northern bridge is closed during the storm.", count: 40).joined(separator: " ")
        let result = try await live.translate([FrameBlock(text: text, box: .zero)])
        let calls = await translator.calls
        #expect(calls.count > 1)
        #expect(calls.allSatisfy { $0.0.count <= 400 })
        #expect(calls.map(\.0).joined(separator: " ") == text)
        #expect(result.count == 1)
        #expect(result[0].contains("訳:The northern bridge"))
    }

    @Test func exactChunkBoundaryNeverSendsAnEmptyRequest() async throws {
        let translator = FrameTestTranslator()
        let live = FrameTranslator(using: translator, glossary: Glossary())
        let text = String(repeating: "a", count: 399) + "."
        _ = try await live.translate([FrameBlock(text: text, box: .zero)])
        let calls = await translator.calls
        #expect(calls.map(\.0) == [text])
    }
}

private actor FrameTestTranslator: SentenceTranslator {
    var calls: [(String, Glossary)] = []
    func translate(_ source: String, context: String, history: [TranslationPair], glossary: Glossary) async throws -> String {
        calls.append((source, glossary))
        return "訳:" + source
    }
}
