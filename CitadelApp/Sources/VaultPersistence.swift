import Foundation
import CCitadelCore

/// Atomic save pipeline for KDBX vaults on macOS/APFS.
///
/// Save sequence:
/// 1. Write to `vault.kdbx.tmp` via `vault_save_to`
/// 2. `F_FULLFSYNC` the temp file
/// 3. Validate temp file with `vault_validate`
/// 4. Rotate snapshots (.prev → .prev2 → .prev3)
/// 5. Rename current vault to `.prev`
/// 6. Atomic rename temp → vault
/// 7. `F_FULLFSYNC` the directory
///
/// Keeps 3 previous versions maximum.
public final class VaultPersistence: Sendable {

    /// Maximum number of previous snapshots to keep.
    private static let maxSnapshots = 3

    /// Perform the full atomic save pipeline.
    ///
    /// - Parameters:
    ///   - engine: The VaultEngine with an open vault.
    ///   - vaultPath: The canonical path for the vault file (e.g. `~/vault.kdbx`).
    ///   - password: The vault password (needed for validation step).
    public static func atomicSave(
        engine: VaultEngine,
        vaultPath: String,
        password: Data
    ) throws {
        let tmpPath = vaultPath + ".tmp"
        let fm = FileManager.default

        // 1. Write to temp file
        try engine.saveTo(path: tmpPath)

        // 2. F_FULLFSYNC the temp file
        try fullFsync(path: tmpPath)

        // 3. Validate the temp file
        do {
            try VaultEngine.validate(path: tmpPath, password: password)
        } catch {
            // Validation failed — remove the temp file and propagate
            try? fm.removeItem(atPath: tmpPath)
            throw error
        }

        // 4. Rotate snapshots: .prev2 → .prev3, .prev → .prev2
        rotateSnapshots(basePath: vaultPath)

        // 5. Copy current vault to .prev (vault stays in place — no gap)
        let prevPath = vaultPath + ".prev"
        if fm.fileExists(atPath: vaultPath) {
            if fm.fileExists(atPath: prevPath) {
                try? fm.removeItem(atPath: prevPath)
            }
            try fm.copyItem(atPath: vaultPath, toPath: prevPath)
        }

        // 6. Atomic rename temp → vault
        //    POSIX rename() atomically replaces the destination on APFS.
        //    The vault file is never missing — it goes directly from old to new.
        let renameResult = rename(tmpPath, vaultPath)
        if renameResult != 0 {
            throw VaultError.writeFailed
        }

        // 7. F_FULLFSYNC the directory
        let dirPath = (vaultPath as NSString).deletingLastPathComponent
        try fullFsync(directoryPath: dirPath)
    }

    // MARK: - Internal

    /// Issue F_FULLFSYNC on a file (NOT fsync — F_FULLFSYNC forces the drive
    /// to flush its write cache, which fsync does not guarantee on macOS).
    static func fullFsync(path: String) throws {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else {
            throw VaultError.writeFailed
        }
        defer { Darwin.close(fd) }

        let rc = fcntl(fd, F_FULLFSYNC)
        if rc != 0 {
            throw VaultError.writeFailed
        }
    }

    /// Issue F_FULLFSYNC on a directory to ensure metadata (renames) are durable.
    static func fullFsync(directoryPath: String) throws {
        let fd = Darwin.open(directoryPath, O_RDONLY)
        guard fd >= 0 else {
            throw VaultError.writeFailed
        }
        defer { Darwin.close(fd) }

        // F_FULLFSYNC on the directory flushes rename metadata
        let rc = fcntl(fd, F_FULLFSYNC)
        if rc != 0 {
            throw VaultError.writeFailed
        }
    }

    /// Rotate .prev, .prev2, .prev3 snapshots.
    /// Deletes .prev3 (the oldest beyond max) if it exists.
    /// If any rename fails, rotation stops to prevent overwriting valid snapshots.
    private static func rotateSnapshots(basePath: String) {
        let fm = FileManager.default

        // Delete oldest snapshot beyond our limit
        let oldest = basePath + ".prev\(maxSnapshots)"
        try? fm.removeItem(atPath: oldest)

        // Shift: .prev(N-1) → .prev(N), working backwards.
        // If a rename fails, stop — continuing could overwrite valid snapshots.
        for i in stride(from: maxSnapshots - 1, through: 2, by: -1) {
            let src = basePath + ".prev\(i)"
            let dst = basePath + ".prev\(i + 1)"
            if fm.fileExists(atPath: src) {
                do {
                    try fm.moveItem(atPath: src, toPath: dst)
                } catch {
                    return
                }
            }
        }

        // .prev → .prev2
        let prev1 = basePath + ".prev"
        let prev2 = basePath + ".prev2"
        if fm.fileExists(atPath: prev1) {
            do {
                try fm.moveItem(atPath: prev1, toPath: prev2)
            } catch {
                // .prev stays; copy step will remove it before overwriting
            }
        }
    }
}
