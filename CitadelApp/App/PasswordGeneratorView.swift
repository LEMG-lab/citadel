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
        if useDigits { flags |= 4 }
        if useSymbols { flags |= 8 }
        return flags
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Password Generator")
                .font(.headline)

            // Preview
            GroupBox {
                Text(generated.isEmpty ? " " : generated)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }

            // Length slider
            HStack {
                Text("Length: \(Int(length))")
                    .monospacedDigit()
                    .frame(width: 80, alignment: .leading)
                Slider(value: $length, in: 12...64, step: 1)
            }

            // Character class toggles
            Toggle("Lowercase (a-z)", isOn: $useLowercase)
            Toggle("Uppercase (A-Z)", isOn: $useUppercase)
            Toggle("Digits (0-9)", isOn: $useDigits)
            Toggle("Symbols (!@#$...)", isOn: $useSymbols)

            if let msg = errorMessage {
                Text(msg).foregroundStyle(.red).font(.callout)
            }

            Divider()

            HStack {
                Button("Regenerate") { generate() }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use This Password") {
                    onUse(generated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(generated.isEmpty)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { generate() }
        .onChange(of: length) { _, _ in generate() }
        .onChange(of: useLowercase) { _, _ in generate() }
        .onChange(of: useUppercase) { _, _ in generate() }
        .onChange(of: useDigits) { _, _ in generate() }
        .onChange(of: useSymbols) { _, _ in generate() }
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
