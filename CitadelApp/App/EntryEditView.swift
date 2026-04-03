import SwiftUI
import CitadelCore

/// Mode for the entry editor.
enum EntryEditMode {
    case add
    case edit(VaultEntryDetail)
}

/// Editable custom field model.
struct EditableCustomField: Identifiable {
    let id = UUID()
    var key: String
    var value: String
    var isProtected: Bool
}

/// Entry creation / editing sheet.
struct EntryEditView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let mode: EntryEditMode

    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var url = ""
    @State private var notes = ""
    @State private var otpURI = ""
    @State private var group = ""
    @State private var originalGroup = ""
    @State private var newGroupName = ""
    @State private var hasExpiry = false
    @State private var expiryDate = Date().addingTimeInterval(90 * 24 * 3600)
    @State private var showingGenerator = false
    @State private var errorMessage: String?
    @State private var entryType = "password"
    @State private var customFields: [EditableCustomField] = []
    @State private var tagsText = ""
    @State private var selectedTemplate: EntryTemplate = .login
    @State private var templateApplied = false
    @State private var revealedFieldIDs: Set<UUID> = []

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isSecureNote: Bool {
        entryType == "secure_note"
    }

    private var isSeedPhraseType: Bool {
        entryType == "seed_phrase" || entryType == "multi_chain_wallet" || entryType == "crypto_wallet"
    }

    private var isCryptoType: Bool {
        EntryTemplate.cryptoTypes.contains(entryType)
    }

    private var usesStandardFields: Bool {
        selectedTemplate.usesStandardFields
    }

    @State private var existingGroups: [String] = []

    private var effectiveGroup: String {
        group == "__new__" ? newGroupName : group
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Title bar ───────────────────────────────────
            sheetHeader

            Divider()

            // ── Scrollable form ─────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !isEditing {
                        templatePicker
                    }

                    coreFieldsSection

                    folderSection

                    expirationSection
                    tagsSection
                    customFieldsSection

                    if let msg = errorMessage {
                        errorBanner(msg)
                    }
                }
                .padding(24)
            }

            Divider()

            // ── Footer buttons ──────────────────────────────
            sheetFooter
        }
        .frame(minWidth: 480, minHeight: 480)
        .onAppear { populateFields() }
        .sheet(isPresented: $showingGenerator) {
            PasswordGeneratorView { generated in
                password = generated
                showPassword = true
            }
        }
    }

    // MARK: - Sheet Header

    @ViewBuilder
    private var sheetHeader: some View {
        HStack {
            Text(isEditing ? "Edit Entry" : "New Entry")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.citadelTertiary)
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    // MARK: - Sheet Footer

    @ViewBuilder
    private var sheetFooter: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(action: save) {
                Text("Save")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.citadelAccent)
            .keyboardShortcut(.defaultAction)
            .disabled(title.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Template Picker

    @ViewBuilder
    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Template")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(EntryTemplate.allCases) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: template.icon)
                                    .font(.system(size: 18))
                                    .frame(width: 38, height: 38)
                                    .background(
                                        selectedTemplate == template
                                            ? Color.citadelAccent.opacity(0.15)
                                            : Color.citadelSecondary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(
                                                selectedTemplate == template ? Color.citadelAccent.opacity(0.4) : .clear,
                                                lineWidth: 1.5
                                            )
                                    )

                                Text(template.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(width: 74)
                            .foregroundStyle(selectedTemplate == template ? Color.citadelAccent : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Core Fields

    @ViewBuilder
    private var coreFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Details")

            styledField("Title", text: $title, icon: "character.cursor.ibeam")

            // Standard layout: username, password, URL
            if usesStandardFields {
                styledField("Username", text: $username, icon: "person", copyAction: username.isEmpty ? nil : { appState.clipboard.copySecure(username) })
                passwordFieldView(placeholder: "Password")
                styledField("URL", text: $url, icon: "link", copyAction: url.isEmpty ? nil : { appState.clipboard.copySecure(url) })
            }

            // Crypto wallet layout: template fields → seed words → passphrase → notes → TOTP → URL
            if isCryptoType && !usesStandardFields {
                cryptoInlineFieldsView

                if isSeedPhraseType {
                    seedWordsSection
                }

                passwordFieldView(placeholder: "Wallet Passphrase")
            }

            // Notes / secure note content
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isSecureNote ? "note.text" : "text.alignleft")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.citadelSecondary)
                        .frame(width: 16)
                        .padding(.top, 4)

                    TextField(
                        text: $notes,
                        prompt: Text(isSecureNote ? "Content" : "Notes").foregroundStyle(.tertiary),
                        axis: .vertical
                    ) {}
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(3...10)

                    if !notes.isEmpty {
                        editCopyButton { appState.clipboard.copySecure(notes) }
                    }
                }
                .padding(10)
                .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
            }

            if !isSecureNote {
                styledField("TOTP URI (otpauth://...)", text: $otpURI, icon: "timer", monospaced: true)
            }

            // URL at end for crypto types
            if isCryptoType && !usesStandardFields {
                styledField("URL", text: $url, icon: "link", copyAction: url.isEmpty ? nil : { appState.clipboard.copySecure(url) })
            }
        }
    }

    // MARK: - Password Field

    @ViewBuilder
    private func passwordFieldView(placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.citadelSecondary)
                    .frame(width: 16)

                if showPassword {
                    TextField(text: $password, prompt: Text(placeholder).foregroundStyle(.tertiary)) {}
                        .font(.system(size: 13, design: .monospaced))
                } else {
                    SecureField(text: $password, prompt: Text(placeholder).foregroundStyle(.tertiary)) {}
                        .font(.system(size: 13))
                }

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary)
                }
                .buttonStyle(.plain)
                .help(showPassword ? "Hide" : "Show")

                Button { showingGenerator = true } label: {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.citadelAccent)
                }
                .buttonStyle(.plain)
                .help("Generate password")

                if !password.isEmpty {
                    editCopyButton { appState.clipboard.copyPassword(Data(password.utf8)) }
                }
            }
            .textFieldStyle(.plain)
            .padding(10)
            .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))

            PasswordStrengthBar(password: password)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Crypto Inline Fields

    @ViewBuilder
    private var cryptoInlineFieldsView: some View {
        let templateFieldKeys = selectedTemplate.fields
            .filter { !$0.key.hasPrefix(EntryTemplate.seedWordPrefix) }
            .map(\.key)
        ForEach(templateFieldKeys, id: \.self) { key in
            if let idx = customFields.firstIndex(where: { $0.key == key }) {
                if customFields[idx].isProtected {
                    protectedInlineField(index: idx, label: key)
                } else {
                    styledField(key, text: $customFields[idx].value, copyAction: customFields[idx].value.isEmpty ? nil : { appState.clipboard.copySecure(customFields[idx].value) })
                }
            }
        }
    }

    @ViewBuilder
    private func protectedInlineField(index: Int, label: String) -> some View {
        let fieldID = customFields[index].id
        let isRevealed = revealedFieldIDs.contains(fieldID)
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.citadelSecondary)
                .frame(width: 16)

            if isRevealed {
                TextField(text: $customFields[index].value, prompt: Text(label).foregroundStyle(.tertiary)) {}
                    .font(.system(size: 13, design: .monospaced))
            } else {
                SecureField(text: $customFields[index].value, prompt: Text(label).foregroundStyle(.tertiary)) {}
                    .font(.system(size: 13))
            }

            Button {
                if revealedFieldIDs.contains(fieldID) {
                    revealedFieldIDs.remove(fieldID)
                } else {
                    revealedFieldIDs.insert(fieldID)
                }
            } label: {
                Image(systemName: isRevealed ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.citadelSecondary)
            }
            .buttonStyle(.plain)

            if !customFields[index].value.isEmpty {
                editCopyButton { appState.clipboard.copyPassword(Data(customFields[index].value.utf8)) }
            }
        }
        .textFieldStyle(.plain)
        .padding(10)
        .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Project

    @ViewBuilder
    private var projectLabel: String {
        if group.isEmpty { return "Root (default)" }
        if group == "__new__" { return "New project\u{2026}" }
        return group
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Project")

            Menu {
                Button("Root (default)") { group = "" }
                ForEach(existingGroups, id: \.self) { g in
                    Button(g) { group = g }
                }
                Divider()
                Button("New project\u{2026}") { group = "__new__" }
            } label: {
                HStack {
                    Text(projectLabel)
                        .font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)

            if group == "__new__" {
                styledField("Project name (e.g. Work)", text: $newGroupName, icon: "folder")
            }
        }
    }

    // MARK: - Expiration

    @ViewBuilder
    private var expirationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Expiration")

            Toggle(isOn: $hasExpiry) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary)
                    Text("Set expiry date")
                        .font(.system(size: 13))
                }
            }

            if hasExpiry {
                DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                    .font(.system(size: 13))
                    .padding(.leading, 18)
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Tags")
            styledField("Comma-separated tags (e.g. work, finance)", text: $tagsText, icon: "tag")
            if !tagsText.isEmpty {
                let parsed = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                HStack(spacing: 6) {
                    ForEach(parsed, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.teal, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Seed Words & Custom Fields

    private var seedWordFields: [Binding<EditableCustomField>] {
        $customFields.filter { $0.wrappedValue.key.hasPrefix(EntryTemplate.seedWordPrefix) }
    }

    private var nonSeedWordFields: [Binding<EditableCustomField>] {
        $customFields.filter { !$0.wrappedValue.key.hasPrefix(EntryTemplate.seedWordPrefix) }
    }

    /// Custom fields not shown inline (for the custom fields section).
    private var visibleCustomFields: [Binding<EditableCustomField>] {
        if isCryptoType && !usesStandardFields {
            // Skip seed words and template-defined fields (shown inline in coreFieldsSection)
            let templateKeys = Set(selectedTemplate.fields.map(\.key))
            return $customFields.filter { !templateKeys.contains($0.wrappedValue.key) }
        } else if isSeedPhraseType {
            return nonSeedWordFields
        } else {
            return Array($customFields)
        }
    }

    @ViewBuilder
    private var seedWordsSection: some View {
        let words = seedWordFields
        if !words.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Seed Phrase Words")

                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(words) { $field in
                        let num = String(field.key.suffix(2))
                        let isRevealed = revealedFieldIDs.contains(field.id)
                        HStack(spacing: 3) {
                            Text(num)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.citadelSecondary)
                                .frame(width: 18)

                            if isRevealed {
                                TextField(text: $field.value, prompt: Text("").foregroundStyle(.tertiary)) {}
                                    .font(.system(size: 11))
                                    .textFieldStyle(.plain)
                            } else {
                                SecureField(text: $field.value, prompt: Text("").foregroundStyle(.tertiary)) {}
                                    .font(.system(size: 11))
                                    .textFieldStyle(.plain)
                            }

                            Button {
                                if revealedFieldIDs.contains(field.id) {
                                    revealedFieldIDs.remove(field.id)
                                } else {
                                    revealedFieldIDs.insert(field.id)
                                }
                            } label: {
                                Image(systemName: isRevealed ? "eye.slash" : "eye")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.citadelSecondary)
                            }
                            .buttonStyle(.plain)

                            if !field.value.isEmpty {
                                Button {
                                    appState.clipboard.copyPassword(Data(field.value.utf8))
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.citadelSecondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy")
                            }
                        }
                        .padding(5)
                        .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
                    }
                }

                // Copy Full Seed Phrase button
                let filledWords = words.map(\.wrappedValue).filter { !$0.value.isEmpty }
                if filledWords.count > 1 {
                    Button {
                        let phrase = filledWords
                            .sorted { $0.key < $1.key }
                            .map(\.value)
                            .joined(separator: " ")
                        appState.clipboard.copyPassword(Data(phrase.utf8))
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                            Text("Copy Full Seed Phrase")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color.citadelAccent)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var customFieldsSection: some View {
        // Seed words for non-crypto seed types (e.g. legacy entries not handled by crypto inline)
        if isSeedPhraseType && !(isCryptoType && !usesStandardFields) {
            seedWordsSection
        }

        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Custom Fields")

            ForEach(visibleCustomFields) { $field in
                HStack(spacing: 8) {
                    TextField(text: $field.key, prompt: Text("Name").foregroundStyle(.tertiary)) {}
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .frame(maxWidth: 130)
                        .padding(8)
                        .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))

                    TextField(text: $field.value, prompt: Text("Value").foregroundStyle(.tertiary)) {}
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(8)
                        .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))

                    if !field.value.isEmpty {
                        editCopyButton {
                            if field.isProtected {
                                appState.clipboard.copyPassword(Data(field.value.utf8))
                            } else {
                                appState.clipboard.copySecure(field.value)
                            }
                        }
                    }

                    Button {
                        field.isProtected.toggle()
                    } label: {
                        Image(systemName: field.isProtected ? "lock.fill" : "lock.open")
                            .font(.system(size: 12))
                            .foregroundStyle(field.isProtected ? Color.citadelAccent : Color.citadelSecondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(field.isProtected ? "Protected" : "Not protected")

                    Button(role: .destructive) {
                        customFields.removeAll { $0.id == field.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.citadelDanger.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Remove field")
                }
            }

            Button {
                customFields.append(EditableCustomField(key: "", value: "", isProtected: false))
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Add Field")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.citadelAccent)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
            Text(message)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.citadelDanger.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Copy Button

    @ViewBuilder
    private func editCopyButton(_ action: @escaping () -> Void) -> some View {
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

    // MARK: - Styled Field

    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>, icon: String? = nil, monospaced: Bool = false, copyAction: (() -> Void)? = nil) -> some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.citadelSecondary)
                    .frame(width: 16)
            }

            TextField(text: text, prompt: Text(placeholder).foregroundStyle(.tertiary)) {}
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: monospaced ? .monospaced : .default))

            if let copyAction {
                editCopyButton(copyAction)
            }
        }
        .padding(10)
        .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: - Template

    private func applyTemplate(_ template: EntryTemplate) {
        selectedTemplate = template
        entryType = template.typeString

        // Only set fields from template on first application or when switching templates
        if !templateApplied || true {
            customFields = template.fields.map {
                EditableCustomField(key: $0.key, value: "", isProtected: $0.isProtected)
            }
            templateApplied = true
        }
    }

    // MARK: - Data

    private func populateFields() {
        existingGroups = (try? appState.engine.listGroups()) ?? []
        if case .edit(let entry) = mode {
            title = entry.title
            username = entry.username
            password = String(decoding: entry.password, as: UTF8.self)
            url = entry.url
            notes = entry.notes
            otpURI = entry.otpURI
            entryType = entry.entryType.isEmpty ? "password" : entry.entryType
            // Set selectedTemplate based on entryType for correct form layout
            if EntryTemplate.cryptoTypes.contains(entryType) {
                selectedTemplate = .cryptoWallet
            } else if let template = EntryTemplate.allCases.first(where: { $0.typeString == entryType }) {
                selectedTemplate = template
            }
            if let exp = entry.expiryDate {
                hasExpiry = true
                expiryDate = exp
            }
            // Load tags and group from entry summary
            if let summary = appState.entries.first(where: { $0.id == entry.uuid }) {
                tagsText = summary.tags
                // Strip "Root/" prefix — group paths from the engine start with "Root/"
                let g = summary.group
                let stripped = g.hasPrefix("Root/") ? String(g.dropFirst(5)) : (g == "Root" ? "" : g)
                group = stripped
                originalGroup = stripped
            }
            customFields = entry.customFields.map {
                EditableCustomField(key: $0.key, value: $0.value, isProtected: $0.isProtected)
            }
        }
    }

    private func save() {
        errorMessage = nil
        do {
            let pwData = isSecureNote ? Data() : Data(password.utf8)
            let expiry: Date? = hasExpiry ? expiryDate : nil
            switch mode {
            case .add:
                let uuid = try appState.engine.addEntry(
                    title: title, username: isSecureNote ? "" : username,
                    password: pwData, url: isSecureNote ? "" : url, notes: notes,
                    otpURI: isSecureNote ? "" : otpURI, group: effectiveGroup,
                    expiryDate: expiry
                )
                if entryType != "password" && !entryType.isEmpty {
                    try appState.engine.setCustomField(
                        uuid: uuid, key: "Citadel_EntryType",
                        value: entryType, isProtected: false
                    )
                }
                for field in customFields where !field.key.isEmpty {
                    try appState.engine.setCustomField(
                        uuid: uuid, key: field.key,
                        value: field.value, isProtected: field.isProtected
                    )
                }
                // Save tags
                let cleanTags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ",")
                if !cleanTags.isEmpty {
                    try appState.engine.setCustomField(uuid: uuid, key: "Citadel_Tags", value: cleanTags, isProtected: false)
                }
                try appState.save()
                try appState.refreshEntries()
                appState.selectedEntryID = uuid
            case .edit(let entry):
                try appState.engine.updateEntry(
                    uuid: entry.uuid, title: title, username: username,
                    password: pwData, url: url, notes: notes,
                    otpURI: otpURI, expiryDate: expiry
                )
                // Sync entry type
                if entryType != "password" && !entryType.isEmpty {
                    try appState.engine.setCustomField(
                        uuid: entry.uuid, key: "Citadel_EntryType",
                        value: entryType, isProtected: false
                    )
                } else {
                    try appState.engine.removeCustomField(uuid: entry.uuid, key: "Citadel_EntryType")
                }
                let newKeys = Set(customFields.filter { !$0.key.isEmpty }.map(\.key))
                for old in entry.customFields where old.key != "Citadel_Tags" {
                    if !newKeys.contains(old.key) {
                        try appState.engine.removeCustomField(uuid: entry.uuid, key: old.key)
                    }
                }
                for field in customFields where !field.key.isEmpty {
                    try appState.engine.setCustomField(
                        uuid: entry.uuid, key: field.key,
                        value: field.value, isProtected: field.isProtected
                    )
                }
                // Save tags
                let editCleanTags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ",")
                if editCleanTags.isEmpty {
                    try appState.engine.removeCustomField(uuid: entry.uuid, key: "Citadel_Tags")
                } else {
                    try appState.engine.setCustomField(uuid: entry.uuid, key: "Citadel_Tags", value: editCleanTags, isProtected: false)
                }
                // Move entry if project changed
                if effectiveGroup != originalGroup {
                    try appState.engine.moveEntry(uuid: entry.uuid, toGroup: effectiveGroup)
                }
                try appState.save()
                try appState.refreshEntries()
            }
            dismiss()
        } catch {
            errorMessage = "Could not save entry"
        }
    }
}
