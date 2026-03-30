import Foundation
import Observation
import CitadelCore

/// Alert flags for a single entry in the entry list.
struct EntryAlertFlags: Sendable {
    var breached = false
    var weak = false
    var old = false
    var missingTOTP = false
}

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

    /// Per-entry alert indicators (breached, weak, old, missing TOTP).
    var entryAlerts: [String: EntryAlertFlags] = [:]

    /// Tracked biometric state — SwiftUI observes these instead of reading
    /// BiometricManager directly (which is not @Observable).
    var biometricEnrolled = false
    var biometricAvailable = false

    // MARK: - Multi-vault

    /// The active vault's display name.
    var activeVaultName: String = "Personal"

    /// Current vault file path (mutable for vault switching).
    private(set) var vaultPath: String

    /// Vault directory path.
    let vaultDirectory: String

    /// Registry of known vaults.
    let vaultRegistry = VaultRegistry()

    /// Known vaults (for UI binding).
    var knownVaults: [VaultInfo] { vaultRegistry.vaults }

    // MARK: - Breach checker

    let breachChecker = BreachChecker()

    // MARK: - Non-observable infrastructure

    let engine = VaultEngine()
    let clipboard = SecureClipboard()
    @ObservationIgnored private var autoLockManager: AutoLockManager?
    @ObservationIgnored private var currentPassword: Data?
    @ObservationIgnored private var currentKeyfilePath: String?
    let auditLogger: AuditLogger
    let biometricManager: BiometricManager
    @ObservationIgnored var statusBar: StatusBarController?
    @ObservationIgnored var quickAccess: QuickAccessPanel?
    @ObservationIgnored let largeTypeWindow = LargeTypeWindow()

    /// Password accessor for biometric enrollment (read-only copy).
    var currentPasswordForBiometric: Data? { currentPassword }

    /// Whether a vault file exists at the active path (or can be recovered).
    var vaultExists: Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: vaultPath) { return true }
        if fm.fileExists(atPath: vaultPath + ".prev") { return true }
        if fm.fileExists(atPath: vaultPath + ".tmp") { return true }
        return false
    }

    // MARK: - Init

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".citadel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vaultDirectory = dir.path
        auditLogger = AuditLogger(vaultDirectory: dir.path)
        biometricManager = BiometricManager(directory: dir.path)

        // Multi-vault: set up registry and determine active vault
        vaultRegistry.ensureDefaults(directory: dir.path)
        if let activePath = vaultRegistry.activeVaultPath {
            vaultPath = activePath
        } else {
            vaultPath = dir.appendingPathComponent("vault.kdbx").path
        }
        if let info = vaultRegistry.vaults.first(where: { $0.path == vaultPath }) {
            activeVaultName = info.name
        }

        // Prevent Spotlight from indexing the vault directory
        let noIndex = dir.appendingPathComponent(".metadata_never_index")
        if !FileManager.default.fileExists(atPath: noIndex.path) {
            FileManager.default.createFile(atPath: noIndex.path, contents: nil)
        }

        recoverVaultIfNeeded()
        cloudSyncWarning = Self.detectCloudSync(vaultDir: dir.path)

        autoLockManager = AutoLockManager { [weak self] in
            self?.lockVault()
        }

        biometricAvailable = biometricManager.isAvailable
        biometricEnrolled = biometricManager.isEnabled

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusBar = StatusBarController(appState: self)
            self.quickAccess = QuickAccessPanel(appState: self)
            self.quickAccess?.registerGlobalShortcut()
        }
    }

    // MARK: - Vault switching

    /// Switch to a different vault. Locks the current vault first.
    func switchVault(to info: VaultInfo) {
        if !isLocked { lockVault() }
        vaultPath = info.path
        activeVaultName = info.name
        vaultRegistry.activeVaultPath = info.path
        recoverVaultIfNeeded()
    }

    /// Create a new vault file and register it.
    func createAndRegisterVault(name: String, password: Data, keyfilePath: String? = nil) async throws {
        let filename = name.lowercased().replacingOccurrences(of: " ", with: "-") + ".kdbx"
        let path = (vaultDirectory as NSString).appendingPathComponent(filename)
        vaultRegistry.register(name: name, path: path)
        vaultPath = path
        activeVaultName = name
        try await createVaultAsync(password: password, keyfilePath: keyfilePath)
    }

    /// Remove a vault from the registry (does not delete the file).
    func removeVault(path: String) {
        vaultRegistry.remove(path: path)
    }

    // MARK: - Biometric

    func refreshBiometricState() {
        biometricEnrolled = biometricManager.isEnabled
        biometricAvailable = biometricManager.isAvailable
    }

    // MARK: - Cloud sync detection

    private static func detectCloudSync(vaultDir: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let knownSyncPaths = [
            home + "/Library/Mobile Documents",
            home + "/Dropbox",
            home + "/Google Drive",
            home + "/OneDrive",
            home + "/Documents",
        ]
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

    // MARK: - Crash recovery

    private func recoverVaultIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: vaultPath) else { return }
        let prevPath = vaultPath + ".prev"
        if fm.fileExists(atPath: prevPath), Self.looksLikeKDBX(atPath: prevPath) {
            try? fm.copyItem(atPath: prevPath, toPath: vaultPath)
            return
        }
        let tmpPath = vaultPath + ".tmp"
        if fm.fileExists(atPath: tmpPath), Self.looksLikeKDBX(atPath: tmpPath) {
            _ = rename(tmpPath, vaultPath)
        }
    }

    private static let kdbxMagic: [UInt8] = [0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5]

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
        computeEntryAlerts()
        statusBar?.refresh()
    }

    func unlockAsync(password: Data, keyfilePath: String? = nil, vaultPathOverride: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }
        let path = vaultPathOverride ?? vaultPath
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
        computeEntryAlerts()
        statusBar?.refresh()
    }

    func unlockWithBiometrics() async throws {
        print("BIO UNLOCK: Starting biometric unlock flow")
        let password = try await biometricManager.unlock()
        print("BIO UNLOCK: Got password (\(password.count) bytes), opening vault")
        try await unlockAsync(password: password, keyfilePath: currentKeyfilePath)
        print("BIO UNLOCK: Vault opened successfully")
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
        vaultRegistry.register(name: activeVaultName, path: vaultPath)
        statusBar?.refresh()
    }

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
        vaultRegistry.register(name: activeVaultName, path: vaultPath)
        statusBar?.refresh()
    }

    func lockVault() {
        autoLockManager?.stop()
        engine.close()
        if currentPassword != nil {
            currentPassword!.resetBytes(in: 0..<currentPassword!.count)
        }
        currentPassword = nil
        currentKeyfilePath = nil
        entries = []
        entryAlerts = [:]
        selectedEntryID = nil
        errorMessage = nil
        expiredEntriesMessage = nil
        isLoading = false
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
        computeEntryAlerts()
        statusBar?.refresh()
    }

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

    /// Compute alert indicators for all entries (async, called after unlock).
    func computeEntryAlerts() {
        let currentEntries = entries
        let eng = engine
        Task {
            var alerts: [String: EntryAlertFlags] = [:]
            let now = Date()
            let sixMonthsAgo = now.addingTimeInterval(-180 * 24 * 3600)

            for summary in currentEntries {
                var flags = EntryAlertFlags()

                // Skip secure notes
                if summary.entryType == "secure_note" {
                    alerts[summary.id] = flags
                    continue
                }

                // Get password for analysis
                if let detail = try? eng.getEntry(uuid: summary.id) {
                    let pwString = String(decoding: detail.password, as: UTF8.self)
                    // Weak password check (< 40 bits entropy)
                    let entropy = PasswordStrength.entropy(of: pwString)
                    if entropy < 40 && !pwString.isEmpty {
                        flags.weak = true
                    }
                }

                // Old password check (> 180 days)
                if let modified = summary.lastModified, modified < sixMonthsAgo {
                    flags.old = true
                }

                // Missing TOTP check (only for login entries)
                if summary.entryType != "secure_note" {
                    if let detail = try? eng.getEntry(uuid: summary.id), detail.otpURI.isEmpty {
                        flags.missingTOTP = true
                    }
                }

                alerts[summary.id] = flags
            }

            // Check breaches if user has consented
            if breachChecker.hasConsented {
                var passwords: [(id: String, title: String, password: Data)] = []
                for summary in currentEntries where summary.entryType != "secure_note" {
                    if let detail = try? eng.getEntry(uuid: summary.id), !detail.password.isEmpty {
                        passwords.append((id: summary.id, title: summary.title, password: detail.password))
                    }
                }
                let results = await breachChecker.checkAll(entries: passwords)
                for result in results where result.breachCount > 0 {
                    alerts[result.id, default: EntryAlertFlags()].breached = true
                }
            }

            self.entryAlerts = alerts
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

        let backupURL = try BackupManager.autoBackup(vaultPath: vaultPath, password: currentPassword, keyfilePath: currentKeyfilePath)
        try engine.changePassword(newPassword, keyfilePath: newKeyfilePath)

        do {
            try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: newPassword, keyfilePath: newKeyfilePath)
        } catch {
            engine.close()
            let fm = FileManager.default
            var restoreFailed = false
            do {
                if fm.fileExists(atPath: vaultPath) { try fm.removeItem(atPath: vaultPath) }
                try fm.moveItem(at: backupURL, to: URL(fileURLWithPath: vaultPath))
                try engine.open(path: vaultPath, password: currentPassword, keyfilePath: self.currentKeyfilePath)
                self.currentPassword = currentPassword
            } catch { restoreFailed = true }

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

    /// Create a full encrypted backup bundle of all known vaults.
    func createFullBackup(backupPassword: String, destination: URL) throws {
        let vaults = vaultRegistry.vaults.map {
            (name: $0.name, path: $0.path, keyfilePath: nil as String?)
        }
        try VaultBackupBundle.createBackup(vaults: vaults, backupPassword: backupPassword, destination: destination)
    }

    /// Verify a backup bundle.
    func verifyBackup(at url: URL, backupPassword: String) throws -> VaultBackupBundle.Manifest {
        try VaultBackupBundle.verify(at: url, backupPassword: backupPassword)
    }

    /// Restore from a backup bundle.
    func restoreFromBackup(at url: URL, backupPassword: String) throws -> VaultBackupBundle.Manifest {
        let manifest = try VaultBackupBundle.restore(from: url, backupPassword: backupPassword, toDirectory: vaultDirectory)
        // Register restored vaults
        for vault in manifest.vaults {
            let path = (vaultDirectory as NSString).appendingPathComponent(vault.filename)
            vaultRegistry.register(name: vault.name, path: path)
        }
        return manifest
    }
}
