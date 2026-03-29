import SwiftUI
import CitadelCore

/// Simple audit log viewer sheet.
struct AuditLogView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Audit Log")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            let entries = appState.auditLogger.recentEntries(limit: 200)

            if entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.citadelSecondary.opacity(0.4))
                    Text("No Log Entries")
                        .font(.system(size: 13, weight: .medium))
                    Text("Audit events will appear here")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary)
                }
                Spacer()
            } else {
                List(entries, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(2)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }

            Divider()

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
        .frame(width: 600, height: 420)
    }
}
