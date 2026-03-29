import Foundation
import CryptoKit

/// Secure sharing using ChaChaPoly encryption.
/// Creates offline share links that contain both the key and encrypted data.
public enum SecureShare {

    /// Shared field payload.
    public struct SharedEntry: Codable {
        public let title: String
        public let fields: [SharedField]
        public let expiresAt: Date?

        public init(title: String, fields: [SharedField], expiresAt: Date? = nil) {
            self.title = title
            self.fields = fields
            self.expiresAt = expiresAt
        }
    }

    public struct SharedField: Codable {
        public let label: String
        public let value: String
        public let isProtected: Bool

        public init(label: String, value: String, isProtected: Bool = false) {
            self.label = label
            self.value = value
            self.isProtected = isProtected
        }
    }

    /// Create an encrypted share link.
    /// Format: citadel://share#BASE64_KEY#BASE64_ENCRYPTED
    public static func createShareLink(entry: SharedEntry) throws -> String {
        let json = try JSONEncoder().encode(entry)
        let key = SymmetricKey(size: .bits256)
        let sealed = try ChaChaPoly.seal(json, using: key)
        let combined = sealed.combined

        let keyData = key.withUnsafeBytes { Data($0) }
        let keyB64 = keyData.base64EncodedString()
        let dataB64 = combined.base64EncodedString()

        return "citadel://share#\(keyB64)#\(dataB64)"
    }

    /// Parse and decrypt a share link.
    public static func decryptShareLink(_ link: String) throws -> SharedEntry {
        let stripped = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.hasPrefix("citadel://share#") else {
            throw ShareError.invalidFormat
        }

        let payload = String(stripped.dropFirst("citadel://share#".count))
        let parts = payload.split(separator: "#", maxSplits: 1)
        guard parts.count == 2 else {
            throw ShareError.invalidFormat
        }

        guard let keyData = Data(base64Encoded: String(parts[0])),
              keyData.count == 32 else {
            throw ShareError.invalidKey
        }

        guard let encryptedData = Data(base64Encoded: String(parts[1])) else {
            throw ShareError.invalidData
        }

        let key = SymmetricKey(data: keyData)
        let sealedBox = try ChaChaPoly.SealedBox(combined: encryptedData)
        let decrypted = try ChaChaPoly.open(sealedBox, using: key)

        let entry = try JSONDecoder().decode(SharedEntry.self, from: decrypted)

        // Check expiry
        if let expiresAt = entry.expiresAt, expiresAt < Date() {
            throw ShareError.expired
        }

        return entry
    }
}

public enum ShareError: Error, LocalizedError {
    case invalidFormat
    case invalidKey
    case invalidData
    case decryptionFailed
    case expired

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Invalid share link format"
        case .invalidKey: return "Invalid encryption key"
        case .invalidData: return "Invalid encrypted data"
        case .decryptionFailed: return "Could not decrypt shared data"
        case .expired: return "This share link has expired"
        }
    }
}
