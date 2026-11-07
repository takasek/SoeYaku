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

/// Remembers a model file's identity while its path, size and modification date stay the same, so a large file is not rehashed on every use.
public actor ModelIdentityCache {
    private struct Stamp: Equatable {
        let size: Int
        let modified: Date
    }

    private var entries: [String: (stamp: Stamp, identity: String)] = [:]

    public init() {}

    /// A missing or unreadable file throws every time; failures are never cached.
    public func identity(for url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = Stamp(size: (attributes[.size] as? NSNumber)?.intValue ?? -1,
                          modified: attributes[.modificationDate] as? Date ?? .distantPast)
        if let entry = entries[url.path], entry.stamp == stamp { return entry.identity }
        let identity = try ModelIdentity.forFile(url)
        entries[url.path] = (stamp, identity)
        return identity
    }
}
