import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation
import OSLog

/// The single source of truth for open windows.
///
/// This is the whole point of consolidating Dock hover previews and a window
/// switcher into one app: both frontends read from this index, so the
/// expensive work of enumerating and tracking windows happens once.
///
/// Scope is deliberately limited to the **current Space**. Reaching windows on
/// other Spaces requires private SkyLight calls, which are out of bounds.
@MainActor
@Observable
public final class WindowIndex {

    public private(set) var windows: [WindowInfo] = []
    public private(set) var lastRebuildDuration: TimeInterval = 0

    @ObservationIgnored private var mru = MRUTracker()
    @ObservationIgnored private let logger = Logger(subsystem: "com.openswitchr.app", category: "WindowIndex")
    @ObservationIgnored private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Windowed processes, remembered across rebuilds. See
    /// `runningApplications(for:)` for why this is safe to cache.
    @ObservationIgnored private var applicationCache: [pid_t: NSRunningApplication] = [:]

    public init() {}

    // MARK: - Queries

    public func windows(forBundleID bundleID: String) -> [WindowInfo] {
        windows.filter { $0.bundleID == bundleID }
    }

    public func windows(forPID pid: pid_t) -> [WindowInfo] {
        windows.filter { $0.pid == pid }
    }

    public func window(id: CGWindowID) -> WindowInfo? {
        windows.first { $0.id == id }
    }

    public func filtered(query: String) -> [WindowInfo] {
        WindowMatcher.filter(windows, query: query)
    }

    // MARK: - Mutation

    /// Marks a window as most recently used and re-sorts.
    public func noteFocus(windowID: CGWindowID) {
        mru.touch(windowID)
        windows = mru.sorted(windows)
    }

    /// Drops a window the app itself just closed.
    ///
    /// The accessibility notification for a destroyed window arrives later, and
    /// only marks the index stale rather than rebuilding it, so a tile would
    /// otherwise keep showing a window that no longer exists.
    public func remove(windowID: CGWindowID) {
        windows.removeAll { $0.id == windowID }
    }

    /// Marks the window an app just moved focus to as most recently used.
    ///
    /// The accessibility element is the only signal that says *which* window of
    /// a multi-window app was focused, and
    /// `kAXFocusedWindowChangedNotification` hands it over for free. When the
    /// caller has none — an app merely became active — the app is asked which
    /// window it considers focused, which costs one synchronous message on an
    /// event that happens at human speed.
    public func noteFocus(pid: pid_t, element: AXUIElement? = nil) {
        let focused = element
            ?? AXBridge.element(AXBridge.application(pid: pid), kAXFocusedWindowAttribute as String)

        guard let target = Self.focusTarget(pid: pid, element: focused, in: windows) else { return }
        noteFocus(windowID: target.id)
    }

    /// Picks the window a focus event refers to.
    ///
    /// Pure and separately testable, because the interesting case cannot be
    /// reached from a pid: `windows` is sorted most-recently-used first, so
    /// "the first window of this pid" is by construction the window that was
    /// *already* most recent. Falling back to it re-promotes the incumbent and
    /// the order never moves — focusing a second Finder window used to leave
    /// the first one at the top forever. The fallback is kept only for apps
    /// that expose no usable element, where re-promoting the app's last known
    /// window still beats ignoring the event.
    static func focusTarget(pid: pid_t, element: AXUIElement?, in windows: [WindowInfo]) -> WindowInfo? {
        if let element,
           let match = windows.first(where: { window in
               window.element.map { CFEqual($0, element) } ?? false
           }) {
            return match
        }

        return windows.first { $0.pid == pid && !$0.isMinimized }
    }

    /// Rebuilds the index from scratch, blocking the caller.
    ///
    /// Every accessibility read is synchronous inter-process messaging, so this
    /// costs roughly one message per window plus a one-time handshake per app.
    /// Use ``rebuildConcurrently()`` on any path where a stall would be visible.
    public func rebuild() {
        let started = CFAbsoluteTimeGetCurrent()
        let (entries, appsByPID, grouped) = gatherCoreGraphicsState()

        var axByPID: [pid_t: [AXWindowLinker.AXWindow]] = [:]
        for pid in grouped.keys {
            axByPID[pid] = AXWindowLinker.windows(forPID: pid)
        }

        apply(entries: entries, appsByPID: appsByPID, grouped: grouped, axByPID: axByPID, started: started)
    }

