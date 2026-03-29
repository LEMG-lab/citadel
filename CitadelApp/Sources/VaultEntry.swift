import Foundation

/// Summary of an entry (no password).
public struct VaultEntrySummary: Identifiable, Sendable {
    public let id: String   // UUID string
    public let title: String
    public let username: String
    public let url: String
}

/// Full entry data including password as raw bytes.
public struct VaultEntryDetail: Sendable {
    public let uuid: String
    public let title: String
    public let username: String
    /// Password as raw bytes — never convert to String.
    public let password: Data
    public let url: String
    public let notes: String
}
