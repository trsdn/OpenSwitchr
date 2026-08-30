import AppKit
import CoreGraphics
import Foundation
import Observation
import OpenSwitchrCore
import SwiftUI

/// Bridges the `ThumbnailStore` actor into SwiftUI.
///
/// Views never await a capture. They ask for whatever is cached, render
/// immediately, and this provider fills the gap asynchronously and publishes
/// the result. That is what keeps the overlay under its 100 ms budget no
/// matter how slow a capture turns out to be.
@MainActor
@Observable
public final class ThumbnailProvider {

    @ObservationIgnored public let store: ThumbnailStore
    private var images: [CGWindowID: CGImage] = [:]
    @ObservationIgnored private var requested: Set<CGWindowID> = []

    /// The pixel size each loaded image was captured at.
    ///
    /// Without this a thumbnail captured for a small tile is reused when the
    /// preview size grows, and SwiftUI scales it up: the setting appears to
    /// work while every preview quietly turns soft.
    @ObservationIgnored private var capturedSizes: [CGWindowID: CGFloat] = [:]

    public init(store: ThumbnailStore = ThumbnailStore()) {
        self.store = store
    }

    /// Already-loaded image for a window, if any.
    public func image(for windowID: CGWindowID) -> CGImage? {
        images[windowID]
    }

    /// Requests a capture unless one for this window is already in flight.
    ///
    /// This always reaches the store, which is what makes the refresh-rate
    /// setting mean anything: the age limit lives there, and short-circuiting
    /// here on "an image is already loaded" made every loaded preview immortal
    /// and the setting a no-op. A cache hit inside the store costs an actor
    /// hop, which is nothing next to a capture.
    public func request(_ windowID: CGWindowID, maxPixelSize: CGFloat = 640) {
        guard !requested.contains(windowID) else { return }

        // Shrinking a tile reuses the larger capture; only growing needs a new
        // one, so the size asked for never goes down.
        let target = max(maxPixelSize, capturedSizes[windowID] ?? 0)

        requested.insert(windowID)

        Task { [weak self] in
            guard let self else { return }
            let thumbnail = await self.store.thumbnail(for: windowID, maxPixelSize: target)
            self.requested.remove(windowID)
            guard let thumbnail else { return }
            self.images[windowID] = thumbnail.cgImage
            self.capturedSizes[windowID] = target
        }
    }

    /// Requests captures for a whole set of windows that is about to be shown.
    ///
    /// A tile's `onAppear` cannot own this. Both panels are only ordered out,
    /// never torn down, so their SwiftUI tree survives and a tile that has been
    /// shown once keeps its identity and never appears again. Every path that
    /// drops an image — `clear()` on a Space change drops all of them — was
    /// therefore permanent: previews thinned out over a session until only
    /// icon tiles were left, and only relaunching brought them back.
    public func prefetch(_ windowIDs: some Sequence<CGWindowID>, maxPixelSize: CGFloat) {
        for id in windowIDs {
            request(id, maxPixelSize: maxPixelSize)
        }
    }

    /// Drops cached captures so the next request re-captures at the current
    /// size. Called when the preview size changes.
    public func invalidateForResize() {
        images.removeAll()
        capturedSizes.removeAll()
        Task { [store] in await store.clear() }
    }

    /// Forgets a window entirely, for example after it closed.
    public func invalidate(_ windowID: CGWindowID) {
        images.removeValue(forKey: windowID)
        capturedSizes.removeValue(forKey: windowID)
        Task { [store] in await store.invalidate(windowID) }
    }

    /// Drops everything not in `ids`, keeping the published set aligned with
    /// the live window index.
    public func retain(only ids: Set<CGWindowID>) {
        images = images.filter { ids.contains($0.key) }
        capturedSizes = capturedSizes.filter { ids.contains($0.key) }
        Task { [store] in await store.retain(only: ids) }
    }

    public func clear() {
        images.removeAll()
        capturedSizes.removeAll()
        requested.removeAll()
        Task { [store] in await store.clear() }
    }
}

/// Small cache for application icons, which are surprisingly expensive to
/// fetch repeatedly while a grid scrolls.
@MainActor
public enum AppIconCache {
    private static var icons: [pid_t: NSImage] = [:]

    public static func icon(forPID pid: pid_t) -> NSImage? {
        if let cached = icons[pid] { return cached }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        icons[pid] = icon
        return icon
    }

    public static func clear() {
        icons.removeAll()
    }
}
