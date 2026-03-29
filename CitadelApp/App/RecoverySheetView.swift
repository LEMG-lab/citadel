import SwiftUI

/// Printable recovery sheet with instructions for opening the vault in other apps.
struct RecoverySheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var dateString: String {
        Date().formatted(date: .long, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recovery Information")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Info fields
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Vault Details")
                        FieldCard(label: "Vault File") {
                            Text(appState.vaultPath)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                        }
                        FieldCard(label: "Date") {
                            Text(dateString)
                                .font(.system(size: 12))
                        }
                    }

                    // KeePassXC
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Opening with KeePassXC")
                        recoverySteps([
                            "Download KeePassXC from keepassxc.org",
                            "Open KeePassXC",
                            "Select File > Open Database",
                            "Navigate to the vault file listed above",
                            "Enter your master password when prompted",
                        ])
                    }

                    // Strongbox
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Opening with Strongbox")
                        recoverySteps([
                            "Download Strongbox from the Mac App Store",
                            "Open Strongbox",
                            "Select File > Open",
                            "Navigate to the vault file listed above",
                            "Enter your master password when prompted",
                        ])
                    }

                    // Encrypted Backup
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Encrypted Backup")
                        VStack(alignment: .leading, spacing: 6) {
                            Text("If you created a Full Vault Backup (.ctdl file), it contains all your vaults encrypted with a separate backup password.")
                                .font(.system(size: 12))
                            Text("To restore: Open Citadel \u{2192} More Actions \u{2192} Restore from Backup, then enter the backup password.")
                                .font(.system(size: 12))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    // Warning
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.citadelWarning)
                        Text("Your master password and backup password are not included in this document. Store them separately and securely.")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(12)
                    .background(Color.citadelWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button {
                    printSheet()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "printer")
                            .font(.system(size: 11))
                        Text("Print")
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.citadelAccent)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 560, height: 620)
    }

    @ViewBuilder
    private func recoverySteps(_ steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.citadelSecondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(step)
                        .font(.system(size: 12))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func printSheet() {
        let text = """
        CITADEL RECOVERY INFORMATION
        =============================

        Vault file: \(appState.vaultPath)
        Date: \(dateString)

        OPENING WITH KEEPASSXC
        ----------------------
        1. Download KeePassXC from https://keepassxc.org
        2. Open KeePassXC
        3. Select File > Open Database
        4. Navigate to the vault file listed above
        5. Enter your master password when prompted

        OPENING WITH STRONGBOX
        ----------------------
        1. Download Strongbox from the Mac App Store
        2. Open Strongbox
        3. Select File > Open
        4. Navigate to the vault file listed above
        5. Enter your master password when prompted

        IMPORTANT: Your master password is NOT included in this document.
        Store it separately and securely.
        """

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.topMargin = 50
        printInfo.bottomMargin = 50
        printInfo.leftMargin = 50
        printInfo.rightMargin = 50

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }
}
