import SwiftUI
import UniformTypeIdentifiers
import CitadelCore

// MARK: - Sidebar Selection

enum SidebarItem: Hashable {
    case allItems
    case favorites
    // Per-type filters
    case logins
    case cryptoWallets
    case multiChainWallets
    case serverSSH
    case apiKeys
    case databases
    case emailAccounts
    case creditCards
    case identities
    case secureNotes
    case recoveryCodes
    case softwareLicenses
    // Organization
    case folder(String)
    case project(String)
    case tag(String)
    case trash
}

// MARK: - Main View

/// Main vault UI with three-column navigation: sidebar, entry list, and detail pane.
struct MainView: View {
    @Environment(AppState.self) private var appState

    // MARK: Sidebar state

    @State private var sidebarSelection: SidebarItem? = .allItems

    // MARK: Sheet state

    @State private var showingAddEntry = false
    @State private var showingSettings = false
    @State private var showingReceiveShare = false
    @State private var showingFullBackup = false
    @State private var showingPasswordHealth = false
    @State private var showingAuditLog = false
    @State private var showingGenerator = false
    @State private var showingAbout = false

    // MARK: Alert state

    @State private var backupResultMessage: String?
    @State private var showingBackupResult = false
    @State private var importResultMessage: String?
    @State private var showingImportResult = false
    @State private var showingExpiredAlert = false
    @State private var showingCSVExportWarning = false
    @State private var showingReAuthForCSV = false
    @State private var reAuthPassword = ""
    @State private var reAuthError: String?
    @State private var showingRestoreOverwriteWarning = false
    @State private var pendingRestoreURL: URL?
    @State private var pendingRestorePassword: String?
    @State private var showingNewProject = false
    @State private var newProjectName = ""

    // MARK: - Filtered entries

    private var filteredEntries: [VaultEntrySummary] {
        switch sidebarSelection {
        case .allItems, .none:
            return appState.entries
        case .favorites:
            return appState.entries.filter(\.isFavorite)
        case .logins:
            return appState.entries.filter { $0.entryType == "password" || $0.entryType.isEmpty }
        case .cryptoWallets:
            return appState.entries.filter { EntryTemplate.cryptoTypes.contains($0.entryType) }
        case .multiChainWallets:
            return appState.entries.filter { $0.entryType == "multi_chain_wallet" }
        case .serverSSH:
            return appState.entries.filter { $0.entryType == "server_ssh" }
        case .apiKeys:
            return appState.entries.filter { $0.entryType == "api_key" }
        case .databases:
            return appState.entries.filter { $0.entryType == "database" }
        case .emailAccounts:
            return appState.entries.filter { $0.entryType == "email_account" }
        case .creditCards:
            return appState.entries.filter { $0.entryType == "credit_card" }
        case .identities:
            return appState.entries.filter { $0.entryType == "identity" }
        case .secureNotes:
            return appState.entries.filter { $0.entryType == "secure_note" }
        case .recoveryCodes:
            return appState.entries.filter { $0.entryType == "recovery_codes" }
        case .softwareLicenses:
            return appState.entries.filter { $0.entryType == "software_license" }
        case .folder(let g):
            return appState.entries.filter { $0.group == g || $0.group.hasPrefix(g + "/") }
        case .project(let p):
            return appState.entries.filter { $0.group == p || $0.group.hasPrefix(p + "/") }
        case .tag(let t):
            return appState.entries.filter { $0.tagList.contains(t) }
        case .trash:
            return appState.recycledEntries
        }
    }

    private var folders: [String] {
        let groups = Set(appState.entries.map(\.group)).filter { !$0.isEmpty }
        return groups.sorted()
    }

    private var allTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in appState.entries {
            for tag in entry.tagList {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.key < $1.key }.map { (tag: $0.key, count: $0.value) }
    }

