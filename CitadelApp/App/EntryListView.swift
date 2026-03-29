import SwiftUI
import CitadelCore

/// Sidebar list of vault entries with search filtering.
struct EntryListView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""

    private var filteredEntries: [VaultEntrySummary] {
        if searchText.isEmpty { return appState.entries }
        let query = searchText.lowercased()
        return appState.entries.filter {
            $0.title.lowercased().contains(query) ||
            $0.username.lowercased().contains(query)
        }
    }

    var body: some View {
        @Bindable var appState = appState
        List(filteredEntries, selection: $appState.selectedEntryID) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)
                if !entry.username.isEmpty {
                    Text(entry.username)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !entry.url.isEmpty {
                    Text(entry.url)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.vertical, 2)
            .tag(entry.id)
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
