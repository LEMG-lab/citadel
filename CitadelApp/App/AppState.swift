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

        // Attempt crash recovery if vault is missing but backup files exist
        recoverVaultIfNeeded()

        autoLockManager = AutoLockManager { [weak self] in
            self?.lockVault()
        }
    }

    /// If vault.kdbx is missing but .prev or .tmp exist, recover the best candidate.
    private func recoverVaultIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: vaultPath) else { return }

        // Prefer .prev (last validated good copy) over .tmp (may be incomplete)
        let prevPath = vaultPath + ".prev"
        if fm.fileExists(atPath: prevPath) {
            try? fm.copyItem(atPath: prevPath, toPath: vaultPath)
            return
        }

        // Fall back to .tmp (might be valid if crash happened after write)
        let tmpPath = vaultPath + ".tmp"
        if fm.fileExists(atPath: tmpPath) {
            _ = rename(tmpPath, vaultPath)
        }
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
            // Restore: close engine, put backup back, reopen with old password
            engine.close()
            let fm = FileManager.default
            try? fm.removeItem(atPath: vaultPath)
            try? fm.moveItem(at: backupURL, to: URL(fileURLWithPath: vaultPath))
            try? engine.open(path: vaultPath, password: currentPassword)
            self.currentPassword = currentPassword
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
