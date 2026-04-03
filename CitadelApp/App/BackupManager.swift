import Foundation
import CryptoKit
import CitadelCore

/// Handles vault backup: copy, validate, and checksum.
enum BackupManager {

    /// Create a timestamped auto-backup in the vault directory (used before password changes).
    /// Validates the copy and writes a SHA-256 checksum, matching the manual backup flow.
    static func autoBackup(vaultPath: String, password: Data, keyfilePath: String? = nil) throws -> URL {
        let sourceURL = URL(fileURLWithPath: vaultPath)
        let dir = sourceURL.deletingLastPathComponent()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let backupURL = dir.appendingPathComponent("vault-backup-\(formatter.string(from: Date())).kdbx")
        try FileManager.default.copyItem(at: sourceURL, to: backupURL)

        // Validate the backup can be opened
        try VaultEngine.validate(path: backupURL.path, password: password, keyfilePath: keyfilePath)

        // SHA-256 checksum
        let data = try Data(contentsOf: backupURL)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let checksumURL = backupURL.appendingPathExtension("sha256")
        let content = "\(hex)  \(backupURL.lastPathComponent)\n"
        try content.write(to: checksumURL, atomically: true, encoding: .utf8)

        return backupURL
    }
}