    /// Top-level groups treated as "projects".
    private var projects: [String] {
        var topLevel = Set<String>()
        // From entries
        for entry in appState.entries {
            let g = entry.group
            guard !g.isEmpty else { continue }
            if let first = g.split(separator: "/").first {
                topLevel.insert(String(first))
            }
        }
        // From vault group list (includes empty groups)
        if let allGroups = try? appState.engine.listGroups() {
            for g in allGroups {
                if let first = g.split(separator: "/").first {
                    topLevel.insert(String(first))
                }
            }
        }
        return topLevel.sorted()
    }

    // MARK: - Body

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            EntryListView(
                entries: filteredEntries,
                selectedEntryID: $appState.selectedEntryID
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            if sidebarSelection == .trash, let id = appState.selectedEntryID {
                TrashDetailView(entryID: id)
            } else if let id = appState.selectedEntryID {
                EntryDetailView(entryID: id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.citadelSecondary.opacity(0.4))
                    Text("No Entry Selected")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.citadelSecondary)
                    Text("Select an entry to view its details")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary.opacity(0.7))
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(appState.knownVaults) { vault in
                        Button {
                            appState.switchVault(to: vault)
                        } label: {
                            HStack {
                                Text(vault.name)
                                if vault.path == appState.vaultPath {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive")
                        Text(appState.activeVaultName)
                            .font(.system(size: 12))
                    }
                }
                .help("Switch vault")

                Button {
                    showingAddEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New entry")

                Menu {
                    Button("Export CSV\u{2026}") { showingCSVExportWarning = true }
                    Button("Import CSV\u{2026}") { importCSV() }
                    Divider()
                    Button("Receive Shared Entry\u{2026}") { showingReceiveShare = true }
                    Divider()
                    Button("Backup Vault\u{2026}") { performBackup() }
                    Button("Full Vault Backup\u{2026}") { showingFullBackup = true }
                    Button("Verify Backup\u{2026}") { verifyBackup() }
                    Button("Restore from Backup\u{2026}") { restoreBackup() }
                    Divider()
                    Button("About Smaug") { showingAbout = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("More actions")

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        // MARK: Sheets
        .sheet(isPresented: $showingAddEntry) {
            EntryEditView(mode: .add)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingReceiveShare) {
            ReceiveShareView()
        }
        .sheet(isPresented: $showingFullBackup) {
            FullBackupSheet()
        }
        .sheet(isPresented: $showingPasswordHealth) {
            PasswordHealthView()
        }
        .sheet(isPresented: $showingAuditLog) {
            AuditLogView()
        }
        .sheet(isPresented: $showingGenerator) {
            PasswordGeneratorView { _ in }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .alert("New Project", isPresented: $showingNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") { createProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a name for the new project. This creates a top-level group in your vault.")
        }
        // MARK: Alerts
        .alert("Backup", isPresented: $showingBackupResult) {
            Button("OK") {}
        } message: {
            Text(backupResultMessage ?? "")
        }
        .alert("CSV Import", isPresented: $showingImportResult) {
            Button("OK") {}
        } message: {
            Text(importResultMessage ?? "")
        }
        .alert("Expired Passwords", isPresented: $showingExpiredAlert) {
            Button("OK") {}
        } message: {
            Text(appState.expiredEntriesMessage ?? "")
        }
        .confirmationDialog("Export Passwords", isPresented: $showingCSVExportWarning, titleVisibility: .visible) {
            Button("Export Anyway", role: .destructive) {
                reAuthPassword = ""
                reAuthError = nil
                showingReAuthForCSV = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WARNING: This will export ALL your passwords in plaintext. The file will NOT be encrypted. Do not save to cloud-synced folders.")
        }
        .sheet(isPresented: $showingReAuthForCSV) {
            VStack(spacing: 16) {
                Text("Re-enter Master Password")
                    .font(.headline)
                Text("Confirm your identity before exporting passwords.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                SecureField("Master Password", text: $reAuthPassword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit {
                        if appState.verifyPassword(Data(reAuthPassword.utf8)) {
                            reAuthPassword = ""
                            reAuthError = nil
                            showingReAuthForCSV = false
                            exportCSV()
                        } else {
                            reAuthError = "Wrong password."
                        }
                    }
                if let err = reAuthError {
                    Text(err).foregroundStyle(.red).font(.system(size: 12))
                }
                HStack {
                    Button("Cancel") {
                        reAuthPassword = ""
                        showingReAuthForCSV = false
                    }
                    Button("Confirm") {
                        if appState.verifyPassword(Data(reAuthPassword.utf8)) {
                            reAuthPassword = ""
                            reAuthError = nil
                            showingReAuthForCSV = false
                            exportCSV()
                        } else {
                            reAuthError = "Wrong password."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.citadelAccent)
                }
            }
            .padding(24)
            .frame(width: 340)
        }
        .confirmationDialog("Replace Existing Vaults?", isPresented: $showingRestoreOverwriteWarning, titleVisibility: .visible) {
            Button("Replace", role: .destructive) {
                if let url = pendingRestoreURL, let pw = pendingRestorePassword {
                    doRestore(from: url, password: pw)
                }
                pendingRestoreURL = nil
                pendingRestorePassword = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRestoreURL = nil
                pendingRestorePassword = nil
            }
        } message: {
            Text("This will replace your current vault(s). Recent changes not backed up will be lost. Continue?")
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            if appState.expiredEntriesMessage != nil {
                showingExpiredAlert = true
            }
        }
        .onChange(of: appState.expiredEntriesMessage) { _, newValue in
            if newValue != nil { showingExpiredAlert = true }
        }
        // MARK: Notification listeners
        .onReceive(NotificationCenter.default.publisher(for: .citadelNewEntry)) { _ in
            showingAddEntry = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .citadelShowSettings)) { _ in
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .citadelCopyPassword)) { _ in
            copySelectedPassword()
        }
        .onReceive(NotificationCenter.default.publisher(for: .citadelCopyUsername)) { _ in
            copySelectedUsername()
        }
        .onReceive(NotificationCenter.default.publisher(for: .citadelShowAbout)) { _ in
            showingAbout = true
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            // Vault header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.citadelAccent)
                Text(appState.activeVaultName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    appState.lockVault()
                } label: {
                    Image(systemName: "lock")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.citadelSecondary)
                }
                .buttonStyle(.plain)
                .help("Lock vault")
            }
            .listRowSeparator(.hidden)
            .padding(.bottom, 2)

            // Favorites
            sidebarRow("Favorites", icon: "star.fill", color: .yellow, item: .favorites, count: appState.entries.filter(\.isFavorite).count)

            // Projects
            Section {
                if projects.isEmpty {
                    Text("Click + to create a project")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(projects, id: \.self) { project in
                        let count = appState.entries.filter { $0.group == project || $0.group.hasPrefix(project + "/") }.count
                        sidebarRow(project, icon: "folder.fill", color: .indigo, item: .project(project), count: count)
                    }
                }
            } header: {
                HStack {
                    Text("PROJECTS")
                    Spacer()
                    Button {
                        newProjectName = ""
                        showingNewProject = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.citadelAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Categories
            Section("Categories") {
                sidebarRow("All Items", icon: "square.grid.2x2", color: .citadelAccent, item: .allItems, count: appState.entries.count)
                sidebarRow("Logins", icon: "key.fill", color: .blue, item: .logins, count: appState.entries.filter { $0.entryType == "password" || $0.entryType.isEmpty }.count)
                sidebarRow("Crypto Wallets", icon: "bitcoinsign.circle", color: .orange, item: .cryptoWallets, count: appState.entries.filter { EntryTemplate.cryptoTypes.contains($0.entryType) }.count)
                sidebarRow("Wallet (Multi-Chain)", icon: "link.circle", color: .orange, item: .multiChainWallets, count: appState.entries.filter { $0.entryType == "multi_chain_wallet" }.count)
                sidebarRow("Server / SSH", icon: "server.rack", color: .cyan, item: .serverSSH, count: appState.entries.filter { $0.entryType == "server_ssh" }.count)
                sidebarRow("API Keys", icon: "curlybraces", color: .red, item: .apiKeys, count: appState.entries.filter { $0.entryType == "api_key" }.count)
                sidebarRow("Databases", icon: "cylinder", color: .blue, item: .databases, count: appState.entries.filter { $0.entryType == "database" }.count)
                sidebarRow("Email Accounts", icon: "envelope.fill", color: .blue, item: .emailAccounts, count: appState.entries.filter { $0.entryType == "email_account" }.count)
                sidebarRow("Credit Cards", icon: "creditcard.fill", color: .green, item: .creditCards, count: appState.entries.filter { $0.entryType == "credit_card" }.count)
                sidebarRow("Identities", icon: "person.text.rectangle", color: .orange, item: .identities, count: appState.entries.filter { $0.entryType == "identity" }.count)
                sidebarRow("Secure Notes", icon: "note.text", color: .purple, item: .secureNotes, count: appState.entries.filter { $0.entryType == "secure_note" }.count)
                sidebarRow("Recovery Codes", icon: "key.viewfinder", color: .pink, item: .recoveryCodes, count: appState.entries.filter { $0.entryType == "recovery_codes" }.count)
                sidebarRow("Software Licenses", icon: "purchased", color: .teal, item: .softwareLicenses, count: appState.entries.filter { $0.entryType == "software_license" }.count)
            }

            // Folders
            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders, id: \.self) { folder in
                        let displayName = folder.split(separator: "/").last.map(String.init) ?? folder
                        let count = appState.entries.filter { $0.group == folder || $0.group.hasPrefix(folder + "/") }.count
                        sidebarRow(displayName, icon: "folder.fill", color: .orange, item: .folder(folder), count: count)
                    }
                }
            }

            // Tags
            if !allTags.isEmpty {
                Section("Tags") {
                    ForEach(allTags, id: \.tag) { item in
                        sidebarRow(item.tag, icon: "tag.fill", color: .teal, item: .tag(item.tag), count: item.count)
                    }
                }
            }

            // Tools (buttons, not selection items)
            Section("Tools") {
                sidebarButton("Password Generator", icon: "wand.and.stars", color: .pink) {
                    showingGenerator = true
                }
                sidebarButton("Password Health", icon: "heart.text.square", color: .citadelSuccess) {
                    showingPasswordHealth = true
                }
                sidebarButton("Breach Check", icon: "shield.slash", color: .citadelDanger) {
                    showingPasswordHealth = true
                }
                sidebarButton("Audit Log", icon: "list.bullet.clipboard", color: .indigo) {
                    showingAuditLog = true
                }
            }

            // Trash
            Section {
                sidebarRow("Trash", icon: "trash", color: .gray, item: .trash, count: appState.recycledEntries.count)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sidebarRow(_ title: String, icon: String, color: Color, item: SidebarItem, count: Int) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
        }
        .tag(item)
    }

    @ViewBuilder
    private func sidebarButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 18)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Actions

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try appState.engine.createGroup(path: name)
            try appState.save()
            try appState.refreshEntries()
            sidebarSelection = .project(name)
        } catch {
            // Silently fail — group may already exist
        }
    }

