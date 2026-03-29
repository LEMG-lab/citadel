import SwiftUI
import CitadelCore

/// Mode for the entry editor.
enum EntryEditMode {
    case add
    case edit(VaultEntryDetail)
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
    @State private var expiryDate = Date().addingTimeInterval(90 * 24 * 3600) // default 90 days
    @State private var showingGenerator = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingGroups: [String] {
        (try? appState.engine.listGroups()) ?? []
    }

    private var effectiveGroup: String {
        group == "__new__" ? newGroupName : group
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Username", text: $username)
                    HStack {
                        if showPassword {
                            TextField("Password", text: $password)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("Password", text: $password)
                        }
                        Button(showPassword ? "Hide" : "Show") {
                            showPassword.toggle()
                        }
                        .buttonStyle(.borderless)
                        Button("Generate") {
                            showingGenerator = true
                        }
                        .buttonStyle(.borderless)
                    }
                    PasswordStrengthBar(password: password)
                    TextField("URL", text: $url)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("TOTP URI (otpauth://...)", text: $otpURI)
                        .font(.system(.body, design: .monospaced))
                }

                if !isEditing {
                    Section("Folder") {
                        Picker("Folder", selection: $group) {
                            Text("Root (default)").tag("")
                            ForEach(existingGroups, id: \.self) { g in
                                Text(g).tag(g)
                            }
                            Text("New folder...").tag("__new__")
                        }
                        if group == "__new__" {
                            TextField("Folder path (e.g. Work/Email)", text: $newGroupName)
                        }
                    }
                }

                Section("Expiration") {
                    Toggle("Set expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expires on", selection: $expiryDate, displayedComponents: .date)
                    }
                }

                if let msg = errorMessage {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 440, minHeight: 360)
        .onAppear { populateFields() }
        .sheet(isPresented: $showingGenerator) {
            PasswordGeneratorView { generated in
                password = generated
                showPassword = true
            }
        }
    }

    private func populateFields() {
        if case .edit(let entry) = mode {
            title = entry.title
            username = entry.username
            password = String(decoding: entry.password, as: UTF8.self)
            url = entry.url
            notes = entry.notes
            otpURI = entry.otpURI
            if let exp = entry.expiryDate {
                hasExpiry = true
                expiryDate = exp
            }
        }
    }

    private func save() {
        errorMessage = nil
        do {
            let pwData = Data(password.utf8)
            let expiry: Date? = hasExpiry ? expiryDate : nil
            switch mode {
            case .add:
                let uuid = try appState.engine.addEntry(
                    title: title, username: username,
                    password: pwData, url: url, notes: notes,
                    otpURI: otpURI, group: effectiveGroup,
                    expiryDate: expiry
                )
                try appState.save()
                try appState.refreshEntries()
                appState.selectedEntryID = uuid
            case .edit(let entry):
                try appState.engine.updateEntry(
                    uuid: entry.uuid, title: title, username: username,
                    password: pwData, url: url, notes: notes,
                    otpURI: otpURI, expiryDate: expiry
                )
                try appState.save()
                try appState.refreshEntries()
            }
            dismiss()
        } catch {
            errorMessage = "Could not save entry"
        }
    }
}
