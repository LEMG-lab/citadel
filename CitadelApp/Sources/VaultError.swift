import Foundation

/// Errors thrown by VaultEngine, mapped from VaultResult FFI codes.
public enum VaultError: Error, Equatable {
    case wrongPassword
    case fileCorrupted
    case fileNotFound
    case writeFailed
    case validationFailed
    case emptyPassword
    case internalError(String)
}
