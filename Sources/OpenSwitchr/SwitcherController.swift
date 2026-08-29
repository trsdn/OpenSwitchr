import AppKit
import OpenSwitchrCore
import OpenSwitchrUI
import OSLog
import SwiftUI

/// Drives the switcher overlay: what is shown, what is selected, and what
/// happens on commit.
@MainActor
public final class SwitcherController {

    private let index: WindowIndex
    private let thumbnails: ThumbnailProvider
    private let preferences: PreferencesStore
    private let panel = OverlayPanel()
    private let logger = Logger(subsystem: "com.openswitchr.app", category: "Switcher")

    private var visibleWindows: [WindowInfo] = []
    private var selectedIndex = 0
    private var query = ""
    private var columnCount = 1

    /// The screen this overlay is appearing on, decided once when it opens.
    ///
    /// It is both a layout input and a filter input, and the two have to agree:
    /// deciding it twice is how a list scoped to "this display" ends up being
    /// drawn on a different one.
    private var surfaceScreen: NSScreen?

    public private(set) var isVisible = false

    /// Called whenever the overlay opens or closes, so the hotkey monitor knows
    /// whether it should be swallowing keystrokes.
    public var onVisibilityChanged: ((Bool) -> Void)?

    public init(index: WindowIndex, thumbnails: ThumbnailProvider, preferences: PreferencesStore) {
        self.index = index
        self.thumbnails = thumbnails
        self.preferences = preferences
    }

    // MARK: - Hotkey handling

    public func handle(_ action: HotkeyMonitor.Action) {
        switch action {
        case .open(let reverse):
            open(reverse: reverse)
        case .advance(let reverse):
            advance(by: reverse ? -1 : 1)
        case .move(let direction):
            move(direction)
        case .commit:
            commit()
        case .cancel:
            close()
        case .append(let text):
            query += text
            refreshList(resetSelection: true)
        case .deleteBackward:
            guard !query.isEmpty else { return }
            query.removeLast()
            refreshList(resetSelection: true)
        }
    }

    // MARK: - Presentation

    private func open(reverse: Bool) {
        guard !isVisible else { return }
        query = ""
        surfaceScreen = OverlayPanel.screenWithMouse() ?? NSScreen.main
        visibleWindows = baseWindows()

        guard !visibleWindows.isEmpty else { return }

        // Opening jumps straight to the previously used window, which is what
        // makes a single hotkey press a fast toggle between two windows.
        selectedIndex = reverse
            ? visibleWindows.count - 1
            : min(1, visibleWindows.count - 1)

        present()
    }

    /// The index, reduced to what the user configured this surface to show.
    ///
    /// A filter and a sort over a list that is already in memory, on the path
    /// that puts the overlay on screen. It issues no accessibility read.
    private func baseWindows() -> [WindowInfo] {
        preferences.switcherFilter.apply(to: index.windows, context: filterContext())
    }

    private func filterContext() -> WindowFilter.Context {
        WindowFilter.Context(frontmostPID: frontmostPID(), screen: surfaceScreen)
    }

