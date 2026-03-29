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

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(_ entry: VaultEntryDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    if isSecureNote {
                        IconBadge(symbol: "note.text", color: .purple, size: 40)
                    } else {
                        IconBadge(symbol: "key.fill", color: .citadelAccent, size: 40)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title.isEmpty ? "(Untitled)" : entry.title)
                            .font(.system(size: 18, weight: .bold))
                        if !isSecureNote && !entry.username.isEmpty {
                            Text(entry.username)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.citadelSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                // Fields
                if !isSecureNote {
                    if !entry.username.isEmpty {
                        fieldRow(label: "Username", value: entry.username, icon: "person") {
                            copyUsername(entry.username)
                        }
                    }

                    passwordRow(entry)

                    if !entry.url.isEmpty {
                        fieldRow(label: "URL", value: entry.url, icon: "link") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(entry.url, forType: .string)
                        }
                    }
                }

                if !entry.notes.isEmpty {
                    FieldCard(label: isSecureNote ? "Content" : "Notes") {
                        Text(entry.notes)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // TOTP
                if !isSecureNote, !entry.otpURI.isEmpty, TOTPGenerator(uri: entry.otpURI) != nil {
                    totpRow
                }

                // Custom Fields
                if !entry.customFields.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Custom Fields")
                        ForEach(entry.customFields) { field in
                            fieldRow(
                                label: field.key,
                                value: field.isProtected ? String(repeating: "\u{2022}", count: 8) : field.value,
                                icon: field.isProtected ? "lock" : "text.alignleft"
                            ) {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(field.value, forType: .string)
                            }
                        }
                    }
                }

                // Expiry
                if let expiry = entry.expiryDate {
                    expiryRow(expiry)
                }

                // Metadata pills
                metadataPills(entry)
            }
            .padding(20)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
                }
                .help(entry.isFavorite ? "Remove from favorites" : "Add to favorites")

                if !isSecureNote {
                    Button {
                        appState.clipboard.copyPassword(entry.password)
                    } label: {
                        Image(systemName: "key")
                    }
                    .help("Copy password")
                }

                Button {
                    showingEdit = true
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit entry")

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete entry")
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

    // MARK: - Field Rows

    @ViewBuilder
    private func fieldRow(label: String, value: String, icon: String, onCopy: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.citadelSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Color.citadelSecondary)
                Text(value)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            Spacer()

            Button {
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.citadelSecondary)
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func passwordRow(_ entry: VaultEntryDetail) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.citadelSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("PASSWORD")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Color.citadelSecondary)
                if showPassword {
                    Text(String(decoding: entry.password, as: UTF8.self))
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text(String(repeating: "\u{2022}", count: 14))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }

            Spacer()

            // Press-and-hold reveal
            Image(systemName: "eye")
                .font(.system(size: 12))
                .foregroundStyle(showPassword ? Color.citadelAccent : Color.citadelSecondary)
                .help("Hold to reveal")
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in showPassword = true }
                        .onEnded { _ in showPassword = false }
                )
                .padding(.trailing, 8)

            Button {
                appState.clipboard.copyPassword(entry.password)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.citadelSecondary)
            }
            .buttonStyle(.plain)
            .help("Copy password")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - TOTP Row

    @ViewBuilder
    private var totpRow: some View {
        HStack(spacing: 12) {
            // Countdown ring
            ZStack {
                ProgressRing(
                    progress: Double(totpSecondsRemaining) / 30.0,
                    color: totpSecondsRemaining <= 5 ? .citadelDanger : .citadelAccent,
                    lineWidth: 3
                )
                Text("\(totpSecondsRemaining)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(totpSecondsRemaining <= 5 ? Color.citadelDanger : Color.citadelSecondary)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("TOTP CODE")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Color.citadelSecondary)
                Text(formatTOTP(totpCode))
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                appState.clipboard.copyPassword(Data(totpCode.utf8))
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.citadelSecondary)
            }
            .buttonStyle(.plain)
            .help("Copy code")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear { startTOTPTimer(uri: entry!.otpURI) }
        .onDisappear { stopTOTPTimer() }
    }

    private func formatTOTP(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }

    // MARK: - Expiry Row

    @ViewBuilder
    private func expiryRow(_ expiry: Date) -> some View {
        let isExpired = expiry < Date()
        let isSoon = expiry < Date().addingTimeInterval(7 * 24 * 3600)
        HStack(spacing: 8) {
            Circle()
                .fill(isExpired ? Color.citadelDanger : isSoon ? Color.citadelWarning : Color.citadelSecondary)
                .frame(width: 6, height: 6)
            Text(isExpired ? "Expired" : isSoon ? "Expiring soon" : "Expires")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isExpired ? Color.citadelDanger : isSoon ? Color.citadelWarning : Color.citadelSecondary)
            Text(expiry, style: .date)
                .font(.system(size: 12))
                .foregroundStyle(Color.citadelSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Metadata

    @ViewBuilder
    private func metadataPills(_ entry: VaultEntryDetail) -> some View {
        HStack(spacing: 6) {
            if let modified = entry.lastModified {
                MetadataPill(icon: "clock", text: "Modified \(modified.formatted(.relative(presentation: .named)))")
            }
            if entry.isFavorite {
                MetadataPill(icon: "star.fill", text: "Favorite", color: .yellow)
            }
            if entry.entryType == "secure_note" {
                MetadataPill(icon: "note.text", text: "Secure Note", color: .purple)
            }
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
