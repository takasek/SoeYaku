import CoreGraphics
import CoreText
import Foundation
import SoeYakuCore
import Vision

/// English text recognition on a captured image, returning lines with boxes in top-left normalized coordinates.
public enum TextRecognizer {
    public static func lines(in image: CGImage) async throws -> [TextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)
        return observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            return TextLine(text: text, box: ScreenGeometry.topLeft(fromVision: observation.boundingBox.cgRect))
        }
    }

    /// The first recognition in a process loads the model and takes tens of seconds; later ones take about 0.1 s per window.
    public static func warmUp() async {
        let width = 240, height = 60
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let text = NSAttributedString(string: "warm up", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        context.textPosition = CGPoint(x: 10, y: 20)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        guard let image = context.makeImage() else { return }
        _ = try? await lines(in: image)
    }
}
