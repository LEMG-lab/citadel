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
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case password
        case confirm
    }

    var body: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [Color.citadelAccent.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Shield icon
                Image(systemName: "shield.lock.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.citadelAccent)
                    .padding(.bottom, 12)

                Text("Citadel")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(isCreating ? "Create a new vault" : "Enter your master password")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.citadelSecondary)
                    .padding(.top, 2)
                    .padding(.bottom, 28)

                // Form content
                VStack(spacing: 14) {
                    if isCreating {
                        createFields
                    } else {
                        unlockFields
                    }
                }
                .frame(width: 280)

                Spacer()

                Text("v1.3")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.citadelSecondary.opacity(0.5))
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Unlock Fields

    @ViewBuilder
    private var unlockFields: some View {
        SecureField(text: $password, prompt: Text("Master Password")) {}
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.citadelAccent.opacity(focusedField == .password ? 0.6 : 0), lineWidth: 1.5)
            )
            .focused($focusedField, equals: .password)
            .onSubmit { unlock() }
            .onAppear { focusedField = .password }
            .disabled(appState.isLoading)

        keyfileRow

        if appState.isLoading {
            ProgressView()
                .controlSize(.small)
                .padding(.vertical, 4)
        }

        if let msg = errorMessage {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                Text(msg)
                    .font(.system(size: 12))
            }
            .foregroundStyle(Color.citadelDanger)
        }

        Button(action: unlock) {
            Text("Unlock")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.citadelAccent)
        .keyboardShortcut(.defaultAction)
        .disabled(password.isEmpty || appState.isLoading)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        if !appState.vaultExists {
            Divider()
                .padding(.vertical, 4)
            Button("Create New Vault") {
                isCreating = true
                password = ""
                confirmPassword = ""
                errorMessage = nil
                focusedField = .password
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.citadelAccent)
            .buttonStyle(.plain)

            Button("Import Existing Vault") { importVault() }
                .font(.system(size: 13))
                .foregroundStyle(Color.citadelSecondary)
                .buttonStyle(.plain)
        }
    }

    // MARK: - Create Fields

    @ViewBuilder
    private var createFields: some View {
        SecureField(text: $password, prompt: Text("Master Password")) {}
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.citadelAccent.opacity(focusedField == .password ? 0.6 : 0), lineWidth: 1.5)
            )
            .focused($focusedField, equals: .password)
            .onAppear { focusedField = .password }

        SecureField(text: $confirmPassword, prompt: Text("Confirm Password")) {}
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.citadelAccent.opacity(focusedField == .confirm ? 0.6 : 0), lineWidth: 1.5)
            )
            .focused($focusedField, equals: .confirm)
            .onSubmit { requestCreate() }

        keyfileRow

        if let msg = errorMessage {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                Text(msg).font(.system(size: 12))
            }
            .foregroundStyle(Color.citadelDanger)
        }

        HStack(spacing: 10) {
            Button("Cancel") {
                isCreating = false
                password = ""
                confirmPassword = ""
                keyfilePath = nil
                errorMessage = nil
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.citadelSecondary)
            .font(.system(size: 13))

            Button(action: requestCreate) {
                Text("Create Vault")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.citadelAccent)
            .keyboardShortcut(.defaultAction)
            .disabled(password.isEmpty || confirmPassword.isEmpty || appState.isLoading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Keyfile

    @ViewBuilder
    private var keyfileRow: some View {
        HStack(spacing: 6) {
            if let path = keyfilePath {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.citadelSecondary)
                Text((path as NSString).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(Color.citadelSecondary)
                    .font(.system(size: 12))
                Button(role: .destructive) { keyfilePath = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    selectKeyfile()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "key")
                            .font(.system(size: 11))
                        Text("Add Key File\u{2026}")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.citadelSecondary)
                }
                .buttonStyle(.plain)
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
