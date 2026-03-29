import SwiftUI
import CitadelCore

/// Application settings sheet.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showingPasswordChange = false
    @State private var showingRecoverySheet = false

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
                }

                Section("Recovery") {
                    Button("Print Recovery Sheet") {
                        showingRecoverySheet = true
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
    }
}
