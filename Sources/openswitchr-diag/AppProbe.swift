import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Drives the installed OpenSwitchr the way a user would and watches the window
/// server for the result.
///
/// The unit tests and the rest of this harness all exercise the core directly,
/// which cannot show whether the *app* works. Two failures once hid behind a
/// green suite: the app never started its subsystems at all, and preferences
/// silently refused to change. Both were only visible from outside.
@MainActor
enum AppProbe {

    private static let tabKey: CGKeyCode = 0x30

    /// Probe the modifier the user actually configured. Hard-coding ⌥ would
    /// happily report success while the user's own ⌘-Tab does nothing.
    private static func configuredModifier() -> (name: String, key: CGKeyCode, flag: CGEventFlags) {
        // The fallback must mirror `PreferencesStore`, which registers
        // `command`. A divergence here would press the wrong key on a fresh
        // install and report an app failure that does not exist.
        let stored = UserDefaults(suiteName: "com.openswitchr.app")?
            .string(forKey: "holdModifier") ?? "command"
        switch stored {
        case "control": return ("⌃", 0x3B, .maskControl)
        case "option": return ("⌥", 0x3A, .maskAlternate)
        default: return ("⌘", 0x37, .maskCommand)
        }
    }

    static func run() {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.openswitchr.app")
            .first
        else {
            print("OpenSwitchr is not running. Launch it, then run this again.")
            exit(1)
        }
        print("Probing OpenSwitchr, pid \(app.processIdentifier).")
        print("")

        probeSwitcher()
        print("")
        probeDockHover()
        print("")
        print("Idle CPU is not measured here; `ps %cpu` averages over process")
        print("lifetime. Use: top -pid \(app.processIdentifier) -l 6 -s 2 -stats cpu,mem")
    }

    // MARK: - Switcher

    private static func probeSwitcher() {
        print("Switcher overlay")

        let modifier = configuredModifier()
        print("  Using the configured hotkey: \(modifier.name)-Tab")

        let before = frontmostWindowDescription()
        let dockBefore = dockWindowIDs()
        key(modifier.key, down: true, flags: modifier.flag)
        usleep(80_000)
        key(tabKey, down: true, flags: modifier.flag)
        key(tabKey, down: false, flags: modifier.flag)

        let appearance = waitForPanel(timeout: 3.0)
        if let appearance {
            print(String(format: "  Appeared in %.0f ms (%@)", appearance.seconds * 1000, appearance.size))
        } else {
            print("  FAILED: no overlay within 3 s.")
        }

        // The Dock always owns windows, so presence proves nothing; only a
        // window that appeared since the keystroke can be the system switcher.
        let newDockWindows = dockWindowIDs().subtracting(dockBefore)
        if modifier.name == "⌘" {
            print(newDockWindows.isEmpty
                ? "  System app switcher: suppressed."
                : "  FAILED: the macOS app switcher appeared as well.")
        }

        usleep(250_000)
        key(modifier.key, down: false, flags: [])
        usleep(700_000)

        print("  On release: \(panelSizes().isEmpty ? "closed" : "STILL OPEN")")

        let after = frontmostWindowDescription()
        print("  Focus: \(before) -> \(after)")
        print(before == after ? "  FAILED: focus did not move." : "  Focus moved.")
    }

    // MARK: - Dock hover

    private static func probeDockHover() {
        print("Dock hover preview")

        let items = dockItems()
        print("  Dock exposes \(items.count) accessibility items.")
        guard let target = items.first(where: {
            ["Safari", "Google Chrome", "Microsoft Edge", "Finder"].contains($0.title)
        }) else {
            print("  SKIPPED: no known windowed app found in the Dock.")
            return
        }

        let restore = NSEvent.mouseLocation
        let height = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        let parked = CGPoint(
            x: NSScreen.main?.frame.midX ?? target.point.x,
            y: (NSScreen.main?.frame.midY ?? 0) / 2
        )

        // Hover the *same* icon twice. Once was never the interesting case: the
        // Dock never reports that the pointer left it, so a stale "last hovered
        // item" makes the second hover look like no movement at all.
        for pass in 1...2 {
            move(to: parked)
            usleep(400_000)

            print("  Hover \(pass) of \"\(target.title)\".")
            move(to: target.point)
            usleep(120_000)
            // A pointer that never moves again may not generate the events a
            // hover monitor is waiting for.
            move(to: CGPoint(x: target.point.x + 1, y: target.point.y))

            if let appearance = waitForPanel(timeout: 3.0) {
                print(String(format: "    appeared in %.0f ms (%@)", appearance.seconds * 1000, appearance.size))
            } else {
                print("    FAILED: no preview within 3 s.")
            }

            move(to: parked)
            usleep(900_000)
            print("    on exit: \(panelSizes().isEmpty ? "hidden" : "STILL VISIBLE")")
        }

        // NSEvent.mouseLocation is bottom-left origin; CGEvent is top-left, and
        // the flip must use the screen that defines the global coordinate space.
        move(to: CGPoint(x: restore.x, y: height - restore.y))
    }

    // MARK: - Window server

    /// Any on-screen window owned by OpenSwitchr is one of its panels.
    private static func dockWindowIDs() -> Set<Int> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { window -> Int? in
            guard (window[kCGWindowOwnerName as String] as? String) == "Dock" else { return nil }
            return window[kCGWindowNumber as String] as? Int
        })
    }

    private static func panelSizes() -> [String] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { window in
            guard (window[kCGWindowOwnerName as String] as? String) == "OpenSwitchr" else { return nil }
            // Both frontends float above normal windows. Without this the
            // Settings window counts as an overlay, which turns a hotkey that
            // does nothing into a passing measurement.
            guard let layer = window[kCGWindowLayer as String] as? Int, layer > 0 else { return nil }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = bounds["Width"] as? Double ?? 0
            let height = bounds["Height"] as? Double ?? 0
            return "\(Int(width))x\(Int(height))"
        }
    }

    private static func waitForPanel(timeout: TimeInterval) -> (seconds: Double, size: String)? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let size = panelSizes().first {
                return (Date().timeIntervalSince(start), size)
            }
            usleep(5_000)
        }
        return nil
    }

    /// `NSWorkspace.frontmostApplication` is updated by notifications, which do
    /// not arrive in a short-lived process with no run loop, so it reports a
    /// stale answer. The window server's z-order is always current.
    private static func frontmostWindowDescription() -> String {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in list where (window[kCGWindowLayer as String] as? Int ?? 0) == 0 {
            let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
            let title = window[kCGWindowName as String] as? String ?? ""
            return title.isEmpty ? owner : "\(owner) — \(title.prefix(40))"
        }
        return "?"
    }

    // MARK: - Synthetic input

    private static func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private static func move(to point: CGPoint) {
        CGEvent(
            mouseEventSource: CGEventSource(stateID: .hidSystemState),
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    // MARK: - Dock geometry

    private static func dockItems() -> [(title: String, point: CGPoint)] {
        guard let dock = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock")
            .first
        else { return [] }

        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var result: [(String, CGPoint)] = []

        for list in children(of: app) {
            for item in children(of: list) {
                guard let title = string(item, kAXTitleAttribute as String),
                      let point = center(of: item) else { continue }
                result.append((title, point))
            }
        }
        return result
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func center(of element: AXUIElement) -> CGPoint? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let position = positionValue, let size = sizeValue
        else { return nil }

        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }

        return CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2)
    }
}
