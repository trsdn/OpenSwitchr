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
}
