import Foundation

/// Result of a fuzzy match attempt.
public struct FuzzyMatchResult: Sendable {
    /// Score — higher is better. 0 means no match.
    public let score: Int
    /// Indices of matched characters in the haystack string.
    public let matchedIndices: [Int]
}

/// Simple fuzzy matching with scoring.
///
/// Scoring tiers:
/// - Exact substring match (case-insensitive): 1000 + bonus for shorter haystack
/// - All query characters present in order (subsequence): 500 + contiguity bonuses
/// - Characters present but out of order: 100
/// - No match: 0
public enum FuzzyMatch {

    /// Match a query against a haystack string.
    public static func match(query: String, in haystack: String) -> FuzzyMatchResult {
        let q = Array(query.lowercased())
        let h = Array(haystack.lowercased())

        guard !q.isEmpty else {
            return FuzzyMatchResult(score: 0, matchedIndices: [])
        }
        guard !h.isEmpty else {
            return FuzzyMatchResult(score: 0, matchedIndices: [])
        }

        // Tier 1: Exact substring match
        if let range = haystack.range(of: query, options: [.caseInsensitive]) {
            let startIdx = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            let indices = Array(startIdx..<(startIdx + q.count))
            // Bonus for match at start, bonus for shorter haystack
            let startBonus = startIdx == 0 ? 200 : 0
            let lengthBonus = max(0, 100 - h.count)
            return FuzzyMatchResult(score: 1000 + startBonus + lengthBonus, matchedIndices: indices)
        }

        // Tier 2: Subsequence match (characters in order)
        if let indices = subsequenceMatch(query: q, haystack: h) {
            // Bonus for consecutive matches and earlier positions
            var contiguityBonus = 0
            for i in 1..<indices.count {
                if indices[i] == indices[i - 1] + 1 {
                    contiguityBonus += 50
                }
            }
            let startBonus = indices.first == 0 ? 100 : 0
            return FuzzyMatchResult(score: 500 + contiguityBonus + startBonus, matchedIndices: indices)
        }

        // Tier 3: All characters present (out of order)
        var remaining = h
        var matchedIndices: [Int] = []
        for qc in q {
            if let idx = remaining.firstIndex(of: qc) {
                let pos = remaining.distance(from: remaining.startIndex, to: idx)
                // Map back to original haystack position
                let originalPos = h.count - remaining.count + pos
                matchedIndices.append(originalPos)
                remaining = Array(remaining[(remaining.index(after: idx))...])
            } else {
                // Character not found — check if it exists anywhere
                if !h.contains(qc) {
                    return FuzzyMatchResult(score: 0, matchedIndices: [])
                }
            }
        }

        // Verify all query chars exist in haystack (may be out of order)
        var charCounts: [Character: Int] = [:]
        for c in h { charCounts[c, default: 0] += 1 }
        for c in q {
            if let count = charCounts[c], count > 0 {
                charCounts[c] = count - 1
            } else {
                return FuzzyMatchResult(score: 0, matchedIndices: [])
            }
        }

        return FuzzyMatchResult(score: 100, matchedIndices: matchedIndices)
    }

    /// Match a query across multiple fields and return the best score.
    public static func bestMatch(query: String, fields: [String]) -> FuzzyMatchResult {
        var best = FuzzyMatchResult(score: 0, matchedIndices: [])
        for field in fields {
            let result = match(query: query, in: field)
            if result.score > best.score {
                best = result
            }
        }
        return best
    }

    // MARK: - Private

    private static func subsequenceMatch(query: [Character], haystack: [Character]) -> [Int]? {
        var indices: [Int] = []
        var hIdx = 0
        for qc in query {
            var found = false
            while hIdx < haystack.count {
                if haystack[hIdx] == qc {
                    indices.append(hIdx)
                    hIdx += 1
                    found = true
                    break
                }
                hIdx += 1
            }
            if !found { return nil }
        }
        return indices
    }
}
