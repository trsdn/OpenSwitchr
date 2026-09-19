import Foundation

/// Whether a CoreGraphics window belongs in the index at all.
///
/// A real window has a title, an accessibility element, or both. Without an
/// accessibility counterpart a CoreGraphics window is either on another Space
/// or one of the untitled helper and overlay surfaces apps keep around, and
/// neither belongs in a switcher. An empty title alone is deliberately not the
/// signal — plenty of real windows are untitled while loading — so it only
/// counts against a window that also has no link.
///
/// The other admission signals live where their data is read: the minimum size
/// and layer 0 in `CGWindowSnapshot`, and role and subrole in
/// `AXWindowLinker.isSwitchable`.
public enum WindowAdmission {

    public static func admits(hasAccessibilityLink: Bool, isOnScreen: Bool, title: String?) -> Bool {
        if hasAccessibilityLink { return true }
        return isOnScreen && !(title ?? "").isEmpty
    }
}
