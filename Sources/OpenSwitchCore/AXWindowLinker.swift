import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Links accessibility windows to CoreGraphics window IDs.
///
/// This is the single trickiest piece of OpenSwitch. The private
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
            guard isSwitchable(role: AXBridge.string(values[0]), subrole: AXBridge.string(values[1])) else {
                return nil
            }

            let origin = AXBridge.point(values[3]) ?? .zero
            let size = AXBridge.size(values[4]) ?? .zero

            return AXWindow(
                element: element,
                title: AXBridge.string(values[2]) ?? "",
                frame: CGRect(origin: origin, size: size),
                isMinimized: AXBridge.bool(values[5]) ?? false
            )
        }
    }

    /// Excludes sheets, drawers, popovers, and other non-switchable surfaces.
    private static func isSwitchable(role: String?, subrole: String?) -> Bool {
        guard role == kAXWindowRole as String else { return false }
        // Some apps omit the subrole entirely; treat those as normal windows.
        guard let subrole else { return true }
        return subrole == kAXStandardWindowSubrole as String
    }

    /// Greedily links AX windows to CoreGraphics entries of the same process.
    ///
    /// Pairs are scored, sorted best-first, and assigned one-to-one. Anything
    /// that only ties on a weak signal stays unlinked.
    static func link(axWindows: [AXWindow], to entries: [CGWindowEntry]) -> [CGWindowID: AXWindow] {
        guard !axWindows.isEmpty, !entries.isEmpty else { return [:] }

        struct Candidate {
            let axIndex: Int
            let entryIndex: Int
            let score: Int
        }

        var candidates: [Candidate] = []
        for (axIndex, ax) in axWindows.enumerated() {
            for (entryIndex, entry) in entries.enumerated() {
                let score = score(ax: ax, entry: entry)
                if score > 0 {
                    candidates.append(Candidate(axIndex: axIndex, entryIndex: entryIndex, score: score))
                }
            }
        }

        candidates.sort { $0.score > $1.score }

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
            score += 3
        } else if ax.frame.size.equalTo(entry.frame.size) {
            score += 1
        }

        if let entryTitle = entry.title, !entryTitle.isEmpty, entryTitle == ax.title {
            score += 3
        } else if ax.title.isEmpty && (entry.title ?? "").isEmpty {
            score += 1
        }

        return score
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= frameTolerance
            && abs(lhs.origin.y - rhs.origin.y) <= frameTolerance
            && abs(lhs.width - rhs.width) <= frameTolerance
            && abs(lhs.height - rhs.height) <= frameTolerance
    }
}
