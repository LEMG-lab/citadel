import SwiftUI
import CitadelCore

/// Sidebar list of vault entries with fuzzy search and group filtering.
struct EntryListView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedGroup: String? = nil

    private var availableGroups: [String] {
        let groups = Set(appState.entries.map(\.group))
        return groups.sorted()
    }

    private var filteredEntries: [(entry: VaultEntrySummary, score: Int)] {
        var source = appState.entries

        if let group = selectedGroup {
            source = source.filter { $0.group == group || $0.group.hasPrefix(group + "/") }
        }

        var results: [(entry: VaultEntrySummary, score: Int)]

        if searchText.isEmpty {
            results = source.map { ($0, 0) }
        } else {
            let query = searchText
            results = source.compactMap { entry in
                let result = FuzzyMatch.bestMatch(
                    query: query,
                    fields: [entry.title, entry.username, entry.url]
                )
                guard result.score > 0 else { return nil }
                return (entry, result.score)
            }
            .sorted { $0.score > $1.score }
        }

        // Stable sort: favorites first
        results.sort { lhs, rhs in
            if lhs.entry.isFavorite != rhs.entry.isFavorite {
                return lhs.entry.isFavorite
            }
            return false
        }

        return results
    }

    private var hasFavorites: Bool {
        filteredEntries.contains { $0.entry.isFavorite }
    }

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            if availableGroups.count > 1 {
                groupPicker
            }

            List(selection: $appState.selectedEntryID) {
                if hasFavorites {
                    Section {
                        ForEach(filteredEntries.filter(\.entry.isFavorite), id: \.entry.id) { item in
                            entryRow(item.entry)
                                .tag(item.entry.id)
                        }
                    } header: {
                        SectionHeader(title: "Favorites")
                    }

                    Section {
                        ForEach(filteredEntries.filter { !$0.entry.isFavorite }, id: \.entry.id) { item in
                            entryRow(item.entry)
                                .tag(item.entry.id)
                        }
                    } header: {
                        SectionHeader(title: "All Entries")
                    }
                } else {
                    ForEach(filteredEntries, id: \.entry.id) { item in
                        entryRow(item.entry)
                            .tag(item.entry.id)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search entries")
            .overlay {
                if appState.entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Color.citadelSecondary.opacity(0.5))
                        Text("No Entries Yet")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Click + to add your first entry")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.citadelSecondary)
                    }
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    // MARK: - Entry Row

    @ViewBuilder
    private func entryRow(_ entry: VaultEntrySummary) -> some View {
        HStack(spacing: 10) {
            // Icon with colored background
            entryIconBadge(entry)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if entry.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                    Text(entry.title.isEmpty ? "(Untitled)" : entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                if entry.entryType != "secure_note" && !entry.username.isEmpty {
                    Text(entry.username)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.citadelSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let expiry = entry.expiryDate {
                if expiry < Date() {
                    Circle()
                        .fill(Color.citadelDanger)
                        .frame(width: 6, height: 6)
                        .help("Expired")
                } else if expiry < Date().addingTimeInterval(7 * 24 * 3600) {
                    Circle()
                        .fill(Color.citadelWarning)
                        .frame(width: 6, height: 6)
                        .help("Expiring soon")
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func entryIconBadge(_ entry: VaultEntrySummary) -> some View {
        if entry.entryType == "secure_note" {
            IconBadge(symbol: "note.text", color: .purple, size: 26)
        } else {
            IconBadge(symbol: "key.fill", color: .citadelAccent, size: 26)
        }
    }

    // MARK: - Group Picker

    @ViewBuilder
    private var groupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                groupChip(label: "All", group: nil)
                ForEach(availableGroups, id: \.self) { group in
                    groupChip(label: groupDisplayName(group), group: group)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        Divider()
    }

    private func groupChip(label: String, group: String?) -> some View {
        Button(label) {
            selectedGroup = group
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: selectedGroup == group ? .semibold : .regular))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            selectedGroup == group
                ? Color.citadelAccent.opacity(0.15)
                : Color.clear,
            in: Capsule()
        )
        .foregroundStyle(selectedGroup == group ? Color.citadelAccent : Color.citadelSecondary)
    }

    private func groupDisplayName(_ path: String) -> String {
        if let last = path.split(separator: "/").last {
            return String(last)
        }
        return path
    }
}
