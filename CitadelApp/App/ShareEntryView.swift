import SwiftUI
import CitadelCore

/// Share entry sheet — lets user pick fields to share and generates an encrypted link.
struct ShareEntryView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: VaultEntryDetail

    @State private var selectedFields: Set<String> = []
    @State private var includeExpiry = false
    @State private var expiryHours: Double = 24
    @State private var shareLink: String?
    @State private var errorMessage: String?
    @State private var copied = false

    private var availableFields: [(label: String, value: String, isProtected: Bool)] {
        var fields: [(String, String, Bool)] = []
        if !entry.username.isEmpty {
            fields.append(("Username", entry.username, false))
        }
        if !entry.password.isEmpty {
            fields.append(("Password", String(decoding: entry.password, as: UTF8.self), true))
        }
        if !entry.url.isEmpty {
            fields.append(("URL", entry.url, false))
        }
        if !entry.notes.isEmpty {
            fields.append(("Notes", entry.notes, false))
        }
        for cf in entry.customFields {
            fields.append((cf.key, cf.value, cf.isProtected))
        }
        return fields
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Share Entry")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if shareLink == nil {
                        fieldSelection
                    } else {
                        linkResult
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if shareLink == nil {
                    Button("Generate Link") { generateLink() }
                        .buttonStyle(.borderedProminent)
                        .tint(.citadelAccent)
                        .disabled(selectedFields.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 460, height: 420)
    }

    @ViewBuilder
    private var fieldSelection: some View {
        SectionHeader(title: "Select fields to share")

        VStack(spacing: 1) {
            ForEach(availableFields, id: \.label) { field in
                HStack {
                    Toggle(isOn: Binding(
                        get: { selectedFields.contains(field.label) },
                        set: { if $0 { selectedFields.insert(field.label) } else { selectedFields.remove(field.label) } }
                    )) {
                        HStack(spacing: 6) {
                            Text(field.label)
                                .font(.system(size: 13))
                            if field.isProtected {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.citadelAccent)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        Toggle("Set expiry", isOn: $includeExpiry)
            .font(.system(size: 13))
        if includeExpiry {
            HStack {
                Text("Expires in")
                    .font(.system(size: 13))
                Picker("", selection: $expiryHours) {
                    Text("1 hour").tag(1.0)
                    Text("6 hours").tag(6.0)
                    Text("24 hours").tag(24.0)
                    Text("7 days").tag(168.0)
                }
                .labelsHidden()
                .frame(width: 120)
            }
        }

        if let msg = errorMessage {
            Text(msg).font(.system(size: 12)).foregroundStyle(Color.citadelDanger)
        }
    }

    @ViewBuilder
    private var linkResult: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.citadelSuccess)
            Text("Encrypted share link created")
                .font(.system(size: 13, weight: .medium))
        }

        Text(shareLink ?? "")
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(4)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

        Button {
            if let link = shareLink {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(link, forType: .string)
                copied = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
                Text(copied ? "Copied!" : "Copy to Clipboard")
                    .font(.system(size: 13))
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(copied ? .citadelSuccess : .citadelAccent)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.citadelWarning)
                Text("Security Warning")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.citadelWarning)
            }
            Text("Anyone with this link can see the shared fields. The encryption key is embedded in the link itself \u{2014} treat it like a password. Send it through a secure channel (not unencrypted email). The link works offline \u{2014} no server needed.")
                .font(.system(size: 11))
                .foregroundStyle(Color.citadelSecondary)
        }
        .padding(10)
        .background(Color.citadelWarning.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func generateLink() {
        errorMessage = nil
        let fields = availableFields
            .filter { selectedFields.contains($0.label) }
            .map { SecureShare.SharedField(label: $0.label, value: $0.value, isProtected: $0.isProtected) }

        let expiry: Date? = includeExpiry ? Date().addingTimeInterval(expiryHours * 3600) : nil
        let sharedEntry = SecureShare.SharedEntry(
            title: entry.title, fields: fields, expiresAt: expiry
        )

        do {
            shareLink = try SecureShare.createShareLink(entry: sharedEntry)
            // Auto-copy
            if let link = shareLink {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(link, forType: .string)
                copied = true
            }
        } catch {
            errorMessage = "Could not create share link"
        }
    }
}
