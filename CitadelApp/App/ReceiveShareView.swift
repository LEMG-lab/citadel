import SwiftUI
import CitadelCore

/// View for receiving and decrypting a shared entry link.
struct ReceiveShareView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var linkText = ""
    @State private var decryptedEntry: SecureShare.SharedEntry?
    @State private var errorMessage: String?
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Receive Shared Entry")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if decryptedEntry == nil {
                        inputSection
                    } else {
                        decryptedSection
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                if let _ = decryptedEntry, !saved {
                    Button("Save as Entry") { saveAsEntry() }
                        .buttonStyle(.borderedProminent)
                        .tint(.citadelAccent)
                }
                Button(saved ? "Done" : "Close") { dismiss() }
                    .keyboardShortcut(saved ? .defaultAction : .cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 480, height: 420)
    }

    @ViewBuilder
    private var inputSection: some View {
        SectionHeader(title: "Paste Share Link")

        TextField(text: $linkText, prompt: Text("citadel://share#...").foregroundStyle(.tertiary), axis: .vertical) {}
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(3...6)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

        if let msg = errorMessage {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                Text(msg).font(.system(size: 12))
            }
            .foregroundStyle(Color.citadelDanger)
        }

        Button("Decrypt") { decrypt() }
            .buttonStyle(.borderedProminent)
            .tint(.citadelAccent)
            .disabled(linkText.isEmpty)
    }

    @ViewBuilder
    private var decryptedSection: some View {
        if let entry = decryptedEntry {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.citadelSuccess)
                Text("Decrypted successfully")
                    .font(.system(size: 13, weight: .medium))
            }

            FieldCard(label: "Title") {
                Text(entry.title).font(.system(size: 13))
            }

            ForEach(entry.fields, id: \.label) { field in
                FieldCard(label: field.label) {
                    if field.isProtected {
                        HStack {
                            Text(field.value)
                                .font(.system(size: 13, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.citadelAccent)
                        }
                    } else {
                        Text(field.value)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                    }
                }
            }

            if let expires = entry.expiresAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("Expires: \(expires.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color.citadelSecondary)
            }

            if saved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Saved to vault")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color.citadelSuccess)
            }
        }
    }

    private func decrypt() {
        errorMessage = nil
        do {
            decryptedEntry = try SecureShare.decryptShareLink(linkText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveAsEntry() {
        guard let entry = decryptedEntry else { return }
        do {
            let uuid = try appState.engine.addEntry(
                title: entry.title, username: "", password: Data(),
                url: "", notes: ""
            )
            for field in entry.fields {
                if field.label.lowercased() == "username" {
                    try appState.engine.updateEntry(
                        uuid: uuid, title: entry.title, username: field.value,
                        password: Data(), url: "", notes: ""
                    )
                } else if field.label.lowercased() == "password" {
                    try appState.engine.updateEntry(
                        uuid: uuid, title: entry.title, username: "",
                        password: Data(field.value.utf8), url: "", notes: ""
                    )
                } else {
                    try appState.engine.setCustomField(
                        uuid: uuid, key: field.label,
                        value: field.value, isProtected: field.isProtected
                    )
                }
            }
            try appState.save()
            try appState.refreshEntries()
            appState.selectedEntryID = uuid
            saved = true
        } catch {
            errorMessage = "Could not save entry"
        }
    }
}
