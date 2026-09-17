import CoreGraphics
import Foundation

/// Where the switcher's selection starts when the overlay opens.
///
/// Extracted and pure for the same reason `WindowIndex.focusTarget` is: the
/// rule reads as if it were obvious, and it was wrong the moment the list
/// stopped being a plain most-recently-used order.
///
/// The rule is "the window you would go back to" — the entry *after* the one
/// you are currently in, so a single press of the hotkey is a fast toggle
/// between two windows. That coincides with index 1 only while the list is in
/// most-recently-used order *and* still contains the current window. Neither
/// holds once a `WindowFilter` is applied: "everything but the current
/// application" removes the current window by definition, and an alphabetical
/// order puts something arbitrary at index 1 — possibly the window the user is
/// already in, which makes the hotkey appear dead.
public enum SwitcherSelection {

    /// - Parameters:
    ///   - count: how many windows the overlay is about to show. Must be > 0.
    ///   - currentIndex: where the window the user is in ended up in that list,
    ///     or `nil` if the list does not contain it.
    ///   - reverse: whether the user opened the switcher backwards.
    public static func initialIndex(count: Int, currentIndex: Int?, reverse: Bool) -> Int {
        guard count > 0 else { return 0 }

        guard let currentIndex, currentIndex >= 0, currentIndex < count else {
            // The current window is not on the list, so there is nothing to
            // step away from: the first entry going forwards, the last going
            // back. Both are already the window the user most wants.
            return reverse ? count - 1 : 0
        }

        let step = reverse ? -1 : 1
        return ((currentIndex + step) % count + count) % count
    }

    /// Where the selection lands after the list is rebuilt while the overlay
    /// stays open — a rebuild landing mid-session, not the switcher opening.
    ///
    /// Unlike ``initialIndex(count:currentIndex:reverse:)``, this does not step
    /// away from anything: the user already chose a window, and a rebuild
    /// reordering the list underneath them must not move the selection off it.
    /// Identity therefore comes from the window's id, not its old position,
    /// which the rebuild is free to change.
    ///
    /// - Parameters:
    ///   - windows: the list after the rebuild.
    ///   - selectedID: the id of the window that was selected before the
    ///     rebuild, or `nil` if nothing was selected.
    ///   - fallbackIndex: where to land if that window is no longer present —
    ///     typically the previous index, clamped to the new list.
    public static func indexPreservingSelection(
        in windows: [WindowInfo],
        selectedID: CGWindowID?,
        fallbackIndex: Int
    ) -> Int {
        guard !windows.isEmpty else { return 0 }

        if let selectedID, let found = windows.firstIndex(where: { $0.id == selectedID }) {
            return found
        }

        return min(max(fallbackIndex, 0), windows.count - 1)
    }
}
