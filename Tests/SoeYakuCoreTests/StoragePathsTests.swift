import Foundation
import Testing

@testable import SoeYakuCore

struct StoragePathsTests {
    private func relative(_ url: URL) -> String {
        let root = StoragePaths.root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }

    @Test func rootIsSoeYakuUnderApplicationSupport() {
        #expect(StoragePaths.root == URL.applicationSupportDirectory.appending(path: "SoeYaku", directoryHint: .isDirectory))
    }

    @Test func commonGlossaryIsDirectlyUnderRoot() {
        #expect(relative(StoragePaths.commonGlossary) == "glossary.txt")
    }

    @Test func documentFilesLiveInAFolderNamedByTheFingerprint() {
        #expect(relative(StoragePaths.documentGlossary(for: "abc123")) == "Documents/abc123/glossary.txt")
        #expect(relative(StoragePaths.memory(for: "abc123")) == "Documents/abc123/memory.json")
    }
}
