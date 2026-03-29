import SwiftUI
import CitadelCore

/// Simple audit log viewer sheet.
struct AuditLogView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("Audit Log")
                .font(.headline)
                .padding(.top)

            let entries = appState.auditLogger.recentEntries(limit: 200)

            if entries.isEmpty {
                ContentUnavailableView(
                    "No Log Entries",
                    systemImage: "doc.text",
                    description: Text("Audit events will appear here.")
                )
            } else {
                List(entries, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
    }
}
