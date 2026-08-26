import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Links accessibility windows to CoreGraphics window IDs.
///
/// This is the single trickiest piece of OpenSwitchr. The private
/// `_AXUIElementGetWindow` would hand out the `CGWindowID` directly, but it is
/// off limits (see AGENTS.md), so the link is reconstructed from observable
/// facts: same process, same frame, same title.
///
/// The matching is deliberately conservative. A wrong link would show the
/// preview of one window on the tile of another, which is worse than showing
/// no preview at all, so ambiguous candidates are left unlinked.
enum AXWindowLinker {

    /// How far apart two frames may be and still be considered the same
    /// window. Accessibility and CoreGraphics occasionally disagree by a point
    /// on window shadows and full-screen transitions.
    private static let frameTolerance: CGFloat = 2.0

    /// An accessibility window plus the attributes needed to link it.
    ///
    /// `AXUIElement` is a CoreFoundation object and the accessibility API may
    /// be called from any thread, so this is safe to hand between the actor
    /// gathering it and the main actor consuming it.
    struct AXWindow: @unchecked Sendable {
        let element: AXUIElement
        let title: String
        let frame: CGRect
        let isMinimized: Bool
    }

    /// Reads the windows an app exposes over accessibility.
    ///
    /// Role, subrole, title, position, and size are fetched in one batched
    /// message per window. Doing this attribute by attribute costs five
    /// synchronous round trips per window, which is the difference between a
    /// switcher that opens instantly and one that stutters.
    static func windows(forPID pid: pid_t) -> [AXWindow] {
        let app = AXBridge.application(pid: pid)
        // Unresponsive apps must not stall the main thread. The system default
        // is six seconds, which would be catastrophic for a switcher.
        AXBridge.setTimeout(app, seconds: 0.25)

        let attributes = [
            kAXRoleAttribute as String,
            kAXSubroleAttribute as String,
            kAXTitleAttribute as String,
            kAXPositionAttribute as String,
            kAXSizeAttribute as String,
            kAXMinimizedAttribute as String
        ]

        return AXBridge.elements(app, kAXWindowsAttribute as String).compactMap { element in
            let values = AXBridge.values(element, attributes)
            let isMinimized = AXBridge.bool(values[5]) ?? false
            guard isSwitchable(
                role: AXBridge.string(values[0]),
                subrole: AXBridge.string(values[1]),
                isMinimized: isMinimized
            ) else {
                return nil
            }

            let origin = AXBridge.point(values[3]) ?? .zero
            let size = AXBridge.size(values[4]) ?? .zero

            return AXWindow(
                element: element,
                title: AXBridge.string(values[2]) ?? "",
                frame: CGRect(origin: origin, size: size),
                isMinimized: isMinimized
            )
        }
    }

    /// Excludes sheets, drawers, popovers, and other non-switchable surfaces.
    ///
    /// The subrole stops being trustworthy the moment a window is minimized:
    /// macOS 26.6 reports a minimized window as `AXDialog`, measured on both
    /// Activity Monitor and Preview, even though the same window reported
    /// `AXStandardWindow` a second earlier. Filtering on subrole alone therefore
    /// dropped every window as it went to the Dock — the accessibility side went
    /// to zero, nothing linked, and `WindowIndex` discarded the CoreGraphics
    /// entry because it was no longer on screen. A window in the Dock is exactly
    /// what a switcher is for, so minimized wins over the subrole rather than
    /// the other way round.
    static func isSwitchable(role: String?, subrole: String?, isMinimized: Bool) -> Bool {
        guard role == kAXWindowRole as String else { return false }
        // Some apps omit the subrole entirely; treat those as normal windows.
        guard let subrole else { return true }
        return subrole == kAXStandardWindowSubrole as String || isMinimized
    }

