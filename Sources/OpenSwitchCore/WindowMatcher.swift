import Foundation

/// Pure matching logic for the switcher's live filter.
///
/// Kept free of AppKit and accessibility types on purpose: this is the one
/// piece of behaviour that is cheap to unit test and expensive to get subtly
/// wrong, so it lives behind a pure interface.
public enum WindowMatcher {

    public struct Score: Equatable, Comparable {
        /// Higher is better.
        public let value: Int
        /// Tie-breaker: earlier match position wins.
        public let offset: Int

        public static func < (lhs: Score, rhs: Score) -> Bool {
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.offset > rhs.offset
        }
    }

    /// Scores `query` against a window's app name and title.
    ///
    /// Returns `nil` when the window does not match at all. Ranking, best
    /// first: title prefix, app-name prefix, word-boundary hit, plain
    /// substring, subsequence.
    public static func score(query: String, appName: String, title: String) -> Score? {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Score(value: 0, offset: 0) }

        let lowerTitle = title.lowercased()
        let lowerApp = appName.lowercased()

        if lowerTitle.hasPrefix(needle) { return Score(value: 100, offset: 0) }
        if lowerApp.hasPrefix(needle) { return Score(value: 90, offset: 0) }

        if let offset = wordBoundaryOffset(of: needle, in: lowerTitle) {
            return Score(value: 80, offset: offset)
        }
        if let offset = wordBoundaryOffset(of: needle, in: lowerApp) {
            return Score(value: 70, offset: offset)
        }
        if let range = lowerTitle.range(of: needle) {
            return Score(value: 60, offset: lowerTitle.distance(from: lowerTitle.startIndex, to: range.lowerBound))
        }
        if let range = lowerApp.range(of: needle) {
            return Score(value: 50, offset: lowerApp.distance(from: lowerApp.startIndex, to: range.lowerBound))
        }
        if isSubsequence(needle, of: lowerTitle) { return Score(value: 30, offset: 0) }
        if isSubsequence(needle, of: lowerApp) { return Score(value: 20, offset: 0) }

        return nil
    }

    /// Filters and re-ranks windows for a query, keeping the incoming order
    /// (which is MRU) as the tie-breaker.
    public static func filter(_ windows: [WindowInfo], query: String) -> [WindowInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return windows }

        let scored: [(window: WindowInfo, score: Score, rank: Int)] = windows.enumerated().compactMap { index, window in
            guard let score = score(query: trimmed, appName: window.appName, title: window.title) else { return nil }
            return (window, score, index)
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.rank < rhs.rank
            }
            .map(\.window)
    }

    // MARK: - Helpers

    private static func wordBoundaryOffset(of needle: String, in haystack: String) -> Int? {
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let isBoundary: Bool
            if range.lowerBound == haystack.startIndex {
                isBoundary = true
            } else {
                let previous = haystack[haystack.index(before: range.lowerBound)]
                isBoundary = !previous.isLetter && !previous.isNumber
            }
            if isBoundary {
                return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            }
            searchStart = haystack.index(after: range.lowerBound)
            if searchStart >= haystack.endIndex { break }
        }
        return nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        for character in needle {
            var found = false
            while let next = iterator.next() {
                if next == character {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }
}
