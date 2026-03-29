import Foundation

/// Simple file-based audit logger for vault operations.
///
/// Logs are stored in the vault directory as `audit.log`.
/// Each line is: `ISO8601_TIMESTAMP EVENT_TYPE DETAIL`
/// Rotation: entries older than 30 days are pruned on init.
@MainActor
public final class AuditLogger {

    public enum Event: String {
        case unlock = "UNLOCK"
        case lock = "LOCK"
        case createVault = "CREATE_VAULT"
        case addEntry = "ADD_ENTRY"
        case updateEntry = "UPDATE_ENTRY"
        case deleteEntry = "DELETE_ENTRY"
        case changePassword = "CHANGE_PASSWORD"
        case exportCSV = "EXPORT_CSV"
        case importCSV = "IMPORT_CSV"
        case backup = "BACKUP"
        case emptyRecycleBin = "EMPTY_RECYCLE_BIN"
    }

    private let logPath: String
    private let maxAge: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(vaultDirectory: String) {
        self.logPath = (vaultDirectory as NSString).appendingPathComponent("audit.log")
        rotate()
    }

    /// Log an event with optional detail.
    public func log(_ event: Event, detail: String = "") {
        let timestamp = formatter.string(from: Date())
        let sanitized = detail.replacingOccurrences(of: "\n", with: " ")
        let line = "\(timestamp) \(event.rawValue) \(sanitized)\n"

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
                // Set restrictive permissions
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logPath)
            }
        }
    }

    /// Read recent log entries (most recent first).
    public func recentEntries(limit: Int = 100) -> [String] {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return []
        }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        return Array(lines.suffix(limit).reversed())
    }

    /// Remove entries older than 30 days.
    private func rotate() {
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: "\n")
        let cutoff = Date().addingTimeInterval(-maxAge)

        let kept = lines.filter { line in
            guard !line.isEmpty else { return false }
            // Parse timestamp from start of line
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let first = parts.first,
                  let date = formatter.date(from: String(first)) else {
                return true // keep unparseable lines
            }
            return date > cutoff
        }

        let rotated = kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n")
        try? rotated.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}
