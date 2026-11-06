import CryptoKit
import Foundation

/// A content identity shared by the app and CLI, independent of a model's filename or location.
public enum ModelIdentity {
    public static func forFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
