import Foundation
import CryptoKit
import CitadelCore

/// Handles vault backup: copy, validate, and checksum.
enum BackupManager {

    /// Copy vault to a user-chosen destination, validate the copy, and write a SHA-256 checksum.
    /// Atomic: writes to .tmp first, validates, then renames over destination.
    static func backup(vaultPath: String, to destination: URL, password: Data, keyfilePath: String? = nil) throws {
        let fm = FileManager.default
        let sourceURL = URL(fileURLWithPath: vaultPath)
        let tmpDestination = destination.appendingPathExtension("tmp")

        // Clean up stale temp if present
        if fm.fileExists(atPath: tmpDestination.path) {
            try fm.removeItem(at: tmpDestination)
        }

        // Copy to temp location first
        try fm.copyItem(at: sourceURL, to: tmpDestination)

        // Validate the temp copy can be opened
        try VaultEngine.validate(path: tmpDestination.path, password: password, keyfilePath: keyfilePath)

        // Only now replace existing backup with validated copy
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tmpDestination, to: destination)

        // Generate SHA-256 checksum file
        let data = try Data(contentsOf: destination)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()

        let checksumURL = destination.appendingPathExtension("sha256")
        let content = "\(hex)  \(destination.lastPathComponent)\n"
        try content.write(to: checksumURL, atomically: true, encoding: .utf8)
    }

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
