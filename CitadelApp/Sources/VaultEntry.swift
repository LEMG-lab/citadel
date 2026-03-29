import Foundation

/// Summary of an entry (no password).
public struct VaultEntrySummary: Identifiable, Sendable {
    public let id: String   // UUID string
    public let title: String
    public let username: String
    public let url: String
    public let group: String
    public let entryType: String
    /// Expiry date, or nil if no expiry is set.
    public let expiryDate: Date?
    /// Last modification date, or nil if unknown.
    public let lastModified: Date?
    public let isFavorite: Bool
}

/// A custom field on an entry.
public struct CustomField: Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let value: String
    public let isProtected: Bool
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
    public let otpURI: String
    public let entryType: String
    public let customFields: [CustomField]
    /// Expiry date, or nil if no expiry is set.
    public let expiryDate: Date?
    /// Last modification date, or nil if unknown.
    public let lastModified: Date?
    public let isFavorite: Bool
}
