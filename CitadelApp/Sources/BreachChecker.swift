import Foundation
import CryptoKit

/// Checks passwords against the HaveIBeenPwned breach database using k-anonymity.
/// Only the first 5 characters of the SHA-1 hash are sent — the full password never leaves the device.
@MainActor
public final class BreachChecker {

    /// Cached results: SHA-1 hash → breach count (0 = not breached).
    private var cache: [String: Int] = [:]
    private var cacheTimestamp: Date?
    private static let cacheDuration: TimeInterval = 24 * 60 * 60 // 24 hours

    /// Whether the user has consented to breach checking.
    public var hasConsented: Bool {
        get { UserDefaults.standard.bool(forKey: "smaug.breachCheckConsent") }
        set { UserDefaults.standard.set(newValue, forKey: "smaug.breachCheckConsent") }
    }

    public init() {}

    /// Clear expired cache.
    public func clearCacheIfExpired() {
        if let ts = cacheTimestamp, Date().timeIntervalSince(ts) > Self.cacheDuration {
            cache.removeAll()
            cacheTimestamp = nil
        }
    }

    /// Check a single password. Returns the number of times it appeared in breaches (0 = safe).
    public func check(password: Data) async throws -> Int {
        let sha1Hex = sha1Hash(password)
        let prefix = String(sha1Hex.prefix(5))
        let suffix = String(sha1Hex.dropFirst(5)).uppercased()

        // Check cache
        clearCacheIfExpired()
        if let cached = cache[sha1Hex] {
            return cached
        }

        // Query HIBP API
        let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)")!
        var request = URLRequest(url: url)
        request.setValue("Smaug Password Manager", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw BreachCheckError.networkError
        }

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw BreachCheckError.parseError
        }

        // Parse response: each line is "SUFFIX:COUNT"
        var breachCount = 0
        for line in responseString.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count == 2 else { continue }
            let responseSuffix = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            if responseSuffix == suffix {
                breachCount = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                break
            }
        }

        // Cache result
        cache[sha1Hex] = breachCount
        if cacheTimestamp == nil { cacheTimestamp = Date() }

        return breachCount
    }

    /// Check multiple passwords. Returns array of (entryID, title, breachCount).
    public func checkAll(entries: [(id: String, title: String, password: Data)]) async -> [(id: String, title: String, breachCount: Int)] {
        var results: [(id: String, title: String, breachCount: Int)] = []

        for entry in entries {
            guard !entry.password.isEmpty else { continue }
            do {
                let count = try await check(password: entry.password)
                if count > 0 {
                    results.append((id: entry.id, title: entry.title, breachCount: count))
                }
            } catch {
                // Skip entries that fail (network issues) — don't block others
                continue
            }
            // Rate limit: HIBP requests ~1.5s between requests to be polite
            try? await Task.sleep(for: .milliseconds(200))
        }

        return results
    }

    /// SHA-1 hash of data, returned as uppercase hex string.
    private func sha1Hash(_ data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}

public enum BreachCheckError: Error, LocalizedError {
    case networkError
    case parseError
    case notConsented

    public var errorDescription: String? {
        switch self {
        case .networkError: return "Could not reach the breach database"
        case .parseError: return "Could not parse breach data"
        case .notConsented: return "Breach checking requires user consent"
        }
    }
}
