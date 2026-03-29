import SwiftUI

/// Printable recovery sheet with instructions for opening the vault in other apps.
struct RecoverySheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var dateString: String {
        Date().formatted(date: .long, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Citadel Recovery Information")
                .font(.title2.weight(.semibold))

            Divider()

            Group {
                LabeledContent("Vault file", value: appState.vaultPath)
                LabeledContent("Date", value: dateString)
            }
            .font(.callout)

            Divider()

            Text("Opening with KeePassXC")
                .font(.headline)
            Text("""
            1. Download KeePassXC from https://keepassxc.org
            2. Open KeePassXC
            3. Select File > Open Database
            4. Navigate to the vault file listed above
            5. Enter your master password when prompted
            """)
            .font(.callout)

            Divider()

            Text("Opening with Strongbox")
                .font(.headline)
            Text("""
            1. Download Strongbox from the Mac App Store
            2. Open Strongbox
            3. Select File > Open
            4. Navigate to the vault file listed above
            5. Enter your master password when prompted
            """)
            .font(.callout)

            Divider()

            Text("IMPORTANT: Your master password is not included in this document. Store it separately and securely.")
                .font(.callout.weight(.semibold))

            Spacer()

            HStack {
                Button("Print") { printSheet() }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(32)
        .frame(width: 580, height: 640)
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
