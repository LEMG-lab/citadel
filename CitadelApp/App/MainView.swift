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
                    Button("Backup Vault\u{2026}") { performBackup() }
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
            if newValue != nil {
                showingExpiredAlert = true
            }
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
}
