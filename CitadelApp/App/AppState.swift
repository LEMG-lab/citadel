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

    /// True while a long-running vault operation (open/create/save) is in progress.
    var isLoading = false

    /// Number of entries that have expired or are expiring within 7 days.
    var expiredEntriesMessage: String?

    /// Tracked biometric state — SwiftUI observes these instead of reading
    /// BiometricManager directly (which is not @Observable).
    var biometricEnrolled = false
    var biometricAvailable = false

    // MARK: - Non-observable infrastructure

    let engine = VaultEngine()
    let clipboard = SecureClipboard()
    @ObservationIgnored private var autoLockManager: AutoLockManager?
    @ObservationIgnored private var currentPassword: Data?
    @ObservationIgnored private var currentKeyfilePath: String?
    let auditLogger: AuditLogger
    let biometricManager: BiometricManager
    @ObservationIgnored var statusBar: StatusBarController?

    /// Password accessor for biometric enrollment (read-only copy).
    var currentPasswordForBiometric: Data? { currentPassword }

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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".citadel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vaultPath = dir.appendingPathComponent("vault.kdbx").path
        auditLogger = AuditLogger(vaultDirectory: dir.path)
        biometricManager = BiometricManager(directory: dir.path)
        biometricManager.unenroll()

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

        // Initialize tracked biometric state for SwiftUI
        biometricAvailable = biometricManager.isAvailable
        biometricEnrolled = biometricManager.isEnabled

        // Menu bar icon
        statusBar = StatusBarController(appState: self)
    }

    /// Sync tracked biometric properties from BiometricManager.
    /// Call after any operation that changes biometric enrollment.
    func refreshBiometricState() {
        biometricEnrolled = biometricManager.isEnabled
        biometricAvailable = biometricManager.isAvailable
    }

    /// Check if the vault directory is inside a known cloud sync path.
    /// The default ~/.citadel is safe, but detect if someone has moved or
    /// symlinked it into a synced folder.
    private static func detectCloudSync(vaultDir: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let knownSyncPaths = [
            home + "/Library/Mobile Documents",   // iCloud Drive
            home + "/Dropbox",
            home + "/Google Drive",
            home + "/OneDrive",
            home + "/Documents",                   // may be synced via iCloud Desktop & Documents
        ]

        // Resolve symlinks to detect if ~/.citadel points into a synced folder
        let resolved = (vaultDir as NSString).resolvingSymlinksInPath

        for syncPath in knownSyncPaths {
            if resolved.hasPrefix(syncPath) {
                return "Your vault is inside a cloud-synced folder (\(syncPath)). "
                    + "This means your vault file is uploaded to remote servers, and concurrent "
                    + "edits from other devices can cause silent data loss. Consider moving your "
                    + "vault to a non-synced location such as ~/.citadel/."
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

    func unlock(password: Data, keyfilePath: String? = nil) throws {
        try engine.open(path: vaultPath, password: password, keyfilePath: keyfilePath)
        currentPassword = password
        currentKeyfilePath = keyfilePath
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
        biometricManager.recordFullAuth()
        auditLogger.log(.unlock)
        checkExpiredEntries()
        statusBar?.refresh()
    }

    /// Async unlock — runs Argon2id off the main thread.
    func unlockAsync(password: Data, keyfilePath: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }
        let path = vaultPath
        let eng = engine
        try await Task.detached {
            try eng.open(path: path, password: password, keyfilePath: keyfilePath)
        }.value
        currentPassword = password
        currentKeyfilePath = keyfilePath
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
        biometricManager.recordFullAuth()
        auditLogger.log(.unlock)
        checkExpiredEntries()
        statusBar?.refresh()
    }

    func createVault(password: Data, keyfilePath: String? = nil) throws {
        try engine.create(password: password, keyfilePath: keyfilePath)
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password, keyfilePath: keyfilePath)
        currentPassword = password
        currentKeyfilePath = keyfilePath
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
        auditLogger.log(.createVault)
        statusBar?.refresh()
    }

    /// Async create — runs Argon2id off the main thread.
    func createVaultAsync(password: Data, keyfilePath: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }
        let eng = engine
        let path = vaultPath
        try await Task.detached {
            try eng.create(password: password, keyfilePath: keyfilePath)
            try VaultPersistence.atomicSave(engine: eng, vaultPath: path, password: password, keyfilePath: keyfilePath)
        }.value
        currentPassword = password
        currentKeyfilePath = keyfilePath
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
        auditLogger.log(.createVault)
        statusBar?.refresh()
    }

    func lockVault() {
        autoLockManager?.stop()
        engine.close()
        // Zero password bytes before releasing the reference
        if currentPassword != nil {
            currentPassword!.resetBytes(in: 0..<currentPassword!.count)
        }
        currentPassword = nil
        currentKeyfilePath = nil
        entries = []
        selectedEntryID = nil
        errorMessage = nil
        expiredEntriesMessage = nil
        isLoading = false
        // Clipboard timer manages its own lifecycle — don't forceClear here
        // so the user can still paste after the vault locks on inactivity/sleep.
        isLocked = true
        auditLogger.log(.lock)
        statusBar?.refresh()
    }

    // MARK: - Persistence

    func save() throws {
        guard let pw = currentPassword else {
            throw VaultError.internalError("no password available")
        }
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: pw, keyfilePath: currentKeyfilePath)
    }

    func refreshEntries() throws {
        entries = try engine.listEntries()
        statusBar?.refresh()
    }

    /// Check for expired entries and set a notification message.
    func checkExpiredEntries() {
        let now = Date()
        let expired = entries.filter { entry in
            guard let expiry = entry.expiryDate else { return false }
            return expiry < now
        }.count
        if expired > 0 {
            expiredEntriesMessage = "\(expired) password\(expired == 1 ? " has" : "s have") expired"
        } else {
            expiredEntriesMessage = nil
        }
    }

    // MARK: - Recycle Bin

    @discardableResult
    func emptyRecycleBin() throws -> Int {
        let count = try engine.emptyRecycleBin()
        try save()
        auditLogger.log(.emptyRecycleBin)
        return count
    }

    // MARK: - Password change

    func changePassword(currentPassword: Data, newPassword: Data, newKeyfilePath: String? = nil) throws {
        guard currentPassword == self.currentPassword else {
            throw VaultError.wrongPassword
        }

        // Auto-backup before changing (validated + checksummed)
        let backupURL = try BackupManager.autoBackup(vaultPath: vaultPath, password: currentPassword, keyfilePath: currentKeyfilePath)

        try engine.changePassword(newPassword, keyfilePath: newKeyfilePath)

        do {
            try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: newPassword, keyfilePath: newKeyfilePath)
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
                try engine.open(path: vaultPath, password: currentPassword, keyfilePath: self.currentKeyfilePath)
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
        self.currentKeyfilePath = newKeyfilePath
        biometricManager.unenroll()
        refreshBiometricState()
        auditLogger.log(.changePassword)

        // Password change succeeded — delete the auto-backup that was encrypted
        // with the old password. Leaving it around lets an attacker brute-force
        // the weaker old password to recover vault contents.
        let fm = FileManager.default
        try? fm.removeItem(at: backupURL)
        try? fm.removeItem(at: backupURL.appendingPathExtension("sha256"))
    }

    // MARK: - KDF

    func applyKdfPreset(_ preset: KdfPreset) throws {
        try engine.setKdfParams(memory: preset.memory, iterations: preset.iterations, parallelism: preset.parallelism)
        try save()
        preset.save()
    }

    // MARK: - Import

    /// Import a vault file from an external location (e.g. migration from unsandboxed install).
    func importVault(from sourceURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: vaultPath) {
            throw VaultError.internalError("A vault already exists at \(vaultPath)")
        }
        try fm.copyItem(at: sourceURL, to: URL(fileURLWithPath: vaultPath))
    }

    // MARK: - Backup

    func performBackup(to destination: URL) throws {
        guard let pw = currentPassword else {
            throw VaultError.internalError("no password available")
        }
        try BackupManager.backup(vaultPath: vaultPath, to: destination, password: pw, keyfilePath: currentKeyfilePath)
    }
}
