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
        var oldPasswords: [(id: String, title: String, age: Int)]
        var missingTOTP: [(id: String, title: String)]

        var totalIssues: Int {
            weakPasswords.count + reusedPasswords.count + oldPasswords.count + missingTOTP.count
        }

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
            if score < 40 { return .citadelDanger }
            if score < 70 { return .citadelWarning }
            return .citadelSuccess
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Password Health")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Divider()

            if isAnalyzing {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Analyzing vault entries\u{2026}")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary)
                }
                Spacer()
            } else if let analysis {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        scoreCard(analysis)
                        categoryCard(
                            icon: "exclamationmark.shield", color: .citadelDanger,
                            title: "Weak Passwords", count: analysis.weakPasswords.count,
                            items: analysis.weakPasswords.map { ($0.id, $0.title, $0.strength.label) }
                        )
                        categoryCard(
                            icon: "doc.on.doc", color: .citadelWarning,
                            title: "Reused Passwords", count: analysis.reusedPasswords.count,
                            items: analysis.reusedPasswords.map { ($0.id, $0.title, "Shared with: \($0.sharedWith.joined(separator: ", "))") }
                        )
                        categoryCard(
                            icon: "clock.badge.exclamationmark", color: .yellow,
                            title: "Old Passwords", count: analysis.oldPasswords.count,
                            items: analysis.oldPasswords.map { ($0.id, $0.title, "\($0.age) days old") }
                        )
                        categoryCard(
                            icon: "lock.open", color: .citadelAccent,
                            title: "Missing TOTP", count: analysis.missingTOTP.count,
                            items: analysis.missingTOTP.map { ($0.id, $0.title, "") }
                        )
                    }
                    .padding(20)
                }
            } else {
                Spacer()
                Text("Analysis failed.")
                    .foregroundStyle(Color.citadelSecondary)
                Spacer()
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
        .frame(width: 520, height: 540)
        .task { await runAnalysis() }
    }

    // MARK: - Score Card

    @ViewBuilder
    private func scoreCard(_ analysis: HealthAnalysis) -> some View {
        HStack(spacing: 16) {
            // Circular score
            ZStack {
                ProgressRing(
                    progress: Double(analysis.score) / 100.0,
                    color: analysis.scoreColor,
                    lineWidth: 8
                )
                VStack(spacing: 0) {
                    Text("\(analysis.score)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(analysis.scoreColor)
                    Text("/100")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.citadelSecondary)
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 4) {
                Text(analysis.scoreLabel)
                    .font(.system(size: 18, weight: .bold))
                if analysis.totalIssues == 0 {
                    Text("No issues found. Great job!")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary)
                } else {
                    Text("\(analysis.totalIssues) issue\(analysis.totalIssues == 1 ? "" : "s") found")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.citadelSecondary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Category Card

    @ViewBuilder
    private func categoryCard(
        icon: String, color: Color, title: String, count: Int,
        items: [(id: String, title: String, detail: String)]
    ) -> some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                ForEach(items, id: \.id) { item in
                    Button {
                        appState.selectedEntryID = item.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(item.title)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                            Spacer()
                            if !item.detail.isEmpty {
                                Text(item.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.citadelSecondary)
                                    .lineLimit(1)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.citadelSecondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 34)
        } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: icon, color: color, size: 24)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                CountBadge(count: count, color: color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Analysis

    private func runAnalysis() async {
        let engine = appState.engine
        let summaries = appState.entries

        let details: [(summary: VaultEntrySummary, detail: VaultEntryDetail)] = summaries.compactMap { summary in
            guard let detail = try? engine.getEntry(uuid: summary.id) else { return nil }
            return (summary, detail)
        }

        let credentials = details.filter { $0.summary.entryType != "secure_note" }

        // Weak passwords
        var weakPasswords: [(id: String, title: String, strength: PasswordStrength)] = []
        for item in credentials {
            let passwordString = String(decoding: item.detail.password, as: UTF8.self)
            guard !passwordString.isEmpty else { continue }
            let strength = PasswordStrength.evaluate(passwordString)
            if strength < .good {
                weakPasswords.append((id: item.summary.id, title: item.summary.title, strength: strength))
            }
        }

        // Reused passwords
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

        // Old passwords
        let now = Date()
        var oldPasswords: [(id: String, title: String, age: Int)] = []
        for item in credentials {
            guard let modified = item.summary.lastModified else { continue }
            let age = Calendar.current.dateComponents([.day], from: modified, to: now).day ?? 0
            if age > 180 {
                oldPasswords.append((id: item.summary.id, title: item.summary.title, age: age))
            }
        }

        // Missing TOTP
        var missingTOTP: [(id: String, title: String)] = []
        for item in credentials {
            if item.detail.otpURI.isEmpty {
                missingTOTP.append((id: item.summary.id, title: item.summary.title))
            }
        }

        analysis = HealthAnalysis(
            weakPasswords: weakPasswords,
            reusedPasswords: reusedPasswords,
            oldPasswords: oldPasswords,
            missingTOTP: missingTOTP
        )
        isAnalyzing = false
    }
}
