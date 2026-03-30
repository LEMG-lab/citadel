import Foundation
import LocalAuthentication
import Security
import CryptoKit
import os

/// Manages Touch ID enrollment and biometric-protected vault unlock via macOS Keychain.
///
/// Architecture (Keychain + Secure Enclave):
/// 1. User enables Touch ID -> biometric check via LAContext -> master password stored
///    in Keychain with SecAccessControl(.biometryCurrentSet) protection
/// 2. Subsequent unlocks -> Keychain query with LAContext triggers Touch ID automatically
///    -> password returned only after biometric auth succeeds
/// 3. 72-hour full re-auth enforced via timestamp prepended to the stored password data
///
/// Per-vault biometrics: each vault gets its own Keychain item keyed by SHA256(vault_path).
///
/// Security model:
/// - Secure Enclave gates all access — no process can read the item without biometric auth
/// - .biometryCurrentSet invalidates the item if fingerprints are added or removed
/// - kSecAttrAccessibleWhenUnlockedThisDeviceOnly prevents backup/sync of the item
/// - No files, no wrapping keys, no nonces — the Keychain IS the secure storage
/// - This is the same approach used by 1Password and other professional password managers
@MainActor
public final class BiometricManager {

    // MARK: - Constants

    private nonisolated static let fullAuthMaxAge: TimeInterval = 72 * 60 * 60 // 72 hours
    private nonisolated static let keychainService = "com.lemg-lab.smaug.biometric"

    private static let logger = Logger(subsystem: "com.lemg-lab.smaug", category: "biometric")

    // MARK: - Per-vault Keychain account

    private let directory: String
    private var keychainAccount: String

    public init(directory: String, vaultPath: String = "") {
        self.directory = directory
        self.keychainAccount = Self.accountName(for: vaultPath)
    }

    /// Update the Keychain account when switching vaults.
    public func configure(forVaultPath vaultPath: String) {
        keychainAccount = Self.accountName(for: vaultPath)
    }

    /// Derive a stable Keychain account name from a vault path.
    private nonisolated static func accountName(for vaultPath: String) -> String {
        guard !vaultPath.isEmpty else { return "default" }
        let hash = SHA256.hash(data: Data(vaultPath.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Public state

    /// Whether Touch ID is currently enrolled (Keychain item exists for this vault).
    public var isEnabled: Bool {
        // Query with interactionNotAllowed — just check existence, don't trigger Touch ID
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: false,
            kSecUseAuthenticationContext as String: context,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed means the item exists but needs auth
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Whether the device supports biometrics.
    public var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        if !available {
            Self.logger.debug("Biometrics not available: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        }
        return available
    }

    // MARK: - Enrollment

    /// Enroll Touch ID: verify biometrics, then store the master password in Keychain.
    /// Call this after the user has already authenticated with their master password.
    public func enroll(password: Data) async throws {
        // 1. Verify biometric availability
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            Self.logger.error("Biometric not available for enrollment: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            throw BiometricError.notAvailable
        }

        // 2. Evaluate biometrics (Touch ID prompt)
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Enable Touch ID for Smaug"
            )
            guard success else {
                throw BiometricError.authFailed
            }
        } catch let authError where !(authError is BiometricError) {
            throw authError
        }

        // 3. Create access control: biometry required, current biometric set, this device only
        var acError: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &acError
        ) else {
            Self.logger.error("Failed to create access control: \(acError?.takeRetainedValue().localizedDescription ?? "unknown")")
            throw BiometricError.storageError
        }

        // 4. Build the stored data: [8 bytes: timestamp] + [N bytes: password]
        let blob = Self.buildBlob(password: password, timestamp: Date().timeIntervalSince1970)

        // 5. Remove any existing enrollment first
        unenroll()

        // 6. Store in Keychain with biometric protection
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: blob,
            kSecAttrAccessControl as String: accessControl,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            Self.logger.error("Keychain add failed: \(status)")
            throw BiometricError.storageError
        }

        // 7. Clean up old file-based biometric data (migration)
        cleanupOldBioFiles()

        Self.logger.info("Touch ID enrolled successfully (Keychain, isEnabled=\(self.isEnabled))")
    }

    // MARK: - Unlock

    /// Attempt biometric unlock. Returns the decrypted master password on success.
    /// The Keychain query triggers Touch ID automatically via LAContext.
    public func unlock() async throws -> Data {
        guard isEnabled else {
            throw BiometricError.notEnrolled
        }

        // LAContext for the Keychain query — this triggers Touch ID
        let context = LAContext()
        context.localizedReason = "Unlock Smaug"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let blob = result as? Data else {
            if status == errSecUserCanceled || status == errSecAuthFailed {
                throw BiometricError.authFailed
            }
            if status == errSecItemNotFound {
                throw BiometricError.notEnrolled
            }
            Self.logger.error("Keychain query failed: \(status)")
            throw BiometricError.authFailed
        }

        // Parse timestamp and password from blob
        let (password, timestamp) = Self.parseBlob(blob)

        // Check 72-hour expiry
        if Self.isFullAuthRequired(lastAuthTimestamp: timestamp, now: Date().timeIntervalSince1970) {
            // Expired — remove the Keychain item and require full password
            unenroll()
            throw BiometricError.fullAuthRequired
        }

        return password
    }

    // MARK: - Unenroll

    /// Remove biometric enrollment (delete the Keychain item for this vault).
    public func unenroll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        Self.logger.info("Touch ID unenrolled (isEnabled=\(self.isEnabled))")
    }

