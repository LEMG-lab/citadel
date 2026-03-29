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
    @State private var errorMessage: String?
    @State private var totpCode: String = ""
    @State private var totpSecondsRemaining: Int = 0
    @State private var totpTimer: Timer?

    private var isSecureNote: Bool {
        entry?.entryType == "secure_note"
    }

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

                if !isSecureNote {
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
                            Image(systemName: "eye")
                                .foregroundStyle(showPassword ? .primary : .secondary)
                                .help("Hold to reveal password")
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { _ in showPassword = true }
                                        .onEnded { _ in showPassword = false }
                                )
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
                }
                if !entry.notes.isEmpty {
                    LabeledContent(isSecureNote ? "Content" : "Notes") {
                        Text(entry.notes)
                            .textSelection(.enabled)
                    }
                }
            }

            if let expiry = entry.expiryDate {
                Section("Expiration") {
                    LabeledContent("Expires") {
                        HStack {
                            if expiry < Date() {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption2)
                                Text("Expired")
                                    .foregroundStyle(.red)
                            } else if expiry < Date().addingTimeInterval(7 * 24 * 3600) {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption2)
                                Text("Expiring soon")
                                    .foregroundStyle(.orange)
                            }
                            Text(expiry, style: .date)
                        }
                    }
                }
            }

            if !isSecureNote, !entry.otpURI.isEmpty, TOTPGenerator(uri: entry.otpURI) != nil {
                Section("Two-Factor Authentication") {
                    LabeledContent("TOTP Code") {
                        HStack {
                            Text(totpCode)
                                .font(.system(.title2, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Text("\(totpSecondsRemaining)s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Copy", systemImage: "doc.on.doc") {
                                appState.clipboard.copyPassword(Data(totpCode.utf8))
                            }
                            .buttonStyle(.borderless)
                            .labelStyle(.iconOnly)
                        }
                    }
                }
                .onAppear { startTOTPTimer(uri: entry.otpURI) }
                .onDisappear { stopTOTPTimer() }
            }

            if !entry.customFields.isEmpty {
                Section("Custom Fields") {
                    ForEach(entry.customFields) { field in
                        LabeledContent(field.key) {
                            HStack {
                                if field.isProtected {
                                    Text(String(repeating: "\u{2022}", count: 8))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(field.value)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                Button("Copy", systemImage: "doc.on.doc") {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.setString(field.value, forType: .string)
                                }
                                .buttonStyle(.borderless)
                                .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(entry.isFavorite ? "Unfavorite" : "Favorite",
                       systemImage: entry.isFavorite ? "star.fill" : "star") {
                    toggleFavorite()
                }
                .help(entry.isFavorite ? "Remove from favorites" : "Add to favorites")

                if !isSecureNote {
                    Button("Copy Password", systemImage: "key") {
                        appState.clipboard.copyPassword(entry.password)
                    }
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
        do {
            entry = try appState.engine.getEntry(uuid: entryID)
            errorMessage = nil
        } catch {
            entry = nil
            errorMessage = "Could not load entry"
        }
    }

    private func copyUsername(_ username: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(username, forType: .string)
    }

    private func toggleFavorite() {
        guard let entry else { return }
        do {
            try appState.engine.setFavorite(uuid: entry.uuid, favorite: !entry.isFavorite)
            try appState.save()
            try appState.refreshEntries()
            loadEntry()
        } catch {
            errorMessage = "Could not update favorite"
        }
    }

    private func startTOTPTimer(uri: String) {
        stopTOTPTimer()
        guard let gen = TOTPGenerator(uri: uri) else { return }
        updateTOTP(gen)
        totpTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in updateTOTP(gen) }
        }
    }

    private func stopTOTPTimer() {
        totpTimer?.invalidate()
        totpTimer = nil
    }

    private func updateTOTP(_ gen: TOTPGenerator) {
        totpCode = gen.code()
        totpSecondsRemaining = gen.secondsRemaining()
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
