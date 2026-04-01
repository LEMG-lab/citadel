import SwiftUI
import CitadelCore

// MARK: - Sort Order

enum SortOrder: String, CaseIterable {
    case name = "Name"
    case dateModified = "Date Modified"
}

// MARK: - Entry List View

/// Middle column: searchable, sortable list of vault entries.
/// Uses ScrollView + LazyVStack instead of List to avoid macOS List text rendering issues.
struct EntryListView: View {
    @Environment(AppState.self) private var appState
    let entries: [VaultEntrySummary]
    @Binding var selectedEntryID: String?

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name
    @State private var showingDeleteConfirmation = false
    @State private var entryToDelete: String?
    @State private var bulkDeleteMode = false
    @State private var selectedForDeletion: Set<String> = []
    @State private var showingBulkDeleteConfirmation = false

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
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                TextField("Search entries", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                    .buttonStyle(.plain)
                }
                if !entries.isEmpty {
                    Button {
                        if bulkDeleteMode {
                            bulkDeleteMode = false
                            selectedForDeletion.removeAll()
                        } else {
                            bulkDeleteMode = true
                            selectedForDeletion.removeAll()
                        }
                    } label: {
                        Image(systemName: bulkDeleteMode ? "xmark.circle" : "trash")
                            .font(.system(size: 12))
                            .foregroundColor(bulkDeleteMode ? Color(nsColor: .secondaryLabelColor) : .red)
                    }
                    .buttonStyle(.plain)
                    .help(bulkDeleteMode ? "Cancel bulk delete" : "Bulk delete entries")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Entry list
            if entries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Text("No Entries Yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(nsColor: .labelColor))
                    Text("Click + to add your first entry")
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
            } else if displayEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Text("No results for \"\(searchText)\"")
                        .font(.system(size: 13))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(displayEntries) { entry in
                                HStack(spacing: 0) {
                                    if bulkDeleteMode {
                                        Image(systemName: selectedForDeletion.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedForDeletion.contains(entry.id) ? Color.red : Color(nsColor: .secondaryLabelColor))
                                            .font(.system(size: 16))
                                            .frame(width: 28)
                                            .padding(.leading, 4)
                                    }
                                    entryRow(entry)
                                }
                                    .id(entry.id)
                                    .background(rowBackground(for: entry.id))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if bulkDeleteMode {
                                            if selectedForDeletion.contains(entry.id) {
                                                selectedForDeletion.remove(entry.id)
                                            } else {
                                                selectedForDeletion.insert(entry.id)
                                            }
                                        } else {
                                            selectedEntryID = entry.id
                                        }
                                    }
                                    .contextMenu {
                                        if !bulkDeleteMode {
                                            Button("Delete") {
                                                entryToDelete = entry.id
                                                showingDeleteConfirmation = true
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedEntryID) { _, newID in
                        if let newID {
                            withAnimation {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer
            if bulkDeleteMode {
                HStack(spacing: 8) {
                    Button(selectedForDeletion.count == displayEntries.count ? "Deselect All" : "Select All") {
                        if selectedForDeletion.count == displayEntries.count {
                            selectedForDeletion.removeAll()
                        } else {
                            selectedForDeletion = Set(displayEntries.map(\.id))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .font(.system(size: 12))
                    Spacer()
                    Text("\(selectedForDeletion.count) selected")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    Button("Delete Selected") {
                        showingBulkDeleteConfirmation = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.system(size: 12, weight: .semibold))
                    .disabled(selectedForDeletion.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    Text("\(displayEntries.count) item\(displayEntries.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))

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
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .confirmationDialog("Delete Entry", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = entryToDelete { deleteEntry(id) }
                entryToDelete = nil
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("This entry will be moved to Trash.")
        }
        .confirmationDialog("Delete \(selectedForDeletion.count) Entries", isPresented: $showingBulkDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete \(selectedForDeletion.count) Entries", role: .destructive) {
                bulkDeleteEntries()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(selectedForDeletion.count) entr\(selectedForDeletion.count == 1 ? "y" : "ies")? They will be moved to Trash.")
        }
    }

    // MARK: - Row Background

    @ViewBuilder
    private func rowBackground(for id: String) -> some View {
        if selectedEntryID == id {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.15))
                .padding(.horizontal, 4)
        } else {
            Color.clear
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
                        .foregroundColor(Color(nsColor: .labelColor))
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
                        .foregroundColor(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                }

                if let host = domain(from: entry.url) {
                    Text(host)
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .lineLimit(1)
                }
            }

            Spacer()

            if entry.attachmentCount > 0 {
                Image(systemName: "paperclip")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .help("\(entry.attachmentCount) attachment\(entry.attachmentCount == 1 ? "" : "s")")
            }

            // Alert indicator dots
            alertDots(for: entry)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func alertDots(for entry: VaultEntrySummary) -> some View {
        let alerts = appState.entryAlerts[entry.id]
        HStack(spacing: 3) {
            if alerts?.breached == true {
                Circle().fill(Color.citadelDanger).frame(width: 7, height: 7).help("Breached password")
            }
            if alerts?.weak == true {
                Circle().fill(Color.orange).frame(width: 7, height: 7).help("Weak password")
            }
            if alerts?.old == true {
                Circle().fill(Color.citadelWarning).frame(width: 7, height: 7).help("Old password (>180 days)")
            }
            if alerts?.missingTOTP == true {
                Circle().fill(Color.citadelAccent).frame(width: 7, height: 7).help("Missing TOTP")
            }
            if let expiry = entry.expiryDate {
                if expiry < Date() {
                    Circle().fill(Color.citadelDanger).frame(width: 7, height: 7).help("Expired")
                } else if expiry < Date().addingTimeInterval(7 * 24 * 3600) {
                    Circle().fill(Color.citadelWarning).frame(width: 7, height: 7).help("Expiring soon")
                }
            }
        }
    }

    // MARK: - Helpers

    private func domain(from urlString: String) -> String? {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let host = url.host else { return nil }
        return host
    }

    private func deleteEntry(_ id: String) {
        do {
            try appState.engine.deleteEntry(uuid: id)
            try appState.save()
            if selectedEntryID == id { selectedEntryID = nil }
            try appState.refreshEntries()
        } catch {
            // Silently fail
        }
    }

    private func bulkDeleteEntries() {
        do {
            for id in selectedForDeletion {
                try appState.engine.deleteEntry(uuid: id)
            }
            try appState.save()
            if let sel = selectedEntryID, selectedForDeletion.contains(sel) {
                selectedEntryID = nil
            }
            try appState.refreshEntries()
        } catch {
            // best-effort
        }
        bulkDeleteMode = false
        selectedForDeletion.removeAll()
    }
}
