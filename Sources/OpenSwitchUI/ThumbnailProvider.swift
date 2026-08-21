import AppKit
import CoreGraphics
import Foundation
import Observation
import OpenSwitchCore
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

    public init(store: ThumbnailStore = ThumbnailStore()) {
        self.store = store
    }

    /// Already-loaded image for a window, if any.
    public func image(for windowID: CGWindowID) -> CGImage? {
        images[windowID]
    }

    /// Requests a capture unless one is already loaded or in flight.
    public func request(_ windowID: CGWindowID, maxPixelSize: CGFloat = 640) {
        guard images[windowID] == nil, !requested.contains(windowID) else { return }
        requested.insert(windowID)

        Task { [weak self] in
            guard let self else { return }
            let thumbnail = await self.store.thumbnail(for: windowID, maxPixelSize: maxPixelSize)
            self.requested.remove(windowID)
            guard let thumbnail else { return }
            self.images[windowID] = thumbnail.cgImage
        }
    }

    /// Forgets a window entirely, for example after it closed.
    public func invalidate(_ windowID: CGWindowID) {
        images.removeValue(forKey: windowID)
        Task { [store] in await store.invalidate(windowID) }
    }

    /// Drops everything not in `ids`, keeping the published set aligned with
    /// the live window index.
    public func retain(only ids: Set<CGWindowID>) {
        images = images.filter { ids.contains($0.key) }
        Task { [store] in await store.retain(only: ids) }
    }

    public func clear() {
        images.removeAll()
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
