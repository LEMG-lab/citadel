import Foundation
import Observation
import CitadelCore

/// Central application state. Manages vault lifecycle, entry data, and security managers.
@MainActor
@Observable
final class AppState {

    // MARK: - Observable state (drives UI)

    var isLocked = true
    var entries: [VaultEntrySummary] = []
    var selectedEntryID: String?
    var errorMessage: String?

    /// Settings — auto-lock timeout in seconds (1–30 min).
    var autoLockTimeout: TimeInterval = 300 {
        didSet { autoLockManager?.timeout = autoLockTimeout }
    }

    /// Settings — clipboard clear time in seconds (5–60 sec).
    var clipboardClearTime: TimeInterval = 15 {
        didSet { clipboard.clearInterval = clipboardClearTime }
    }

    /// True when the vault directory appears to be inside a cloud-synced folder.
    var cloudSyncWarning: String?

    // MARK: - Non-observable infrastructure

    let engine = VaultEngine()
    let clipboard = SecureClipboard()
    @ObservationIgnored private var autoLockManager: AutoLockManager?
    @ObservationIgnored private var currentPassword: Data?

    /// Canonical vault file path.
    let vaultPath: String

    /// Whether a vault file exists at the default path (or can be recovered).
    var vaultExists: Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: vaultPath) { return true }
        // Recoverable from backup files
        if fm.fileExists(atPath: vaultPath + ".prev") { return true }
        if fm.fileExists(atPath: vaultPath + ".tmp") { return true }
        return false
    }

    // MARK: - Init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("Citadel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vaultPath = dir.appendingPathComponent("vault.kdbx").path

        // Prevent Spotlight from indexing the vault directory
        let noIndex = dir.appendingPathComponent(".metadata_never_index")
        if !FileManager.default.fileExists(atPath: noIndex.path) {
            FileManager.default.createFile(atPath: noIndex.path, contents: nil)
        }

        // Attempt crash recovery if vault is missing but backup files exist
        recoverVaultIfNeeded()

        // Warn if vault directory is inside a cloud-synced folder
        cloudSyncWarning = Self.detectCloudSync(vaultDir: dir.path)

        autoLockManager = AutoLockManager { [weak self] in
            self?.lockVault()
        }
    }

    /// Check if the vault directory is inside a known cloud sync path.
    private static func detectCloudSync(vaultDir: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let knownSyncPaths = [
            home + "/Library/Mobile Documents",   // iCloud Drive
            home + "/Dropbox",
            home + "/Google Drive",
            home + "/OneDrive",
        ]

        for syncPath in knownSyncPaths {
            if vaultDir.hasPrefix(syncPath) {
                return "Your vault is inside a cloud-synced folder (\(syncPath)). "
                    + "This means your vault file is uploaded to remote servers, and concurrent "
                    + "edits from other devices can cause silent data loss. Consider moving your "
                    + "vault to a non-synced location."
            }
        }

        // Check if ~/Documents is synced via iCloud "Desktop & Documents"
        // by looking for the com.apple.bird extended attribute
        let docsPath = home + "/Documents"
        if vaultDir.hasPrefix(docsPath) {
            let mobileDocs = home + "/Library/Mobile Documents/com~apple~CloudDocs/Documents"
            let fm = FileManager.default
            // If ~/Documents is a symlink into Mobile Documents, iCloud sync is active
            if let resolved = try? fm.destinationOfSymbolicLink(atPath: docsPath),
               resolved.contains("Mobile Documents") {
                return "Your ~/Documents folder is synced to iCloud. Your vault file may be "
                    + "uploaded to Apple servers. Consider disabling 'Desktop & Documents Folders' "
                    + "in System Settings > iCloud > iCloud Drive, or move the vault elsewhere."
            }
            // Also check if the iCloud mirror of Documents exists
            if fm.fileExists(atPath: mobileDocs) {
                return "iCloud 'Desktop & Documents Folders' may be enabled. Your vault file "
                    + "could be synced to Apple servers. Consider checking System Settings > "
                    + "iCloud > iCloud Drive, or moving the vault to a non-synced location."
            }
        }

        return nil
    }

    /// If vault.kdbx is missing but .prev or .tmp exist, recover the best candidate.
    private func recoverVaultIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: vaultPath) else { return }

        // Prefer .prev (last validated good copy) over .tmp (may be incomplete)
        let prevPath = vaultPath + ".prev"
        if fm.fileExists(atPath: prevPath), Self.looksLikeKDBX(atPath: prevPath) {
            try? fm.copyItem(atPath: prevPath, toPath: vaultPath)
            return
        }

        // Fall back to .tmp — only promote if it passes structural checks
        let tmpPath = vaultPath + ".tmp"
        if fm.fileExists(atPath: tmpPath), Self.looksLikeKDBX(atPath: tmpPath) {
            _ = rename(tmpPath, vaultPath)
        }
    }

    /// KDBX4 signature: primary 0x9AA2D903 + secondary 0xB54BFB67 (little-endian).
    private static let kdbxMagic: [UInt8] = [0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5]

    /// Check that a file is at least 1024 bytes and starts with valid KDBX magic.
    /// This is a structural sanity check — full validation requires the password.
    private static func looksLikeKDBX(atPath path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64,
              size >= 1024 else {
            return false
        }
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        let header = fh.readData(ofLength: 8)
        return header.count == 8 && header.elementsEqual(kdbxMagic)
    }

    // MARK: - Vault lifecycle

    func unlock(password: Data) throws {
        try engine.open(path: vaultPath, password: password)
        currentPassword = password
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
    }

    func createVault(password: Data) throws {
        try engine.create(password: password)
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password)
        currentPassword = password
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
    }

    func lockVault() {
        autoLockManager?.stop()
        engine.close()
        // Zero password bytes before releasing the reference
        if currentPassword != nil {
            currentPassword!.resetBytes(in: 0..<currentPassword!.count)
        }
        currentPassword = nil
        entries = []
        selectedEntryID = nil
        errorMessage = nil
        clipboard.forceClear()
        isLocked = true
    }

    // MARK: - Persistence

    func save() throws {
        guard let pw = currentPassword else {
            throw VaultError.internalError("no password available")
        }
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: pw)
    }

    func refreshEntries() throws {
        entries = try engine.listEntries()
    }

    // MARK: - Password change

    func changePassword(currentPassword: Data, newPassword: Data) throws {
        guard currentPassword == self.currentPassword else {
            throw VaultError.wrongPassword
        }

        // Auto-backup before changing (validated + checksummed)
        let backupURL = try BackupManager.autoBackup(vaultPath: vaultPath, password: currentPassword)

        try engine.changePassword(newPassword)

        do {
            try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: newPassword)
        } catch {
            // Attempt to restore from backup
            engine.close()
            let fm = FileManager.default
            var restoreFailed = false

            do {
                if fm.fileExists(atPath: vaultPath) {
                    try fm.removeItem(atPath: vaultPath)
                }
                try fm.moveItem(at: backupURL, to: URL(fileURLWithPath: vaultPath))
                try engine.open(path: vaultPath, password: currentPassword)
                self.currentPassword = currentPassword
            } catch {
                restoreFailed = true
            }

            if restoreFailed {
                throw VaultError.internalError(
                    "Password change failed and restore also failed. "
                    + "Your vault backup is at: \(backupURL.path). "
                    + "Use it to recover manually."
                )
            }
            throw error
        }

        self.currentPassword = newPassword
    }

    // MARK: - Backup

    func performBackup(to destination: URL) throws {
        guard let pw = currentPassword else {
            throw VaultError.internalError("no password available")
        }
        try BackupManager.backup(vaultPath: vaultPath, to: destination, password: pw)
    }
}
