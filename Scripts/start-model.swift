#!/usr/bin/env swift
import Darwin
import Foundation

struct StartupError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// Only GGUF metadata is read. Tensor weights stay in the memory-mapped file.
struct GGUF {
    let bytes: Data
    var position = 0
    static let invalid = StartupError("GGUF メタデータが破損しているか、未対応の形式です。")

    mutating func skip(_ length: Int) throws {
        guard length >= 0, length <= bytes.count - position else { throw Self.invalid }
        position += length
    }

    mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let start = position
        try skip(MemoryLayout<T>.size)
        return bytes.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: start, as: T.self)) }
    }

    mutating func count() throws -> Int {
        guard let length = Int(exactly: try integer(UInt64.self)) else { throw Self.invalid }
        return length
    }

    mutating func string() throws -> String {
        let length = try count()
        let start = position
        try skip(length)
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    mutating func skipArray() throws {
        let kind = try integer(UInt32.self)
        let length = try count()
        if kind == 8 { // tokenizer strings, each prefixed by its length
            for _ in 0..<length { let size = try count(); try skip(size) }
            return
        }
        let widths: [UInt32: Int] = [0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8]
        guard let width = widths[kind], length <= (bytes.count - position) / width else { throw Self.invalid }
        try skip(length * width)
    }

    mutating func metadata() throws -> [String: String] {
        guard try integer(UInt32.self) == 0x46554747, [2, 3].contains(try integer(UInt32.self)) else {
            throw Self.invalid
        }
        _ = try integer(UInt64.self)  // tensor count
        let entries = try count()
        var values = [String: String]()
        for _ in 0..<entries {
            let key = try string()
            switch try integer(UInt32.self) {
            case 0, 7: values[key] = String(try integer(UInt8.self))
            case 1: values[key] = String(try integer(Int8.self))
            case 2: values[key] = String(try integer(UInt16.self))
            case 3: values[key] = String(try integer(Int16.self))
            case 4: values[key] = String(try integer(UInt32.self))
            case 5: values[key] = String(try integer(Int32.self))
            case 6: values[key] = String(Float(bitPattern: try integer(UInt32.self)))
            case 8: values[key] = try string()
            case 9: try skipArray()
            case 10: values[key] = String(try integer(UInt64.self))
            case 11: values[key] = String(try integer(Int64.self))
            case 12: values[key] = String(Double(bitPattern: try integer(UInt64.self)))
            default: throw Self.invalid
            }
        }
        return values
    }
}

func yarnArguments(_ metadata: [String: String]) throws -> [String] {
    guard metadata["general.architecture"] == "plamo3" else {
        throw StartupError("PLaMo 3 の GGUF を指定してください。")
    }
    let prefix = "plamo3.rope.scaling."
    guard metadata[prefix + "type"] == "yarn", metadata[prefix + "yarn_truncate"] == "0" else { return [] }
    func number(_ key: String) -> Double? { metadata[key].flatMap(Double.init) }
    guard let dimensions = number("plamo3.rope.dimension_count") ?? number("plamo3.attention.key_length"),
          let base = number("plamo3.rope.freq_base"), let original = number(prefix + "original_context_length"),
          dimensions > 0, base > 1, original > 0 else { throw GGUF.invalid }

    // b11960 rounds correction dimensions outwards. Move them just inside the nearest integers.
    let scale = dimensions / (2 * log(base))
    func dimension(_ beta: Double) -> Double {
        (scale * log(original / (beta * 2 * .pi))).rounded(.toNearestOrEven)
    }
    func beta(_ dimension: Double) -> String {
        String(format: "%.8g", original / (2 * .pi * exp(dimension / scale)))
    }
    let low = dimension(number(prefix + "yarn_beta_fast") ?? 32) + 0.001
    let high = dimension(number(prefix + "yarn_beta_slow") ?? 1) - 0.001
    guard low > 0, low < high, high.isFinite else { throw GGUF.invalid }
    return ["--yarn-beta-fast", beta(low), "--yarn-beta-slow", beta(high)]
}

func arguments() throws -> [String] {
    let args = Array(CommandLine.arguments.dropFirst())
    guard (1...2).contains(args.count), let port = Int(args.count == 2 ? args[1] : "8080"),
          (1...65535).contains(port) else { throw StartupError("使い方: Scripts/start-model.swift MODEL.gguf [PORT]") }
    let model = URL(fileURLWithPath: args[0]).standardizedFileURL
    var gguf = try GGUF(bytes: Data(contentsOf: model, options: .alwaysMapped))
    let yarn = try yarnArguments(gguf.metadata())
    return ["llama-server", "--model", model.path, "--host", "127.0.0.1", "--port", String(port),
            "--offline", "--ctx-size", "8192", "--parallel", "1", "--threads", "2", "--n-gpu-layers", "99",
            "--flash-attn", "on", "--cache-type-k", "f16", "--cache-type-v", "f16",
            "--no-context-shift", "--no-webui", "--chat-template", "chatml", "--fit", "off",
            "--cache-ram", "0", "--ctx-checkpoints", "0", "--log-verbosity", "2"] + yarn
}

do {
    let args = try arguments()
    let argv = args.map { strdup($0) } + [nil]
    execvp("llama-server", argv)
    throw StartupError("llama-server を起動できませんでした: " + String(cString: strerror(errno)))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