    /// Rebuilds the index, querying every app's accessibility tree in parallel
    /// and off the main thread.
    ///
    /// The first message to an app is far more expensive than later ones, so a
    /// cold serial rebuild is dominated by per-app handshakes. Fanning them out
    /// turns that sum into a maximum, and keeps the main thread free while the
    /// slowest app runs out its timeout.
    public func rebuildConcurrently() async {
        let started = CFAbsoluteTimeGetCurrent()
        let (entries, appsByPID, grouped) = gatherCoreGraphicsState()
        let pids = Array(grouped.keys)

        let axByPID = await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: (pid_t, [AXWindowLinker.AXWindow]).self) { group in
                for pid in pids {
                    group.addTask { (pid, AXWindowLinker.windows(forPID: pid)) }
                }

                var collected: [pid_t: [AXWindowLinker.AXWindow]] = [:]
                for await (pid, windows) in group {
                    collected[pid] = windows
                }
                return collected
            }
        }.value

        apply(entries: entries, appsByPID: appsByPID, grouped: grouped, axByPID: axByPID, started: started)
    }

    private func gatherCoreGraphicsState() -> (
        entries: [CGWindowEntry],
        appsByPID: [pid_t: NSRunningApplication],
        grouped: [pid_t: [CGWindowEntry]]
    ) {
        let entries = CGWindowSnapshot.current()
        let appsByPID = runningApplications(for: entries)

        var grouped: [pid_t: [CGWindowEntry]] = [:]
        for entry in entries where entry.pid != ownPID {
            guard appsByPID[entry.pid] != nil else { continue }
            grouped[entry.pid, default: []].append(entry)
        }

        return (entries, appsByPID, grouped)
    }

    private func apply(
        entries: [CGWindowEntry],
        appsByPID: [pid_t: NSRunningApplication],
        grouped: [pid_t: [CGWindowEntry]],
        axByPID: [pid_t: [AXWindowLinker.AXWindow]],
        started: CFAbsoluteTime
    ) {
        var result: [WindowInfo] = []
        result.reserveCapacity(entries.count)

        for (pid, pidEntries) in grouped {
            guard let app = appsByPID[pid] else { continue }
            let appName = app.localizedName ?? pidEntries.first?.ownerName ?? "Unknown"
            let links = AXWindowLinker.link(axWindows: axByPID[pid] ?? [], to: pidEntries)

            for entry in pidEntries {
                let link = links[entry.id]
                // Without an accessibility counterpart a CoreGraphics window is
                // either on another Space, or one of the untitled helper and
                // overlay surfaces apps keep around. Neither belongs in a
                // switcher: a real window has a title, an AX element, or both.
                if link == nil, !entry.isOnScreen || (entry.title ?? "").isEmpty { continue }

                result.append(
                    WindowInfo(
                        id: entry.id,
                        pid: pid,
                        bundleID: app.bundleIdentifier,
                        appName: appName,
                        title: link?.title.isEmpty == false ? link!.title : (entry.title ?? ""),
                        frame: entry.frame,
                        isMinimized: link?.isMinimized ?? false,
                        isOnScreen: entry.isOnScreen,
                        element: link?.element
                    )
                )
            }
        }

        let zOrdered = entries
            .filter { entry in result.contains { $0.id == entry.id } }
            .sorted { $0.zOrder < $1.zOrder }
            .map(\.id)

        mru.seed(zOrdered: zOrdered)
        mru.retain(only: Set(result.map(\.id)))

        // Stamped here rather than looked up later, so a pure filter can order
        // by "most recently opened" without reaching back into the index.
        for offset in result.indices {
            result[offset].openedRank = mru.openedRank(of: result[offset].id)
        }

        windows = mru.sorted(result)
        lastRebuildDuration = CFAbsoluteTimeGetCurrent() - started

        logger.debug("Rebuilt index: \(self.windows.count) windows in \(self.lastRebuildDuration * 1000, format: .fixed(precision: 1)) ms")
    }

    /// How many switchable windows an app exposes over accessibility.
    ///
    /// Diagnostics only: it separates "the linker failed" from "this app
    /// exposes nothing", which call for very different fixes.
    public static func accessibilityWindowCount(forPID pid: pid_t) -> Int {
        AXWindowLinker.windows(forPID: pid).count
    }

    /// Resolves only the processes that actually own a window, and remembers
    /// them.
    ///
    /// `NSWorkspace.runningApplications` walks every process on the system and
    /// dominated rebuild cost — around 60% of it in a sampled profile — even
    /// though a rebuild only ever needs the handful of processes with windows
    /// on screen. A direct per-pid lookup is far cheaper, and the result is
    /// stable enough to cache: pids are not reused while the process lives, so
    /// an entry is valid until that process terminates.
    private func runningApplications(for entries: [CGWindowEntry]) -> [pid_t: NSRunningApplication] {
        var map: [pid_t: NSRunningApplication] = [:]

        for pid in Set(entries.map(\.pid)) where pid != ownPID {
            if let cached = applicationCache[pid] {
                // A terminated process can leave a stale window entry behind
                // for a moment, and its NSRunningApplication goes hollow.
                if cached.isTerminated {
                    applicationCache[pid] = nil
                } else {
                    map[pid] = cached
                    continue
                }
            }

            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular
            else { continue }

            applicationCache[pid] = app
            map[pid] = app
        }

        return map
    }
}
