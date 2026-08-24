import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OpenSwitchrCore

/// Measures whether focusing a window actually brings *that* window forward.
///
/// This exists because `WindowActions.focus` asserted an ordering — raise, then
/// activate — that had never been measured. Raising and activating are separate
/// asynchronous messages to two different processes, so whichever runs last
/// decides, and getting it backwards produces exactly the symptom that prompted
/// this: usually the right window, sometimes any other one.
///
/// Nothing here is destructive: it raises windows the user already has open and
/// restores the previously frontmost app when it is done.
@MainActor
enum FocusProbe {

    /// The order the two calls are issued in.
    enum Order: String, CaseIterable {
        /// Neither activation nor `AXMain`, to see what the raise does alone.
        case raiseOnly
        /// What OpenSwitchr shipped with.
        case raiseThenActivate
        /// Activation first, so it cannot undo the raise that follows.
        case activateThenRaise
        /// Tell the app which window is focused, rather than only raising it.
        case focusedWindowAttribute
    }

    static func run(appFilter: String?, rounds: Int, allOrders: Bool = false) {
        let index = WindowIndex()
        index.rebuild()

        let candidates = index.windows.filter { window in
            guard window.element != nil, !window.isMinimized else { return false }
            guard let appFilter else { return true }
            return window.appName.localizedCaseInsensitiveContains(appFilter)
        }

        let grouped = Dictionary(grouping: candidates, by: \.pid)
        guard let (pid, windows) = grouped.max(by: { $0.value.count < $1.value.count }), windows.count > 1 else {
            print("Need an app with at least two linked, non-minimized windows.")
            print("Pass a name, for example: --probe-focus PowerPoint")
            return
        }

        let previousApp = NSWorkspace.shared.frontmostApplication
        print("Probing \(windows[0].appName) (pid \(pid)) with \(windows.count) windows, \(rounds) round(s) each")
        print("")

        // Every raise shuffles windows the user is working in, so the default is
        // the order the app actually ships. The alternatives exist to settle an
        // argument about ordering, not to be run routinely.
        let orders: [Order] = allOrders ? Order.allCases : [.raiseThenActivate]
        for order in orders {
            var hits = 0
            var attempts = 0
            var misses: [(CGWindowID, CGWindowID?)] = []

            for _ in 0..<rounds {
                for target in windows {
                    let before = frontmostWindow(ofPID: pid)
                    let accepted = apply(order, to: target)
                    // The raise is handled by another process; nothing reports
                    // back when it lands, so poll instead of guessing a delay.
                    var front = before
                    for _ in 0..<20 {
                        Thread.sleep(forTimeInterval: 0.05)
                        front = frontmostWindow(ofPID: pid)
                        if front == target.id { break }
                    }

                    attempts += 1
                    if front == target.id {
                        hits += 1
                    } else {
                        misses.append((target.id, front))
                        if misses.count == 1 {
                            print("    accessibility accepted the call: \(accepted)")
                            dumpState(pid: pid, wanted: target)
                        }
                    }
                }
            }

            let rate = attempts == 0 ? 0 : Int((Double(hits) / Double(attempts) * 100).rounded())
            print("\(pad(order.rawValue, 22)) \(hits)/\(attempts) correct (\(rate) %)")
            for (wanted, got) in misses.prefix(6) {
                print("    wanted \(wanted), got \(got.map(String.init) ?? "none")")
            }
        }

        previousApp?.activate(options: [])
    }

    @discardableResult
    private static func apply(_ order: Order, to window: WindowInfo) -> Bool {
        guard let element = window.element else { return false }
        let app = NSRunningApplication(processIdentifier: window.pid)

        switch order {
        case .raiseOnly:
            return AXBridge.perform(element, kAXRaiseAction as String)

        case .raiseThenActivate:
            let raised = AXBridge.perform(element, kAXRaiseAction as String)
            AXBridge.setBool(element, kAXMainAttribute as String, true)
            app?.activate(options: [])
            return raised

        case .activateThenRaise:
            app?.activate(options: [])
            AXBridge.setBool(element, kAXMainAttribute as String, true)
            return AXBridge.perform(element, kAXRaiseAction as String)

        case .focusedWindowAttribute:
            app?.activate(options: [])
            let ok = AXBridge.setValue(
                AXBridge.application(pid: window.pid),
                kAXFocusedWindowAttribute as String,
                element
            )
            AXBridge.setBool(element, kAXMainAttribute as String, true)
            return AXBridge.perform(element, kAXRaiseAction as String) || ok
        }
    }

    /// The window of this process that the window server currently draws in
    /// front. Read from the z-order rather than from `NSWorkspace`, whose
    /// frontmost-application property is updated by notifications and stays
    /// stale in a short-lived process with no run loop.
    private static func frontmostWindow(ofPID pid: pid_t) -> CGWindowID? {
        CGWindowSnapshot.current()
            .filter { $0.pid == pid && $0.isOnScreen }
            .min { $0.zOrder < $1.zOrder }?
            .id
    }

    /// Prints what the two sides actually report right after a miss, which is
    /// the only way to tell "the raise did not work" apart from "the raise
    /// worked on a different window than the tile claimed".
    private static func dumpState(pid: pid_t, wanted: WindowInfo) {
        print("    --- state after failing to raise \(wanted.id) (\(wanted.title)) ---")
        for entry in CGWindowSnapshot.current().filter({ $0.pid == pid }) {
            print("    cg  id=\(entry.id) z=\(entry.zOrder) onScreen=\(entry.isOnScreen) "
                  + "frame=\(Int(entry.frame.origin.x)),\(Int(entry.frame.origin.y)) "
                  + "title=\(entry.title ?? "-")")
        }
        for (position, element) in AXBridge.elements(AXBridge.application(pid: pid), kAXWindowsAttribute as String).enumerated() {
            let title = AXBridge.string(element, kAXTitleAttribute as String) ?? "-"
            let main = AXBridge.bool(element, kAXMainAttribute as String) ?? false
            let origin = AXBridge.point(element, kAXPositionAttribute as String) ?? .zero
            print("    ax  [\(position)] main=\(main) pos=\(Int(origin.x)),\(Int(origin.y)) title=\(title)")
        }
        let targetTitle = wanted.element.flatMap { AXBridge.string($0, kAXTitleAttribute as String) } ?? "-"
        print("    ax element attached to \(wanted.id) reports title: \(targetTitle)")
        print("    ---")
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }
}
