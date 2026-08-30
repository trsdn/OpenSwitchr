import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

/// A captured window image. `CGImage` is immutable but not marked `Sendable`,
/// so it travels in this box.
public struct ThumbnailImage: @unchecked Sendable {
    public let cgImage: CGImage
    public let capturedAt: Date

    public var byteCount: Int {
        cgImage.bytesPerRow * cgImage.height
    }
}

/// Shared, budgeted thumbnail cache backed by ScreenCaptureKit.
///
/// Both frontends draw from this one store, which is the reason OpenSwitchr
/// captures a window once instead of twice. Captures are lazy (only what is
/// actually on screen), coalesced (concurrent requests for the same window
/// share one capture), and bounded (a hard byte budget with LRU eviction).
///
/// `SCScreenshotManager` is the supported path; `CGWindowListCreateImage` has
/// been deprecated since macOS 14 and is deliberately not used as a fallback.
/// When a capture fails the frontends fall back to an icon tile instead.
public actor ThumbnailStore {

    private struct Entry {
        let image: ThumbnailImage
        var lastAccess: Date
    }

    /// How long a cached thumbnail may be reused before it is refreshed on the
    /// next request. Window content changes without any observable event, so a
    /// short age limit is the only sane invalidation for "content changed".
    ///
    /// This is a *threshold checked on request*, never a timer. Nothing here
    /// may run while no frontend is on screen.
    public static let defaultMaxAge: TimeInterval = ThumbnailRefreshRate.default.maxAge

    /// How long the shareable-content listing may be reused. Fetching it is
    /// the expensive part of a capture, so a burst of tile requests shares one
    /// listing.
    private static let contentCacheLifetime: TimeInterval = 1.0

    private var cache: [CGWindowID: Entry] = [:]
    private var inFlight: [CGWindowID: Task<ThumbnailImage?, Never>] = [:]
    private var currentBytes = 0

    private var cachedContent: SCShareableContent?
    private var cachedContentDate: Date = .distantPast
    private var inFlightContent: Task<ContentBox?, Never>?

    /// `SCShareableContent` is not `Sendable`, but it is an immutable snapshot
    /// once returned, so handing it back to the actor is safe.
    private struct ContentBox: @unchecked Sendable {
        let content: SCShareableContent
    }

    private var budgetBytes: Int
    private var maxAge: TimeInterval
    private let logger = Logger(subsystem: "com.openswitchr.app", category: "ThumbnailStore")

    /// Changing the budget takes effect immediately, so lowering it in the
    /// settings frees memory now rather than at the next launch.
    public func setBudget(bytes: Int) {
        budgetBytes = max(1, bytes)
        evictIfNeeded()
    }

    /// Bounds how often a visible thumbnail re-captures. `0` always captures,
    /// `.infinity` reuses the cache until something explicitly invalidates it.
    ///
    /// Lowering the value does not refresh anything by itself; it only makes
    /// the *next* request consider the cache stale. That keeps this free of
    /// timers, which is what keeps idle CPU at zero.
    public func setMaxAge(_ seconds: TimeInterval) {
        maxAge = max(0, seconds)
    }

    public init(budgetBytes: Int = 96 * 1024 * 1024, maxAge: TimeInterval = ThumbnailStore.defaultMaxAge) {
        self.budgetBytes = budgetBytes
        self.maxAge = maxAge
    }

    // MARK: - Reads

    /// Returns a cached thumbnail without triggering a capture. Frontends call
    /// this first so a tile can render instantly.
    public func cached(_ windowID: CGWindowID) -> ThumbnailImage? {
        guard var entry = cache[windowID] else { return nil }
        entry.lastAccess = Date()
        cache[windowID] = entry
        return entry.image
    }

    /// Returns a thumbnail, capturing it if the cache is empty or stale.
    ///
    /// Never throws: a failed capture is a normal outcome (window closed
    /// mid-flight, screen recording not granted) and simply yields `nil`.
    public func thumbnail(for windowID: CGWindowID, maxPixelSize: CGFloat = 640) async -> ThumbnailImage? {
        if let entry = cache[windowID], Date().timeIntervalSince(entry.image.capturedAt) < maxAge {
            return cached(windowID)
        }

        if let existing = inFlight[windowID] {
            return await existing.value
        }

        let task = Task<ThumbnailImage?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.capture(windowID: windowID, maxPixelSize: maxPixelSize)
        }
        inFlight[windowID] = task

        let image = await task.value
        inFlight[windowID] = nil

        if let image {
            store(image, for: windowID)
        }
        return image
    }

    // MARK: - Invalidation

    public func invalidate(_ windowID: CGWindowID) {
        if let entry = cache.removeValue(forKey: windowID) {
            currentBytes -= entry.image.byteCount
        }
    }

    public func retain(only ids: Set<CGWindowID>) {
        for id in cache.keys where !ids.contains(id) {
            invalidate(id)
        }
    }

    /// Drops everything. Wired to memory pressure by the app layer.
    public func clear() {
        cache.removeAll()
        currentBytes = 0
        cachedContent = nil
        cachedContentDate = .distantPast
    }

    public var byteCount: Int { currentBytes }

    // MARK: - Capture

    private func capture(windowID: CGWindowID, maxPixelSize: CGFloat) async -> ThumbnailImage? {
        guard let window = await shareableWindow(id: windowID) else { return nil }

        let width = window.frame.width
        let height = window.frame.height
        guard width > 0, height > 0 else { return nil }

        let scale = min(1.0, maxPixelSize / max(width, height))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(width * scale * 2))
        configuration.height = max(1, Int(height * scale * 2))
        configuration.showsCursor = false
        configuration.ignoreGlobalClipDisplay = true
        configuration.scalesToFit = true

        let filter = SCContentFilter(desktopIndependentWindow: window)

        do {
            return try await Self.captureImage(
                CaptureRequest(filter: filter, configuration: configuration)
            )
        } catch {
            logger.debug("Capture failed for window \(windowID): \(error.localizedDescription)")
            return nil
        }
    }

    /// One capture's inputs, ready to leave the actor.
    ///
    /// Neither type is `Sendable`. Both are built immediately above, used
    /// exactly once, and never read or mutated again on this side, so carrying
    /// them across is safe in the way `@unchecked` is meant to assert.
    private struct CaptureRequest: @unchecked Sendable {
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    /// Runs the capture outside the actor.
    ///
    /// `SCScreenshotManager.captureImage` is nonisolated, so calling it with a
    /// filter built inside the actor sends a `self`-isolated, non-`Sendable`
    /// value into another isolation domain. The macOS 26 SDK annotates its way
    /// out of that; the macOS 15 SDK the release is built against does not, and
    /// rejects it outright — which is why this has to cross the boundary as
    /// `Sendable` values in both directions. The result is boxed in
    /// ``ThumbnailImage`` for the same reason: `CGImage` is immutable but
    /// unmarked.
    private nonisolated static func captureImage(
        _ request: CaptureRequest
    ) async throws -> ThumbnailImage {
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: request.filter,
            configuration: request.configuration
        )
        return ThumbnailImage(cgImage: image, capturedAt: Date())
    }

    private func shareableWindow(id: CGWindowID) async -> SCWindow? {
        guard let content = await shareableContent() else { return nil }
        return content.windows.first { $0.windowID == id }
    }

    /// Returns the current shareable content, at most one query at a time.
    ///
    /// Listing shareable content is expensive, and the overlay asks for every
    /// visible tile at once. Without this coalescing a cold burst of captures
    /// fires one redundant query per tile and the captures stop overlapping.
    private func shareableContent() async -> SCShareableContent? {
        if let cachedContent, Date().timeIntervalSince(cachedContentDate) < Self.contentCacheLifetime {
            return cachedContent
        }

        if let inFlightContent {
            return await inFlightContent.value?.content
        }

        let task = Task<ContentBox?, Never> { [logger] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: false
                )
                return ContentBox(content: content)
            } catch {
                logger.debug("Could not list shareable content: \(error.localizedDescription)")
                return nil
            }
        }
        inFlightContent = task

        let box = await task.value
        inFlightContent = nil

        if let box {
            cachedContent = box.content
            cachedContentDate = Date()
        }
        return box?.content
    }

    // MARK: - Budget

    private func store(_ image: ThumbnailImage, for windowID: CGWindowID) {
        if let previous = cache.removeValue(forKey: windowID) {
            currentBytes -= previous.image.byteCount
        }
        cache[windowID] = Entry(image: image, lastAccess: Date())
        currentBytes += image.byteCount
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        guard currentBytes > budgetBytes else { return }
        for (id, _) in cache.sorted(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            invalidate(id)
            if currentBytes <= budgetBytes { break }
        }
    }
}
