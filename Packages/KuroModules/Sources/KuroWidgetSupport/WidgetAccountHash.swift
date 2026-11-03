import CryptoKit
import Foundation

/// Opaque account tag written into the App Group instead of the user id.
///
/// `SHA-256(installSalt | lower-cased user id)`, hex. The salt is a random per-install value kept in
/// the APP's own defaults (never in the App Group), so the extension can only echo a tag back and
/// cannot derive or compare user ids, and the tag is not linkable across installs. The app compares a
/// queued request's tag with the tag of the account that is current when it drains.
public struct WidgetAccountHash: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    public init(value: String) {
        self.value = value
    }

    public var description: String { value }

    /// The tag of `userId` under `salt`.
    public static func make(userId: String, salt: String) -> WidgetAccountHash {
        let input = Data("\(salt)|\(userId.lowercased())".utf8)
        let digest = SHA256.hash(data: input)
        return WidgetAccountHash(value: digest.map { String(format: "%02x", $0) }.joined())
    }

    /// The per-install salt from `defaults`, created once (32 random bytes, hex).
    public static func installSalt(in defaults: UserDefaults, key: String = "com.kuro.widgets.accountSalt") -> String {
        if let existing = defaults.string(forKey: key), existing.count >= 32 { return existing }
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        let salt = bytes.map { String(format: "%02x", $0) }.joined()
        defaults.set(salt, forKey: key)
        return salt
    }
}
