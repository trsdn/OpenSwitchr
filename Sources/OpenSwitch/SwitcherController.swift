import AppKit
import OpenSwitchCore
import OpenSwitchUI
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
    private let logger = Logger(subsystem: "com.openswitch.app", category: "Switcher")

    private var visibleWindows: [WindowInfo] = []
    private var selectedIndex = 0
    private var query = ""
    private var columnCount = 1

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
        visibleWindows = index.windows

        guard !visibleWindows.isEmpty else { return }

        // Opening jumps straight to the previously used window, which is what
        // makes a single hotkey press a fast toggle between two windows.
        selectedIndex = reverse
            ? visibleWindows.count - 1
            : min(1, visibleWindows.count - 1)

        present()
    }

    private func present() {
        let tileSize = tileSize()
        let screen = OverlayPanel.screenWithMouse() ?? NSScreen.main
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

        render()
        panel.showCentered(size: size)
        setVisible(true)
    }

    private func render() {
        panel.setContent(
            SwitcherView(
                windows: visibleWindows,
                selectedIndex: selectedIndex,
                query: query,
                thumbnails: thumbnails,
                tileSize: tileSize(),
                onActivate: { [weak self] index in
                    self?.selectedIndex = index
                    self?.commit()
                },
                onHover: { [weak self] index in
                    guard let self, self.selectedIndex != index else { return }
                    self.selectedIndex = index
                    self.render()
                }
            )
        )
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
        visibleWindows = WindowMatcher.filter(index.windows, query: query)
        if resetSelection {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, max(0, visibleWindows.count - 1))
        }
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
