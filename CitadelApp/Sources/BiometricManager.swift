import Foundation
import LocalAuthentication
import Security

/// Manages Touch ID enrollment and biometric-protected vault unlock.
///
/// Architecture:
/// 1. User enables Touch ID → biometric check → random wrapping key stored in Keychain
///    with kSecAccessControlBiometryCurrentSet → master password encrypted with wrapping key
///    → encrypted blob stored in a second Keychain item
/// 2. Subsequent unlocks → Touch ID prompt → retrieve wrapping key (requires biometric) →
///    decrypt password blob → open vault
/// 3. 72-hour full re-auth enforced via UserDefaults timestamp
@MainActor
public final class BiometricManager {

    // MARK: - Constants

    private static let wrappingKeyService = "com.lemg-lab.citadel.biometric-key"
    private static let encryptedBlobService = "com.lemg-lab.citadel.biometric-blob"
    private static let keychainAccount = "citadel-touchid"
    private static let lastFullAuthKey = "citadel.lastFullAuthTimestamp"
    private static let touchIDEnabledKey = "citadel.touchIDEnabled"
    private nonisolated static let fullAuthMaxAge: TimeInterval = 72 * 60 * 60 // 72 hours

    public init() {}

    // MARK: - Public state

    /// Whether Touch ID is currently enrolled and available.
    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.touchIDEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.touchIDEnabledKey) }
    }

    /// Whether the device supports biometrics.
    public var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Whether a full master password re-entry is required (72h expiry).
    public var requiresFullAuth: Bool {
        let lastAuth = UserDefaults.standard.double(forKey: Self.lastFullAuthKey)
        guard lastAuth > 0 else { return true }
        return Date().timeIntervalSince1970 - lastAuth > Self.fullAuthMaxAge
    }

    // MARK: - Enrollment

    /// Enroll Touch ID: verify biometrics, then store the encrypted master password.
    /// Call this after the user has already authenticated with their master password.
    public func enroll(password: Data) async throws {
        // 1. Verify biometric availability
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw BiometricError.notAvailable
        }

        // 2. Evaluate biometrics
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Enable Touch ID for Citadel"
        )
        guard success else { throw BiometricError.authFailed }

        // 3. Generate random wrapping key (256-bit)
        var wrappingKey = Data(count: 32)
        let status = wrappingKey.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        guard status == errSecSuccess else { throw BiometricError.keychainError }

        // 4. Encrypt password with wrapping key (XOR — simple symmetric; the Keychain ACL
        //    protects the wrapping key, not the encryption scheme)
        let encryptedBlob = xorEncrypt(data: password, key: wrappingKey)

        // 5. Delete any existing items
        unenroll()

        // 6. Store wrapping key with biometric protection
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            nil
        )

        let wrappingQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.wrappingKeyService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: wrappingKey,
            kSecAttrAccessControl as String: access as Any,
        ]

        let addStatus = SecItemAdd(wrappingQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw BiometricError.keychainError }

        // 7. Store encrypted blob (no biometric protection needed — it's encrypted)
        let blobQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.encryptedBlobService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: encryptedBlob,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let blobStatus = SecItemAdd(blobQuery as CFDictionary, nil)
        guard blobStatus == errSecSuccess else {
            // Clean up wrapping key
            deleteKeychainItem(service: Self.wrappingKeyService)
            throw BiometricError.keychainError
        }

        isEnabled = true
        recordFullAuth()
    }

    // MARK: - Unlock

    /// Attempt biometric unlock. Returns the decrypted master password on success.
    public func unlock() async throws -> Data {
        guard isEnabled else { throw BiometricError.notEnrolled }
        guard !requiresFullAuth else { throw BiometricError.fullAuthRequired }

        // 1. Retrieve encrypted blob (no biometric needed)
        guard let encryptedBlob = retrieveKeychainData(service: Self.encryptedBlobService) else {
            throw BiometricError.notEnrolled
        }

        // 2. Retrieve wrapping key (triggers Touch ID)
        let context = LAContext()
        context.localizedReason = "Unlock Citadel"

        let wrappingQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.wrappingKeyService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(wrappingQuery as CFDictionary, &result)

        guard status == errSecSuccess, let wrappingKey = result as? Data else {
            if status == errSecUserCanceled || status == errSecAuthFailed {
                throw BiometricError.authFailed
            }
            throw BiometricError.keychainError
        }

        // 3. Decrypt
        let password = xorEncrypt(data: encryptedBlob, key: wrappingKey)
        return password
    }

    // MARK: - Unenroll

    /// Remove all biometric enrollment data.
    public func unenroll() {
        deleteKeychainItem(service: Self.wrappingKeyService)
        deleteKeychainItem(service: Self.encryptedBlobService)
        isEnabled = false
    }

    // MARK: - Full auth tracking

    /// Record that the user entered their full master password.
    public func recordFullAuth() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastFullAuthKey)
    }

    /// Check if full auth is required based on a given timestamp. Testable.
    public nonisolated static func isFullAuthRequired(lastAuthTimestamp: TimeInterval, now: TimeInterval) -> Bool {
        guard lastAuthTimestamp > 0 else { return true }
        return now - lastAuthTimestamp > fullAuthMaxAge
    }

    // MARK: - Internal

    private func xorEncrypt(data: Data, key: Data) -> Data {
        var result = Data(count: data.count)
        for i in 0..<data.count {
            result[i] = data[i] ^ key[i % key.count]
        }
        return result
    }

    private func deleteKeychainItem(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func retrieveKeychainData(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}

public enum BiometricError: Error {
    case notAvailable
    case authFailed
    case keychainError
    case notEnrolled
    case fullAuthRequired
}
