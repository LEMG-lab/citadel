import Foundation
import CryptoKit

/// Creates and restores encrypted vault backup bundles.
/// Format: manifest JSON + vault files, all encrypted with ChaChaPoly using a user-provided backup password.
/// v2 uses Argon2id key derivation with random salt. v1 (legacy SHA-256) is supported for reading.
public enum VaultBackupBundle {

    private static let magic = Data("CTDL".utf8)
    private static let versionArgon2: UInt8 = 0x02

    public struct Manifest: Codable {
        public let version: Int
        public let createdAt: Date
        public let vaults: [VaultEntry]
        public let checksums: [String: String]  // filename → SHA-256 hex

        public struct VaultEntry: Codable {
            public let name: String
            public let filename: String
            public let keyfileName: String?
        }
    }

    /// Create an encrypted backup bundle containing all vault files.
    /// Uses Argon2id key derivation (v2 format).
    public static func createBackup(
        vaults: [(name: String, path: String, keyfilePath: String?)],
        backupPassword: String,
        destination: URL
    ) throws {
        let fm = FileManager.default
        var files: [(name: String, data: Data)] = []
        var checksums: [String: String] = [:]
        var manifestVaults: [Manifest.VaultEntry] = []

        for vault in vaults {
            guard fm.fileExists(atPath: vault.path) else { continue }
            let data = try Data(contentsOf: URL(fileURLWithPath: vault.path))
            let filename = (vault.path as NSString).lastPathComponent
            files.append((name: filename, data: data))
            checksums[filename] = sha256Hex(data)

            var keyfileName: String?
            if let kfPath = vault.keyfilePath, fm.fileExists(atPath: kfPath) {
                let kfData = try Data(contentsOf: URL(fileURLWithPath: kfPath))
                let kfName = "keyfile-\((kfPath as NSString).lastPathComponent)"
                files.append((name: kfName, data: kfData))
                checksums[kfName] = sha256Hex(kfData)
                keyfileName = kfName
            }

            manifestVaults.append(Manifest.VaultEntry(
                name: vault.name, filename: filename, keyfileName: keyfileName
            ))
        }

        let manifest = Manifest(
            version: 1,
            createdAt: Date(),
            vaults: manifestVaults,
            checksums: checksums
        )

        let manifestData = try JSONEncoder().encode(manifest)
        files.insert((name: "manifest.json", data: manifestData), at: 0)

        // Serialize all files into a simple container: [nameLen:UInt32][name:UTF8][dataLen:UInt64][data]...
        var container = Data()
        for file in files {
            let nameData = Data(file.name.utf8)
            var nameLen = UInt32(nameData.count)
            container.append(Data(bytes: &nameLen, count: 4))
            container.append(nameData)
            var dataLen = UInt64(file.data.count)
            container.append(Data(bytes: &dataLen, count: 8))
            container.append(file.data)
        }

        // Derive key from backup password using Argon2id with random salt
        let salt = Argon2Bridge.randomSalt()
        guard let key = Argon2Bridge.deriveKey(from: backupPassword, salt: salt) else {
            throw BackupBundleError.keyDerivationFailed
        }

        // Encrypt
        let sealed = try ChaChaPoly.seal(container, using: key)

        // Write: magic(4) + version(1) + salt(32) + sealed.combined
        var output = magic
        output.append(versionArgon2)
        output.append(salt)
        output.append(sealed.combined)
        try output.write(to: destination)
    }

    /// Verify a backup bundle: decrypt, parse manifest, validate checksums.
    public static func verify(at url: URL, backupPassword: String) throws -> Manifest {
        let manifest = try readManifest(at: url, backupPassword: backupPassword)
        let files = try readFiles(at: url, backupPassword: backupPassword)

        // Validate checksums
        for (filename, expectedHash) in manifest.checksums {
            guard let fileData = files[filename] else {
                throw BackupBundleError.missingFile(filename)
            }
            let actualHash = sha256Hex(fileData)
            if actualHash != expectedHash {
                throw BackupBundleError.checksumMismatch(filename)
            }
        }

        return manifest
    }

