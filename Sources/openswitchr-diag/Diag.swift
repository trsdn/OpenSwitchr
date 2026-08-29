import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OpenSwitchrCore

/// A command-line harness for the parts of OpenSwitchrCore that unit tests
/// cannot judge: whether accessibility enumeration, the AX-to-CGWindowID
/// linking heuristic, and ScreenCaptureKit actually agree with the windows on
/// this Mac.
///
/// Run it from a terminal that already holds the Accessibility permission:
///
///     swift run openswitchr-diag              # window index and linking
///     swift run openswitchr-diag --capture    # also exercise ScreenCaptureKit
///     swift run openswitchr-diag --bench      # also time repeated rebuilds
///     swift run openswitchr-diag --filters    # apply the filter profiles to real windows
///     swift run openswitchr-diag --probe-app  # drive the *installed* app
@main
@MainActor
enum Diag {

    static func main() async {
        let arguments = Set(CommandLine.arguments.dropFirst())

        guard AXBridge.isTrusted else {
            FileHandle.standardError.write(Data("""
            Accessibility permission missing for this process.

            Grant it to the terminal you are running from:
              System Settings > Privacy & Security > Accessibility

            """.utf8))
            exit(1)
        }

        // The core can be perfectly healthy while the app is dead, so this
        // mode deliberately touches none of it.
        if arguments.contains("--probe-app") {
            AppProbe.run()
            return
        }

        if arguments.contains("--probe-focus") {
            let all = CommandLine.arguments
            let filter = all.firstIndex(of: "--probe-focus")
                .flatMap { $0 + 1 < all.count ? all[$0 + 1] : nil }
                .flatMap { $0.hasPrefix("--") ? nil : $0 }
            await MainActor.run {
                FocusProbe.run(
                    appFilter: filter,
                    rounds: 2,
                    allOrders: arguments.contains("--all-orders")
                )
            }
            return
        }

        let index = WindowIndex()
        await index.rebuildConcurrently()
        let windows = index.windows

        print("Cold rebuild: \(windows.count) windows in \(ms(index.lastRebuildDuration))")
        let linked = windows.filter { $0.element != nil }.count
        print("Linked to an accessibility element: \(linked)/\(windows.count)")

        print("")
        printPerApp(windows)
        print("")
        printWindows(windows)

        // Churning window IDs would break both the MRU order and the thumbnail
        // cache, so identity has to survive a rebuild.
        await index.rebuildConcurrently()
        let churn = Set(windows.map(\.id)).symmetricDifference(index.windows.map(\.id))
        print("")
        print("Identity across two rebuilds: \(churn.isEmpty ? "stable" : "\(churn.count) window ID(s) changed")")

        if arguments.contains("--bench") {
            await benchmarkRebuilds(index)
        }
        if arguments.contains("--capture") {
            await benchmarkCaptures(windows)
        }
        if arguments.contains("--audit-links") {
            auditLinks(windows)
        }
        if arguments.contains("--filters") {
            reportFilters(windows)
        }
    }

