import SwiftUI
import CitadelCore

// MARK: - Sort Order

enum SortOrder: String, CaseIterable {
    case name = "Name"
    case dateModified = "Date Modified"
}

// MARK: - Entry List View

/// Middle column: searchable, sortable list of vault entries.
struct EntryListView: View {
    let entries: [VaultEntrySummary]
    @Binding var selectedEntryID: String?

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name

    // MARK: - Filtered & sorted entries

    private var displayEntries: [VaultEntrySummary] {
        var results: [VaultEntrySummary]

        if searchText.isEmpty {
            results = entries
        } else {
            let query = searchText
            results = entries
                .compactMap { entry -> (entry: VaultEntrySummary, score: Int)? in
                    let result = FuzzyMatch.bestMatch(
                        query: query,
                        fields: [entry.title, entry.username, entry.url]
                    )
                    guard result.score > 0 else { return nil }
                    return (entry, result.score)
                }
                .sorted { $0.score > $1.score }
                .map(\.entry)
        }

        // Apply sort order (only when not searching, since search has its own ranking)
        if searchText.isEmpty {
            switch sortOrder {
            case .name:
                results.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .dateModified:
                results.sort { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
            }
        }

        return results
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedEntryID) {
                ForEach(displayEntries) { entry in
                    entryRow(entry)
                        .tag(entry.id)
                }
            }
            .searchable(text: $searchText, prompt: "Search entries")
            .overlay {
                if entries.isEmpty {
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
                } else if displayEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }

            Divider()

            // Footer: item count and sort picker
            HStack(spacing: 8) {
                Text("\(displayEntries.count) item\(displayEntries.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.citadelSecondary)

                Spacer()

                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 10))
                        Text(sortOrder.rawValue)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.citadelSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Entry Row

    @ViewBuilder
    private func entryRow(_ entry: VaultEntrySummary) -> some View {
        HStack(spacing: 10) {
            EntryIcon(title: entry.title, entryType: entry.entryType, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.title.isEmpty ? "(Untitled)" : entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if entry.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                }

                if entry.entryType != "secure_note" && !entry.username.isEmpty {
                    Text(entry.username)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let host = domain(from: entry.url) {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let expiry = entry.expiryDate {
                if expiry < Date() {
                    Circle()
                        .fill(Color.citadelDanger)
                        .frame(width: 7, height: 7)
                        .help("Expired")
                } else if expiry < Date().addingTimeInterval(7 * 24 * 3600) {
                    Circle()
                        .fill(Color.citadelWarning)
                        .frame(width: 7, height: 7)
                        .help("Expiring soon")
                }
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Helpers

    private func domain(from urlString: String) -> String? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else { return nil }
        return host
    }
}
