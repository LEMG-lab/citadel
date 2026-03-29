import SwiftUI
import CitadelCore

/// Watchtower Security Dashboard — comprehensive analysis of vault security.
struct PasswordHealthView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var analysis: HealthAnalysis?
    @State private var isAnalyzing = true
    @State private var breachResults: [(id: String, title: String, breachCount: Int)] = []
    @State private var isCheckingBreaches = false
    @State private var showingBreachConsent = false
    @State private var breachError: String?

    // MARK: - Model

    struct HealthAnalysis {
        var weakPasswords: [(id: String, title: String, strength: PasswordStrength)]
        var reusedPasswords: [(id: String, title: String, sharedWith: [String])]
        var oldPasswords: [(id: String, title: String, age: Int)]
        var missingTOTP: [(id: String, title: String)]
        var breachedPasswords: [(id: String, title: String, breachCount: Int)]
        var httpURLs: [(id: String, title: String, url: String)]
        var expiringSoon: [(id: String, title: String, daysLeft: Int)]

        var totalIssues: Int {
            breachedPasswords.count + weakPasswords.count + reusedPasswords.count
            + oldPasswords.count + missingTOTP.count + httpURLs.count + expiringSoon.count
        }

        var score: Int {
            let penalty = breachedPasswords.count * 15
                + weakPasswords.count * 10
                + reusedPasswords.count * 8
                + oldPasswords.count * 3
                + missingTOTP.count * 2
                + httpURLs.count * 2
                + expiringSoon.count * 3
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
            headerBar
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
                    dashboardContent(analysis)
                }
            } else {
                Spacer()
                Text("Analysis failed.")
                    .foregroundStyle(Color.citadelSecondary)
                Spacer()
            }

            Divider()
            footerBar
        }
        .frame(width: 560, height: 620)
        .task { await runAnalysis() }
        .confirmationDialog("Check for Breaches", isPresented: $showingBreachConsent, titleVisibility: .visible) {
            Button("Check Passwords") { Task { await runBreachCheck() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will check your passwords against a database of known breaches. Only a partial hash is sent \u{2014} your passwords never leave this device. Allow?")
        }
    }

    // MARK: - Header & Footer

    private var headerBar: some View {
        HStack {
            Text("Security Dashboard")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            if !isAnalyzing {
                Button {
                    isAnalyzing = true
                    Task { await runAnalysis() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.citadelAccent)
                .help("Refresh analysis")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var footerBar: some View {
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

    // MARK: - Dashboard Content

    @ViewBuilder
    private func dashboardContent(_ analysis: HealthAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            scoreCard(analysis)
            breachSection(analysis)
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
                title: "Old Passwords (>180 days)", count: analysis.oldPasswords.count,
                items: analysis.oldPasswords.map { ($0.id, $0.title, "\($0.age) days old") }
            )
            categoryCard(
                icon: "calendar.badge.exclamationmark", color: .citadelWarning,
                title: "Expiring Soon", count: analysis.expiringSoon.count,
                items: analysis.expiringSoon.map { ($0.id, $0.title, "\($0.daysLeft) days left") }
            )
            categoryCard(
                icon: "lock.open", color: .citadelAccent,
                title: "Missing TOTP", count: analysis.missingTOTP.count,
                items: analysis.missingTOTP.map { ($0.id, $0.title, "") }
            )
            categoryCard(
                icon: "exclamationmark.triangle", color: .orange,
                title: "Insecure URLs (HTTP)", count: analysis.httpURLs.count,
                items: analysis.httpURLs.map { ($0.id, $0.title, $0.url) }
            )
        }
        .padding(20)
    }

    // MARK: - Score Card

    @ViewBuilder
    private func scoreCard(_ analysis: HealthAnalysis) -> some View {
        HStack(spacing: 16) {
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

    // MARK: - Breach Section

    @ViewBuilder
    private func breachSection(_ analysis: HealthAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconBadge(symbol: "shield.slash", color: .citadelDanger, size: 24)
                Text("Breached Passwords")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if analysis.breachedPasswords.isEmpty && !isCheckingBreaches {
                    Button {
                        if appState.breachChecker.hasConsented {
                            Task { await runBreachCheck() }
                        } else {
                            showingBreachConsent = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                            Text("Check for Breaches")
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.citadelDanger)
                    .controlSize(.small)
                } else {
                    CountBadge(count: analysis.breachedPasswords.count, color: .citadelDanger)
                }
            }

            if isCheckingBreaches {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking passwords against breach database\u{2026}")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.citadelSecondary)
                }
                .padding(.leading, 34)
            }

            if let err = breachError {
                Text(err).font(.system(size: 11)).foregroundStyle(Color.citadelDanger)
                    .padding(.leading, 34)
            }

            if !analysis.breachedPasswords.isEmpty {
                VStack(spacing: 0) {
                    ForEach(analysis.breachedPasswords, id: \.id) { item in
                        breachRow(item)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func breachRow(_ item: (id: String, title: String, breachCount: Int)) -> some View {
        HStack {
            Text(item.title)
                .font(.system(size: 12))
            Spacer()
            Text("\(item.breachCount) breaches")
                .font(.system(size: 11))
                .foregroundStyle(Color.citadelDanger)
            Button {
                appState.selectedEntryID = item.id
                dismiss()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.citadelSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
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
        let now = Date()

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

        // Old passwords (>180 days)
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

        // HTTP URLs
        var httpURLs: [(id: String, title: String, url: String)] = []
        for item in credentials {
            let u = item.detail.url.lowercased()
            if u.hasPrefix("http://") {
                httpURLs.append((id: item.summary.id, title: item.summary.title, url: item.detail.url))
            }
        }

        // Expiring soon (within 30 days)
        var expiringSoon: [(id: String, title: String, daysLeft: Int)] = []
        for item in details {
            guard let expiry = item.summary.expiryDate else { continue }
            let daysLeft = Calendar.current.dateComponents([.day], from: now, to: expiry).day ?? 0
            if daysLeft >= 0 && daysLeft <= 30 {
                expiringSoon.append((id: item.summary.id, title: item.summary.title, daysLeft: daysLeft))
            }
        }

        analysis = HealthAnalysis(
            weakPasswords: weakPasswords,
            reusedPasswords: reusedPasswords,
            oldPasswords: oldPasswords,
            missingTOTP: missingTOTP,
            breachedPasswords: breachResults,
            httpURLs: httpURLs,
            expiringSoon: expiringSoon
        )
        isAnalyzing = false
    }

    private func runBreachCheck() async {
        isCheckingBreaches = true
        breachError = nil
        appState.breachChecker.hasConsented = true

        let engine = appState.engine
        let entries = appState.entries.compactMap { summary -> (id: String, title: String, password: Data)? in
            guard summary.entryType != "secure_note",
                  let detail = try? engine.getEntry(uuid: summary.id),
                  !detail.password.isEmpty else { return nil }
            return (id: summary.id, title: summary.title, password: detail.password)
        }

        let results = await appState.breachChecker.checkAll(entries: entries)
        breachResults = results

        // Re-run analysis with breach data
        if var a = analysis {
            a.breachedPasswords = results
            analysis = a
        }

        isCheckingBreaches = false

        if results.isEmpty && entries.count > 0 {
            breachError = nil // All clear, no error
        }
    }
}
