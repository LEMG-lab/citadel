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
    @State private var passwordHistory: [(password: String, date: Date)] = []
    @State private var showPasswordHistory = false
    @State private var attachments: [(name: String, size: Int)] = []
    @State private var showAttachments = false
    @State private var showingAttachmentPicker = false
    @State private var attachmentToOpen: String?
    @State private var showingAttachmentWarning = false

    @State private var showingSeedWords = false
    @State private var seedWordDismissTask: Task<Void, Never>?
    @State private var revealedFieldKeys: Set<String> = []
    @State private var revealedSeedWords: Set<Int> = []

    private var isSecureNote: Bool {
        entry?.entryType == "secure_note"
    }

    private var isCryptoSeedType: Bool {
        let t = entry?.entryType ?? ""
        return t == "seed_phrase" || t == "multi_chain_wallet"
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

                    if isCryptoSeedType {
                        seedPhraseSection(entry)
                    }

                    if !entry.customFields.isEmpty {
                        customFieldsSection(entry)
                    }

                    // Tags (from summary, since Citadel_Tags is a standard field)
                    if let summary = appState.entries.first(where: { $0.id == entry.uuid }), !summary.tags.isEmpty {
                        tagsSection(summary.tags)
                    }
                }

                // ── Password History ──────────────────────────────
                if !isSecureNote {
                    passwordHistorySection
                }

                // ── Attachments ────────────────────────────────
                attachmentsSection

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
            Text("This entry will be moved to Trash. To permanently delete it, empty the Trash from Settings.")
        }
        .confirmationDialog(
            "Open Attachment",
            isPresented: $showingAttachmentWarning,
            titleVisibility: .visible
        ) {
            Button("Open") {
                if let name = attachmentToOpen { openAttachment(name) }
                attachmentToOpen = nil
            }
            Button("Cancel", role: .cancel) { attachmentToOpen = nil }
        } message: {
            Text("This will temporarily extract the file unencrypted to your system. The file will be deleted after 60 seconds. Continue?")
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
                        .foregroundStyle(.secondary)
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

                Button {
                    appState.largeTypeWindow.show(password: String(decoding: entry.password, as: UTF8.self))
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary)
                        .padding(6)
                        .background(Color.citadelSecondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Large Type")

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
                    appState.clipboard.copySecure(url)
                }
            }
        }
    }

    // MARK: - Notes Card

    @ViewBuilder
    private func notesCard(_ entry: VaultEntryDetail) -> some View {
        FieldCard(label: isSecureNote ? "Content" : "Notes") {
            HStack(alignment: .top, spacing: 10) {
                Text(entry.notes)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                copyButton {
                    appState.clipboard.copySecure(entry.notes)
                }
            }
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

    // MARK: - Seed Phrase Section

    private func seedWords(from entry: VaultEntryDetail) -> [(num: Int, word: String)] {
        entry.customFields
            .filter { $0.key.hasPrefix(EntryTemplate.seedWordPrefix) }
            .compactMap { field -> (num: Int, word: String)? in
                guard let n = Int(field.key.suffix(2)) else { return nil }
                return (n, field.value)
            }
            .filter { !$0.word.isEmpty }
            .sorted { $0.num < $1.num }
    }

    @ViewBuilder
    private func seedPhraseSection(_ entry: VaultEntryDetail) -> some View {
        let words = seedWords(from: entry)
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Seed Phrase (\(words.count) words)")
                    .padding(.top, 4)

                // Masked grid
                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(words, id: \.num) { item in
                        HStack(spacing: 4) {
                            Text("\(item.num)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.citadelSecondary)
                                .frame(width: 18, alignment: .trailing)
                            if revealedSeedWords.contains(item.num) {
                                Text(item.word)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                            } else {
                                Text(String(repeating: "\u{2022}", count: 5))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                if revealedSeedWords.contains(item.num) {
                                    revealedSeedWords.remove(item.num)
                                } else {
                                    revealedSeedWords.insert(item.num)
                                }
                            } label: {
                                Image(systemName: revealedSeedWords.contains(item.num) ? "eye.fill" : "eye")
                                    .font(.system(size: 9))
                                    .foregroundStyle(revealedSeedWords.contains(item.num) ? Color.citadelAccent : Color.citadelSecondary)
                            }
                            .buttonStyle(.plain)
                            Button {
                                appState.clipboard.copySecure(item.word)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.citadelSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 5)
                        .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        let phrase = words.map(\.word).joined(separator: " ")
                        appState.clipboard.copyPassword(Data(phrase.utf8))
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 12))
                            Text("Copy Full Seed Phrase")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.citadelAccent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingSeedWords = true
                        seedWordDismissTask?.cancel()
                        seedWordDismissTask = Task {
                            try? await Task.sleep(for: .seconds(30))
                            if !Task.isCancelled {
                                showingSeedWords = false
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "eye")
                                .font(.system(size: 12))
                            Text("Show All Words")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.citadelAccent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .sheet(isPresented: $showingSeedWords) {
                seedWordDismissTask?.cancel()
            } content: {
                seedWordsOverlay(words)
            }
        }
    }

    @ViewBuilder
    private func seedWordsOverlay(_ words: [(num: Int, word: String)]) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Seed Phrase")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("Auto-dismiss in 30s")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(words, id: \.num) { item in
                    HStack(spacing: 4) {
                        Text("\(item.num)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.citadelSecondary)
                            .frame(width: 22, alignment: .trailing)
                        Text(item.word)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
                }
            }

            Button("Dismiss") {
                showingSeedWords = false
                seedWordDismissTask?.cancel()
            }
            .buttonStyle(.borderedProminent)
            .tint(.citadelAccent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 500)
        .interactiveDismissDisabled(false)
    }

    // MARK: - Custom Fields

    @ViewBuilder
    private func customFieldsSection(_ entry: VaultEntryDetail) -> some View {
        let fields = isCryptoSeedType
            ? entry.customFields.filter { !$0.key.hasPrefix(EntryTemplate.seedWordPrefix) }
            : entry.customFields

        if !fields.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Custom Fields")
                    .padding(.top, 4)

                ForEach(fields) { field in
                    FieldCard(label: field.key) {
                        HStack(spacing: 10) {
                            Image(systemName: field.isProtected ? "lock" : "text.alignleft")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.citadelSecondary)
                                .frame(width: 20)

                            if field.isProtected && !revealedFieldKeys.contains(field.key) {
                                Text(String(repeating: "\u{2022}", count: 8))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary.opacity(0.6))
                            } else {
                                Text(field.value)
                                    .font(.system(size: 13, design: field.isProtected ? .monospaced : .default))
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }

                            Spacer()

                            if field.isProtected {
                                Button {
                                    if revealedFieldKeys.contains(field.key) {
                                        revealedFieldKeys.remove(field.key)
                                    } else {
                                        revealedFieldKeys.insert(field.key)
                                    }
                                } label: {
                                    Image(systemName: revealedFieldKeys.contains(field.key) ? "eye.fill" : "eye")
                                        .font(.system(size: 12))
                                        .foregroundStyle(revealedFieldKeys.contains(field.key) ? Color.citadelAccent : Color.citadelSecondary)
                                        .padding(6)
                                        .background(Color.citadelSecondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Reveal")
                            }

                            copyButton {
                                appState.clipboard.copySecure(field.value)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tags Section

    @ViewBuilder
    private func tagsSection(_ tagsString: String) -> some View {
        let tags = tagsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Tags")
                .padding(.top, 4)
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.teal, in: Capsule())
                }
            }
        }
    }

    // MARK: - Password History

    @ViewBuilder
    private var passwordHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showPasswordHistory.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showPasswordHistory ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    SectionHeader(title: "Password History (\(passwordHistory.count))")
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            if showPasswordHistory {
                if passwordHistory.isEmpty {
                    Text("No previous passwords recorded")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                }
                ForEach(Array(passwordHistory.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 10) {
                        Text(String(repeating: "\u{2022}", count: 12))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.6))
                            .lineLimit(1)

                        Spacer()

                        Text(item.date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        copyButton {
                            appState.clipboard.copyPassword(Data(item.password.utf8))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
                }
            }
        }
    }

    // MARK: - Attachments Section

    @ViewBuilder
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    showAttachments.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showAttachments ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        SectionHeader(title: "Attachments (\(attachments.count))")
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showingAttachmentPicker = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.citadelAccent)
                }
                .buttonStyle(.plain)
                .help("Add attachment")
                .fileImporter(isPresented: $showingAttachmentPicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                    guard case .success(let urls) = result, let url = urls.first else { return }
                    addAttachment(from: url)
                }
            }

            if showAttachments {
                ForEach(attachments, id: \.name) { att in
                    HStack(spacing: 10) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.citadelSecondary)

                        Text(att.name)
                            .font(.system(size: 13))
                            .lineLimit(1)

                        Spacer()

                        Text(formatBytes(att.size))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Button {
                            attachmentToOpen = att.name
                            showingAttachmentWarning = true
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.citadelAccent)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Save to disk")

                        Button(role: .destructive) {
                            deleteAttachment(att.name)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.citadelDanger)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Remove attachment")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
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
                    .foregroundStyle(.tertiary)
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
        showPasswordHistory = false
        revealedFieldKeys.removeAll()
        revealedSeedWords.removeAll()
        do {
            entry = try appState.engine.getEntry(uuid: entryID)
            passwordHistory = (try? appState.engine.getEntryHistory(uuid: entryID)) ?? []
            attachments = (try? appState.engine.listAttachments(uuid: entryID)) ?? []
            errorMessage = nil
        } catch {
            entry = nil
            passwordHistory = []
            attachments = []
            errorMessage = "Could not load entry"
        }
    }

    private func copyUsername(_ username: String) {
        appState.clipboard.copySecure(username)
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

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }

    private func addAttachment(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            try appState.engine.addAttachment(uuid: entryID, name: url.lastPathComponent, data: data)
            try appState.save()
            try appState.refreshEntries()
            attachments = (try? appState.engine.listAttachments(uuid: entryID)) ?? []
        } catch {
            errorMessage = "Could not add attachment"
        }
    }

    private func openAttachment(_ name: String) {
        do {
            let data = try appState.engine.getAttachment(uuid: entryID, name: name)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("smaug-attachments-\(UUID().uuidString)", isDirectory: true)
            // Guard against symlink attacks
            if FileManager.default.fileExists(atPath: tmpDir.path) {
                try FileManager.default.removeItem(at: tmpDir)
            }
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Sanitize attachment name to prevent path traversal
            let sanitized = name
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "..", with: "_")
                .replacingOccurrences(of: "\0", with: "")
            let fileURL = tmpDir.appendingPathComponent(sanitized)
            guard fileURL.standardizedFileURL.path.hasPrefix(tmpDir.standardizedFileURL.path + "/") else {
                errorMessage = "Invalid attachment name"
                return
            }
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            NSWorkspace.shared.open(fileURL)
            // Schedule cleanup after 10 seconds
            let dirToClean = tmpDir
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                try? FileManager.default.removeItem(at: dirToClean)
            }
        } catch {
            errorMessage = "Could not open attachment"
        }
    }

    private func deleteAttachment(_ name: String) {
        do {
            try appState.engine.removeAttachment(uuid: entryID, name: name)
            try appState.save()
            try appState.refreshEntries()
            attachments = (try? appState.engine.listAttachments(uuid: entryID)) ?? []
        } catch {
            errorMessage = "Could not remove attachment"
        }
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
