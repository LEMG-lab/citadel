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
        VStack(spacing: 16) {
            Text("Change Master Password")
                .font(.headline)

            SecureField("Current Password", text: $currentPassword)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .current)
            SecureField("New Password", text: $newPassword)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .new)
            SecureField("Confirm New Password", text: $confirmPassword)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .confirm)

            if let msg = errorMessage {
                Text(msg).foregroundStyle(.red).font(.callout)
            }

            if succeeded {
                Text("Password changed successfully. Remember to update your physical backups.")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            Divider()

            HStack {
                Spacer()
                if succeeded {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Change Password") { validate() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
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
