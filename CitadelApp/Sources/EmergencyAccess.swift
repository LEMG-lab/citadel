import Foundation
import CryptoKit

/// Creates and opens double-encrypted emergency access files (.ctdl-emergency).
/// Layer 1: KDBX vault data (already encrypted with the vault master password).
/// Layer 2: ChaChaPoly encryption using a separate emergency password.
public enum EmergencyAccess {

    private static let magic = Data("CTEM".utf8) // Smaug Emergency (legacy magic bytes)
    private static let versionLegacy: UInt8 = 1
    private static let versionArgon2: UInt8 = 2

    /// Export the current vault as a double-encrypted emergency file.
    /// Uses Argon2id key derivation with a random salt (v2 format).
    public static func export(vaultPath: String, emergencyPassword: String, destination: URL) throws {
        let kdbxData = try Data(contentsOf: URL(fileURLWithPath: vaultPath))

        // Generate random salt and derive key via Argon2id
        let salt = Argon2Bridge.randomSalt()
        guard let key = Argon2Bridge.deriveKey(from: emergencyPassword, salt: salt) else {
            throw EmergencyAccessError.keyDerivationFailed
        }

        // Encrypt KDBX data with ChaChaPoly
        let sealed = try ChaChaPoly.seal(kdbxData, using: key)

        // Write: magic(4) + version(1) + salt(32) + sealed.combined
        var output = magic
        output.append(versionArgon2)
        output.append(salt)
        output.append(sealed.combined)
        try output.write(to: destination)
    }

    /// Decrypt an emergency file and return the inner KDBX data.
    /// Supports both v1 (legacy SHA-256) and v2 (Argon2id) formats.
    public static func decrypt(at url: URL, emergencyPassword: String) throws -> Data {
        let raw = try Data(contentsOf: url)
        guard raw.count > 5,
              raw.prefix(4) == magic else {
            throw EmergencyAccessError.invalidFormat
        }

        let version = raw[4]

        if version == versionArgon2 {
            // v2: magic(4) + version(1) + salt(32) + sealed
            guard raw.count > 37 else { throw EmergencyAccessError.invalidFormat }
            let salt = raw.subdata(in: 5..<37)
            let encrypted = raw.dropFirst(37)
            guard let key = Argon2Bridge.deriveKey(from: emergencyPassword, salt: salt) else {
                throw EmergencyAccessError.keyDerivationFailed
            }
            do {
                let sealedBox = try ChaChaPoly.SealedBox(combined: encrypted)
                return try ChaChaPoly.open(sealedBox, using: key)
            } catch {
                throw EmergencyAccessError.wrongPassword
            }
        } else if version == versionLegacy {
            // v1: magic(4) + version(1) + sealed (legacy SHA-256)
            let encrypted = raw.dropFirst(5)
            let key = deriveLegacyKey(from: emergencyPassword)
            do {
                let sealedBox = try ChaChaPoly.SealedBox(combined: encrypted)
                return try ChaChaPoly.open(sealedBox, using: key)
            } catch {
                throw EmergencyAccessError.wrongPassword
            }
        } else {
            throw EmergencyAccessError.invalidFormat
        }
    }

    /// Open an emergency file: decrypt outer layer, write temp KDBX, open with vault password.
    /// Returns the path to the temporary KDBX file.
    public static func openToTempFile(at url: URL, emergencyPassword: String) throws -> String {
        let kdbxData = try decrypt(at: url, emergencyPassword: emergencyPassword)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("smaug-emergency", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpPath = tmpDir.appendingPathComponent("emergency-vault.kdbx")
        try kdbxData.write(to: tmpPath, options: [.atomic])
        // Set restrictive permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpPath.path)
        return tmpPath.path
    }

    // MARK: - Legacy key derivation (v1 backward compat)

    private static func deriveLegacyKey(from password: String) -> SymmetricKey {
        let salt = Data("CitadelEmergency-v1".utf8)
        let input = Data(password.utf8) + salt
        let hash = SHA256.hash(data: input)
        return SymmetricKey(data: hash)
    }
}

public enum EmergencyAccessError: Error, LocalizedError {
    case invalidFormat
    case wrongPassword
    case keyDerivationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Not a valid Smaug emergency file"
        case .wrongPassword: return "Wrong emergency password"
        case .keyDerivationFailed: return "Key derivation failed"
        }
    }
}
