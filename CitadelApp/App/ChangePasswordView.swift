import SwiftUI
import CitadelCore

/// Master password change flow with confirmation.
struct ChangePasswordView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var showingConfirmation = false
    @State private var succeeded = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case current, new, confirm
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Change Master Password")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Current")
                SecureField(text: $currentPassword, prompt: Text("Current Password").foregroundStyle(.tertiary)) {}
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .focused($focusedField, equals: .current)

                SectionHeader(title: "New Password")
                SecureField(text: $newPassword, prompt: Text("New Password").foregroundStyle(.tertiary)) {}
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .focused($focusedField, equals: .new)

                SecureField(text: $confirmPassword, prompt: Text("Confirm New Password").foregroundStyle(.tertiary)) {}
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .focused($focusedField, equals: .confirm)

                if let msg = errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                        Text(msg).font(.system(size: 12))
                    }
                    .foregroundStyle(Color.citadelDanger)
                }

                if succeeded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Password changed successfully. Remember to update your physical backups.")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color.citadelSuccess)
                }
            }
            .padding(20)

            Spacer()
            Divider()

            HStack {
                Spacer()
                if succeeded {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(.citadelAccent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Change Password") { validate() }
                        .buttonStyle(.borderedProminent)
                        .tint(.citadelAccent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 360)
        .onAppear { focusedField = .current }
        .confirmationDialog(
            "Change Master Password",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Change Password") { doChange() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will change the master password for your vault. A backup will be created automatically.")
        }
    }

    private func validate() {
        errorMessage = nil
        guard !newPassword.isEmpty else {
            errorMessage = "Password cannot be empty"
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "New passwords do not match"
            return
        }
        showingConfirmation = true
    }

    private func doChange() {
        do {
            try appState.changePassword(
                currentPassword: Data(currentPassword.utf8),
                newPassword: Data(newPassword.utf8)
            )
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            errorMessage = nil
            succeeded = true
        } catch VaultError.wrongPassword {
            errorMessage = "Current password is incorrect"
        } catch {
            errorMessage = "Could not change password"
        }
    }
}
