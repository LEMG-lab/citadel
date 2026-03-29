import Foundation

/// KDF strength presets for Argon2id.
public enum KdfPreset: String, CaseIterable, Identifiable {
    case standard
    case high
    case maximum

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .standard: "Standard (256 MB)"
        case .high: "High (512 MB)"
        case .maximum: "Maximum (1 GB)"
        }
    }

    /// Memory cost in bytes.
    public var memory: UInt64 {
        switch self {
        case .standard: 256 * 1024 * 1024
        case .high: 512 * 1024 * 1024
        case .maximum: 1024 * 1024 * 1024
        }
    }

    /// Argon2id iterations.
    public var iterations: UInt64 {
        switch self {
        case .standard: 3
        case .high: 5
        case .maximum: 10
        }
    }

    /// Parallelism (thread count).
    public var parallelism: UInt32 { 4 }

    /// UserDefaults key.
    private static let defaultsKey = "citadel.kdfPreset"

    /// Load saved preset (defaults to .standard).
    public static var saved: KdfPreset {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? "standard"
        return KdfPreset(rawValue: raw) ?? .standard
    }

    /// Persist the selected preset.
    public func save() {
        UserDefaults.standard.set(rawValue, forKey: KdfPreset.defaultsKey)
    }
}
