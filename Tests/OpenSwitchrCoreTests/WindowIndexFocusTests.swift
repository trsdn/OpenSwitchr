import ApplicationServices
import CoreGraphics
import Testing

@testable import OpenSwitchrCore

/// Covers which window a focus event is taken to mean.
///
/// The bug these pin down was invisible in every single-window app and wrong in
/// every multi-window one: the pid alone cannot say which of an app's windows
/// was focused, and the list being searched is sorted most-recently-used first,
/// so the answer was always the window that was already on top.
@Suite("WindowIndex focus target")
@MainActor
struct WindowIndexFocusTests {

    private func distinctElement(_ seed: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(seed)
    }

    private func window(
        id: CGWindowID,
        pid: pid_t = 42,
        element: AXUIElement?,
        minimized: Bool = false
    ) -> WindowInfo {
        WindowInfo(
            id: id,
            pid: pid,
            bundleID: "com.example.app",
            appName: "App",
            title: "Window \(id)",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            isMinimized: minimized,
            isOnScreen: !minimized,
            element: element
        )
    }

    @Test("The focused element wins over most-recently-used order")
    func elementBeatsMRUOrder() {
        let first = distinctElement(1)
        let second = distinctElement(2)
        // Most-recently-used first, so window 10 is the incumbent.
        let windows = [window(id: 10, element: first), window(id: 11, element: second)]

        let target = WindowIndex.focusTarget(pid: 42, element: second, in: windows)

        #expect(target?.id == 11)
    }

    @Test("Without an element the app's most recent window is the best guess")
    func fallsBackToTheAppsMostRecentWindow() {
        let windows = [window(id: 10, element: distinctElement(1)),
                       window(id: 11, element: distinctElement(2))]

        let target = WindowIndex.focusTarget(pid: 42, element: nil, in: windows)

        #expect(target?.id == 10)
    }

    @Test("An element belonging to no known window falls back rather than failing")
    func unknownElementFallsBack() {
        let windows = [window(id: 10, element: distinctElement(1))]

        let target = WindowIndex.focusTarget(pid: 42, element: distinctElement(99), in: windows)

        #expect(target?.id == 10)
    }

    /// Focus implies the window is no longer in the Dock; the index simply has
    /// not rebuilt yet. Skipping it here would drop the event that says so.
    @Test("A matched element still wins when the index still thinks it is minimized")
    func matchedElementWinsOverStaleMinimizedFlag() {
        let restored = distinctElement(2)
        let windows = [window(id: 10, element: distinctElement(1)),
                       window(id: 11, element: restored, minimized: true)]

        let target = WindowIndex.focusTarget(pid: 42, element: restored, in: windows)

        #expect(target?.id == 11)
    }

    @Test("The fallback never picks a minimized window")
    func fallbackSkipsMinimizedWindows() {
        let windows = [window(id: 10, element: distinctElement(1), minimized: true),
                       window(id: 11, element: distinctElement(2))]

        let target = WindowIndex.focusTarget(pid: 42, element: nil, in: windows)

        #expect(target?.id == 11)
    }

    @Test("An event for an app with no windows in the index is ignored")
    func unknownProcessIsIgnored() {
        let windows = [window(id: 10, pid: 42, element: distinctElement(1))]

        let target = WindowIndex.focusTarget(pid: 99, element: nil, in: windows)

        #expect(target == nil)
    }
}
