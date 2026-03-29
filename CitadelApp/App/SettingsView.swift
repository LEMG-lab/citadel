import SwiftUI
import CitadelCore

/// Application settings sheet.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showingPasswordChange = false
    @State private var showingRecoverySheet = false
    @State private var showingAuditLog = false
    @State private var touchIDError: String?
    @State private var enrollingTouchID = false
    @State private var selectedKdfPreset: KdfPreset = .saved
    @State private var showingKdfConfirmation = false
    @State private var kdfMessage: String?

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            Form {
                Section("Security") {
                    HStack {
                        Text("Auto-lock timeout")
                        Spacer()
                        Text("\(Int(appState.autoLockTimeout / 60)) min")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appState.autoLockTimeout, in: 60...1800, step: 60)

                    HStack {
                        Text("Clipboard clear time")
                        Spacer()
                        Text("\(Int(appState.clipboardClearTime)) sec")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appState.clipboardClearTime, in: 5...60, step: 5)

                    if appState.biometricManager.isAvailable {
                        Toggle("Unlock with Touch ID", isOn: Binding(
                            get: { appState.biometricManager.isEnabled },
                            set: { newValue in
                                if newValue {
                                    enrollTouchID()
                                } else {
                                    appState.biometricManager.unenroll()
                                }
                            }
                        ))
                        .disabled(enrollingTouchID)

                        if appState.biometricManager.isEnabled {
                            Text("Full password re-entry required every 72 hours.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let err = touchIDError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Vault") {
                    LabeledContent("Location") {
                        Text(appState.vaultPath)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .font(.callout)
                    }
                    Button("Change Master Password") {
                        showingPasswordChange = true
                    }

                    Picker("KDF Strength", selection: $selectedKdfPreset) {
                        ForEach(KdfPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .onChange(of: selectedKdfPreset) { _, newValue in
                        if newValue != .saved {
                            showingKdfConfirmation = true
                        }
                    }

                    if let msg = kdfMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.contains("failed") ? .red : .green)
                    }
                }

                Section("Recovery") {
                    Button("Print Recovery Sheet") {
                        showingRecoverySheet = true
                    }
                }

                Section("Audit") {
                    Button("View Audit Log") {
                        showingAuditLog = true
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .sheet(isPresented: $showingPasswordChange) {
            ChangePasswordView()
        }
        .sheet(isPresented: $showingRecoverySheet) {
            RecoverySheetView()
        }
        .sheet(isPresented: $showingAuditLog) {
            AuditLogView()
        }
        .confirmationDialog(
            "Change KDF Strength",
            isPresented: $showingKdfConfirmation,
            titleVisibility: .visible
        ) {
            Button("Re-encrypt Vault") { applyKdfChange() }
            Button("Cancel", role: .cancel) {
                selectedKdfPreset = .saved
            }
        } message: {
            Text("This will re-encrypt your vault with \(selectedKdfPreset.label) KDF parameters. This may take a moment.")
        }
    }

    private func applyKdfChange() {
        do {
            try appState.applyKdfPreset(selectedKdfPreset)
            kdfMessage = "KDF updated to \(selectedKdfPreset.label)."
        } catch {
            kdfMessage = "KDF change failed."
            selectedKdfPreset = .saved
        }
    }

    private func enrollTouchID() {
        enrollingTouchID = true
        touchIDError = nil
        Task {
            do {
                guard let pw = appState.currentPasswordForBiometric else {
                    touchIDError = "Password not available. Lock and unlock first."
                    enrollingTouchID = false
                    return
                }
                try await appState.biometricManager.enroll(password: pw)
            } catch BiometricError.notAvailable {
                touchIDError = "Touch ID is not available on this device."
            } catch BiometricError.authFailed {
                touchIDError = "Touch ID verification failed."
            } catch {
                touchIDError = "Could not enable Touch ID."
            }
            enrollingTouchID = false
        }
    }
}