    /// Applies each surface's filter profile to the windows actually open.
    ///
    /// Everything here is covered by unit tests except the one axis that cannot
    /// be: the display scope compares a window frame reported by CoreGraphics
    /// against a screen frame AppKit reports in the opposite vertical
    /// direction. A wrong flip still looks correct on a single display, because
    /// the two coordinate spaces coincide there, so the only way to judge it is
    /// against the displays attached to this Mac.
    private static func reportFilters(_ windows: [WindowInfo]) {
        let frontmost = windows.first?.pid
        let context = WindowFilter.Context(frontmostPID: frontmost)

        print("")
        print("Filter profiles")
        if let frontmost, let name = windows.first?.appName {
            print("Current application: \(name) (pid \(frontmost))")
        }

        func report(_ label: String, _ filter: WindowFilter, _ context: WindowFilter.Context) {
            let kept = filter.apply(to: windows, context: context)
            print("  " + pad(label, 36) + "\(kept.count)/\(windows.count)")
        }

        report("Dock preview profile", .dockPreview, WindowFilter.Context())
        report("Switcher, defaults", WindowFilter(), context)
        report("Only the current application", WindowFilter(applications: .frontmostOnly), context)
        report("Everything but the current one", WindowFilter(applications: .excludingFrontmost), context)
        report("Minimized hidden", WindowFilter(minimized: .hide), context)
        report("Minimized last", WindowFilter(minimized: .showAfterOthers), context)

        print("")
        print("Display scope, against the attached displays")
        let scoped = WindowFilter(screens: .surfaceScreenOnly)
        var reachable = Set<CGWindowID>()

        for (offset, screen) in NSScreen.screens.enumerated() {
            let frame = WindowFilter.coreGraphicsFrame(of: screen)
            let kept = scoped.apply(to: windows, context: .init(screenFrame: frame))
            reachable.formUnion(kept.map(\.id))

            let geometry = "\(Int(frame.width))×\(Int(frame.height)) at \(Int(frame.minX)),\(Int(frame.minY))"
            print("  " + pad("Display \(offset + 1)  \(geometry)", 36) + "\(kept.count)/\(windows.count)")
        }

        // The check that matters: scoping by display must never make a window
        // unreachable from every display. One that no display claims is either
        // a coordinate flip that is wrong, or a window somewhere nobody can
        // see it.
        let unreachable = windows.filter { !reachable.contains($0.id) }
        print("")
        if unreachable.isEmpty {
            print("Every window is claimed by at least one display.")
        } else {
            print("Claimed by no display: \(unreachable.count)")
            for window in unreachable {
                let frame = window.frame
                print("  " + pad(short(window.appName, 20), 22)
                      + pad(window.isMinimized ? "minimized" : "on screen", 12)
                      + "\(Int(frame.width))×\(Int(frame.height)) at \(Int(frame.minX)),\(Int(frame.minY))")
            }
        }
    }

    /// Checks every accessibility link against CoreGraphics without touching a
    /// single window.
    ///
    /// A mis-link is invisible in the tile — the thumbnail comes from the
    /// `CGWindowID` and is therefore always right — but every *action* goes
    /// through the accessibility element, so the wrong window gets raised. The
    /// only observable cross-checks are the title and the frame the two sides
    /// report for the same window, so that is what this compares.
    private static func auditLinks(_ windows: [WindowInfo]) {
        let entries = CGWindowSnapshot.current()
        var byID: [CGWindowID: CGWindowEntry] = [:]
        for entry in entries { byID[entry.id] = entry }

        print("")
        print("Link audit")
        print(pad("ID", 8) + pad("APP", 16) + pad("CG FRAME", 22) + pad("AX FRAME", 22)
              + pad("TITLES", 10) + "AX TITLE")

        var titleMismatches = 0
        var frameMismatches = 0

        for window in windows.sorted(by: { ($0.appName, $0.id) < ($1.appName, $1.id) }) {
            guard let element = window.element, let entry = byID[window.id] else { continue }

            let axFrame = CGRect(
                origin: AXBridge.point(element, kAXPositionAttribute as String) ?? .zero,
                size: AXBridge.size(element, kAXSizeAttribute as String) ?? .zero
            )
            let axTitle = AXBridge.string(element, kAXTitleAttribute as String) ?? ""
            let cgTitle = entry.title ?? ""

            let titlesComparable = !axTitle.isEmpty && !cgTitle.isEmpty
            let titleVerdict: String
            if !titlesComparable {
                titleVerdict = "n/a"
            } else if axTitle == cgTitle {
                titleVerdict = "equal"
            } else if axTitle.hasPrefix(cgTitle) || cgTitle.hasPrefix(axTitle) {
                titleVerdict = "prefix"
                titleMismatches += 1
            } else {
                titleVerdict = "DIFFER"
                titleMismatches += 1
            }

            let framesEqual = abs(axFrame.origin.x - entry.frame.origin.x) <= 2
                && abs(axFrame.origin.y - entry.frame.origin.y) <= 2
                && abs(axFrame.width - entry.frame.width) <= 2
                && abs(axFrame.height - entry.frame.height) <= 2
            if !framesEqual { frameMismatches += 1 }

            print(
                pad(String(window.id), 8)
                    + pad(short(window.appName, 14), 16)
                    + pad(rect(entry.frame), 22)
                    + pad(framesEqual ? "=" : rect(axFrame), 22)
                    + pad(titleVerdict, 10)
                    + short(axTitle, 30)
            )
        }

        print("")
        print("Titles that are not exactly equal: \(titleMismatches)")
        print("Frames that disagree: \(frameMismatches)")
        reportAmbiguity(windows, byID: byID)
        reportOrdinalHypothesis(windows, byID: byID)
    }

