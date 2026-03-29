import SwiftUI
import UniformTypeIdentifiers
import CitadelCore

/// Lock screen — master password entry and vault creation.
struct LockScreenView: View {
    @Environment(AppState.self) private var appState

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isCreating = false
    @State private var showCreateConfirmation = false
    @State private var errorMessage: String?
    @State private var keyfilePath: String?
    @State private var attemptingBiometric = false
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
            .disabled(appState.isLoading)

        keyfileRow

        if appState.isLoading {
            ProgressView()
                .controlSize(.small)
        }

        if let msg = errorMessage {
            Text(msg)
                .foregroundStyle(.red)
                .font(.callout)
        }

        Button("Unlock") { unlock() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(password.isEmpty || appState.isLoading)

        if appState.biometricManager.isEnabled
            && appState.biometricManager.isAvailable
            && !appState.biometricManager.requiresFullAuth
            && appState.vaultExists {
            Button {
                attemptBiometricUnlock()
            } label: {
                Label("Unlock with Touch ID", systemImage: "touchid")
            }
            .disabled(attemptingBiometric)
        }

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
                .disabled(password.isEmpty || confirmPassword.isEmpty || appState.isLoading)
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
        let pw = Data(password.utf8)
        let kf = keyfilePath
        password = ""
        Task {
            do {
                try await appState.unlockAsync(password: pw, keyfilePath: kf)
            } catch {
                errorMessage = "Could not open vault"
            }
        }
    }

    private func attemptBiometricUnlock() {
        attemptingBiometric = true
        errorMessage = nil
        Task {
            do {
                let pw = try await appState.biometricManager.unlock()
                try await appState.unlockAsync(password: pw, keyfilePath: nil)
            } catch BiometricError.authFailed {
                errorMessage = "Touch ID failed"
            } catch BiometricError.fullAuthRequired {
                errorMessage = "Please enter your master password"
            } catch {
                errorMessage = "Could not open vault"
            }
            attemptingBiometric = false
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
        let pw = Data(password.utf8)
        let kf = keyfilePath
        password = ""
        confirmPassword = ""
        Task {
            do {
                try await appState.createVaultAsync(password: pw, keyfilePath: kf)
            } catch {
                errorMessage = "Could not create vault"
            }
        }
    }
}
