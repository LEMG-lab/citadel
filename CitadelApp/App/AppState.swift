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
    var recycledEntries: [VaultEntrySummary] = []
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
    @ObservationIgnored private var vaultLockFD: Int32 = -1

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
        let dir = home.appendingPathComponent(".smaug")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        vaultDirectory = dir.path
        auditLogger = AuditLogger(vaultDirectory: dir.path)

        // Determine active vault path first, then init biometric manager with it
        vaultRegistry.ensureDefaults(directory: dir.path)
        let resolvedPath: String
        if let activePath = vaultRegistry.activeVaultPath {
            resolvedPath = activePath
        } else {
            resolvedPath = dir.appendingPathComponent("vault.kdbx").path
        }
        vaultPath = resolvedPath
        biometricManager = BiometricManager(directory: dir.path, vaultPath: resolvedPath)

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

        // Migrate: remove old file-based biometric data (replaced by Keychain)
        BiometricManager.cleanupOldBioFiles(inDirectory: dir.path)

        // Clean up stale temp dirs from previous crashes
        let tmpBase = FileManager.default.temporaryDirectory
        if let tmpContents = try? FileManager.default.contentsOfDirectory(atPath: tmpBase.path) {
            for item in tmpContents where item.hasPrefix("smaug-attachments") || item.hasPrefix("smaug-emergency") {
                try? FileManager.default.removeItem(at: tmpBase.appendingPathComponent(item))
            }
        }

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
        if !isLocked {
            try? save()  // Persist pending changes before switching
            lockVault()
        } else {
            releaseVaultLock() // Release any stale lock from a failed unlock attempt
        }
        vaultPath = info.path
        activeVaultName = info.name
        vaultRegistry.activeVaultPath = info.path
        biometricManager.configure(forVaultPath: info.path)
        refreshBiometricState()
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
                    + "vault to a non-synced location such as ~/.smaug/."
            }
        }
        return nil
    }

    // MARK: - Crash recovery

    private func recoverVaultIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: vaultPath) else { return }

        // Try candidates in priority order (.tmp is newest — written during save before rename)
        let candidates = [
            vaultPath + ".tmp",
            vaultPath + ".prev",
            vaultPath + ".prev2",
            vaultPath + ".prev3",
        ]

        for candidate in candidates {
            guard fm.fileExists(atPath: candidate), Self.looksLikeKDBX(atPath: candidate) else { continue }
            do {
                try fm.copyItem(atPath: candidate, toPath: vaultPath)
                // Validate: use empty password — wrongPassword means it's a real KDBX
                do {
                    try VaultEngine.validate(path: vaultPath, password: Data())
                    return // Valid KDBX opened with empty password
                } catch VaultError.wrongPassword {
                    return // Valid KDBX, just wrong password — file is good
                } catch {
                    // Invalid file — remove and mark as bad
                    try? fm.removeItem(atPath: vaultPath)
                    let invalidPath = candidate + ".recovered-invalid"
                    try? fm.moveItem(atPath: candidate, toPath: invalidPath)
                    continue // Try next candidate
                }
            } catch {
                continue // Copy failed, try next candidate
            }
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

    // MARK: - Vault reset

    /// Delete the current vault file and all its backups so the user can start fresh.
    func resetCurrentVault() {
        releaseVaultLock()
        let fm = FileManager.default
        // Delete the vault file and all .prev backups
        let filesToDelete = [
            vaultPath,
            vaultPath + ".tmp",
            vaultPath + ".prev",
            vaultPath + ".prev2",
            vaultPath + ".prev3",
        ]
        for file in filesToDelete {
            try? fm.removeItem(atPath: file)
        }
        // Delete audit log
        let auditLog = (vaultDirectory as NSString).appendingPathComponent("audit.log")
        try? fm.removeItem(atPath: auditLog)
        // Delete unlock failure counter
        try? fm.removeItem(atPath: unlockFailuresPath)
        // Remove from registry
        vaultRegistry.remove(path: vaultPath)
        // Unenroll biometrics for this vault
        biometricManager.unenroll()
        refreshBiometricState()
        // Reset UI state
        entries = []
        recycledEntries = []
        entryAlerts = [:]
        selectedEntryID = nil
        errorMessage = nil
        expiredEntriesMessage = nil
        isLocked = true
    }

    // MARK: - Vault lifecycle

    func unlock(password: Data, keyfilePath: String? = nil) throws {
        // Brute-force throttling
        let delay = unlockThrottleDelay()
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        try acquireVaultLock()
        do {
            try engine.open(path: vaultPath, password: password, keyfilePath: keyfilePath)
        } catch {
            releaseVaultLock()
            recordFailedUnlock()
            throw error
        }
        resetFailedUnlocks()
        currentPassword = password
        currentKeyfilePath = keyfilePath
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
        biometricManager.recordFullAuth(password: password)
        auditLogger.log(.unlock)
        checkExpiredEntries()
        computeEntryAlerts()
        statusBar?.refresh()
    }

    func unlockAsync(password: Data, keyfilePath: String? = nil, vaultPathOverride: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }
        let path = vaultPathOverride ?? vaultPath
        if vaultPathOverride == nil { try acquireVaultLock() }
        let eng = engine
        do {
            try await Task.detached {
                try eng.open(path: path, password: password, keyfilePath: keyfilePath)
            }.value
        } catch {
            if vaultPathOverride == nil { releaseVaultLock() }
            recordFailedUnlock()
            throw error
        }
        currentPassword = password
        currentKeyfilePath = keyfilePath
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
        biometricManager.recordFullAuth(password: password)
        auditLogger.log(.unlock)
        checkExpiredEntries()
        computeEntryAlerts()
        statusBar?.refresh()
    }

    func unlockWithBiometrics() async throws {
        let password = try await biometricManager.unlock()
        try await unlockAsync(password: password, keyfilePath: currentKeyfilePath)
    }

    func createVault(password: Data, keyfilePath: String? = nil) throws {
        try engine.create(password: password, keyfilePath: keyfilePath)
        // Apply the user's saved KDF preset (default: maximum/1GB) to newly created vaults
        let preset = KdfPreset.saved
        try engine.setKdfParams(memory: preset.memory, iterations: preset.iterations, parallelism: preset.parallelism)
        try VaultPersistence.atomicSave(engine: engine, vaultPath: vaultPath, password: password, keyfilePath: keyfilePath)
        currentPassword = password
        currentKeyfilePath = keyfilePath
        entries = try engine.listEntries()
        isLocked = false
        errorMessage = nil
        autoLockManager?.start()
        auditLogger.log(.createVault)
        vaultRegistry.register(name: activeVaultName, path: vaultPath)
        refreshBiometricState()
        statusBar?.refresh()
    }

    func createVaultAsync(password: Data, keyfilePath: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }
        let eng = engine
        let path = vaultPath
        let preset = KdfPreset.saved
        try await Task.detached {
            try eng.create(password: password, keyfilePath: keyfilePath)
            // Apply the user's saved KDF preset (default: maximum/1GB) to newly created vaults
            try eng.setKdfParams(memory: preset.memory, iterations: preset.iterations, parallelism: preset.parallelism)
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
        refreshBiometricState()
        statusBar?.refresh()
    }

    func lockVault() {
        autoLockManager?.stop()
        engine.close()
        releaseVaultLock()
        clipboard.forceClear()
        if currentPassword != nil {
            currentPassword!.resetBytes(in: 0..<currentPassword!.count)
        }
        currentPassword = nil
        currentKeyfilePath = nil
        entries = []
        recycledEntries = []
        entryAlerts = [:]
        selectedEntryID = nil
        errorMessage = nil
        expiredEntriesMessage = nil
        isLoading = false
        isLocked = true
        cleanupTempFiles()
        auditLogger.log(.lock)
        statusBar?.refresh()
    }

    // MARK: - Temp file cleanup

    /// Remove temporary files (attachments, emergency vault extractions) on lock.
    /// Matches any directory starting with the smaug-attachments or smaug-emergency prefix.
    private func cleanupTempFiles() {
        let fm = FileManager.default
        let tmpBase = fm.temporaryDirectory
        let prefixes = ["smaug-attachments", "smaug-emergency"]
        guard let contents = try? fm.contentsOfDirectory(atPath: tmpBase.path) else { return }
        for item in contents {
            if prefixes.contains(where: { item.hasPrefix($0) }) {
                let path = tmpBase.appendingPathComponent(item)
                try? fm.removeItem(at: path)
            }
        }
    }

    // MARK: - Brute-force throttling

    private var unlockFailuresPath: String {
        (vaultDirectory as NSString).appendingPathComponent(".unlock-failures")
    }

    private func readFailureCount() -> Int {
        guard let data = FileManager.default.contents(atPath: unlockFailuresPath),
              let str = String(data: data, encoding: .utf8),
              let count = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return count
    }

    private func recordFailedUnlock() {
        let count = readFailureCount() + 1
        try? "\(count)".write(toFile: unlockFailuresPath, atomically: true, encoding: .utf8)
        auditLogger.log(.unlock, detail: "FAILED attempt \(count)")
    }

    private func resetFailedUnlocks() {
        try? FileManager.default.removeItem(atPath: unlockFailuresPath)
    }

    private func unlockThrottleDelay() -> TimeInterval {
        let count = readFailureCount()
        if count >= 20 { return 300 }  // 5 minutes
        if count >= 10 { return 30 }
        if count >= 5 { return 5 }
        if count >= 3 { return 1 }
        return 0
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
        recycledEntries = (try? engine.listRecycledEntries()) ?? []
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
        do {
            try save()
        } catch {
            // Save failed — reopen vault from disk to restore pre-empty state
            if let pw = currentPassword {
                engine.close()
                try? engine.open(path: vaultPath, password: pw, keyfilePath: currentKeyfilePath)
                try? refreshEntries()
            }
            throw VaultError.internalError("Empty recycle bin failed to save. Changes reverted.")
        }
        auditLogger.log(.emptyRecycleBin)
        return count
    }

    // MARK: - Re-authentication

    /// Verify the given password matches the current master password.
    func verifyPassword(_ password: Data) -> Bool {
        guard let current = currentPassword else { return false }
        return password == current
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
            var restoreFailed = false
            do {
                // Atomic restore: POSIX rename() replaces destination without a gap
                let rc = Darwin.rename(backupURL.path, vaultPath)
                guard rc == 0 else { throw VaultError.writeFailed }
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
        // Validate the copied file is a real KDBX
        do {
            try VaultEngine.validate(path: vaultPath, password: Data())
        } catch VaultError.wrongPassword {
            // Valid KDBX — wrong password just means it's a real vault file
        } catch {
            // Not a valid KDBX — remove and throw
            try? fm.removeItem(atPath: vaultPath)
            throw VaultError.fileCorrupted
        }
    }

    // MARK: - Backup

    /// Create a full encrypted backup bundle of all known vaults.
    func createFullBackup(backupPassword: String, destination: URL) throws {
        let vaults = vaultRegistry.vaults.map {
            (name: $0.name, path: $0.path, keyfilePath: nil as String?)
        }
        try VaultBackupBundle.createBackup(vaults: vaults, backupPassword: backupPassword, destination: destination)
    }

    /// Verify a backup bundle.
    func verifyBackup(at url: URL, backupPassword: String) throws -> VaultBackupBundle.RestoreResult {
        try VaultBackupBundle.verify(at: url, backupPassword: backupPassword)
    }

    /// Restore from a backup bundle.
    func restoreFromBackup(at url: URL, backupPassword: String) throws -> VaultBackupBundle.RestoreResult {
        let result = try VaultBackupBundle.restore(from: url, backupPassword: backupPassword, toDirectory: vaultDirectory)
        // Register restored vaults
        for vault in result.manifest.vaults {
            let path = (vaultDirectory as NSString).appendingPathComponent(vault.filename)
            vaultRegistry.register(name: vault.name, path: path)
        }
        return result
    }

    // MARK: - File locking

    /// Acquire an advisory lock on the vault file to prevent concurrent access.
    private func acquireVaultLock() throws {
        releaseVaultLock() // Release any stale lock from a previous failed attempt
        let fd = open(vaultPath, O_RDONLY)
        guard fd >= 0 else { return } // File may not exist yet (create flow)
        let rc = flock(fd, LOCK_EX | LOCK_NB)
        if rc != 0 {
            close(fd)
            throw VaultError.internalError("This vault is already open in another instance.")
        }
        vaultLockFD = fd
    }

    /// Release the advisory lock on the vault file.
    private func releaseVaultLock() {
        guard vaultLockFD >= 0 else { return }
        flock(vaultLockFD, LOCK_UN)
        close(vaultLockFD)
        vaultLockFD = -1
    }
}