    /// Tests whether accessibility window order tracks CoreGraphics z-order.
    ///
    /// When two windows share a frame *and* a title — four Edge windows did on
    /// the machine this was written on — nothing else observable tells them
    /// apart, and order is the only public signal left. Before relying on it,
    /// this checks it against the cases where titles *do* decide: if the
    /// title-matched pairing and the order-matched pairing agree everywhere the
    /// title is conclusive, order is trustworthy where it is not.
    private static func reportOrdinalHypothesis(_ windows: [WindowInfo], byID: [CGWindowID: CGWindowEntry]) {
        var byPID: [pid_t: [WindowInfo]] = [:]
        for window in windows { byPID[window.pid, default: []].append(window) }

        var agree = 0
        var disagree = 0

        for (pid, group) in byPID where group.count > 1 {
            // Minimized windows have no meaningful z-order, so they cannot take
            // part in an ordering argument either way.
            let live = group.filter { !$0.isMinimized && byID[$0.id]?.isOnScreen == true }
            guard live.count > 1 else { continue }

            let axElements = AXBridge.elements(AXBridge.application(pid: pid), kAXWindowsAttribute as String)
            // Keyed by title, which is all this read-only audit has: it never
            // links, so it cannot tell two windows with the same title apart.
            // Such a group collapses onto one index and reads as "agrees"
            // without having been tested. The real evidence for those windows
            // comes from --probe-focus, which raises them and looks.
            var axOrder: [String: Int] = [:]
            for (position, element) in axElements.enumerated() {
                guard let title = AXBridge.string(element, kAXTitleAttribute as String), !title.isEmpty else { continue }
                if axOrder[title] == nil { axOrder[title] = position }
            }

            let byZOrder = live.sorted { (byID[$0.id]?.zOrder ?? 0) < (byID[$1.id]?.zOrder ?? 0) }
            print("  \(byZOrder[0].appName): z-order vs accessibility index")
            for window in byZOrder {
                let position = axOrder[window.title].map(String.init) ?? "?"
                print("    z=\(byID[window.id]?.zOrder ?? -1)  ax=\(position)  \(short(window.title, 44))")
            }
            var previous = -1
            var conclusive = true
            for window in byZOrder {
                guard let position = axOrder[window.title] else { conclusive = false; break }
                if position < previous { conclusive = false }
                previous = position
            }
            if conclusive { agree += 1 } else { disagree += 1 }
        }

        print("Apps where accessibility order tracks z-order: \(agree) agree, \(disagree) disagree")
    }

    /// Counts windows the linker cannot tell apart.
    ///
    /// Two windows of one app that share a frame, with titles the linker scores
    /// as unequal, are indistinguishable to it — and it still picks one. That is
    /// the difference between "no preview" and "raises the wrong window".
    private static func reportAmbiguity(_ windows: [WindowInfo], byID: [CGWindowID: CGWindowEntry]) {
        var byPID: [pid_t: [WindowInfo]] = [:]
        for window in windows { byPID[window.pid, default: []].append(window) }

        var ambiguous = 0
        for (_, group) in byPID where group.count > 1 {
            for a in group {
                let clashes = group.contains { b in
                    guard b.id != a.id,
                          let fa = byID[a.id]?.frame, let fb = byID[b.id]?.frame else { return false }
                    return abs(fa.origin.x - fb.origin.x) <= 2 && abs(fa.origin.y - fb.origin.y) <= 2
                        && abs(fa.width - fb.width) <= 2 && abs(fa.height - fb.height) <= 2
                }
                if clashes { ambiguous += 1 }
            }
        }
        print("Windows sharing a frame with a sibling: \(ambiguous)")
    }

