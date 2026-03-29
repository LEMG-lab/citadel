import Testing
import Foundation
@testable import CitadelCore

@Suite("FuzzyMatch")
struct FuzzyMatchTests {

    @Test("Exact substring match scores highest")
    func exactSubstring() {
        let result = FuzzyMatch.match(query: "mail", in: "Gmail")
        #expect(result.score >= 1000)
        #expect(result.matchedIndices == [1, 2, 3, 4])
    }

    @Test("Case-insensitive exact match")
    func caseInsensitive() {
        let result = FuzzyMatch.match(query: "GITHUB", in: "GitHub")
        #expect(result.score >= 1000)
    }

    @Test("Subsequence match — characters in order but not contiguous")
    func subsequenceMatch() {
        let result = FuzzyMatch.match(query: "gml", in: "Gmail")
        #expect(result.score >= 500)
        #expect(result.score < 1000)
    }

    @Test("No match returns zero score")
    func noMatch() {
        let result = FuzzyMatch.match(query: "xyz", in: "Gmail")
        #expect(result.score == 0)
    }

    @Test("Empty query returns zero score")
    func emptyQuery() {
        let result = FuzzyMatch.match(query: "", in: "Gmail")
        #expect(result.score == 0)
    }

    @Test("Empty haystack returns zero score")
    func emptyHaystack() {
        let result = FuzzyMatch.match(query: "test", in: "")
        #expect(result.score == 0)
    }

    @Test("Best match across multiple fields")
    func bestMatchMultiFields() {
        let result = FuzzyMatch.bestMatch(
            query: "alice",
            fields: ["GitHub", "alice@example.com", "https://github.com"]
        )
        #expect(result.score >= 1000) // exact substring in username
    }

    @Test("Match at start gets bonus")
    func startBonus() {
        let atStart = FuzzyMatch.match(query: "git", in: "GitHub")
        let inMiddle = FuzzyMatch.match(query: "hub", in: "GitHub")
        #expect(atStart.score > inMiddle.score)
    }

    @Test("Sorting: exact match ranks above subsequence")
    func sortingOrder() {
        let exact = FuzzyMatch.match(query: "mail", in: "Gmail")
        let subseq = FuzzyMatch.match(query: "gml", in: "Gmail")
        #expect(exact.score > subseq.score)
    }

    @Test("Matched indices are correct for subsequence")
    func subsequenceIndices() {
        let result = FuzzyMatch.match(query: "gml", in: "Gmail")
        // G=0, m=1, a=2, i=3, l=4 → g→0, m→1, l→4
        #expect(result.matchedIndices == [0, 1, 4])
    }
}
