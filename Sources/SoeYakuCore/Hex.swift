import Foundation

extension Sequence<UInt8> {
    /// Two lowercase hex digits per byte, as used by every persisted hash key.
    var lowercaseHex: String { map { String(format: "%02x", $0) }.joined() }
}