    // MARK: - Full auth tracking

    /// Record that the user entered their full master password.
    /// Re-stores the Keychain item with a fresh timestamp if enrolled.
    public func recordFullAuth(password: Data? = nil) {
        guard isEnabled, let pw = password else { return }

        // Build new blob with fresh timestamp
        let blob = Self.buildBlob(password: pw, timestamp: Date().timeIntervalSince1970)

        // Update the existing Keychain item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: blob,
        ]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess {
            Self.logger.debug("Keychain update for timestamp refresh failed: \(status)")
        }
    }

    /// Check if full auth is required based on a given timestamp. Testable.
    public nonisolated static func isFullAuthRequired(lastAuthTimestamp: TimeInterval, now: TimeInterval) -> Bool {
        guard lastAuthTimestamp > 0 else { return true }
        return now - lastAuthTimestamp > fullAuthMaxAge
    }

    // MARK: - Blob format

    /// Build stored blob: [8 bytes: timestamp (Double LE)] + [N bytes: password]
    nonisolated static func buildBlob(password: Data, timestamp: TimeInterval) -> Data {
        var blob = Data(count: 8)
        var ts = timestamp
        blob.replaceSubrange(0..<8, with: Data(bytes: &ts, count: 8))
        blob.append(password)
        return blob
    }

    /// Parse stored blob into (password, timestamp).
    nonisolated static func parseBlob(_ blob: Data) -> (password: Data, timestamp: TimeInterval) {
        guard blob.count > 8 else { return (Data(), 0) }
        let tsData = blob.prefix(8)
        let timestamp: TimeInterval = tsData.withUnsafeBytes { $0.load(as: TimeInterval.self) }
        let password = blob.dropFirst(8)
        return (Data(password), timestamp)
    }

    // MARK: - Migration cleanup

    /// Remove old file-based biometric data (.bio-nonce-*, .bio-blob-*).
    private func cleanupOldBioFiles() {
        Self.cleanupOldBioFiles(inDirectory: directory)
    }

    /// Static version for use from AppState.init().
    public nonisolated static func cleanupOldBioFiles(inDirectory directory: String) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for item in contents where item.hasPrefix(".bio-nonce") || item.hasPrefix(".bio-blob") {
            let path = (directory as NSString).appendingPathComponent(item)
            try? fm.removeItem(atPath: path)
        }
    }
}

public enum BiometricError: Error {
    case notAvailable
    case authFailed
    case storageError
    case notEnrolled
    case fullAuthRequired
}
