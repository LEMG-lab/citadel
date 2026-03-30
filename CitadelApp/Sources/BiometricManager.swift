import Foundation
import LocalAuthentication
import Security
import CryptoKit
import os

/// Manages Touch ID enrollment and biometric-protected vault unlock.
///
/// Architecture (file-based — avoids Keychain entitlement issues with ad-hoc signing):
/// 1. User enables Touch ID → biometric check via LAContext → random nonce generated →
///    wrapping key derived as SHA-256(nonce + hardware UUID) → master password encrypted
///    with ChaChaPoly → nonce + encrypted blob written to files with 0600 permissions
/// 2. Subsequent unlocks → Touch ID via LAContext → read nonce from file →
///    re-derive wrapping key → ChaChaPoly decrypt → extract password + timestamp → open vault
/// 3. 72-hour full re-auth enforced via timestamp embedded in encrypted blob
///
/// Per-vault biometrics: each vault gets its own .bio-nonce-<hash> and .bio-blob-<hash>
/// files, where <hash> is the first 8 characters of SHA256(vault_path). This allows
/// independent Touch ID enrollment per vault.
///
/// Security model:
/// - LAContext biometric check is enforced at the OS level
/// - Wrapping key is never stored — it's derived from the nonce file + hardware UUID
/// - Hardware UUID binding prevents using copied bio files on a different machine
/// - ChaChaPoly authenticated encryption protects password + timestamp integrity
/// - 72-hour timestamp is inside the encrypted blob (cannot be tampered with)
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

    public init(directory: String, vaultPath: String = "") {
        self.directory = directory
        let suffix = Self.vaultSuffix(for: vaultPath)
        noncePath = (directory as NSString).appendingPathComponent(".bio-nonce\(suffix)")
        encryptedBlobPath = (directory as NSString).appendingPathComponent(".bio-blob\(suffix)")
    }

    /// Update paths when switching vaults.
    public func configure(forVaultPath vaultPath: String) {
        let suffix = Self.vaultSuffix(for: vaultPath)
        noncePath = (directory as NSString).appendingPathComponent(".bio-nonce\(suffix)")
        encryptedBlobPath = (directory as NSString).appendingPathComponent(".bio-blob\(suffix)")
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

    // MARK: - Enrollment

    /// Enroll Touch ID: verify biometrics, then store the encrypted master password.
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

        // 3. Generate random nonce (32 bytes)
        var nonce = Data(count: 32)
        let status = nonce.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        guard status == errSecSuccess else {
            Self.logger.error("SecRandomCopyBytes failed: \(status)")
            throw BiometricError.storageError
        }

        // 4. Derive wrapping key and encrypt password + timestamp
        let wrappingKey = Self.deriveWrappingKey(nonce: nonce)
        let blob = Self.buildBlob(password: password, timestamp: Date().timeIntervalSince1970)
        let encryptedBlob = try Self.chachaEncrypt(data: blob, key: wrappingKey)

        // 5. Remove old enrollment files
        unenroll()

        // 6. Write nonce file (permissions 0600)
        let fm = FileManager.default
        guard fm.createFile(atPath: noncePath, contents: nonce, attributes: [.posixPermissions: 0o600]) else {
            Self.logger.error("Failed to write nonce file at \(self.noncePath, privacy: .public)")
            throw BiometricError.storageError
        }

        // 7. Write encrypted blob (permissions 0600)
        guard fm.createFile(atPath: encryptedBlobPath, contents: encryptedBlob, attributes: [.posixPermissions: 0o600]) else {
            Self.logger.error("Failed to write blob file at \(self.encryptedBlobPath, privacy: .public)")
            try? fm.removeItem(atPath: noncePath)
            throw BiometricError.storageError
        }

        Self.logger.info("Touch ID enrolled successfully (file-based, isEnabled=\(self.isEnabled))")
    }

    // MARK: - Unlock

    /// Attempt biometric unlock. Returns the decrypted master password on success.
    /// Checks 72-hour expiry from the timestamp embedded in the encrypted blob.
    public func unlock() async throws -> Data {
        guard isEnabled else {
            throw BiometricError.notEnrolled
        }

        // 1. Authenticate with Touch ID
        let context = LAContext()
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Smaug"
            )
            guard success else {
                throw BiometricError.authFailed
            }
        } catch let authError where !(authError is BiometricError) {
            throw authError
        }

        // 2. Read nonce from file
        let fm = FileManager.default
        guard let nonce = fm.contents(atPath: noncePath), nonce.count == 32 else {
            Self.logger.error("Nonce file missing or invalid — unenrolling")
            unenroll()
            throw BiometricError.notEnrolled
        }

        // 3. Read encrypted blob from file
        guard let encryptedBlob = fm.contents(atPath: encryptedBlobPath), !encryptedBlob.isEmpty else {
            Self.logger.error("Blob file missing or invalid — unenrolling")
            unenroll()
            throw BiometricError.notEnrolled
        }

        // 4. Derive wrapping key and decrypt
        let wrappingKey = Self.deriveWrappingKey(nonce: nonce)
        let blob: Data
        do {
            blob = try Self.chachaDecrypt(data: encryptedBlob, key: wrappingKey)
        } catch {
            Self.logger.error("Failed to decrypt bio blob — unenrolling")
            unenroll()
            throw BiometricError.notEnrolled
        }

        // 5. Extract timestamp and password from blob
        let (password, timestamp) = Self.parseBlob(blob)

        // 6. Check 72-hour expiry
        if Self.isFullAuthRequired(lastAuthTimestamp: timestamp, now: Date().timeIntervalSince1970) {
            throw BiometricError.fullAuthRequired
        }

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
    /// Re-encrypts the bio blob with the current timestamp if enrolled.
    public func recordFullAuth(password: Data? = nil) {
        guard isEnabled, let pw = password else { return }
        let fm = FileManager.default
        guard let nonce = fm.contents(atPath: noncePath), nonce.count == 32 else { return }
        let wrappingKey = Self.deriveWrappingKey(nonce: nonce)
        let blob = Self.buildBlob(password: pw, timestamp: Date().timeIntervalSince1970)
        guard let encrypted = try? Self.chachaEncrypt(data: blob, key: wrappingKey) else { return }
        fm.createFile(atPath: encryptedBlobPath, contents: encrypted, attributes: [.posixPermissions: 0o600])
    }

    /// Check if full auth is required based on a given timestamp. Testable.
    public nonisolated static func isFullAuthRequired(lastAuthTimestamp: TimeInterval, now: TimeInterval) -> Bool {
        guard lastAuthTimestamp > 0 else { return true }
        return now - lastAuthTimestamp > fullAuthMaxAge
    }

    // MARK: - Blob format

    /// Build plaintext blob: [8 bytes: timestamp (Double LE)] + [N bytes: password]
    private nonisolated static func buildBlob(password: Data, timestamp: TimeInterval) -> Data {
        var blob = Data(count: 8)
        var ts = timestamp
        blob.replaceSubrange(0..<8, with: Data(bytes: &ts, count: 8))
        blob.append(password)
        return blob
    }

    /// Parse plaintext blob into (password, timestamp).
    private nonisolated static func parseBlob(_ blob: Data) -> (password: Data, timestamp: TimeInterval) {
        guard blob.count > 8 else { return (Data(), 0) }
        let tsData = blob.prefix(8)
        let timestamp: TimeInterval = tsData.withUnsafeBytes { $0.load(as: TimeInterval.self) }
        let password = blob.dropFirst(8)
        return (Data(password), timestamp)
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

    // MARK: - Encryption (ChaChaPoly)

    /// Encrypt data using ChaChaPoly with a 32-byte wrapping key.
    private nonisolated static func chachaEncrypt(data: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealed = try ChaChaPoly.seal(data, using: symmetricKey)
        return sealed.combined
    }

    /// Decrypt ChaChaPoly-encrypted data with a 32-byte wrapping key.
    private nonisolated static func chachaDecrypt(data: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try ChaChaPoly.SealedBox(combined: data)
        return try ChaChaPoly.open(sealedBox, using: symmetricKey)
    }
}

public enum BiometricError: Error {
    case notAvailable
    case authFailed
    case storageError
    case notEnrolled
    case fullAuthRequired
}