    private func copySelectedPassword() {
        guard let id = appState.selectedEntryID,
              let entry = try? appState.engine.getEntry(uuid: id) else { return }
        appState.clipboard.copyPassword(entry.password)
    }

    private func copySelectedUsername() {
        guard let id = appState.selectedEntryID,
              let entry = try? appState.engine.getEntry(uuid: id) else { return }
        appState.clipboard.copySecure(entry.username)
    }

    private func exportCSV() {
        do {
            let entries: [(title: String, username: String, password: String, url: String, notes: String)] =
                try appState.entries.map { summary in
                    let detail = try appState.engine.getEntry(uuid: summary.id)
                    return (
                        title: detail.title,
                        username: detail.username,
                        password: String(decoding: detail.password, as: UTF8.self),
                        url: detail.url,
                        notes: detail.notes
                    )
                }
            let csvData = CSVManager.export(entries: entries)
            let panel = NSSavePanel()
            panel.title = "Export Entries as CSV"
            panel.nameFieldStringValue = "smaug-export.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            if Self.isCloudSyncedPath(url.path) {
                importResultMessage = "Cannot export to a cloud-synced folder. Please choose a local directory."
                showingImportResult = true
                return
            }
            try csvData.write(to: url)
            appState.auditLogger.log(.exportCSV, detail: "\(entries.count) entries")
        } catch {
            importResultMessage = "Export failed."
            showingImportResult = true
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.title = "Import CSV"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let entries = try CSVManager.parse(data: data)
            var count = 0
            for entry in entries {
                _ = try appState.engine.addEntry(
                    title: entry.title, username: entry.username,
                    password: Data(entry.password.utf8),
                    url: entry.url, notes: entry.notes
                )
                count += 1
            }
            if count > 0 {
                try appState.save()
                try appState.refreshEntries()
            }
            importResultMessage = "Imported \(count) entries."
            appState.auditLogger.log(.importCSV, detail: "\(count) entries")
        } catch {
            importResultMessage = "Import failed."
        }
        showingImportResult = true
    }

    private func performBackup() {
        let panel = NSSavePanel()
        panel.title = "Save Vault Backup"
        panel.nameFieldStringValue = "vault-backup.kdbx"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try appState.performBackup(to: url)
            backupResultMessage = "Backup saved and verified successfully."
        } catch {
            backupResultMessage = "Backup failed."
        }
        showingBackupResult = true
    }

    private func verifyBackup() {
        let panel = NSOpenPanel()
        panel.title = "Select Backup to Verify"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Backup Password"
        alert.informativeText = "Enter the backup password to verify:"
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Verify")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let result = try appState.verifyBackup(at: url, backupPassword: input.stringValue)
            var msg = "Backup verified. Contains \(result.manifest.vaults.count) vault(s), created \(result.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))."
            if result.isLegacyFormat {
                msg += "\n\nWarning: This backup uses weak encryption (v1). Please re-export it using the current version for stronger protection."
            }
            backupResultMessage = msg
        } catch {
            backupResultMessage = "Verification failed: \(error.localizedDescription)"
        }
        showingBackupResult = true
    }

    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.title = "Select Backup to Restore"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Backup Password"
        alert.informativeText = "Enter the backup password to restore:"
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // Check if any vault files at the destination already exist
        let fm = FileManager.default
        let dir = appState.vaultDirectory
        let hasExisting = (try? fm.contentsOfDirectory(atPath: dir))?.contains { $0.hasSuffix(".kdbx") } ?? false
        if hasExisting {
            pendingRestoreURL = url
            pendingRestorePassword = input.stringValue
            showingRestoreOverwriteWarning = true
        } else {
            doRestore(from: url, password: input.stringValue)
        }
    }

    private func doRestore(from url: URL, password: String) {
        do {
            let result = try appState.restoreFromBackup(at: url, backupPassword: password)
            var msg = "Restored \(result.manifest.vaults.count) vault(s) successfully."
            if result.isLegacyFormat {
                msg += "\n\nWarning: This backup used weak encryption (v1). Please re-export using the current version for stronger protection."
            }
            backupResultMessage = msg
        } catch {
            backupResultMessage = "Restore failed: \(error.localizedDescription)"
        }
        showingBackupResult = true
    }

    /// Check if a path is inside a known cloud-synced directory.
    private static func isCloudSyncedPath(_ path: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cloudPrefixes = [
            home + "/Library/Mobile Documents",
            home + "/Library/CloudStorage",
            home + "/Dropbox",
            home + "/Google Drive",
            home + "/OneDrive",
        ]
        let resolved = (path as NSString).resolvingSymlinksInPath
        return cloudPrefixes.contains { resolved.hasPrefix($0) }
    }
}

