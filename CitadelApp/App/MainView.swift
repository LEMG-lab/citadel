import SwiftUI
import CitadelCore

/// Main vault UI with sidebar entry list and detail pane.
struct MainView: View {
    @Environment(AppState.self) private var appState

    @State private var showingAddEntry = false
    @State private var showingSettings = false
    @State private var backupResultMessage: String?
    @State private var showingBackupResult = false

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            EntryListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if let id = appState.selectedEntryID {
                EntryDetailView(entryID: id)
            } else {
                ContentUnavailableView(
                    "No Entry Selected",
                    systemImage: "doc.text",
                    description: Text("Select an entry to view its details.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Add Entry", systemImage: "plus") {
                    showingAddEntry = true
                }
                Button("Backup", systemImage: "arrow.down.doc") {
                    performBackup()
                }
                Button("Settings", systemImage: "gearshape") {
                    showingSettings = true
                }
            }
            ToolbarItem(placement: .automatic) {
                Button("Lock", systemImage: "lock") {
                    appState.lockVault()
                }
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
