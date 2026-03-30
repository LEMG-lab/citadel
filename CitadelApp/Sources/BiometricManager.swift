import Foundation
import LocalAuthentication
import Security
import CryptoKit
import os

/// Manages Touch ID enrollment and biometric-protected vault unlock.
///
/// Architecture (file-based — avoids Keychain entitlement issues with ad-hoc signing):
/// 1. User enables Touch ID → biometric check via LAContext → random nonce generated →
///    wrapping key derived as SHA-256(nonce + hardware UUID) → master password XOR-encrypted →
///    nonce + encrypted blob written to files with 0600 permissions
/// 2. Subsequent unlocks → Touch ID via LAContext → read nonce from file →
///    re-derive wrapping key → decrypt password → open vault
/// 3. 72-hour full re-auth enforced via UserDefaults timestamp
///
/// Per-vault biometrics: each vault gets its own .bio-nonce-<hash> and .bio-blob-<hash>
/// files, where <hash> is the first 8 characters of SHA256(vault_path). This allows
/// independent Touch ID enrollment per vault.
///
/// Security model:
/// - LAContext biometric check is enforced at the OS level
/// - Wrapping key is never stored — it's derived from the nonce file + hardware UUID
/// - Hardware UUID binding prevents using copied bio files on a different machine
/// - File permissions (0600) prevent access by other users
@MainActor
public final class BiometricManager {

    // MARK: - Constants

    private nonisolated static let fullAuthMaxAge: TimeInterval = 72 * 60 * 60 // 72 hours

    private static let logger = Logger(subsystem: "com.lemg-lab.smaug", category: "biometric")

    // MARK: - File paths

    private let directory: String
    private var noncePath: String
    private var encryptedBlobPath: String

    /// The last-full-auth UserDefaults key, unique per vault.
    private var lastFullAuthKey: String

    public init(directory: String, vaultPath: String = "") {
        self.directory = directory
        let suffix = Self.vaultSuffix(for: vaultPath)
        noncePath = (directory as NSString).appendingPathComponent(".bio-nonce\(suffix)")
        encryptedBlobPath = (directory as NSString).appendingPathComponent(".bio-blob\(suffix)")
        lastFullAuthKey = "smaug.lastFullAuthTimestamp\(suffix)"
    }

    /// Update paths when switching vaults.
    public func configure(forVaultPath vaultPath: String) {
        let suffix = Self.vaultSuffix(for: vaultPath)
        noncePath = (directory as NSString).appendingPathComponent(".bio-nonce\(suffix)")
        encryptedBlobPath = (directory as NSString).appendingPathComponent(".bio-blob\(suffix)")
        lastFullAuthKey = "smaug.lastFullAuthTimestamp\(suffix)"
    }

    /// Derive a short hash suffix from a vault path for per-vault file naming.
    private nonisolated static func vaultSuffix(for vaultPath: String) -> String {
        guard !vaultPath.isEmpty else { return "" }
        let hash = SHA256.hash(data: Data(vaultPath.utf8))
        let prefix = hash.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "-\(prefix)"
    }

    // MARK: - Public state