// MARK: - Full Backup Sheet

struct FullBackupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var backupPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Full Vault Backup")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Creates a single encrypted file containing all vault files, keyfiles, and checksums.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.citadelSecondary)

                SectionHeader(title: "Backup Password")
                SecureField(text: $backupPassword, prompt: Text("Backup password").foregroundStyle(.tertiary)) {}
                    .textFieldStyle(.plain).font(.system(size: 13)).padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                SecureField(text: $confirmPassword, prompt: Text("Confirm password").foregroundStyle(.tertiary)) {}
                    .textFieldStyle(.plain).font(.system(size: 13)).padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.citadelWarning)
                    Text("This password is separate from your vault password. Store it securely.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.citadelSecondary)
                }

                if let msg = errorMessage {
                    Text(msg).font(.system(size: 12)).foregroundStyle(Color.citadelDanger)
                }
                if let msg = successMessage {
                    Text(msg).font(.system(size: 12)).foregroundStyle(Color.citadelSuccess)
                }
            }
            .padding(20)

            Spacer()
            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Backup") { createBackup() }
                    .buttonStyle(.borderedProminent)
                    .tint(.citadelAccent)
                    .disabled(backupPassword.isEmpty || backupPassword != confirmPassword)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 400, minHeight: 340)
    }

    private func createBackup() {
        let panel = NSSavePanel()
        panel.title = "Save Encrypted Backup"
        panel.nameFieldStringValue = "smaug-backup.ctdl"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try appState.createFullBackup(backupPassword: backupPassword, destination: url)
            successMessage = "Backup created and encrypted successfully."
            errorMessage = nil
        } catch {
            errorMessage = "Backup failed: \(error.localizedDescription)"
            successMessage = nil
        }
    }
}

