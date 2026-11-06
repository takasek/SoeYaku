import Foundation

/// Where SoeYaku keeps the user's files, shared by the app and `soeyaku-cli` so that both see the same glossaries and saved translations.
public enum StoragePaths {
    public static var root: URL {
        URL.applicationSupportDirectory.appending(path: "SoeYaku", directoryHint: .isDirectory)
    }

    public static var commonGlossary: URL { root.appending(path: "glossary.txt") }

    public static func documentGlossary(for fingerprint: String) -> URL {
        folder(for: fingerprint).appending(path: "glossary.txt")
    }

    public static func memory(for fingerprint: String) -> URL {
        folder(for: fingerprint).appending(path: "memory.json")
    }

    private static func folder(for fingerprint: String) -> URL {
        root.appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: fingerprint, directoryHint: .isDirectory)
    }
}