    /// Whether Touch ID is currently enrolled (bio files exist on disk).
    public var isEnabled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: noncePath) && fm.fileExists(atPath: encryptedBlobPath)
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

    /// Whether a full master password re-entry is required (72h expiry).
    public var requiresFullAuth: Bool {
        let lastAuth = UserDefaults.standard.double(forKey: lastFullAuthKey)
        guard lastAuth > 0 else { return true }
        return Date().timeIntervalSince1970 - lastAuth > Self.fullAuthMaxAge
    }

    // MARK: - Enrollment

    /// Enroll Touch ID: verify biometrics, then store the encrypted master password.
    /// Call this after the user has already authenticated with their master password.
    public func enroll(password: Data) async throws {
        print("BIO: Starting enrollment")

        // 1. Verify biometric availability
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            print("BIO ERROR: Biometric not available: \(error?.localizedDescription ?? "unknown")")
            Self.logger.error("Biometric not available for enrollment: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            throw BiometricError.notAvailable
        }

        // 2. Evaluate biometrics (Touch ID prompt)
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Enable Touch ID for Smaug"
            )
            print("BIO: LAContext auth result: \(success), error: nil")
            guard success else {
                print("BIO ERROR: Auth returned false")
                throw BiometricError.authFailed
            }
        } catch let authError where !(authError is BiometricError) {
            print("BIO ERROR: LAContext auth threw: \(authError)")
            throw authError
        }

        // 3. Generate random nonce (32 bytes)
        var nonce = Data(count: 32)
        let status = nonce.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        guard status == errSecSuccess else {
            print("BIO ERROR: SecRandomCopyBytes failed: \(status)")
            Self.logger.error("SecRandomCopyBytes failed: \(status)")
            throw BiometricError.storageError
        }
        print("BIO: Nonce generated: \(nonce.count) bytes")

        // 4. Derive wrapping key: SHA-256(nonce + device ID)
        let wrappingKey = Self.deriveWrappingKey(nonce: nonce)
        print("BIO: Key derived: \(wrappingKey.count) bytes")

        // 5. Encrypt password with wrapping key
        let encryptedBlob = Self.xorEncrypt(data: password, key: wrappingKey)
        print("BIO: Encrypted blob: \(encryptedBlob.count) bytes")

        // 6. Remove old enrollment files
        unenroll()

        // 7. Write nonce file (permissions 0600)
        let fm = FileManager.default
        print("BIO: Writing nonce to \(noncePath)")
        guard fm.createFile(atPath: noncePath, contents: nonce, attributes: [.posixPermissions: 0o600]) else {
            print("BIO ERROR: Failed to write nonce file")
            Self.logger.error("Failed to write nonce file at \(self.noncePath, privacy: .public)")
            throw BiometricError.storageError
        }

        // 8. Write encrypted blob (permissions 0600)
        print("BIO: Writing blob to \(encryptedBlobPath)")
        guard fm.createFile(atPath: encryptedBlobPath, contents: encryptedBlob, attributes: [.posixPermissions: 0o600]) else {
            print("BIO ERROR: Failed to write blob file")
            Self.logger.error("Failed to write blob file at \(self.encryptedBlobPath, privacy: .public)")
            try? fm.removeItem(atPath: noncePath)
            throw BiometricError.storageError
        }

        print("BIO: Write success: nonce=\(fm.fileExists(atPath: noncePath)), blob=\(fm.fileExists(atPath: encryptedBlobPath))")

        recordFullAuth()
        Self.logger.info("Touch ID enrolled successfully (file-based, isEnabled=\(self.isEnabled))")
        print("BIO: Enrollment complete (isEnabled=\(isEnabled))")
    }

    // MARK: - Unlock

    /// Attempt biometric unlock. Returns the decrypted master password on success.
    public func unlock() async throws -> Data {
        print("BIO: Starting unlock (isEnabled=\(isEnabled), requiresFullAuth=\(requiresFullAuth))")
        guard isEnabled else {
            print("BIO ERROR: Not enrolled")
            throw BiometricError.notEnrolled
        }
        guard !requiresFullAuth else {
            print("BIO ERROR: Full auth required (72h expired)")
            throw BiometricError.fullAuthRequired
        }

        // 1. Authenticate with Touch ID
        let context = LAContext()
        print("BIO: Requesting Touch ID authentication")
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Smaug"
            )
            print("BIO: LAContext auth result: \(success), error: nil")
            guard success else {
                print("BIO ERROR: Auth returned false")
                throw BiometricError.authFailed
            }
        } catch let authError where !(authError is BiometricError) {
            print("BIO ERROR: LAContext auth threw: \(authError)")
            throw authError
        }

        // 2. Read nonce from file
        let fm = FileManager.default
        print("BIO: Reading nonce from \(noncePath)")
        guard let nonce = fm.contents(atPath: noncePath), nonce.count == 32 else {
            print("BIO ERROR: Nonce file missing or invalid — unenrolling")
            Self.logger.error("Nonce file missing or invalid — unenrolling")
            unenroll()
            throw BiometricError.notEnrolled
        }
        print("BIO: Nonce read: \(nonce.count) bytes")

        // 3. Read encrypted blob from file
        print("BIO: Reading blob from \(encryptedBlobPath)")
        guard let encryptedBlob = fm.contents(atPath: encryptedBlobPath), !encryptedBlob.isEmpty else {
            print("BIO ERROR: Blob file missing or invalid — unenrolling")
            Self.logger.error("Blob file missing or invalid — unenrolling")
            unenroll()
            throw BiometricError.notEnrolled
        }
        print("BIO: Blob read: \(encryptedBlob.count) bytes")

        // 4. Derive wrapping key and decrypt
        let wrappingKey = Self.deriveWrappingKey(nonce: nonce)
        print("BIO: Key derived: \(wrappingKey.count) bytes")
        let password = Self.xorEncrypt(data: encryptedBlob, key: wrappingKey)
        print("BIO: Password decrypted: \(password.count) bytes")
        print("BIO: Unlock complete")
        return password
    }

    // MARK: - Unenroll

    /// Remove all biometric enrollment data.
    public func unenroll() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: noncePath)
        try? fm.removeItem(atPath: encryptedBlobPath)
        Self.logger.info("Touch ID unenrolled (isEnabled=\(self.isEnabled))")
    }

    // MARK: - Full auth tracking

    /// Record that the user entered their full master password.
    public func recordFullAuth() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastFullAuthKey)
    }

    /// Check if full auth is required based on a given timestamp. Testable.
    public nonisolated static func isFullAuthRequired(lastAuthTimestamp: TimeInterval, now: TimeInterval) -> Bool {
        guard lastAuthTimestamp > 0 else { return true }
        return now - lastAuthTimestamp > fullAuthMaxAge
    }

    // MARK: - Key derivation

    /// Derive a wrapping key from a random nonce and a device-specific identifier.
    /// SHA-256(nonce || device_id) — binds the key to this specific machine.
    nonisolated static func deriveWrappingKey(nonce: Data) -> Data {
        let deviceID = deviceIdentifier()
        var input = nonce
        input.append(Data(deviceID.utf8))
        let hash = SHA256.hash(data: input)
        return Data(hash)
    }

    /// Stable device identifier for key derivation.
    /// Uses the boot volume UUID which is unique per macOS installation.
    private nonisolated static func deviceIdentifier() -> String {
        let volumeURL = URL(fileURLWithPath: "/")
        if let values = try? volumeURL.resourceValues(forKeys: [.volumeUUIDStringKey]),
           let uuid = values.volumeUUIDString {
            return uuid
        }
        // Fallback: use a stable identifier from the system
        return ProcessInfo.processInfo.hostName + "-smaug"
    }

    // MARK: - Encryption

    /// XOR-based symmetric encryption. Security relies on the wrapping key being
    /// secret and derived from a random nonce + device identifier.
    nonisolated static func xorEncrypt(data: Data, key: Data) -> Data {
        guard !key.isEmpty else { return data }
        var result = Data(count: data.count)
        for i in 0..<data.count {
            result[i] = data[i] ^ key[i % key.count]
        }
        return result
    }
}

public enum BiometricError: Error {
    case notAvailable
    case authFailed
    case storageError
    case notEnrolled
    case fullAuthRequired
}
