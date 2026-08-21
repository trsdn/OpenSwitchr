import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// A single switchable window.
///
/// Identity comes from CoreGraphics (`CGWindowID`) because that is what
/// ScreenCaptureKit needs and because it survives title changes. The
/// accessibility element is attached opportunistically: apps that deny
/// accessibility still show up in the switcher, they just fall back to
/// app-level activation instead of per-window raising.
public struct WindowInfo: Identifiable, Equatable {
    public let id: CGWindowID
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    public var title: String
    public var frame: CGRect
    public var isMinimized: Bool
    public var isOnScreen: Bool
    public var element: AXUIElement?

    public init(
        id: CGWindowID,
        pid: pid_t,
        bundleID: String?,
        appName: String,
        title: String,
        frame: CGRect,
        isMinimized: Bool,
        isOnScreen: Bool,
        element: AXUIElement?
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
        self.isOnScreen = isOnScreen
        self.element = element
    }

    /// What the switcher shows as the primary label.
    public var displayTitle: String {
        title.isEmpty ? appName : title
    }

    public static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.frame == rhs.frame
            && lhs.isMinimized == rhs.isMinimized
            && lhs.isOnScreen == rhs.isOnScreen
    }
}
