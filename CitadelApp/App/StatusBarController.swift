import AppKit
import CitadelCore

/// Menu bar status item controller for quick access to vault entries.
///
/// Displays a shield icon in the macOS menu bar and provides:
/// - Quick password copy for favorite entries
/// - An "All Entries" submenu for the full vault
/// - Lock/unlock awareness with appropriate menu states
///
/// Call `refresh()` whenever the vault lock state or entry list changes.
@MainActor
final class StatusBarController: NSObject {

    private var statusItem: NSStatusItem?
    private weak var appState: AppState?

    /// Maximum number of entries shown directly in the top-level menu.
    private static let maxVisibleEntries = 20

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setupStatusItem()
    }

    func tearDown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Setup

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "lock.shield",
                accessibilityDescription: "Citadel"
            )
            button.image?.size = NSSize(width: 18, height: 18)
        }

        rebuildMenu()
    }

    /// Rebuild the menu to reflect the current vault state.
    /// Call this whenever entries change or the lock state changes.
    func refresh() {
        rebuildMenu()
    }

    // MARK: - Menu Construction

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        guard let appState else {
            statusItem?.menu = menu
            return
        }

        if appState.isLocked {
            buildLockedMenu(menu)
        } else {
            buildUnlockedMenu(menu, entries: appState.entries)
        }

        statusItem?.menu = menu
    }

    /// Build the menu shown when the vault is locked.
    private func buildLockedMenu(_ menu: NSMenu) {
        let header = NSMenuItem(title: "Citadel \u{2014} Locked", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())

        let openItem = NSMenuItem(
            title: "Open Citadel",
            action: #selector(openMainWindow),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
    }

    /// Build the menu shown when the vault is unlocked.
    private func buildUnlockedMenu(_ menu: NSMenu, entries: [VaultEntrySummary]) {
        let favorites = entries.filter(\.isFavorite)
        let nonFavorites = entries.filter { !$0.isFavorite }

        // Favorites section
        if !favorites.isEmpty {
            let favHeader = NSMenuItem(title: "Favorites", action: nil, keyEquivalent: "")
            favHeader.isEnabled = false
            menu.addItem(favHeader)

            for entry in favorites.prefix(Self.maxVisibleEntries) {
                menu.addItem(makeEntryMenuItem(entry))
            }

            menu.addItem(.separator())
        }

        // All Entries submenu
        if !nonFavorites.isEmpty {
            let allEntriesItem = NSMenuItem(title: "All Entries", action: nil, keyEquivalent: "")
            let submenu = NSMenu()

            for entry in nonFavorites.prefix(Self.maxVisibleEntries) {
                submenu.addItem(makeEntrySubmenuItem(entry))
            }

            if nonFavorites.count > Self.maxVisibleEntries {
                submenu.addItem(.separator())
                let moreItem = NSMenuItem(
                    title: "Open Citadel to see all\u{2026}",
                    action: #selector(openMainWindow),
                    keyEquivalent: ""
                )
                moreItem.target = self
                submenu.addItem(moreItem)
            }

            allEntriesItem.submenu = submenu
            menu.addItem(allEntriesItem)

            menu.addItem(.separator())
        } else if favorites.isEmpty {
            // No entries at all
            let emptyItem = NSMenuItem(title: "No Entries", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            menu.addItem(.separator())
        }

        // Vault switcher
        if let appState, appState.knownVaults.count > 1 {
            let switchItem = NSMenuItem(title: "Switch Vault", action: nil, keyEquivalent: "")
            let switchSubmenu = NSMenu()
            for vault in appState.knownVaults {
                let item = NSMenuItem(
                    title: vault.name,
                    action: #selector(switchToVault(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = vault
                if vault.path == appState.vaultPath {
                    item.state = .on
                }
                switchSubmenu.addItem(item)
            }
            switchItem.submenu = switchSubmenu
            menu.addItem(switchItem)
            menu.addItem(.separator())
        }

        // Lock Vault
        let lockItem = NSMenuItem(
            title: "Lock Vault",
            action: #selector(lockVault),
            keyEquivalent: ""
        )
        lockItem.target = self
        menu.addItem(lockItem)

        // Open Citadel
        let openItem = NSMenuItem(
            title: "Open Citadel",
            action: #selector(openMainWindow),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
    }

    // MARK: - Entry Menu Items

    /// Create a menu item for a favorite entry. Clicking copies the password directly.
    private func makeEntryMenuItem(_ entry: VaultEntrySummary) -> NSMenuItem {
        let item = NSMenuItem(
            title: entry.title.isEmpty ? "(Untitled)" : entry.title,
            action: #selector(copyPasswordForEntry(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = entry.id

        if !entry.username.isEmpty {
            item.subtitle = entry.username
        }

        return item
    }

    /// Create a menu item with a submenu containing "Copy Password" and "Copy Username".
    private func makeEntrySubmenuItem(_ entry: VaultEntrySummary) -> NSMenuItem {
        let item = NSMenuItem(
            title: entry.title.isEmpty ? "(Untitled)" : entry.title,
            action: nil,
            keyEquivalent: ""
        )

        if !entry.username.isEmpty {
            item.subtitle = entry.username
        }

        let submenu = NSMenu()

        let copyPassword = NSMenuItem(
            title: "Copy Password",
            action: #selector(copyPasswordForEntry(_:)),
            keyEquivalent: ""
        )
        copyPassword.target = self
        copyPassword.representedObject = entry.id
        submenu.addItem(copyPassword)

        if !entry.username.isEmpty {
            let copyUsername = NSMenuItem(
                title: "Copy Username",
                action: #selector(copyUsernameForEntry(_:)),
                keyEquivalent: ""
            )
            copyUsername.target = self
            copyUsername.representedObject = entry.username
            submenu.addItem(copyUsername)
        }

        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    @objc private func copyPasswordForEntry(_ sender: NSMenuItem) {
        guard let appState,
              let entryID = sender.representedObject as? String else { return }

        do {
            let detail = try appState.engine.getEntry(uuid: entryID)
            appState.clipboard.copyPassword(detail.password)
        } catch {
            // Silently fail — the entry may have been deleted since the menu was built
        }
    }

    @objc private func copyUsernameForEntry(_ sender: NSMenuItem) {
        guard let username = sender.representedObject as? String else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(username, forType: .string)
    }

    @objc private func switchToVault(_ sender: NSMenuItem) {
        guard let appState, let vault = sender.representedObject as? VaultInfo else { return }
        appState.switchVault(to: vault)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func lockVault() {
        appState?.lockVault()
    }

    @objc private func openMainWindow() {
        let app = NSApplication.shared
        app.activate(ignoringOtherApps: true)

        // Find an existing content window (skip menu bar panels, popovers, etc.)
        let contentWindow = app.windows.first(where: {
            $0.canBecomeMain || $0.title == "Citadel"
        })

        if let window = contentWindow {
            window.makeKeyAndOrderFront(nil)
            // If the window was miniaturized, deminiaturize it
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
        } else {
            // No window exists — re-open the app which triggers WindowGroup creation
            if let appURL = NSRunningApplication.current.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            }
        }
    }
}