    /// Restore vaults from a backup bundle to a directory.
    public static func restore(from url: URL, backupPassword: String, toDirectory: String) throws -> Manifest {
        let manifest = try verify(at: url, backupPassword: backupPassword)
        let files = try readFiles(at: url, backupPassword: backupPassword)
        let fm = FileManager.default

        try fm.createDirectory(atPath: toDirectory, withIntermediateDirectories: true)

        for vault in manifest.vaults {
            if let data = files[vault.filename] {
                let destPath = (toDirectory as NSString).appendingPathComponent(vault.filename)
                try data.write(to: URL(fileURLWithPath: destPath))
            }
            if let kfName = vault.keyfileName, let kfData = files[kfName] {
                let destPath = (toDirectory as NSString).appendingPathComponent(kfName)
                try kfData.write(to: URL(fileURLWithPath: destPath))
            }
        }

        return manifest
    }

    // MARK: - Internal

    /// Decrypt backup file. Supports v2 (Argon2id) and v1 (legacy SHA-256) formats.
    private static func decrypt(at url: URL, backupPassword: String) throws -> Data {
        let raw = try Data(contentsOf: url)
        guard raw.count > 4, raw.prefix(4) == magic else {
            throw BackupBundleError.invalidFormat
        }

        // Check for v2 format: magic(4) + 0x02(1) + salt(32) + sealed
        if raw.count > 37 && raw[4] == versionArgon2 {
            let salt = raw.subdata(in: 5..<37)
            let encrypted = raw.dropFirst(37)

            // Try new 256MB params first
            if let key = Argon2Bridge.deriveKey(from: backupPassword, salt: salt) {
                do {
                    let sealedBox = try ChaChaPoly.SealedBox(combined: encrypted)
                    return try ChaChaPoly.open(sealedBox, using: key)
                } catch {
                    // Fall through to try old params
                }
            }

            // Fallback: try old 64MB params (for v2 files created before param upgrade)
            guard let lowKey = Argon2Bridge.deriveKeyLow(from: backupPassword, salt: salt) else {
                throw BackupBundleError.keyDerivationFailed
            }
            let sealedBox = try ChaChaPoly.SealedBox(combined: encrypted)
            return try ChaChaPoly.open(sealedBox, using: lowKey)
        }

        // v1 legacy: magic(4) + sealed (SHA-256 key derivation)
        let encrypted = raw.dropFirst(4)
        let key = deriveLegacyKey(from: backupPassword)
        let sealedBox = try ChaChaPoly.SealedBox(combined: encrypted)
        return try ChaChaPoly.open(sealedBox, using: key)
    }

    private static func readFiles(at url: URL, backupPassword: String) throws -> [String: Data] {
        let container = try decrypt(at: url, backupPassword: backupPassword)
        var files: [String: Data] = [:]
        var offset = 0

        while offset < container.count {
            guard offset + 4 <= container.count else { break }
            let nameLen = container.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4

            guard offset + Int(nameLen) <= container.count else { break }
            let nameData = container.subdata(in: offset..<offset+Int(nameLen))
            let name = String(decoding: nameData, as: UTF8.self)
            offset += Int(nameLen)

            guard offset + 8 <= container.count else { break }
            let dataLen = container.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
            offset += 8

            guard offset + Int(dataLen) <= container.count else { break }
            let data = container.subdata(in: offset..<offset+Int(dataLen))
            offset += Int(dataLen)

            files[name] = data
        }

        return files
    }

    private static func readManifest(at url: URL, backupPassword: String) throws -> Manifest {
        let files = try readFiles(at: url, backupPassword: backupPassword)
        guard let manifestData = files["manifest.json"] else {
            throw BackupBundleError.missingManifest
        }
        return try JSONDecoder().decode(Manifest.self, from: manifestData)
    }

    /// Legacy SHA-256 key derivation for reading old backup files.
    private static func deriveLegacyKey(from password: String) -> SymmetricKey {
        let salt = Data("CitadelBackupSalt-v1".utf8)
        let input = Data(password.utf8) + salt
        let hash = SHA256.hash(data: input)
        return SymmetricKey(data: hash)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum BackupBundleError: Error, LocalizedError {
    case invalidFormat
    case missingManifest
    case missingFile(String)
    case checksumMismatch(String)
    case keyDerivationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Not a valid Smaug backup file"
        case .missingManifest: return "Backup manifest is missing"
        case .missingFile(let name): return "Missing file in backup: \(name)"
        case .checksumMismatch(let name): return "Checksum mismatch for: \(name)"
        case .keyDerivationFailed: return "Key derivation failed"
        }
    }
}
