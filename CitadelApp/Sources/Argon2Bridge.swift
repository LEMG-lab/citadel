import Foundation
import CryptoKit
import CCitadelCore

/// Swift bridge to the Rust Argon2id key derivation functions.
/// Used by EmergencyAccess and VaultBackupBundle for password-based encryption.
public enum Argon2Bridge {

    /// Derive a 32-byte symmetric key from a password and salt using Argon2id
    /// with high parameters (256 MB memory, 4 iterations, 4 parallelism).
    /// Used for emergency and backup file encryption.
    public static func deriveKey(from password: String, salt: Data) -> SymmetricKey? {
        let passwordData = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: 32)

        let result = passwordData.withUnsafeBufferPointer { pwBuf in
            salt.withUnsafeBytes { saltBuf in
                output.withUnsafeMutableBufferPointer { outBuf in
                    vault_derive_key_argon2_high(
                        pwBuf.baseAddress,
                        UInt32(pwBuf.count),
                        saltBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        UInt32(salt.count),
                        outBuf.baseAddress,
                        UInt32(outBuf.count)
                    )
                }
            }
        }

        guard result == VAULT_RESULT_OK else { return nil }
        return SymmetricKey(data: output)
    }

    /// Derive key with the old 64MB parameters (for reading old v2 files).
    public static func deriveKeyLow(from password: String, salt: Data) -> SymmetricKey? {
        let passwordData = Array(password.utf8)
        var output = [UInt8](repeating: 0, count: 32)

        let result = passwordData.withUnsafeBufferPointer { pwBuf in
            salt.withUnsafeBytes { saltBuf in
                output.withUnsafeMutableBufferPointer { outBuf in
                    vault_derive_key_argon2(
                        pwBuf.baseAddress,
                        UInt32(pwBuf.count),
                        saltBuf.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        UInt32(salt.count),
                        outBuf.baseAddress,
                        UInt32(outBuf.count)
                    )
                }
            }
        }

        guard result == VAULT_RESULT_OK else { return nil }
        return SymmetricKey(data: output)
    }

    /// Generate a random 32-byte salt.
    public static func randomSalt() -> Data {
        var salt = Data(count: 32)
        salt.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }
        return salt
    }
}
