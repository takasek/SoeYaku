import CoreGraphics
import Foundation

/// A command-line mistake. The tool prints `message` and the usage text to stderr and exits with status 2.
public struct UsageError: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

public struct TranslateOptions: Equatable, Sendable {
    public var file: String
    public var port: Int
    public var apiKey: String?
    public var glossaries: [String]
    public var memory: String?
    public var model: String?
    public var modelFile: String?

    public init(file: String, port: Int, apiKey: String? = nil, glossaries: [String] = [], memory: String? = nil, model: String? = nil, modelFile: String? = nil) {
        self.file = file
        self.port = port
        self.apiKey = apiKey
        self.glossaries = glossaries
        self.memory = memory
        self.model = model
        self.modelFile = modelFile
    }
}

public enum Command: Equatable, Sendable {
    case extract(file: String)
    case translate(TranslateOptions)
    /// `pointer` is in image pixels with a top-left origin.
    case locate(file: String, image: String, pointer: CGPoint)

    public static let usage = """
        使い方:
          soeyaku-cli extract FILE.pdf
          soeyaku-cli translate FILE.pdf --port N [--api-key K] [--glossary FILE]... [--memory FILE] [--model-file FILE.gguf | --model VERSION]
          soeyaku-cli locate FILE.pdf IMAGE.png --pointer X,Y
        """

    public static func parse(_ arguments: [String]) throws -> Command {
        guard let name = arguments.first else { throw UsageError("コマンドを指定してください。") }
        switch name {
        case "extract":
            let (positional, _) = try split(arguments.dropFirst(), valued: [])
            return .extract(file: try one(positional, "extract は FILE.pdf を 1 つ取ります。"))
        case "translate":
            let (positional, options) = try split(arguments.dropFirst(), valued: ["--port", "--api-key", "--glossary", "--memory", "--model", "--model-file"])
            let file = try one(positional, "translate は FILE.pdf を 1 つ取ります。")
            guard let portText = options.first(where: { $0.name == "--port" })?.value else {
                throw UsageError("--port を指定してください。")
            }
            guard let port = Int(portText), (1...65535).contains(port) else {
                throw UsageError("--port は 1〜65535 の整数で指定してください。")
            }
            func last(_ name: String) -> String? { options.last { $0.name == name }?.value }
            guard last("--model") == nil || last("--model-file") == nil else {
                throw UsageError("--model と --model-file は同時に指定できません。")
            }
            return .translate(
                TranslateOptions(
                    file: file, port: port, apiKey: last("--api-key"),
                    glossaries: options.filter { $0.name == "--glossary" }.map(\.value),
                    memory: last("--memory"), model: last("--model"), modelFile: last("--model-file")))
        case "locate":
            let (positional, options) = try split(arguments.dropFirst(), valued: ["--pointer"])
            guard positional.count == 2 else { throw UsageError("locate は FILE.pdf と IMAGE.png を取ります。") }
            guard let text = options.last(where: { $0.name == "--pointer" })?.value else {
                throw UsageError("--pointer X,Y を指定してください。")
            }
            return .locate(file: positional[0], image: positional[1], pointer: try pointer(text))
        default:
            throw UsageError("不明なコマンドです: \(name)")
        }
    }

    private static func one(_ positional: [String], _ message: String) throws -> String {
        guard positional.count == 1 else { throw UsageError(message) }
        return positional[0]
    }

    private static func pointer(_ text: String) throws -> CGPoint {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]), x.isFinite, y.isFinite, x >= 0, y >= 0 else {
            throw UsageError("--pointer は画像のピクセル座標を X,Y（0 以上）で指定してください。")
        }
        return CGPoint(x: x, y: y)
    }

    /// Splits into positional arguments and `--name value` options. Only names in `valued` are accepted.
    private static func split(_ arguments: ArraySlice<String>, valued: Set<String>) throws -> ([String], [(name: String, value: String)]) {
        var positional: [String] = []
        var options: [(name: String, value: String)] = []
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument.hasPrefix("--") {
                guard valued.contains(argument) else { throw UsageError("不明なオプションです: \(argument)") }
                guard let value = iterator.next() else { throw UsageError("\(argument) には値が必要です。") }
                options.append((argument, value))
            } else {
                positional.append(argument)
            }
        }
        return (positional, options)
    }
}
