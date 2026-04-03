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
    @State private var biometricAttempted = false
    @State private var showingEmergencyOpen = false
    @State private var emergencyPassword = ""
    @State private var emergencyVaultPassword = ""
    @State private var emergencyMessage: String?
    @State private var showResetConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case password
        case confirm
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [Color.citadelAccent.opacity(0.04), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Dragon sigil
                DragonIcon(size: 64)
                    .padding(.bottom, 14)

                // App name
                Text("Smaug")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                Text("by Luis Maumejean G.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                // Vault name
                if let vault = appState.knownVaults.first(where: { $0.path == appState.vaultPath }) {
                    Text(vault.name)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                // Subtitle
                Text(isCreating ? "Create a new vault" : "Enter your master password")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.citadelSecondary)
                    .padding(.top, 4)
                    .padding(.bottom, 28)

                // Vault picker
                if appState.knownVaults.count > 1 {
                    Picker("", selection: Binding(
                        get: { appState.vaultPath },
                        set: { newPath in
                            if let vault = appState.knownVaults.first(where: { $0.path == newPath }) {
                                appState.switchVault(to: vault)
                                password = ""
                                errorMessage = nil
                            }
                        }
                    )) {
                        ForEach(appState.knownVaults) { vault in
                            Text(vault.name).tag(vault.path)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .padding(.bottom, 8)
                }

                // Form content
                VStack(spacing: 14) {
                    if isCreating {
                        createFields
                    } else {
                        unlockFields
                    }
                }
                .frame(width: 340)

                Spacer()

                // Version
                Text("v1.5")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.citadelTertiary)
                    .padding(.bottom, 20)
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
        .alert(
            "Reset Vault",
            isPresented: $showResetConfirmation
        ) {
            Button("Delete Everything", role: .destructive) { resetVault() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the current vault and all its data. You will start fresh with a new vault.\n\nThis cannot be undone.")
        }
    }

    // MARK: - Unlock Fields

    @ViewBuilder
    private var unlockFields: some View {
        SecureField(text: $password, prompt: Text("Master Password")) {}
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            HStack(spacing: 5) {
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
                .frame(height: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(.citadelAccent)
        .keyboardShortcut(.defaultAction)
        .disabled(password.isEmpty || appState.isLoading)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        if appState.biometricEnrolled && appState.vaultExists {
            Button(action: unlockWithBiometrics) {
                HStack(spacing: 8) {
                    Image(systemName: "touchid")
                        .font(.system(size: 22))
                    Text("Unlock with Touch ID")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.citadelAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(appState.isLoading)
        }

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

        if appState.vaultExists {
            Button("Forgot password? Reset vault") {
                showResetConfirmation = true
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.citadelTertiary)
            .buttonStyle(.plain)
        }

        Divider()
            .padding(.vertical, 4)

        Button("Open Emergency File\u{2026}") { openEmergencyFile() }
            .font(.system(size: 13))
            .foregroundStyle(Color.citadelDanger)
            .buttonStyle(.plain)

        if showingEmergencyOpen {
            emergencyOpenFields
        }
    }

    // MARK: - Create Fields

    @ViewBuilder
    private var createFields: some View {
        SecureField(text: $password, prompt: Text("Master Password")) {}
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.citadelAccent.opacity(focusedField == .password ? 0.6 : 0), lineWidth: 1.5)
            )
            .focused($focusedField, equals: .password)
            .onAppear { focusedField = .password }

        SecureField(text: $confirmPassword, prompt: Text("Confirm Password")) {}
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.citadelAccent.opacity(focusedField == .confirm ? 0.6 : 0), lineWidth: 1.5)
            )
            .focused($focusedField, equals: .confirm)
            .onSubmit { requestCreate() }

        keyfileRow

        if let msg = errorMessage {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                Text(msg).font(.system(size: 12))
            }
            .foregroundStyle(Color.citadelDanger)
        }

        HStack(spacing: 12) {
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
                    .frame(height: 40)
            }
            .buttonStyle(.borderedProminent)
            .tint(.citadelAccent)
            .keyboardShortcut(.defaultAction)
            .disabled(password.isEmpty || confirmPassword.isEmpty || appState.isLoading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    // MARK: - Emergency Open

    @ViewBuilder
    private var emergencyOpenFields: some View {
        VStack(spacing: 8) {
            SecureField(text: $emergencyPassword, prompt: Text("Emergency Password")) {}
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            SecureField(text: $emergencyVaultPassword, prompt: Text("Vault Master Password")) {}
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onSubmit { doEmergencyOpen() }

            if let msg = emergencyMessage {
                Text(msg).font(.system(size: 11)).foregroundStyle(Color.citadelDanger)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showingEmergencyOpen = false
                    emergencyPassword = ""
                    emergencyVaultPassword = ""
                    emergencyMessage = nil
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.citadelSecondary)
                .buttonStyle(.plain)

                Button(action: doEmergencyOpen) {
                    Text("Open")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.citadelDanger)
                .disabled(emergencyPassword.isEmpty || emergencyVaultPassword.isEmpty)
            }
        }
    }

    @State private var emergencyFilePath: String?

    private func openEmergencyFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Emergency File"
        panel.allowedContentTypes = [.init(filenameExtension: "ctdl-emergency") ?? .data]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        emergencyFilePath = url.path
        showingEmergencyOpen = true
        emergencyPassword = ""
        emergencyVaultPassword = ""
        emergencyMessage = nil
    }

    private func doEmergencyOpen() {
        guard let filePath = emergencyFilePath else { return }
        emergencyMessage = nil
        do {
            let result = try EmergencyAccess.openToTempFile(
                at: URL(fileURLWithPath: filePath),
                emergencyPassword: emergencyPassword
            )
            if result.isLegacyFormat {
                emergencyMessage = "Warning: This file uses weak encryption (v1). Please re-export it using the current version for stronger protection."
            }
            let pw = Data(emergencyVaultPassword.utf8)
            emergencyPassword = ""
            emergencyVaultPassword = ""
            Task {
                do {
                    try await appState.unlockAsync(password: pw, vaultPathOverride: result.path)
                    showingEmergencyOpen = false
                } catch {
                    emergencyMessage = "Could not open vault — check both passwords"
                }
            }
        } catch {
            emergencyMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func resetVault() {
        appState.resetCurrentVault()
        password = ""
        confirmPassword = ""
        keyfilePath = nil
        errorMessage = nil
        isCreating = false
        focusedField = .password
    }

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

    private func unlockWithBiometrics() {
        errorMessage = nil
        Task {
            do {
                try await appState.unlockWithBiometrics()
            } catch {
                errorMessage = "Touch ID failed \u{2014} enter password manually"
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
