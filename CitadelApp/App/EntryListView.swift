import SwiftUI
import CitadelCore

/// Sidebar list of vault entries with fuzzy search and group filtering.
struct EntryListView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var selectedGroup: String? = nil

    /// All distinct group paths from entries.
    private var availableGroups: [String] {
        let groups = Set(appState.entries.map(\.group))
        return groups.sorted()
    }

    private var filteredEntries: [(entry: VaultEntrySummary, score: Int)] {
        var source = appState.entries

        // Filter by group if one is selected
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

        // Sort favorites first (stable sort preserves relative order within each group)
        results.sort { lhs, rhs in
            if lhs.entry.isFavorite != rhs.entry.isFavorite {
                return lhs.entry.isFavorite
            }
            return false
        }

        return results
    }

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 0) {
            if availableGroups.count > 1 {
                groupPicker
            }

            List(filteredEntries, id: \.entry.id, selection: $appState.selectedEntryID) { item in
                HStack {
                    entryIcon(item.entry)
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            if item.entry.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                            highlightedText(item.entry.title, query: searchText)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        if item.entry.entryType != "secure_note" && !item.entry.username.isEmpty {
                            highlightedText(item.entry.username, query: searchText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if item.entry.entryType != "secure_note" && !item.entry.url.isEmpty {
                            highlightedText(item.entry.url, query: searchText)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer()
                    if let expiry = item.entry.expiryDate {
                        if expiry < Date() {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                                .help("Expired")
                        } else if expiry < Date().addingTimeInterval(7 * 24 * 3600) {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption2)
                                .help("Expiring soon")
                        }
                    }
                }
                .padding(.vertical, 2)
                .tag(item.entry.id)
            }
            .searchable(text: $searchText, prompt: "Search entries")
            .overlay {
                if appState.entries.isEmpty {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "key",
                        description: Text("Click + to add your first entry.")
                    )
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        }
    }

    @ViewBuilder
    private func entryIcon(_ entry: VaultEntrySummary) -> some View {
        if entry.entryType == "secure_note" {
            Image(systemName: "note.text")
        } else {
            Image(systemName: "key")
        }
    }

    @ViewBuilder
    private var groupPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                groupButton(label: "All", group: nil)
                ForEach(availableGroups, id: \.self) { group in
                    groupButton(label: groupDisplayName(group), group: group)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        Divider()
    }

    private func groupButton(label: String, group: String?) -> some View {
        Button(label) {
            selectedGroup = group
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(selectedGroup == group ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .foregroundStyle(selectedGroup == group ? .primary : .secondary)
        .font(.callout)
    }

    /// Display name: last component of the group path.
    private func groupDisplayName(_ path: String) -> String {
        if let last = path.split(separator: "/").last {
            return String(last)
        }
        return path
    }

    /// Build an AttributedString with matched characters highlighted.
    private func highlightedText(_ text: String, query: String) -> Text {
        guard !query.isEmpty else { return Text(text) }

        let result = FuzzyMatch.match(query: query, in: text)
        guard result.score > 0, !result.matchedIndices.isEmpty else {
            return Text(text)
        }

        let chars = Array(text)
        let matchedSet = Set(result.matchedIndices)
        var attributed = AttributedString()

        for (i, char) in chars.enumerated() {
            var chunk = AttributedString(String(char))
            if matchedSet.contains(i) {
                chunk.foregroundColor = .accentColor
                chunk.font = .body.bold()
            }
            attributed.append(chunk)
        }

        return Text(attributed)
    }
}
