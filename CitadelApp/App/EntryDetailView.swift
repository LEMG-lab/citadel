import SwiftUI
import CitadelCore

/// Read-only detail view for a vault entry.
struct EntryDetailView: View {
    @Environment(AppState.self) private var appState
    let entryID: String

    @State private var entry: VaultEntryDetail?
    @State private var showPassword = false
    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    @State private var revealTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let entry {
                detailContent(entry)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
            }
        }
        .task(id: entryID) {
            loadEntry()
        }
    }

    @ViewBuilder
    private func detailContent(_ entry: VaultEntryDetail) -> some View {
        Form {
            Section("Details") {
                LabeledContent("Title", value: entry.title)
                LabeledContent("Username") {
                    HStack {
                        Text(entry.username)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copy", systemImage: "doc.on.doc") {
                            copyUsername(entry.username)
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                    }
                }
                LabeledContent("Password") {
                    HStack {
                        if showPassword {
                            Text(String(decoding: entry.password, as: UTF8.self))
                                .textSelection(.enabled)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            Text(String(repeating: "\u{2022}", count: 12))
                        }
                        Spacer()
                        Button(showPassword ? "Hide" : "Reveal") {
                            toggleReveal()
                        }
                        .buttonStyle(.borderless)
                        Button("Copy", systemImage: "doc.on.doc") {
                            appState.clipboard.copyPassword(entry.password)
                        }
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                    }
                }
                if !entry.url.isEmpty {
                    LabeledContent("URL") {
                        Text(entry.url)
                            .textSelection(.enabled)
                    }
                }
                if !entry.notes.isEmpty {
                    LabeledContent("Notes") {
                        Text(entry.notes)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy Password", systemImage: "key") {
                    appState.clipboard.copyPassword(entry.password)
                }
                Button("Edit", systemImage: "pencil") {
                    showingEdit = true
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .sheet(isPresented: $showingEdit, onDismiss: { loadEntry() }) {
            EntryEditView(mode: .edit(entry))
        }
        .confirmationDialog(
            "Delete Entry",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteEntry() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(entry.title)\"? This cannot be undone.")
        }
    }

    // MARK: - Actions

    private func loadEntry() {
        showPassword = false
        revealTask?.cancel()
        do {
            entry = try appState.engine.getEntry(uuid: entryID)
            errorMessage = nil
        } catch {
            entry = nil
            errorMessage = "Could not load entry"
        }
    }

    private func toggleReveal() {
        if showPassword {
            showPassword = false
            revealTask?.cancel()
        } else {
            showPassword = true
            revealTask?.cancel()
            revealTask = Task {
                try? await Task.sleep(for: .seconds(10))
                if !Task.isCancelled {
                    showPassword = false
                }
            }
        }
    }

    private func copyUsername(_ username: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(username, forType: .string)
    }

    private func deleteEntry() {
        do {
            try appState.engine.deleteEntry(uuid: entryID)
            try appState.save()
            try appState.refreshEntries()
            appState.selectedEntryID = nil
        } catch {
            errorMessage = "Could not delete entry"
        }
    }
}
