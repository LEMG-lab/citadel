import SwiftUI
import UniformTypeIdentifiers
import CitadelCore

/// Application settings sheet.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showingPasswordChange = false
    @State private var showingRecoverySheet = false
    @State private var showingAuditLog = false
    @State private var showingPasswordHealth = false
    @State private var selectedKdfPreset: KdfPreset = .saved
    @State private var showingKdfConfirmation = false
    @State private var kdfMessage: String?
    @State private var showingEmptyRecycleBin = false
    @State private var recycleBinMessage: String?
    @State private var dataResultMessage: String?
    @State private var showingDataResult = false

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Security") {
                HStack {
                    Text("Auto-lock timeout")
                    Spacer()
                    Text("\(Int(appState.autoLockTimeout / 60)) min")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $appState.autoLockTimeout, in: 60...1800, step: 60)

                HStack {
                    Text("Clipboard clear time")
                    Spacer()
                    Text("\(Int(appState.clipboardClearTime)) sec")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $appState.clipboardClearTime, in: 5...60, step: 5)

                LabeledContent("Touch ID") {
                    Text("Coming in v1.3")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Vault") {
                LabeledContent("Location") {
                    Text(appState.vaultPath)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .font(.callout)
                }
                Button("Change Master Password") {
                    showingPasswordChange = true
                }

                Picker("KDF Strength", selection: $selectedKdfPreset) {
                    ForEach(KdfPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .onChange(of: selectedKdfPreset) { _, newValue in
                    if newValue != .saved {
                        showingKdfConfirmation = true
                    }
                }

                if let msg = kdfMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("failed") ? .red : .green)
                }
            }

            Section("Recycle Bin") {
                Button("Empty Recycle Bin", role: .destructive) {
                    showingEmptyRecycleBin = true
                }
                if let msg = recycleBinMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data") {
                Button("Export CSV…") { exportCSV() }
                Button("Import CSV…") { importCSV() }
                if let msg = dataResultMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("failed") ? .red : .secondary)
                }
            }

            Section("Recovery") {
                Button("Print Recovery Sheet") {
                    showingRecoverySheet = true
                }
            }

            Section("Audit") {
                Button("View Audit Log") {
                    showingAuditLog = true
                }
                Button("Password Health Report") {
                    showingPasswordHealth = true
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
                .background(.background)
            }
        }
        .frame(width: 500, height: 640)
        .sheet(isPresented: $showingPasswordChange) {
            ChangePasswordView()
        }
        .sheet(isPresented: $showingRecoverySheet) {
            RecoverySheetView()
        }
        .sheet(isPresented: $showingAuditLog) {
            AuditLogView()
        }
        .sheet(isPresented: $showingPasswordHealth) {
            PasswordHealthView()
        }
        .confirmationDialog(
            "Change KDF Strength",
            isPresented: $showingKdfConfirmation,
            titleVisibility: .visible
        ) {
            Button("Re-encrypt Vault") { applyKdfChange() }
            Button("Cancel", role: .cancel) {
                selectedKdfPreset = .saved
            }
        } message: {
            Text("This will re-encrypt your vault with \(selectedKdfPreset.label) KDF parameters. This may take a moment.")
        }
        .alert("Data Operation", isPresented: $showingDataResult) {
            Button("OK") {}
        } message: {
            Text(dataResultMessage ?? "")
        }
        .confirmationDialog(
            "Empty Recycle Bin",
            isPresented: $showingEmptyRecycleBin,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) { emptyRecycleBin() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All entries in the Recycle Bin will be permanently deleted. This cannot be undone.")
        }
    }

    private func applyKdfChange() {
        do {
            try appState.applyKdfPreset(selectedKdfPreset)
            kdfMessage = "KDF updated to \(selectedKdfPreset.label)."
        } catch {
            kdfMessage = "KDF change failed."
            selectedKdfPreset = .saved
        }
    }

    private func emptyRecycleBin() {
        do {
            let count = try appState.emptyRecycleBin()
            recycleBinMessage = count > 0 ? "\(count) entry(s) permanently deleted." : "Recycle Bin was already empty."
        } catch {
            recycleBinMessage = "Failed to empty Recycle Bin."
        }
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
            dataResultMessage = "Exported \(entries.count) entries."
        } catch {
            dataResultMessage = "Export failed."
        }
        showingDataResult = true
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
                    title: entry.title,
                    username: entry.username,
                    password: Data(entry.password.utf8),
                    url: entry.url,
                    notes: entry.notes
                )
                count += 1
            }
            if count > 0 {
                try appState.save()
                try appState.refreshEntries()
            }
            dataResultMessage = "Imported \(count) entries."
            appState.auditLogger.log(.importCSV, detail: "\(count) entries")
        } catch {
            dataResultMessage = "Import failed."
        }
        showingDataResult = true
    }

}