    /// Which application the user is currently in.
    ///
    /// Read from the index rather than from `NSWorkspace.frontmostApplication`,
    /// which is driven by notifications and is the value that has already
    /// caused trouble here when read on a short path. The index is sorted
    /// most-recently-used first, so its head is the window the user was last
    /// in — which is the better answer anyway. The workspace is kept only as a
    /// fallback for an empty index.
    private func frontmostPID() -> pid_t? {
        index.windows.first?.pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func present() {
        let tileSize = tileSize()
        let screen = surfaceScreen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let maxWidth = min(visible.width * 0.86, 1400)
        let perTile = tileSize.width + 16 + 4
        columnCount = max(1, Int(((maxWidth - 32) / perTile).rounded(.down)))

        let rows = max(1, Int(ceil(Double(visibleWindows.count) / Double(columnCount))))
        let contentHeight = CGFloat(min(rows, 3)) * (tileSize.height + 16 + 20 + 8)
        let size = NSSize(
            width: min(maxWidth, CGFloat(max(1, min(visibleWindows.count, columnCount))) * perTile + 32),
            height: min(visible.height * 0.8, contentHeight + 70)
        )

        prefetchThumbnails()
        render()
        panel.showCentered(size: size)
        setVisible(true)
    }

    /// Asks for the captures the tiles are about to want.
    ///
    /// Deliberately not in `render()`, which also runs on every hover: one pass
    /// per shown list is enough, and per mouse move is not free.
    private func prefetchThumbnails() {
        thumbnails.prefetch(visibleWindows.map(\.id), maxPixelSize: tileSize().width * 2)
    }

    private func render() {
        panel.setContent(
            SwitcherView(
                windows: visibleWindows,
                selectedIndex: selectedIndex,
                query: query,
                thumbnails: thumbnails,
                tileSize: tileSize(),
                showsCloseButtons: preferences.showCloseButton,
                onActivate: { [weak self] index in
                    self?.selectedIndex = index
                    self?.commit()
                },
                onClose: { [weak self] index in
                    self?.close(at: index)
                },
                onQuitApp: { [weak self] index in
                    self?.quitApp(at: index)
                },
                onHover: { [weak self] index in
                    guard let self, self.selectedIndex != index else { return }
                    self.selectedIndex = index
                    self.render()
                }
            )
        )
    }

    /// Closes the window behind a tile and drops it from the overlay at once,
    /// rather than waiting for the accessibility notification.
    private func close(at index: Int) {
        guard visibleWindows.indices.contains(index) else { return }
        let window = visibleWindows[index]
        guard WindowActions.close(window) else { return }

        self.index.remove(windowID: window.id)
        thumbnails.invalidate(window.id)
        visibleWindows.remove(at: index)

        guard !visibleWindows.isEmpty else {
            close()
            return
        }
        selectedIndex = min(selectedIndex, visibleWindows.count - 1)
        render()
    }

    /// Asks the app behind a tile to quit, then dismisses the overlay.
    ///
    /// Deliberately does not prune the app's other tiles the way `close(at:)`
    /// prunes one: `terminate()` is a request, not an outcome, and an app with
    /// unsaved work may put up a dialog and stay. Removing its windows would
    /// state something we do not know. Dismissing also puts that dialog in
    /// front of the user, which an overlay would otherwise cover.
    private func quitApp(at index: Int) {
        guard visibleWindows.indices.contains(index) else { return }
        WindowActions.quitApp(visibleWindows[index])
        close()
    }

    private func tileSize() -> CGSize {
        let width = max(120, preferences.tileWidth)
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }

    // MARK: - Selection

    private func advance(by delta: Int) {
        guard !visibleWindows.isEmpty else { return }
        let count = visibleWindows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
        render()
    }

    private func move(_ direction: HotkeyMonitor.Direction) {
        switch direction {
        case .left: advance(by: -1)
        case .right: advance(by: 1)
        case .up: advance(by: -columnCount)
        case .down: advance(by: columnCount)
        }
    }

    private func refreshList(resetSelection: Bool) {
        visibleWindows = WindowMatcher.filter(baseWindows(), query: query)
        if resetSelection {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, max(0, visibleWindows.count - 1))
        }
        prefetchThumbnails()
        render()
    }

    // MARK: - Commit

    private func commit() {
        defer { close() }
        guard visibleWindows.indices.contains(selectedIndex) else { return }

        let window = visibleWindows[selectedIndex]
        WindowActions.focus(window)
        index.noteFocus(windowID: window.id)
    }

    public func close() {
        guard isVisible else { return }
        panel.hidePanel()
        query = ""
        setVisible(false)
    }

    private func setVisible(_ visible: Bool) {
        isVisible = visible
        onVisibilityChanged?(visible)
    }
}
