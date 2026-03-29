import Foundation

/// CSV import/export in KeePassXC-compatible format.
///
/// Format: `"Group","Title","Username","Password","URL","Notes"`
/// - Export includes a header row
/// - Import accepts files with or without a header row
/// - Fields are double-quote escaped (embedded quotes become `""`)
public enum CSVManager {

    // MARK: - Export

    /// Export entries to CSV data (UTF-8).
    public static func export(entries: [(title: String, username: String, password: String, url: String, notes: String)]) -> Data {
        var lines: [String] = []
        lines.append(csvLine(["Group", "Title", "Username", "Password", "URL", "Notes"]))
        for entry in entries {
            lines.append(csvLine(["Root", entry.title, entry.username, entry.password, entry.url, entry.notes]))
        }
        let csv = lines.joined(separator: "\n") + "\n"
        return Data(csv.utf8)
    }

    // MARK: - Import

    /// Parse CSV data into entries. Returns (title, username, password, url, notes) tuples.
    public static func parse(data: Data) throws -> [(title: String, username: String, password: String, url: String, notes: String)] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CSVError.invalidEncoding
        }

        let rows = parseCSVRows(text)
        guard !rows.isEmpty else { return [] }

        // Detect header row
        let startIndex: Int
        if rows[0].count >= 2 && rows[0][1].lowercased() == "title" {
            startIndex = 1
        } else {
            startIndex = 0
        }

        var entries: [(title: String, username: String, password: String, url: String, notes: String)] = []
        for i in startIndex..<rows.count {
            let row = rows[i]
            // KeePassXC format: Group, Title, Username, Password, URL, Notes
            // Minimum: need at least Title (column 1 in 6-col, or column 0 in 5-col)
            let title: String
            let username: String
            let password: String
            let url: String
            let notes: String

            if row.count >= 6 {
                // Standard KeePassXC format with Group column
                title = row[1]
                username = row[2]
                password = row[3]
                url = row[4]
                notes = row[5]
            } else if row.count >= 5 {
                // Without Group column
                title = row[0]
                username = row[1]
                password = row[2]
                url = row[3]
                notes = row[4]
            } else if row.count >= 2 {
                // Minimal: title + password
                title = row[0]
                username = row.count > 2 ? row[2] : ""
                password = row[1]
                url = row.count > 3 ? row[3] : ""
                notes = row.count > 4 ? row[4] : ""
            } else {
                continue // skip malformed rows
            }

            if title.isEmpty { continue }
            entries.append((title: title, username: username, password: password, url: url, notes: notes))
        }
        return entries
    }

    // MARK: - Internal

    private static func csvLine(_ fields: [String]) -> String {
        fields.map { escapeCSV($0) }.joined(separator: ",")
    }

    private static func escapeCSV(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// RFC 4180-compliant CSV parser supporting quoted fields with embedded commas, newlines, and quotes.
    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        // Escaped quote
                        currentField.append("\"")
                        i = text.index(after: next)
                    } else {
                        // End of quoted field
                        inQuotes = false
                        i = text.index(after: i)
                    }
                } else {
                    currentField.append(c)
                    i = text.index(after: i)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                    i = text.index(after: i)
                } else if c == "," {
                    currentRow.append(currentField)
                    currentField = ""
                    i = text.index(after: i)
                } else if c == "\n" || c == "\r" {
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    // Handle \r\n
                    if c == "\r" {
                        let next = text.index(after: i)
                        if next < text.endIndex && text[next] == "\n" {
                            i = text.index(after: next)
                        } else {
                            i = text.index(after: i)
                        }
                    } else {
                        i = text.index(after: i)
                    }
                } else {
                    currentField.append(c)
                    i = text.index(after: i)
                }
            }
        }

        // Final field/row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        return rows
    }
}

public enum CSVError: Error {
    case invalidEncoding
}