    private static func rect(_ frame: CGRect) -> String {
        "\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))"
    }

    // MARK: - Reports

    /// Separates "the linker failed" from "this app exposes no accessibility
    /// windows at all", which call for very different responses.
    private static func printPerApp(_ windows: [WindowInfo]) {
        var byPID: [pid_t: [WindowInfo]] = [:]
        for window in windows { byPID[window.pid, default: []].append(window) }

        print(pad("APP", 24) + pad("CG", 5) + pad("AX", 5) + "LINKED")
        for (pid, group) in byPID.sorted(by: { $0.value[0].appName < $1.value[0].appName }) {
            print(
                pad(short(group[0].appName, 22), 24)
                    + pad(String(group.count), 5)
                    + pad(String(WindowIndex.accessibilityWindowCount(forPID: pid)), 5)
                    + String(group.filter { $0.element != nil }.count)
            )
        }
    }

    private static func printWindows(_ windows: [WindowInfo]) {
        print(pad("ID", 8) + pad("PID", 7) + pad("AX", 4) + pad("MIN", 5) + pad("APP", 22) + "TITLE")
        for window in windows {
            print(
                pad(String(window.id), 8)
                    + pad(String(window.pid), 7)
                    + pad(window.element == nil ? "-" : "y", 4)
                    + pad(window.isMinimized ? "y" : "-", 5)
                    + pad(short(window.appName, 20), 22)
                    + short(window.title)
            )
        }
    }

    // MARK: - Benchmarks

    private static func benchmarkRebuilds(_ index: WindowIndex) async {
        var serial: [TimeInterval] = []
        var concurrent: [TimeInterval] = []

        for _ in 0..<5 {
            index.rebuild()
            serial.append(index.lastRebuildDuration)
            await index.rebuildConcurrently()
            concurrent.append(index.lastRebuildDuration)
        }

        print("")
        print("Warm rebuild, serial:     \(summary(serial))")
        print("Warm rebuild, concurrent: \(summary(concurrent))")
    }

    private static func benchmarkCaptures(_ windows: [WindowInfo]) async {
        print("")
        guard CGPreflightScreenCaptureAccess() else {
            print("Capture check skipped: Screen Recording permission missing.")
            return
        }

        let store = ThumbnailStore()
        let ids = windows.prefix(8).map(\.id)

        // The overlay asks for every visible tile at once, so the parallel
        // number is the one that decides whether previews feel instant.
        let started = CFAbsoluteTimeGetCurrent()
        let hits = await Task.detached { () -> Int in
            await withTaskGroup(of: Bool.self) { group in
                for id in ids {
                    group.addTask { await store.thumbnail(for: id, maxPixelSize: 320) != nil }
                }
                var hits = 0
                for await success in group where success { hits += 1 }
                return hits
            }
        }.value
        print("Capture, cold and parallel: \(hits)/\(ids.count) in \(ms(CFAbsoluteTimeGetCurrent() - started))")

        let cached = CFAbsoluteTimeGetCurrent()
        for id in ids { _ = await store.cached(id) }
        print("Capture, cache hits:        \(ms(CFAbsoluteTimeGetCurrent() - cached))")
    }

    // MARK: - Formatting

    private static func summary(_ samples: [TimeInterval]) -> String {
        guard let min = samples.min(), let max = samples.max() else { return "no samples" }
        let mean = samples.reduce(0, +) / Double(samples.count)
        return "min \(ms(min)), mean \(ms(mean)), max \(ms(max))"
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        value.count >= width ? value : value + String(repeating: " ", count: width - value.count)
    }

    private static func short(_ value: String, _ limit: Int = 46) -> String {
        value.count <= limit ? value : String(value.prefix(limit - 1)) + "…"
    }

    private static func ms(_ seconds: TimeInterval) -> String {
        String(format: "%.1f ms", seconds * 1000)
    }
}
