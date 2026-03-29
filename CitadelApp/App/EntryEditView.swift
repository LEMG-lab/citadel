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

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isSecureNote: Bool {
        entryType == "secure_note"
    }

    private var existingGroups: [String] {
        (try? appState.engine.listGroups()) ?? []
    }

    private var effectiveGroup: String {
        group == "__new__" ? newGroupName : group
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Entry" : "New Entry")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Entry type selector (new entries only)
                    if !isEditing {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(title: "Entry Type")
                            Picker("Type", selection: $entryType) {
                                Label("Password", systemImage: "key.fill").tag("password")
                                Label("Secure Note", systemImage: "note.text").tag("secure_note")
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Core fields
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Details")

                        styledField("Title", text: $title)

                        if !isSecureNote {
                            styledField("Username", text: $username)

                            // Password with show/generate
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
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
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.citadelAccent)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Generate password")
                                }
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                                PasswordStrengthBar(password: password)
                            }

                            styledField("URL", text: $url)
                        }

                        // Notes / Secure note content
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(
                                text: $notes,
                                prompt: Text(isSecureNote ? "Content" : "Notes").foregroundStyle(.tertiary),
                                axis: .vertical
                            ) {}
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .lineLimit(3...8)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }

                        if !isSecureNote {
                            styledField("TOTP URI (otpauth://...)", text: $otpURI, monospaced: true)
                        }
                    }

                    // Folder (new entries only)
                    if !isEditing {
                        VStack(alignment: .leading, spacing: 6) {
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
                                styledField("Folder path (e.g. Work/Email)", text: $newGroupName)
                            }
                        }
                    }

                    // Expiration
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Expiration")
                        Toggle("Set expiry date", isOn: $hasExpiry)
                            .font(.system(size: 13))
                        if hasExpiry {
                            DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                                .font(.system(size: 13))
                        }
                    }

                    // Custom Fields
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Custom Fields")

                        ForEach($customFields) { $field in
                            HStack(spacing: 6) {
                                // FIX: Use explicit prompt: parameter so placeholder clears properly
                                TextField(text: $field.key, prompt: Text("Name").foregroundStyle(.tertiary)) {}
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: 120)
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                                TextField(text: $field.value, prompt: Text("Value").foregroundStyle(.tertiary)) {}
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .padding(6)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                                Button {
                                    field.isProtected.toggle()
                                } label: {
                                    Image(systemName: field.isProtected ? "lock.fill" : "lock.open")
                                        .font(.system(size: 11))
                                        .foregroundStyle(field.isProtected ? Color.citadelAccent : Color.citadelSecondary)
                                }
                                .buttonStyle(.plain)
                                .help(field.isProtected ? "Protected" : "Not protected")

                                Button(role: .destructive) {
                                    customFields.removeAll { $0.id == field.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.citadelDanger.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button {
                            customFields.append(EditableCustomField(key: "", value: "", isProtected: false))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13))
                                Text("Add Field")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.citadelAccent)
                        }
                        .buttonStyle(.plain)
                    }

                    if let msg = errorMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12))
                            Text(msg).font(.system(size: 12))
                        }
                        .foregroundStyle(Color.citadelDanger)
                    }
                }
                .padding(20)
            }

            Divider()

            // Bottom bar
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.citadelAccent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 460, minHeight: 440)
        .onAppear { populateFields() }
        .sheet(isPresented: $showingGenerator) {
            PasswordGeneratorView { generated in
                password = generated
                showPassword = true
            }
        }
    }

    // MARK: - Styled Field

    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        TextField(text: text, prompt: Text(placeholder).foregroundStyle(.tertiary)) {}
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: monospaced ? .monospaced : .default))
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                if entryType == "secure_note" {
                    try appState.engine.setCustomField(
                        uuid: uuid, key: "Citadel_EntryType",
                        value: "secure_note", isProtected: false
                    )
                }
                for field in customFields where !field.key.isEmpty {
                    try appState.engine.setCustomField(
                        uuid: uuid, key: field.key,
                        value: field.value, isProtected: field.isProtected
                    )
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
                let newKeys = Set(customFields.filter { !$0.key.isEmpty }.map(\.key))
                for old in entry.customFields {
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
                try appState.save()
                try appState.refreshEntries()
            }
            dismiss()
        } catch {
            errorMessage = "Could not save entry"
        }
    }
}
