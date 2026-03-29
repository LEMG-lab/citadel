import Foundation

/// Manages known vault files via UserDefaults. Stores names and paths only — never passwords.
public struct VaultInfo: Codable, Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

@MainActor
public final class VaultRegistry {
    public init() {}
    private static let storageKey = "citadel.knownVaults"
    private static let activeKey = "citadel.activeVaultPath"

    /// All known vaults.
    public var vaults: [VaultInfo] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
                  let list = try? JSONDecoder().decode([VaultInfo].self, from: data) else {
                return []
            }
            return list
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }

    /// The path of the currently active vault.
    public var activeVaultPath: String? {
        get { UserDefaults.standard.string(forKey: Self.activeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.activeKey) }
    }

    /// Register a vault if not already known.
    public func register(name: String, path: String) {
        var list = vaults
        if !list.contains(where: { $0.path == path }) {
            list.append(VaultInfo(name: name, path: path))
            vaults = list
        }
        activeVaultPath = path
    }

    /// Remove a vault from the registry (does not delete the file).
    public func remove(path: String) {
        var list = vaults
        list.removeAll { $0.path == path }
        vaults = list
    }

    /// Rename a vault.
    public func rename(path: String, newName: String) {
        var list = vaults
        if let idx = list.firstIndex(where: { $0.path == path }) {
            list[idx] = VaultInfo(name: newName, path: path)
            vaults = list
        }
    }

    /// Ensure default vaults exist. Called once on first launch.
    public func ensureDefaults(directory: String) {
        if vaults.isEmpty {
            let personalPath = (directory as NSString).appendingPathComponent("personal.kdbx")
            let workPath = (directory as NSString).appendingPathComponent("work.kdbx")
            vaults = [
                VaultInfo(name: "Personal", path: personalPath),
                VaultInfo(name: "Work", path: workPath),
            ]
            // If old vault.kdbx exists, register it as "Personal" at that path
            let legacyPath = (directory as NSString).appendingPathComponent("vault.kdbx")
            if FileManager.default.fileExists(atPath: legacyPath) {
                vaults = [
                    VaultInfo(name: "Personal", path: legacyPath),
                    VaultInfo(name: "Work", path: workPath),
                ]
                activeVaultPath = legacyPath
            } else {
                activeVaultPath = personalPath
            }
        }
    }
}
