import SwiftUI
import UniformTypeIdentifiers

/// Lock screen — master password entry and vault creation.
struct LockScreenView: View {
    @Environment(AppState.self) private var appState

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isCreating = false
    @State private var showCreateConfirmation = false
    @State private var errorMessage: String?
    @State private var keyfilePath: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case password
        case confirm
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Citadel")
                .font(.largeTitle.weight(.semibold))

            if isCreating {
                createView
            } else {
                unlockView
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: 320)
        .confirmationDialog(
            "Create New Vault",
            isPresented: $showCreateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Create") { doCreate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a new vault at \(appState.vaultPath)?")
        }
    }

    // MARK: - Unlock

    @ViewBuilder
    private var unlockView: some View {
        SecureField("Master Password", text: $password)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .password)
            .onSubmit { unlock() }
            .onAppear { focusedField = .password }

        keyfileRow

        if let msg = errorMessage {
            Text(msg)
                .foregroundStyle(.red)
                .font(.callout)
        }

        Button("Unlock") { unlock() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(password.isEmpty)

        if !appState.vaultExists {
            Divider().frame(width: 200)
            Button("Create New Vault") {
                isCreating = true
                password = ""
                confirmPassword = ""
                errorMessage = nil
                focusedField = .password
            }
            Button("Import Existing Vault") {
                importVault()
            }
        }
    }

    // MARK: - Create

    @ViewBuilder
    private var createView: some View {
        SecureField("Master Password", text: $password)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .password)
            .onAppear { focusedField = .password }

        SecureField("Confirm Password", text: $confirmPassword)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .confirm)
            .onSubmit { requestCreate() }

        keyfileRow

        if let msg = errorMessage {
            Text(msg)
                .foregroundStyle(.red)
                .font(.callout)
        }

        HStack(spacing: 12) {
            Button("Cancel") {
                isCreating = false
                password = ""
                confirmPassword = ""
                keyfilePath = nil
                errorMessage = nil
            }
            Button("Create Vault") { requestCreate() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || confirmPassword.isEmpty)
        }
    }

    // MARK: - Keyfile

    @ViewBuilder
    private var keyfileRow: some View {
        HStack {
            if let path = keyfilePath {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                Text((path as NSString).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Button(role: .destructive) {
                    keyfilePath = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button("Add Key File…") { selectKeyfile() }
                    .font(.callout)
            }
        }
    }

    private func selectKeyfile() {
        let panel = NSOpenPanel()
        panel.title = "Select Key File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        keyfilePath = url.path
    }

    // MARK: - Actions

    private func unlock() {
        errorMessage = nil
        do {
            try appState.unlock(password: Data(password.utf8), keyfilePath: keyfilePath)
            password = ""
        } catch {
            errorMessage = "Could not open vault"
            password = ""
        }
    }

    private func requestCreate() {
        guard !password.isEmpty else {
            errorMessage = "Password cannot be empty"
            return
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        showCreateConfirmation = true
    }

    private func importVault() {
        let panel = NSOpenPanel()
        panel.title = "Select Vault File"
        panel.allowedContentTypes = [.init(filenameExtension: "kdbx")!]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try appState.importVault(from: url)
            errorMessage = nil
            focusedField = .password
        } catch {
            errorMessage = "Could not import vault file"
        }
    }

    private func doCreate() {
        do {
            try appState.createVault(password: Data(password.utf8), keyfilePath: keyfilePath)
            password = ""
            confirmPassword = ""
        } catch {
            errorMessage = "Could not create vault"
            password = ""
            confirmPassword = ""
        }
    }
}
