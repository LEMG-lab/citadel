import SwiftUI

/// Lock screen — master password entry and vault creation.
struct LockScreenView: View {
    @Environment(AppState.self) private var appState

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isCreating = false
    @State private var showCreateConfirmation = false
    @State private var errorMessage: String?
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
                errorMessage = nil
            }
            Button("Create Vault") { requestCreate() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || confirmPassword.isEmpty)
        }
    }

    // MARK: - Actions

    private func unlock() {
        errorMessage = nil
        do {
            try appState.unlock(password: Data(password.utf8))
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

    private func doCreate() {
        do {
            try appState.createVault(password: Data(password.utf8))
            password = ""
            confirmPassword = ""
        } catch {
            errorMessage = "Could not create vault"
            password = ""
            confirmPassword = ""
        }
    }
}
