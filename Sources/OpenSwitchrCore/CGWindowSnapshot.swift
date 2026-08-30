import CoreGraphics
import Foundation

/// One entry from `CGWindowListCopyWindowInfo`.
///
/// The CoreGraphics window list is the authoritative *set* of windows: unlike
/// the accessibility API it hands out `CGWindowID`s (which ScreenCaptureKit
/// needs), it includes minimized windows, and its ordering seeds the initial
/// MRU list. The accessibility API is layered on top of it for actions.
public struct CGWindowEntry: Sendable, Hashable {
    public let id: CGWindowID
    public let pid: pid_t
    public let title: String?
    public let ownerName: String?
    public let frame: CGRect
    public let isOnScreen: Bool
    /// Position in the front-to-back list. Lower is more in front.
    public let zOrder: Int
}

public enum CGWindowSnapshot {

    /// Smallest window we consider a real, switchable window. Filters out
    /// tooltips, notification shims, and stray helper windows.
    public static let minimumSize = CGSize(width: 48, height: 48)

    /// Reads the current window list, front-most first.
    ///
    /// Only layer 0 windows are kept, which is where normal application
    /// windows live. Panels, menus, the Dock, and the menu bar sit on other
    /// layers and are never switch targets.
    ///
    /// Z-order comes from a second, on-screen-only query rather than from the
    /// position in the `.optionAll` list. Front-to-back ordering is only
    /// documented for the on-screen list; `.optionAll` appends windows on other
    /// Spaces and minimized ones in an order of its own, and mixing the two
    /// produces confident nonsense. Two TextEdit windows one pixel apart
    /// measured as positions 15 and 603 out of 704 while the on-screen list —
    /// correctly — had them adjacent at 145 and 146.
    public static func current() -> [CGWindowEntry] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ranks = onScreenRanks()

        var entries: [CGWindowEntry] = []
        entries.reserveCapacity(raw.count)

        for info in raw {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            guard frame.width >= minimumSize.width, frame.height >= minimumSize.height else { continue }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }

            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let ownerName = info[kCGWindowOwnerName as String] as? String
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false

            entries.append(
                CGWindowEntry(
                    id: id,
                    pid: pid,
                    title: title,
                    ownerName: ownerName,
                    frame: frame,
                    isOnScreen: isOnScreen,
                    // A window that is not on screen is behind every window
                    // that is, so it sorts after all of them rather than
                    // wherever `.optionAll` happened to put it.
                    zOrder: ranks[id] ?? (ranks.count + Int(id))
                )
            )
        }

        return entries.sorted { $0.zOrder < $1.zOrder }
    }

    /// Front-to-back position of every on-screen window, which is the only
    /// ordering CoreGraphics actually promises.
    private static func onScreenRanks() -> [CGWindowID: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var ranks: [CGWindowID: Int] = [:]
        ranks.reserveCapacity(raw.count)
        for (rank, info) in raw.enumerated() {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            ranks[id] = rank
        }
        return ranks
    }
}
