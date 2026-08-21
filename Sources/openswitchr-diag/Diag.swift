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
