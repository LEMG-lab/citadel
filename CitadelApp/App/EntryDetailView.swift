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
    @State private var showingShare = false
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
            VStack(alignment: .leading, spacing: 20) {
                // ── Header ──────────────────────────────────────
                headerSection(entry)

                // ── Action bar ──────────────────────────────────
                actionBar(entry)

                // ── Field cards ─────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    if !isSecureNote {
                        if !entry.username.isEmpty {
                            usernameCard(entry.username)
                        }

                        passwordCard(entry)

                        if !entry.url.isEmpty {
                            urlCard(entry.url)
                        }
                    }

                    if !entry.notes.isEmpty {
                        notesCard(entry)
                    }

                    if !isSecureNote, !entry.otpURI.isEmpty, TOTPGenerator(uri: entry.otpURI) != nil {
                        totpCard
                    }

                    if !entry.customFields.isEmpty {
                        customFieldsSection(entry)
                    }
                }

                // ── Expiry ──────────────────────────────────────
                if let expiry = entry.expiryDate {
                    expiryRow(expiry)
                }

                // ── Footer metadata ─────────────────────────────
                footerMetadata(entry)
            }
            .padding(24)
        }
        .sheet(isPresented: $showingEdit, onDismiss: { loadEntry() }) {
            EntryEditView(mode: .edit(entry))
        }
        .sheet(isPresented: $showingShare) {
            ShareEntryView(entry: entry)
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

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ entry: VaultEntryDetail) -> some View {
        HStack(spacing: 14) {
            EntryIcon(
                title: entry.title,
                entryType: entry.entryType,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title.isEmpty ? "(Untitled)" : entry.title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)

                if !isSecureNote && !entry.username.isEmpty {
                    Text(entry.username)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.citadelSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private func actionBar(_ entry: VaultEntryDetail) -> some View {
        HStack(spacing: 6) {
            actionButton(
                icon: "pencil.circle.fill",
                label: "Edit",
                color: .citadelAccent
            ) {
                showingEdit = true
            }

            actionButton(
                icon: "square.and.arrow.up.circle.fill",
                label: "Share",
                color: .citadelAccent
            ) {
                showingShare = true
            }

            actionButton(
                icon: "trash.circle.fill",
                label: "Delete",
                color: .citadelDanger
            ) {
                showingDeleteConfirmation = true
            }

            Spacer()

            Button {
                toggleFavorite()
            } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 20))
                    .foregroundStyle(entry.isFavorite ? .yellow : Color.citadelSecondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(entry.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Username Card

    @ViewBuilder
    private func usernameCard(_ username: String) -> some View {
        FieldCard(label: "Username") {
            HStack(spacing: 10) {
                Image(systemName: "person")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.citadelSecondary)
                    .frame(width: 20)

                Text(username)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .lineLimit(2)

                Spacer()

                copyButton {
                    copyUsername(username)
                }
            }
        }
    }

    // MARK: - Password Card

    @ViewBuilder
    private func passwordCard(_ entry: VaultEntryDetail) -> some View {
        FieldCard(label: "Password") {
            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.citadelSecondary)
                    .frame(width: 20)

                if showPassword {
                    Text(String(decoding: entry.password, as: UTF8.self))
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text(String(repeating: "\u{2022}", count: 14))
                        .font(.system(size: 13))
                        .foregroundStyle(.primary.opacity(0.6))
                }

                Spacer()

                // Press-and-hold reveal
                Image(systemName: showPassword ? "eye.fill" : "eye")
                    .font(.system(size: 13))
                    .foregroundStyle(showPassword ? Color.citadelAccent : Color.citadelSecondary)
                    .help("Hold to reveal")
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in showPassword = true }
                            .onEnded { _ in showPassword = false }
                    )

                copyButton {
                    appState.clipboard.copyPassword(entry.password)
                }
            }
        }
    }

    // MARK: - URL Card

    @ViewBuilder
    private func urlCard(_ url: String) -> some View {
        FieldCard(label: "URL") {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.citadelSecondary)
                    .frame(width: 20)

                if let parsed = URL(string: url) {
                    Link(destination: parsed) {
                        Text(url)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.citadelAccent)
                            .lineLimit(2)
                            .underline()
                    }
                } else {
                    Text(url)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                Spacer()

                copyButton {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(url, forType: .string)
                }
            }
        }
    }

    // MARK: - Notes Card

    @ViewBuilder
    private func notesCard(_ entry: VaultEntryDetail) -> some View {
        FieldCard(label: isSecureNote ? "Content" : "Notes") {
            Text(entry.notes)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - TOTP Card

    @ViewBuilder
    private var totpCard: some View {
        FieldCard(label: "TOTP Code") {
            HStack(spacing: 14) {
                // Countdown ring
                ZStack {
                    ProgressRing(
                        progress: Double(totpSecondsRemaining) / 30.0,
                        color: totpSecondsRemaining <= 5 ? .citadelDanger : .citadelAccent,
                        lineWidth: 3.5
                    )
                    Text("\(totpSecondsRemaining)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(totpSecondsRemaining <= 5 ? Color.citadelDanger : Color.citadelSecondary)
                }
                .frame(width: 40, height: 40)

                Text(formatTOTP(totpCode))
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)

                Spacer()

                copyButton {
                    appState.clipboard.copyPassword(Data(totpCode.utf8))
                }
            }
        }
        .onAppear { startTOTPTimer(uri: entry!.otpURI) }
        .onDisappear { stopTOTPTimer() }
    }

    private func formatTOTP(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }

    // MARK: - Custom Fields

    @ViewBuilder
    private func customFieldsSection(_ entry: VaultEntryDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Custom Fields")
                .padding(.top, 4)

            ForEach(entry.customFields) { field in
                FieldCard(label: field.key) {
                    HStack(spacing: 10) {
                        Image(systemName: field.isProtected ? "lock" : "text.alignleft")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.citadelSecondary)
                            .frame(width: 20)

                        Text(field.isProtected ? String(repeating: "\u{2022}", count: 8) : field.value)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .lineLimit(3)

                        Spacer()

                        copyButton {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(field.value, forType: .string)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Expiry Row

    @ViewBuilder
    private func expiryRow(_ expiry: Date) -> some View {
        let isExpired = expiry < Date()
        let isSoon = expiry < Date().addingTimeInterval(7 * 24 * 3600)

        HStack(spacing: 8) {
            Circle()
                .fill(isExpired ? Color.citadelDanger : isSoon ? Color.citadelWarning : Color.citadelSecondary)
                .frame(width: 7, height: 7)
            Text(isExpired ? "Expired" : isSoon ? "Expiring soon" : "Expires")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isExpired ? Color.citadelDanger : isSoon ? Color.citadelWarning : Color.citadelSecondary)
            Text(expiry, style: .date)
                .font(.system(size: 12))
                .foregroundStyle(Color.citadelSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            (isExpired ? Color.citadelDanger : isSoon ? Color.citadelWarning : Color.citadelSecondary).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    // MARK: - Footer Metadata

    @ViewBuilder
    private func footerMetadata(_ entry: VaultEntryDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let modified = entry.lastModified {
                Text("Last modified: \(modified.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.citadelTertiary)
            }

            HStack(spacing: 6) {
                if entry.isFavorite {
                    MetadataPill(icon: "star.fill", text: "Favorite", color: .yellow)
                }
                if entry.entryType == "secure_note" {
                    MetadataPill(icon: "note.text", text: "Secure Note", color: .purple)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Copy Button

    @ViewBuilder
    private func copyButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12))
                .foregroundStyle(Color.citadelSecondary)
                .padding(6)
                .background(Color.citadelSecondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Copy")
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