// MARK: - Trash Detail View

/// Detail view for entries in the Recycle Bin — shows restore and permanently delete options.
struct TrashDetailView: View {
    @Environment(AppState.self) private var appState
    let entryID: String

    @State private var errorMessage: String?

    private var entry: VaultEntrySummary? {
        appState.recycledEntries.first { $0.id == entryID }
    }

    var body: some View {
        if let entry {
            VStack(spacing: 20) {
                Spacer()

                EntryIcon(title: entry.title, entryType: entry.entryType, size: 56)

                Text(entry.title.isEmpty ? "(Untitled)" : entry.title)
                    .font(.system(size: 18, weight: .semibold))

                if !entry.username.isEmpty {
                    Text(entry.username)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Text("This entry is in the Trash.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        restoreEntry()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.citadelAccent)

                    Button(role: .destructive) {
                        permanentlyDelete()
                    } label: {
                        Label("Delete Permanently", systemImage: "trash.slash")
                    }
                    .buttonStyle(.bordered)
                }

                if let msg = errorMessage {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            Text("Entry not found")
                .foregroundStyle(.secondary)
        }
    }

    private func restoreEntry() {
        do {
            try appState.engine.restoreEntry(uuid: entryID)
            try appState.save()
            try appState.refreshEntries()
            appState.selectedEntryID = nil
        } catch {
            errorMessage = "Could not restore entry"
        }
    }

    private func permanentlyDelete() {
        do {
            try appState.engine.permanentlyDeleteEntry(uuid: entryID)
            try appState.save()
            try appState.refreshEntries()
            appState.selectedEntryID = nil
        } catch {
            errorMessage = "Could not delete entry"
        }
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)

            DragonIcon(size: 96)

            Spacer().frame(height: 16)

            Text("Smaug")
                .font(.system(size: 24, weight: .bold))

            Text("Personal Vault")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            Spacer().frame(height: 20)

            Text("Created by Luis Maumejean G.")
                .font(.system(size: 14))

            Text("luismaumejean@gmail.com")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer().frame(height: 16)

            if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("Version \(version)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: 16)

            Text("Rust + SwiftUI \u{00B7} ChaCha20-256 \u{00B7} Argon2id \u{00B7} Secure Enclave")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            Link("github.com/LEMG-lab/citadel", destination: URL(string: "https://github.com/LEMG-lab/citadel")!)
                .font(.system(size: 12))
                .foregroundStyle(Color.citadelAccent)

            Spacer().frame(height: 24)

            Button("OK") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.citadelAccent)
                .keyboardShortcut(.defaultAction)

            Spacer().frame(height: 20)
        }
        .frame(width: 340, height: 420)
    }
}
