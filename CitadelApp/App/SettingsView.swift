import SwiftUI
import UniformTypeIdentifiers
import CitadelCore

/// Application settings sheet — iOS Settings-style layout with icon badges,
/// grouped sections, and adaptive appearance controls.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appearanceMode) private var appearanceMode

    @State private var showingPasswordChange = false
    @State private var showingRecoverySheet = false
    @State private var showingAuditLog = false
    @State private var showingPasswordHealth = false
    @State private var selectedKdfPreset: KdfPreset = .saved
    @State private var showingKdfConfirmation = false
    @State private var kdfMessage: String?
    @State private var showingEmptyRecycleBin = false
    @State private var recycleBinMessage: String?
    @State private var dataResultMessage: String?
    @State private var showingDataResult = false
    @State private var biometricMessage: String?
    @State private var showingEmergencyExport = false
    @State private var emergencyPassword = ""
    @State private var emergencyConfirm = ""
    @State private var emergencyMessage: String?
    @State private var showingAbout = false
    @State private var showingCSVExportWarning = false

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                settingsAllSections(appState: $appState)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.citadelAccent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 500, minHeight: 500)
        .sheet(isPresented: $showingPasswordChange) { ChangePasswordView() }
        .sheet(isPresented: $showingRecoverySheet) { RecoverySheetView() }
        .sheet(isPresented: $showingAuditLog) { AuditLogView() }
        .sheet(isPresented: $showingPasswordHealth) { PasswordHealthView() }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .onChange(of: selectedKdfPreset) { _, newValue in
            if newValue != .saved { showingKdfConfirmation = true }
        }
        .confirmationDialog("Change KDF Strength", isPresented: $showingKdfConfirmation, titleVisibility: .visible) {
            Button("Re-encrypt Vault") { applyKdfChange() }
            Button("Cancel", role: .cancel) { selectedKdfPreset = .saved }
        } message: {
            Text("This will re-encrypt your vault with \(selectedKdfPreset.label) KDF parameters.")
        }
        .alert("Data Operation", isPresented: $showingDataResult) { Button("OK") {} } message: { Text(dataResultMessage ?? "") }
        .confirmationDialog("Export Passwords", isPresented: $showingCSVExportWarning, titleVisibility: .visible) {
            Button("Export Anyway", role: .destructive) { exportCSV() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WARNING: This will export ALL your passwords in plaintext. The file will NOT be encrypted. Do not save to cloud-synced folders.")
        }
        .confirmationDialog("Empty Recycle Bin", isPresented: $showingEmptyRecycleBin, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) { emptyRecycleBin() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All entries in the Recycle Bin will be permanently deleted. This cannot be undone.")
        }
    }

    // MARK: - All Sections

    @ViewBuilder
    private func settingsAllSections(appState: Bindable<AppState>) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            appearanceSection
            securitySection(appState: appState)
            vaultSection
            recycleBinSection
            dataSection
            emergencySection
            auditSection
            aboutSection
        }
        .padding(20)
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        settingsSection("Appearance") {
            settingsRow(icon: "paintbrush", iconColor: .purple) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme").font(.system(size: 13))
                    Picker("", selection: Binding(
                        get: { appearanceMode.wrappedValue },
                        set: { newValue in
                            appearanceMode.wrappedValue = newValue
                            newValue.save()
                        }
                    )) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: - Security

    @ViewBuilder
    private func securitySection(appState: Bindable<AppState>) -> some View {
        settingsSection("Security") {
            settingsRow(icon: "clock", iconColor: .citadelAccent) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Auto-lock timeout").font(.system(size: 13))
                        Spacer()
                        Text("\(Int(appState.wrappedValue.autoLockTimeout / 60)) min")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color.citadelSecondary)
                    }
                    Slider(value: appState.autoLockTimeout, in: 60...1800, step: 60)
                }
            }
            settingsRow(icon: "clipboard", iconColor: .orange) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Clipboard clear time").font(.system(size: 13))
                        Spacer()
                        Text("\(Int(appState.wrappedValue.clipboardClearTime)) sec")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color.citadelSecondary)
                    }
                    Slider(value: appState.clipboardClearTime, in: 5...60, step: 5)
                }
            }
            settingsRow(icon: "touchid", iconColor: .pink) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Touch ID").font(.system(size: 13))
                        Spacer()
                        if appState.wrappedValue.biometricAvailable {
                            Toggle("", isOn: Binding(
                                get: { appState.wrappedValue.biometricEnrolled },
                                set: { newValue in
                                    if newValue {
                                        enrollBiometric()
                                    } else {
                                        unenrollBiometric()
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        } else {
                            Text("Not available").font(.system(size: 12)).foregroundStyle(Color.citadelSecondary)
                        }
                    }
                    if appState.wrappedValue.biometricEnrolled {
                        Text("Unlock with Touch ID. Full password required every 72 hours.")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.citadelSecondary)
                    }
                    if let msg = biometricMessage {
                        Text(msg).font(.system(size: 11))
                            .foregroundStyle(msg.contains("failed") ? Color.citadelDanger : Color.citadelSuccess)
                    }
                }
            }
        }
    }

    // MARK: - Vault

    @ViewBuilder
    private var vaultSection: some View {
        settingsSection("Vault") {
            settingsRow(icon: "externaldrive", iconColor: .gray) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vault location").font(.system(size: 13))
                    Text(appState.vaultPath).font(.system(size: 11))
                        .foregroundStyle(Color.citadelSecondary).textSelection(.enabled).lineLimit(2)
                }
            }
            settingsRow(icon: "lock.rotation", iconColor: .citadelAccent) {
                HStack {
                    Text("Change Master Password").font(.system(size: 13))
                    Spacer()
                    Button("Change\u{2026}") { showingPasswordChange = true }.font(.system(size: 12))
                }
            }
            settingsRow(icon: "cpu", iconColor: .purple) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("KDF Strength").font(.system(size: 13))
                        Spacer()
                        Picker("", selection: $selectedKdfPreset) {
                            ForEach(KdfPreset.allCases) { preset in Text(preset.label).tag(preset) }
                        }.labelsHidden().frame(width: 140)
                    }
                    if let msg = kdfMessage {
                        Text(msg).font(.system(size: 11))
                            .foregroundStyle(msg.contains("failed") ? Color.citadelDanger : Color.citadelSuccess)
                    }
                }
            }
        }
    }

    // MARK: - Recycle Bin

    @ViewBuilder
    private var recycleBinSection: some View {
        settingsSection("Recycle Bin") {
            settingsRow(icon: "trash", iconColor: .citadelDanger) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Empty Recycle Bin").font(.system(size: 13))
                        Spacer()
                        Button("Empty\u{2026}", role: .destructive) { showingEmptyRecycleBin = true }.font(.system(size: 12))
                    }
                    if let msg = recycleBinMessage {
                        Text(msg).font(.system(size: 11)).foregroundStyle(Color.citadelSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Data

    @ViewBuilder
    private var dataSection: some View {
        settingsSection("Data") {
            settingsRow(icon: "arrow.up.doc", iconColor: .green) {
                HStack {
                    Text("Export CSV").font(.system(size: 13))
                    Spacer()
                    Button("Export\u{2026}") { showingCSVExportWarning = true }.font(.system(size: 12))
                }
            }
            settingsRow(icon: "arrow.down.doc", iconColor: .blue) {
                HStack {
                    Text("Import CSV").font(.system(size: 13))
                    Spacer()
                    Button("Import\u{2026}") { importCSV() }.font(.system(size: 12))
                }
            }
            if let msg = dataResultMessage {
                Text(msg).font(.system(size: 11))
                    .foregroundStyle(msg.contains("failed") ? Color.citadelDanger : Color.citadelSecondary)
                    .padding(.leading, 40)
            }
        }
    }

    // MARK: - Recovery & Audit

    @ViewBuilder
    private var auditSection: some View {
        settingsSection("Recovery & Audit") {
            settingsRow(icon: "printer", iconColor: .teal) {
                HStack {
                    Text("Print Recovery Sheet").font(.system(size: 13))
                    Spacer()
                    Button("Print\u{2026}") { showingRecoverySheet = true }.font(.system(size: 12))
                }
            }
            settingsRow(icon: "list.bullet.rectangle", iconColor: .indigo) {
                HStack {
                    Text("Audit Log").font(.system(size: 13))
                    Spacer()
                    Button("View") { showingAuditLog = true }.font(.system(size: 12))
                }
            }
            settingsRow(icon: "heart.text.square", iconColor: .citadelSuccess) {
                HStack {
                    Text("Password Health Report").font(.system(size: 13))
                    Spacer()
                    Button("Analyze") { showingPasswordHealth = true }.font(.system(size: 12))
                }
            }
        }
    }

    // MARK: - Emergency Access

    @ViewBuilder
    private var emergencySection: some View {
        settingsSection("Emergency Access") {
            settingsRow(icon: "exclamationmark.shield", iconColor: .citadelDanger) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Export Emergency File").font(.system(size: 13))
                        Spacer()
                        Button("Export\u{2026}") { showingEmergencyExport = true }.font(.system(size: 12))
                    }
                    Text("Creates a .ctdl-emergency file protected by a separate emergency password. To restore, you need both this file and your vault master password.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.citadelSecondary)
                    if showingEmergencyExport {
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField("Emergency password", text: $emergencyPassword)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                            SecureField("Confirm emergency password", text: $emergencyConfirm)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                            HStack(spacing: 8) {
                                Button("Cancel") {
                                    showingEmergencyExport = false
                                    emergencyPassword = ""
                                    emergencyConfirm = ""
                                    emergencyMessage = nil
                                }
                                .font(.system(size: 12))
                                Button("Create Emergency File") { exportEmergency() }
                                    .font(.system(size: 12, weight: .semibold))
                                    .disabled(emergencyPassword.isEmpty || emergencyPassword != emergencyConfirm)
                            }
                        }
                        .padding(.top, 4)
                    }
                    if let msg = emergencyMessage {
                        Text(msg).font(.system(size: 11))
                            .foregroundStyle(msg.contains("failed") ? Color.citadelDanger : Color.citadelSuccess)
                    }
                }
            }
        }
    }

    // MARK: - About

    @ViewBuilder
    private var aboutSection: some View {
        settingsSection("About") {
            settingsRow(icon: "info.circle", iconColor: .citadelAccent) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smaug").font(.system(size: 13, weight: .medium))
                        Text("v1.5").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("About Smaug") { showingAbout = true }
                        .font(.system(size: 12))
                }
            }
        }
    }

    // MARK: - Reusable Layout

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            VStack(spacing: 1) {
                content()
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private func settingsRow(icon: String, iconColor: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconBadge(symbol: icon, color: iconColor, size: 24)
                .padding(.top, 2)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func applyKdfChange() {
        do {
            try appState.applyKdfPreset(selectedKdfPreset)
            kdfMessage = "KDF updated to \(selectedKdfPreset.label)."
        } catch {
            kdfMessage = "KDF change failed."
            selectedKdfPreset = .saved
        }
    }

    private func emptyRecycleBin() {
        do {
            let count = try appState.emptyRecycleBin()
            recycleBinMessage = count > 0 ? "\(count) entry(s) permanently deleted." : "Recycle Bin was already empty."
        } catch {
            recycleBinMessage = "Failed to empty Recycle Bin."
        }
    }

    private func exportCSV() {
        do {
            let entries: [(title: String, username: String, password: String, url: String, notes: String)] =
                try appState.entries.map { summary in
                    let detail = try appState.engine.getEntry(uuid: summary.id)
                    return (
                        title: detail.title,
                        username: detail.username,
                        password: String(decoding: detail.password, as: UTF8.self),
                        url: detail.url,
                        notes: detail.notes
                    )
                }
            let csvData = CSVManager.export(entries: entries)
            let panel = NSSavePanel()
            panel.title = "Export Entries as CSV"
            panel.nameFieldStringValue = "smaug-export.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try csvData.write(to: url)
            appState.auditLogger.log(.exportCSV, detail: "\(entries.count) entries")
            dataResultMessage = "Exported \(entries.count) entries."
        } catch {
            dataResultMessage = "Export failed."
        }
        showingDataResult = true
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.title = "Import CSV"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let entries = try CSVManager.parse(data: data)
            var count = 0
            for entry in entries {
                _ = try appState.engine.addEntry(
                    title: entry.title, username: entry.username,
                    password: Data(entry.password.utf8),
                    url: entry.url, notes: entry.notes
                )
                count += 1
            }
            if count > 0 {
                try appState.save()
                try appState.refreshEntries()
            }
            dataResultMessage = "Imported \(count) entries."
            appState.auditLogger.log(.importCSV, detail: "\(count) entries")
        } catch {
            dataResultMessage = "Import failed."
        }
        showingDataResult = true
    }

    private func exportEmergency() {
        let panel = NSSavePanel()
        panel.title = "Save Emergency Access File"
        panel.nameFieldStringValue = "smaug-emergency.ctdl-emergency"
        panel.allowedContentTypes = [.init(filenameExtension: "ctdl-emergency") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try EmergencyAccess.export(
                vaultPath: appState.vaultPath,
                emergencyPassword: emergencyPassword,
                destination: url
            )
            emergencyMessage = "Emergency file created."
            appState.auditLogger.log(.exportCSV, detail: "Emergency access file exported")
            showingEmergencyExport = false
            emergencyPassword = ""
            emergencyConfirm = ""
        } catch {
            emergencyMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func enrollBiometric() {
        biometricMessage = nil
        guard let password = appState.currentPasswordForBiometric else {
            biometricMessage = "Enrollment failed: vault not unlocked."
            return
        }
        Task {
            do {
                try await appState.biometricManager.enroll(password: password)
                appState.refreshBiometricState()
                biometricMessage = "Touch ID enabled."
            } catch {
                appState.refreshBiometricState()
                biometricMessage = "Enrollment failed: \(error.localizedDescription)"
            }
        }
    }

    private func unenrollBiometric() {
        appState.biometricManager.unenroll()
        appState.refreshBiometricState()
        biometricMessage = nil
    }
}
