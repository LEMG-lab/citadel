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

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isSecureNote: Bool {
        entryType == "secure_note"
    }

    private var isSeedPhraseType: Bool {
        entryType == "seed_phrase" || entryType == "multi_chain_wallet"
    }

    private var isPrivateKeyType: Bool {
        entryType == "private_key"
    }

    private var isCryptoType: Bool {
        EntryTemplate.cryptoTypes.contains(entryType)
    }

    private var usesStandardFields: Bool {
        selectedTemplate.usesStandardFields
    }

    private var existingGroups: [String] {
        (try? appState.engine.listGroups()) ?? []
    }

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

                    if !isEditing {
                        folderSection
                    }

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

            if isPrivateKeyType {
                // Private Key uses the standard password field for the key
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.citadelSecondary)
                            .frame(width: 16)

                        if showPassword {
                            TextField(text: $password, prompt: Text("Private Key").foregroundStyle(.tertiary)) {}
                                .font(.system(size: 13, design: .monospaced))
                        } else {
                            SecureField(text: $password, prompt: Text("Private Key").foregroundStyle(.tertiary)) {}
                                .font(.system(size: 13))
                        }

                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.citadelSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
                }
            }

            if usesStandardFields {
                styledField("Username", text: $username, icon: "person")

                // Password field with strength bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.citadelSecondary)
                            .frame(width: 16)

                        if showPassword {
                            TextField(text: $password, prompt: Text("Password").foregroundStyle(.tertiary)) {}
                                .font(.system(size: 13, design: .monospaced))
                        } else {
                            SecureField(text: $password, prompt: Text("Password").foregroundStyle(.tertiary)) {}
                                .font(.system(size: 13))
                        }

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.citadelSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(showPassword ? "Hide" : "Show")

                        Button {
                            showingGenerator = true
                        } label: {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.citadelAccent)
                        }
                        .buttonStyle(.plain)
                        .help("Generate password")
                    }
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))

                    PasswordStrengthBar(password: password)
                        .padding(.horizontal, 2)
                }

                styledField("URL", text: $url, icon: "link")
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
                }
                .padding(10)
                .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
            }

            if !isSecureNote {
                styledField("TOTP URI (otpauth://...)", text: $otpURI, icon: "timer", monospaced: true)
            }
        }
    }

    // MARK: - Folder

    @ViewBuilder
    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Folder")

            Picker("Folder", selection: $group) {
                Text("Root (default)").tag("")
                ForEach(existingGroups, id: \.self) { g in
                    Text(g).tag(g)
                }
                Text("New folder\u{2026}").tag("__new__")
            }
            .labelsHidden()

            if group == "__new__" {
                styledField("Folder path (e.g. Work/Email)", text: $newGroupName, icon: "folder")
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

    // MARK: - Custom Fields

    private var seedWordFields: [Binding<EditableCustomField>] {
        $customFields.filter { $0.wrappedValue.key.hasPrefix(EntryTemplate.seedWordPrefix) }
    }

    private var nonSeedWordFields: [Binding<EditableCustomField>] {
        $customFields.filter { !$0.wrappedValue.key.hasPrefix(EntryTemplate.seedWordPrefix) }
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
                        HStack(spacing: 4) {
                            Text(num)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.citadelSecondary)
                                .frame(width: 18)
                            SecureField(text: $field.value, prompt: Text("").foregroundStyle(.tertiary)) {}
                                .font(.system(size: 12))
                                .textFieldStyle(.plain)
                        }
                        .padding(6)
                        .background(Color.cardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.subtleSeparator.opacity(0.3), lineWidth: 0.5))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var customFieldsSection: some View {
        if isSeedPhraseType {
            seedWordsSection
        }

        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Custom Fields")

            let fields = isSeedPhraseType ? nonSeedWordFields : Array($customFields)
            ForEach(fields) { $field in
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

    // MARK: - Styled Field

    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>, icon: String? = nil, monospaced: Bool = false) -> some View {
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
        if case .edit(let entry) = mode {
            title = entry.title
            username = entry.username
            password = String(decoding: entry.password, as: UTF8.self)
            url = entry.url
            notes = entry.notes
            otpURI = entry.otpURI
            entryType = entry.entryType.isEmpty ? "password" : entry.entryType
            if let exp = entry.expiryDate {
                hasExpiry = true
                expiryDate = exp
            }
            // Load tags from entry summary (Citadel_Tags is a standard field, not in customFields)
            if let summary = appState.entries.first(where: { $0.id == entry.uuid }) {
                tagsText = summary.tags
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
                try appState.save()
                try appState.refreshEntries()
            }
            dismiss()
        } catch {
            errorMessage = "Could not save entry"
        }
    }
}
