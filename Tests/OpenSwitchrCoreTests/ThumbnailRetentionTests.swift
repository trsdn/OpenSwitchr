import CoreGraphics
import Foundation
import Testing

@testable import OpenSwitchrCore

@Suite("ThumbnailRetention")
struct ThumbnailRetentionTests {

    // MARK: - Freshness

    @Test("A live window's thumbnail goes stale after the age limit")
    func liveWindowGoesStale() {
        #expect(ThumbnailRetention.isFresh(age: 1, maxAge: 5, isMinimized: false))
        #expect(!ThumbnailRetention.isFresh(age: 5, maxAge: 5, isMinimized: false))
        #expect(!ThumbnailRetention.isFresh(age: 60, maxAge: 5, isMinimized: false))
    }

    @Test("A minimized window's thumbnail never goes stale")
    func minimizedIsExemptFromTheAgeLimit() {
        // A minimized window can never satisfy a refresh, so ageing it out would
        // revert the preview to an icon maxAge seconds in.
        #expect(ThumbnailRetention.isFresh(age: 3600, maxAge: 5, isMinimized: true))
        #expect(ThumbnailRetention.isFresh(age: 3600, maxAge: 0, isMinimized: true))
    }

    // MARK: - Eviction

    @Test("Eviction order takes live entries first, oldest access first")
    func liveEntriesGoFirst() {
        let entries: [ThumbnailRetention.Candidate] = [
            .init(id: 1, lastAccess: Date(timeIntervalSince1970: 30), isMinimized: false),
            .init(id: 2, lastAccess: Date(timeIntervalSince1970: 10), isMinimized: false),
            .init(id: 3, lastAccess: Date(timeIntervalSince1970: 20), isMinimized: false),
        ]
        #expect(ThumbnailRetention.evictionOrder(entries) == [2, 3, 1])
    }

    @Test("A minimized entry is evicted after every live one, however old")
    func minimizedGoesLast() {
        let entries: [ThumbnailRetention.Candidate] = [
            .init(id: 1, lastAccess: Date(timeIntervalSince1970: 1), isMinimized: true),
            .init(id: 2, lastAccess: Date(timeIntervalSince1970: 100), isMinimized: false),
            .init(id: 3, lastAccess: Date(timeIntervalSince1970: 50), isMinimized: false),
        ]
        // The minimized entry is the oldest, and it is the only one that cannot
        // be re-created, so it goes last.
        #expect(ThumbnailRetention.evictionOrder(entries) == [3, 2, 1])
    }

    @Test("Minimized entries are still ordered oldest first among themselves")
    func minimizedOrderedAmongThemselves() {
        let entries: [ThumbnailRetention.Candidate] = [
            .init(id: 1, lastAccess: Date(timeIntervalSince1970: 20), isMinimized: true),
            .init(id: 2, lastAccess: Date(timeIntervalSince1970: 10), isMinimized: true),
        ]
        #expect(ThumbnailRetention.evictionOrder(entries) == [2, 1])
    }

    // MARK: - Restore

    @Test("Windows that left the minimized set have been restored")
    func restoredWindows() {
        #expect(ThumbnailRetention.restored(previous: [1, 2, 3], current: [2]) == [1, 3])
    }

    @Test("Newly minimized windows are not restores")
    func newlyMinimizedAreNotRestored() {
        #expect(ThumbnailRetention.restored(previous: [1], current: [1, 2]).isEmpty)
    }
}
