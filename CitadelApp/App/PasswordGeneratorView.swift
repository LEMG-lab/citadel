import SwiftUI
import CitadelCore

/// Password generator sheet.
struct PasswordGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    let onUse: (String) -> Void

    @State private var length: Double = 20
    @State private var useLowercase = true
    @State private var useUppercase = true
    @State private var useDigits = true
    @State private var useSymbols = true
    @State private var generated = ""
    @State private var errorMessage: String?

    private var charset: UInt32 {
        var flags: UInt32 = 0
        if useLowercase { flags |= 1 }
        if useUppercase { flags |= 2 }
        if useDigits    { flags |= 4 }
        if useSymbols   { flags |= 8 }
        return flags
    }

    var body: some View {
        VStack(spacing: 0) {
            generatorHeader
            Divider()
            generatorContent
            Spacer()
            Divider()
            generatorFooter
        }
        .frame(width: 440, height: 420)
        .onAppear { generate() }
        .onChange(of: length) { _, _ in generate() }
        .onChange(of: useLowercase) { _, _ in generate() }
        .onChange(of: useUppercase) { _, _ in generate() }
        .onChange(of: useDigits) { _, _ in generate() }
        .onChange(of: useSymbols) { _, _ in generate() }
    }

    private var generatorHeader: some View {
        HStack {
            Text("Password Generator")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var generatorContent: some View {
        VStack(spacing: 14) {
            Text(generated.isEmpty ? " " : generated)
                .font(.system(size: 14, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            PasswordStrengthBar(password: generated)

            HStack {
                Text("Length")
                    .font(.system(size: 13))
                Spacer()
                Text("\(Int(length))")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.citadelSecondary)
                    .frame(width: 30, alignment: .trailing)
            }
            Slider(value: $length, in: 12...64, step: 1)

            VStack(spacing: 8) {
                Toggle("Lowercase (a\u{2013}z)", isOn: $useLowercase)
                Toggle("Uppercase (A\u{2013}Z)", isOn: $useUppercase)
                Toggle("Digits (0\u{2013}9)", isOn: $useDigits)
                Toggle("Symbols (!@#$\u{2026})", isOn: $useSymbols)
            }
            .font(.system(size: 13))
            .toggleStyle(.switch)

            if let msg = errorMessage {
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.citadelDanger)
            }
        }
        .padding(20)
    }

    private var generatorFooter: some View {
        HStack {
            Button {
                generate()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Regenerate")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.citadelAccent)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Use This Password") {
                onUse(generated)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.citadelAccent)
            .keyboardShortcut(.defaultAction)
            .disabled(generated.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func generate() {
        errorMessage = nil
        guard charset != 0 else {
            generated = ""
            errorMessage = "Select at least one character set"
            return
        }
        do {
            let data = try VaultEngine.generatePassword(length: Int(length), charset: charset)
            generated = String(decoding: data, as: UTF8.self)
        } catch {
            generated = ""
            errorMessage = "Generation failed"
        }
    }
}
