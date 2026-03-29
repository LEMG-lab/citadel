import SwiftUI
import CitadelCore

/// Password Health Dashboard — analyzes all vault entries and surfaces
/// weak, reused, old, and TOTP-less credentials with an overall score.
struct PasswordHealthView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var analysis: HealthAnalysis?
    @State private var isAnalyzing = true

    // MARK: - Model

    struct HealthAnalysis {
        var weakPasswords: [(id: String, title: String, strength: PasswordStrength)]
        var reusedPasswords: [(id: String, title: String, sharedWith: [String])]
        var oldPasswords: [(id: String, title: String, age: Int)] // age in days
        var missingTOTP: [(id: String, title: String)]

        var totalIssues: Int {
            weakPasswords.count + reusedPasswords.count + oldPasswords.count + missingTOTP.count
        }

        /// Health score: 100 minus weighted penalties, floored at 0.
        var score: Int {
            let penalty = weakPasswords.count * 10
                + reusedPasswords.count * 8
                + oldPasswords.count * 3
                + missingTOTP.count * 2
            return max(0, 100 - penalty)
        }

        var scoreLabel: String {
            switch score {
            case 90...100: return "Excellent"
            case 70..<90:  return "Good"
            case 40..<70:  return "Fair"
            default:       return "Poor"
            }
        }

        var scoreColor: Color {
            if score < 40 { return .red }
            if score < 70 { return .orange }
            return .green
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isAnalyzing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Analyzing vault entries\u{2026}")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let analysis {
                Form {
                    scoreSection(analysis)
                    weakSection(analysis)
                    reusedSection(analysis)
                    oldSection(analysis)
                    totpSection(analysis)
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(
                    "Analysis Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Could not analyze vault entries.")
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .padding()
                .background(.background)
            }
        }
        .frame(width: 500, height: 500)
        .task {
            await runAnalysis()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func scoreSection(_ analysis: HealthAnalysis) -> some View {
        Section {
            HStack {
                Text("\(analysis.score)/100")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(analysis.scoreColor)
                Text("- \(analysis.scoreLabel)")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if analysis.totalIssues == 0 {
                Text("No issues found. Great job!")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(analysis.totalIssues) issue\(analysis.totalIssues == 1 ? "" : "s") found across your vault.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func weakSection(_ analysis: HealthAnalysis) -> some View {
        Section {
            DisclosureGroup {
                ForEach(analysis.weakPasswords, id: \.id) { entry in
                    Button {
                        selectEntry(entry.id)
                    } label: {
                        HStack {
                            Text(entry.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(entry.strength.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                Label {
                    HStack {
                        Text("Weak Passwords")
                        Spacer()
                        Text("\(analysis.weakPasswords.count)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(analysis.weakPasswords.isEmpty ? .gray : .red, in: Capsule())
                    }
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder
    private func reusedSection(_ analysis: HealthAnalysis) -> some View {
        Section {
            DisclosureGroup {
                ForEach(analysis.reusedPasswords, id: \.id) { entry in
                    Button {
                        selectEntry(entry.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .foregroundStyle(.primary)
                            Text("Shared with: \(entry.sharedWith.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                Label {
                    HStack {
                        Text("Reused Passwords")
                        Spacer()
                        Text("\(analysis.reusedPasswords.count)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(analysis.reusedPasswords.isEmpty ? .gray : .orange, in: Capsule())
                    }
                } icon: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func oldSection(_ analysis: HealthAnalysis) -> some View {
        Section {
            DisclosureGroup {
                ForEach(analysis.oldPasswords, id: \.id) { entry in
                    Button {
                        selectEntry(entry.id)
                    } label: {
                        HStack {
                            Text(entry.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(entry.age) days old")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                Label {
                    HStack {
                        Text("Old Passwords")
                        Spacer()
                        Text("\(analysis.oldPasswords.count)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(analysis.oldPasswords.isEmpty ? .gray : .yellow, in: Capsule())
                    }
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    @ViewBuilder
    private func totpSection(_ analysis: HealthAnalysis) -> some View {
        Section {
            DisclosureGroup {
                ForEach(analysis.missingTOTP, id: \.id) { entry in
                    Button {
                        selectEntry(entry.id)
                    } label: {
                        Text(entry.title)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                Label {
                    HStack {
                        Text("Missing TOTP")
                        Spacer()
                        Text("\(analysis.missingTOTP.count)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(analysis.missingTOTP.isEmpty ? .gray : .blue, in: Capsule())
                    }
                } icon: {
                    Image(systemName: "lock.open")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Actions

    private func selectEntry(_ id: String) {
        appState.selectedEntryID = id
        dismiss()
    }

    // MARK: - Analysis

    private func runAnalysis() async {
        let engine = appState.engine
        let summaries = appState.entries

        // Fetch all details off the main actor
        let details: [(summary: VaultEntrySummary, detail: VaultEntryDetail)] = summaries.compactMap { summary in
            guard let detail = try? engine.getEntry(uuid: summary.id) else { return nil }
            return (summary, detail)
        }

        // Filter out secure notes
        let credentials = details.filter { $0.summary.entryType != "secure_note" }

        // 1. Weak passwords
        var weakPasswords: [(id: String, title: String, strength: PasswordStrength)] = []
        for item in credentials {
            let passwordString = String(decoding: item.detail.password, as: UTF8.self)
            guard !passwordString.isEmpty else { continue }
            let strength = PasswordStrength.evaluate(passwordString)
            if strength < .good {
                weakPasswords.append((id: item.summary.id, title: item.summary.title, strength: strength))
            }
        }

        // 2. Reused passwords — group by password bytes, skip empties
        var passwordGroups: [Data: [(id: String, title: String)]] = [:]
        for item in credentials {
            guard !item.detail.password.isEmpty else { continue }
            passwordGroups[item.detail.password, default: []].append(
                (id: item.summary.id, title: item.summary.title)
            )
        }

        var reusedPasswords: [(id: String, title: String, sharedWith: [String])] = []
        for (_, group) in passwordGroups where group.count > 1 {
            for entry in group {
                let others = group.filter { $0.id != entry.id }.map(\.title)
                reusedPasswords.append((id: entry.id, title: entry.title, sharedWith: others))
            }
        }

        // 3. Old passwords — lastModified older than 180 days
        let now = Date()
        var oldPasswords: [(id: String, title: String, age: Int)] = []
        for item in credentials {
            guard let modified = item.summary.lastModified else { continue }
            let age = Calendar.current.dateComponents([.day], from: modified, to: now).day ?? 0
            if age > 180 {
                oldPasswords.append((id: item.summary.id, title: item.summary.title, age: age))
            }
        }

        // 4. Missing TOTP
        var missingTOTP: [(id: String, title: String)] = []
        for item in credentials {
            if item.detail.otpURI.isEmpty {
                missingTOTP.append((id: item.summary.id, title: item.summary.title))
            }
        }

        let result = HealthAnalysis(
            weakPasswords: weakPasswords,
            reusedPasswords: reusedPasswords,
            oldPasswords: oldPasswords,
            missingTOTP: missingTOTP
        )

        analysis = result
        isAnalyzing = false
    }
}
