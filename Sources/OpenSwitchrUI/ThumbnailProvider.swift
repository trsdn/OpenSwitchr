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

    /// Requests a capture unless one is already loaded at a sufficient size or
    /// is already in flight.
    public func request(_ windowID: CGWindowID, maxPixelSize: CGFloat = 640) {
        guard !requested.contains(windowID) else { return }

        if images[windowID] != nil {
            // Shrinking reuses the existing capture; only growing needs a new
            // one, and only by enough to be visible.
            let captured = capturedSizes[windowID] ?? maxPixelSize
            guard maxPixelSize > captured * 1.15 else { return }
        }

        requested.insert(windowID)

        Task { [weak self] in
            guard let self else { return }
            let thumbnail = await self.store.thumbnail(for: windowID, maxPixelSize: maxPixelSize)
            self.requested.remove(windowID)
            guard let thumbnail else { return }
            self.images[windowID] = thumbnail.cgImage
            self.capturedSizes[windowID] = maxPixelSize
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
