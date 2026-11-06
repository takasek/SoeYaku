import Foundation

/// Files SoeYaku keeps for the user: the shared glossary and, per document, its glossary and saved translations.
enum Storage {
    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "SoeYaku", directoryHint: .isDirectory)
    }
    static var commonGlossary: URL { root.appending(path: "glossary.txt") }
    static func folder(for fingerprint: String) -> URL {
        root.appending(path: "Documents", directoryHint: .isDirectory).appending(path: fingerprint, directoryHint: .isDirectory)
    }
    static func documentGlossary(for fingerprint: String) -> URL { folder(for: fingerprint).appending(path: "glossary.txt") }
    static func memory(for fingerprint: String) -> URL { folder(for: fingerprint).appending(path: "memory.json") }

    /// Creates an empty glossary with a format note so that opening it in an editor shows how to write entries.
    static func ensureGlossary(at url: URL, scope: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let note = """
        # SoeYaku \(scope)の用語集。1行に「原語 = 訳語」（Kikiyaku と同じ形式）または「原語<TAB>訳語」を書きます。
        # # で始まる行と空行は読み飛ばします。文書の用語集は共通の用語集より優先されます。
        # 例: speech recognition = 音声認識

        """
        try note.write(to: url, atomically: true, encoding: .utf8)
    }
}
