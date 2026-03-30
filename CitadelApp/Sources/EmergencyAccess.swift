import Foundation
import CryptoKit

/// Creates and opens double-encrypted emergency access files (.ctdl-emergency).
/// Layer 1: KDBX vault data (already encrypted with the vault master password).
/// Layer 2: ChaChaPoly encryption using a separate emergency password.
public enum EmergencyAccess {

    private static let magic = Data("CTEM".utf8) // Citadel Emergency
    private static let version: UInt8 = 1

    /// Export the current vault as a double-encrypted emergency file.
    /// - Parameters:
    ///   - vaultPath: Path to the KDBX vault file on disk.
    ///   - emergencyPassword: A separate password used for the outer encryption layer.
    ///   - destination: Where to write the .ctdl-emergency file.
    public static func export(vaultPath: String, emergencyPassword: String, destination: URL) throws {
        let kdbxData = try Data(contentsOf: URL(fileURLWithPath: vaultPath))

        // Derive key from emergency password
        let key = deriveKey(from: emergencyPassword)

        // Encrypt KDBX data with ChaChaPoly
        let sealed = try ChaChaPoly.seal(kdbxData, using: key)

        // Write: magic + version + sealed.combined
        var output = magic
        output.append(version)
        output.append(sealed.combined)
        try output.write(to: destination)
    }

    /// Decrypt an emergency file and return the inner KDBX data.
    /// The caller must then open the KDBX with the vault master password.
    /// - Parameters:
    ///   - url: Path to the .ctdl-emergency file.
    ///   - emergencyPassword: The emergency password used during export.
    /// - Returns: Raw KDBX data that can be opened with VaultEngine.
    public static func decrypt(at url: URL, emergencyPassword: String) throws -> Data {
        let raw = try Data(contentsOf: url)
        guard raw.count > 5,
              raw.prefix(4) == magic,
              raw[4] == version else {
            throw EmergencyAccessError.invalidFormat
        }
        let encrypted = raw.dropFirst(5)
        let key = deriveKey(from: emergencyPassword)
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: encrypted)
            return try ChaChaPoly.open(sealedBox, using: key)
        } catch {
            throw EmergencyAccessError.wrongPassword
        }
    }

    /// Open an emergency file: decrypt outer layer, write temp KDBX, open with vault password.
    /// Returns the path to the temporary KDBX file.
    public static func openToTempFile(at url: URL, emergencyPassword: String) throws -> String {
        let kdbxData = try decrypt(at: url, emergencyPassword: emergencyPassword)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("citadel-emergency", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpPath = tmpDir.appendingPathComponent("emergency-vault.kdbx")
        try kdbxData.write(to: tmpPath)
        return tmpPath.path
    }

    // MARK: - Internal

    private static func deriveKey(from password: String) -> SymmetricKey {
        let salt = Data("CitadelEmergency-v1".utf8)
        let input = Data(password.utf8) + salt
        let hash = SHA256.hash(data: input)
        return SymmetricKey(data: hash)
    }
}

public enum EmergencyAccessError: Error, LocalizedError {
    case invalidFormat
    case wrongPassword

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Not a valid Citadel emergency file"
        case .wrongPassword: return "Wrong emergency password"
        }
    }
}