    /// Greedily links AX windows to CoreGraphics entries of the same process.
    ///
    /// Pairs are scored, sorted best-first, and assigned one-to-one. Ties are
    /// broken by depth — see `link` — because leaving them to `sort`, which is
    /// not stable in Swift, is how a Dock preview ends up raising a window the
    /// user did not click.
    static func link(axWindows: [AXWindow], to entries: [CGWindowEntry]) -> [CGWindowID: AXWindow] {
        guard !axWindows.isEmpty, !entries.isEmpty else { return [:] }

        struct Candidate {
            let axIndex: Int
            let entryIndex: Int
            let score: Int
            let depthDistance: Int
        }

        // Depth is the only thing telling apart windows that share a frame and
        // a title, which browsers produce in quantity. Both lists are
        // front-to-back for the windows that are actually on screen, so the
        // n-th live accessibility window is the n-th live CoreGraphics one.
        // Minimized windows have no depth on either side and are excluded.
        var axDepth: [Int: Int] = [:]
        var liveAX = 0
        for (index, ax) in axWindows.enumerated() where !ax.isMinimized {
            axDepth[index] = liveAX
            liveAX += 1
        }

        var entryDepth: [Int: Int] = [:]
        let liveEntries = entries.enumerated()
            .filter { $0.element.isOnScreen }
            .sorted { $0.element.zOrder < $1.element.zOrder }
        for (depth, pair) in liveEntries.enumerated() {
            entryDepth[pair.offset] = depth
        }

        var candidates: [Candidate] = []
        for (axIndex, ax) in axWindows.enumerated() {
            for (entryIndex, entry) in entries.enumerated() {
                let score = score(ax: ax, entry: entry)
                if score > 0 {
                    let distance: Int
                    if let a = axDepth[axIndex], let b = entryDepth[entryIndex] {
                        distance = abs(a - b)
                    } else {
                        distance = Int.max
                    }
                    candidates.append(
                        Candidate(axIndex: axIndex, entryIndex: entryIndex, score: score, depthDistance: distance)
                    )
                }
            }
        }

        // Every component is compared, so the outcome never depends on the
        // order `sort` happens to leave equal elements in.
        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.depthDistance != rhs.depthDistance { return lhs.depthDistance < rhs.depthDistance }
            if lhs.axIndex != rhs.axIndex { return lhs.axIndex < rhs.axIndex }
            return lhs.entryIndex < rhs.entryIndex
        }

        var usedAX = Set<Int>()
        var usedEntry = Set<Int>()
        var result: [CGWindowID: AXWindow] = [:]

        for candidate in candidates {
            guard !usedAX.contains(candidate.axIndex), !usedEntry.contains(candidate.entryIndex) else { continue }
            usedAX.insert(candidate.axIndex)
            usedEntry.insert(candidate.entryIndex)
            result[entries[candidate.entryIndex].id] = axWindows[candidate.axIndex]
        }

        // A process with exactly one window on each side is unambiguous even
        // when frame and title disagree, which happens during animations. The
        // minimized veto still applies: it is a hard contradiction, not a weak
        // signal.
        if result.isEmpty, axWindows.count == 1, entries.count == 1,
           isCompatible(ax: axWindows[0], entry: entries[0]) {
            result[entries[0].id] = axWindows[0]
        }

        return result
    }

    /// A minimized CoreGraphics window is never on screen. If accessibility
    /// disagrees, the two cannot describe the same window.
    private static func isCompatible(ax: AXWindow, entry: CGWindowEntry) -> Bool {
        !(ax.isMinimized && entry.isOnScreen)
    }

    private static func score(ax: AXWindow, entry: CGWindowEntry) -> Int {
        guard isCompatible(ax: ax, entry: entry) else { return 0 }

        var score = 0

        if framesMatch(ax.frame, entry.frame) {
            score += 4
        } else if ax.frame.size.equalTo(entry.frame.size) {
            score += 1
        }

        score += titleScore(ax: ax.title, entry: entry.title ?? "")

        return score
    }

    /// Scores how well two titles for the same window agree.
    ///
    /// Exact equality is the strong case, but several browsers decorate the
    /// accessibility title and leave the CoreGraphics one bare — every Microsoft
    /// Edge window on the machine this was written on reported "Connect Form"
    /// to CoreGraphics and "Connect Form – Standbymodus - Microsoft Edge –
    /// Geschäftlich" to accessibility. Demanding equality scored all of them
    /// zero on title, which threw away the one signal that could tell them
    /// apart and left the frame to decide alone.
    private static func titleScore(ax: String, entry: String) -> Int {
        if !ax.isEmpty, ax == entry { return 4 }
        if ax.isEmpty && entry.isEmpty { return 1 }
        guard !ax.isEmpty, !entry.isEmpty else { return 0 }

        // A shared prefix of one or two characters is a coincidence, not a
        // signal, so only a substantial one counts.
        let shorter = ax.count <= entry.count ? ax : entry
        let longer = ax.count <= entry.count ? entry : ax
        guard shorter.count >= 4, longer.hasPrefix(shorter) else { return 0 }
        return 2
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= frameTolerance
            && abs(lhs.origin.y - rhs.origin.y) <= frameTolerance
            && abs(lhs.width - rhs.width) <= frameTolerance
            && abs(lhs.height - rhs.height) <= frameTolerance
    }
}
