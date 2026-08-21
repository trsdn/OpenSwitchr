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

    /// Reads the current window list, newest z-order first.
    ///
    /// Only layer 0 windows are kept, which is where normal application
    /// windows live. Panels, menus, the Dock, and the menu bar sit on other
    /// layers and are never switch targets.
    public static func current() -> [CGWindowEntry] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var entries: [CGWindowEntry] = []
        entries.reserveCapacity(raw.count)

        for (index, info) in raw.enumerated() {
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
                    zOrder: index
                )
            )
        }

        return entries
    }
}
