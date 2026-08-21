import CoreGraphics
import Testing

@testable import OpenSwitchCore

@Suite("WindowMatcher")
struct WindowMatcherTests {

    private func window(app: String, title: String, id: CGWindowID = 1) -> WindowInfo {
        WindowInfo(
            id: id,
            pid: 1,
            bundleID: "com.example.\(app.lowercased())",
            appName: app,
            title: title,
            frame: .zero,
            isMinimized: false,
            isOnScreen: true,
            element: nil
        )
    }

    @Test("An empty query keeps every window in MRU order")
    func emptyQueryPreservesOrder() {
        let windows = [
            window(app: "Safari", title: "GitHub", id: 1),
            window(app: "Xcode", title: "Package.swift", id: 2)
        ]

        #expect(WindowMatcher.filter(windows, query: "   ").map(\.id) == [1, 2])
    }

    @Test("A title prefix outranks an app-name prefix")
    func titlePrefixWinsOverAppPrefix() {
        let titleHit = WindowMatcher.score(query: "pack", appName: "Safari", title: "Package.swift")
        let appHit = WindowMatcher.score(query: "pack", appName: "Packages", title: "Untitled")

        #expect(titleHit != nil)
        #expect(appHit != nil)
        #expect(titleHit! > appHit!)
    }

    @Test("A word-boundary hit outranks a mid-word substring")
    func wordBoundaryWinsOverSubstring() {
        let boundary = WindowMatcher.score(query: "hub", appName: "Safari", title: "My hub page")
        let midWord = WindowMatcher.score(query: "hub", appName: "Safari", title: "GitHubbery")

        #expect(boundary != nil)
        #expect(midWord != nil)
        #expect(boundary! > midWord!)
    }

    @Test("Matching is case insensitive")
    func caseInsensitive() {
        #expect(WindowMatcher.score(query: "SAFARI", appName: "Safari", title: "") != nil)
    }

    @Test("A subsequence still matches, but ranks last")
    func subsequenceMatchesWeakly() {
        let subsequence = WindowMatcher.score(query: "pkg", appName: "Finder", title: "Package Manager")
        let substring = WindowMatcher.score(query: "pack", appName: "Finder", title: "My Package")

        #expect(subsequence != nil)
        #expect(substring != nil)
        #expect(substring! > subsequence!)
    }

    @Test("Windows that match nothing are filtered out")
    func nonMatchesAreDropped() {
        let windows = [
            window(app: "Safari", title: "GitHub", id: 1),
            window(app: "Xcode", title: "Package.swift", id: 2)
        ]

        #expect(WindowMatcher.filter(windows, query: "zzz").isEmpty)
        #expect(WindowMatcher.filter(windows, query: "github").map(\.id) == [1])
    }

    @Test("Equal scores fall back to the incoming MRU order")
    func tiesFallBackToMRUOrder() {
        let windows = [
            window(app: "Notes", title: "Report", id: 7),
            window(app: "Notes", title: "Report", id: 8)
        ]

        #expect(WindowMatcher.filter(windows, query: "report").map(\.id) == [7, 8])
    }
}
