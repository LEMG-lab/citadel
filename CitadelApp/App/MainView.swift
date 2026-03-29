import SwiftUI
import UniformTypeIdentifiers
import CitadelCore

/// Main vault UI with sidebar entry list and detail pane.
struct MainView: View {
    @Environment(AppState.self) private var appState

    @State private var showingAddEntry = false
    @State private var showingSettings = false
    @State private var backupResultMessage: String?
    @State private var showingBackupResult = false
    @State private var importResultMessage: String?
    @State private var showingImportResult = false
    @State private var showingExpiredAlert = false
    @State private var showingReceiveShare = false
    @State private var showingFullBackup = false
    @State private var showingVerifyBackup = false
    @State private var showingRestoreBackup = false
    @State private var backupPassword = ""
    @State private var backupMessage: String?

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            EntryListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let id = appState.selectedEntryID {
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
                // Vault switcher
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
                    Button("Export CSV\u{2026}") { exportCSV() }
                    Button("Import CSV\u{2026}") { importCSV() }
                    Divider()
                    Button("Receive Shared Entry\u{2026}") { showingReceiveShare = true }
                    Divider()
                    Button("Backup Vault\u{2026}") { performBackup() }
                    Button("Full Vault Backup\u{2026}") { showingFullBackup = true }
                    Button("Verify Backup\u{2026}") { verifyBackup() }
                    Button("Restore from Backup\u{2026}") { restoreBackup() }
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
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.lockVault()
                } label: {
                    Image(systemName: "lock")
                }
                .help("Lock vault")
            }
        }
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
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            if appState.expiredEntriesMessage != nil {
                showingExpiredAlert = true
            }
        }
        .onChange(of: appState.expiredEntriesMessage) { _, newValue in
            if newValue != nil { showingExpiredAlert = true }
        }
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
    }

    private func copySelectedPassword() {
        guard let id = appState.selectedEntryID,
              let entry = try? appState.engine.getEntry(uuid: id) else { return }
        appState.clipboard.copyPassword(entry.password)
    }

    private func copySelectedUsername() {
        guard let id = appState.selectedEntryID,
              let entry = try? appState.engine.getEntry(uuid: id) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.username, forType: .string)
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
            panel.nameFieldStringValue = "citadel-export.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
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
            let manifest = try appState.verifyBackup(at: url, backupPassword: input.stringValue)
            backupResultMessage = "Backup verified. Contains \(manifest.vaults.count) vault(s), created \(manifest.createdAt.formatted(date: .abbreviated, time: .shortened))."
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

        do {
            let manifest = try appState.restoreFromBackup(at: url, backupPassword: input.stringValue)
            backupResultMessage = "Restored \(manifest.vaults.count) vault(s) successfully."
        } catch {
            backupResultMessage = "Restore failed: \(error.localizedDescription)"
        }
        showingBackupResult = true
    }
}

/// Sheet for creating an encrypted full backup.
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
        .frame(width: 440, height: 380)
    }

    private func createBackup() {
        let panel = NSSavePanel()
        panel.title = "Save Encrypted Backup"
        panel.nameFieldStringValue = "citadel-backup.ctdl"
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
