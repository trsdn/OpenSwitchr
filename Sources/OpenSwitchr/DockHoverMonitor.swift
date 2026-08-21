import AppKit
import ApplicationServices
import Foundation
import OpenSwitchrCore
import OSLog

/// Detects which Dock icon the pointer is over.
///
/// Uses only the public accessibility API. The Dock updates its selected child
/// as the pointer moves across it, so hovering is observable as a notification
/// instead of by polling the mouse — which is what keeps idle CPU at zero.
@MainActor
public final class DockHoverMonitor {

    public struct DockItem: Equatable {
        public let title: String
        public let bundleID: String?
        /// Frame in accessibility coordinates (origin at the top-left of the
        /// primary display, y growing downwards).
        public let frame: CGRect
    }

    /// Fires with the hovered item, or `nil` when the pointer leaves the Dock.
    public var onHover: ((DockItem?) -> Void)?

    private var observer: AXObserver?
    private var dockElement: AXUIElement?
    private var listElement: AXUIElement?
    private var lastItem: DockItem?
    private let logger = Logger(subsystem: "com.openswitchr.app", category: "DockHover")

    public init() {}

    // MARK: - Lifecycle

    @discardableResult
    public func start() -> Bool {
        guard observer == nil else { return true }
        guard AXBridge.isTrusted else { return false }

        guard let dockApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first
        else {
            logger.notice("Dock process not found")
            return false
        }

        let app = AXBridge.application(pid: dockApp.processIdentifier)
        AXBridge.setTimeout(app, seconds: 0.25)
        dockElement = app

        guard let list = Self.findItemList(in: app) else {
            logger.notice("Could not locate the Dock item list")
            return false
        }
        listElement = list

        var created: AXObserver?
        guard AXObserverCreate(dockApp.processIdentifier, Self.callback, &created) == .success,
              let created
        else {
            logger.error("Could not create Dock AX observer")
            return false
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        var attached = false

        if AXObserverAddNotification(created, list, kAXSelectedChildrenChangedNotification as CFString, context) == .success {
            attached = true
        }
        // Fallback for Dock builds that report hovering as a focus change
        // rather than a selection change.
        if AXObserverAddNotification(created, app, kAXFocusedUIElementChangedNotification as CFString, context) == .success {
            attached = true
        }

        guard attached else {
            logger.notice("Dock accepted no hover notifications")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        return true
    }

    public func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        dockElement = nil
        listElement = nil
        lastItem = nil
    }

    // MARK: - Callback

    private static let callback: AXObserverCallback = { _, _, _, context in
        guard let context else { return }
        let monitor = Unmanaged<DockHoverMonitor>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            monitor.readHoveredItem()
        }
    }

    private func readHoveredItem() {
        let item = currentSelection()
        guard item != lastItem else { return }
        lastItem = item
        onHover?(item)
    }

    private func currentSelection() -> DockItem? {
        guard let listElement else { return nil }
        let selected = AXBridge.elements(listElement, kAXSelectedChildrenAttribute as String)
        guard let element = selected.first else { return nil }
        return describe(element)
    }

    private func describe(_ element: AXUIElement) -> DockItem? {
        let title = AXBridge.string(element, kAXTitleAttribute as String) ?? ""
        guard let frame = AXBridge.frame(element) else { return nil }

        var bundleID: String?
        if let url = AXBridge.copyValue(element, kAXURLAttribute as String) as? URL {
            bundleID = Bundle(url: url)?.bundleIdentifier
        }

        return DockItem(title: title, bundleID: bundleID, frame: frame)
    }

    // MARK: - Discovery

    /// Walks the Dock's element tree to find the list that holds the icons.
    private static func findItemList(in app: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 4 else { return nil }

        for child in AXBridge.elements(app, kAXChildrenAttribute as String) {
            if let role = AXBridge.string(child, kAXRoleAttribute as String), role == kAXListRole as String {
                return child
            }
            if let nested = findItemList(in: child, depth: depth + 1) {
                return nested
            }
        }
        return nil
    }
}
