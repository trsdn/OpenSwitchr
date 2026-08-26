import AppKit
import Foundation
import Observation
import OpenSwitchrCore
import OpenSwitchrUI
import OSLog

/// Wires the shared foundation to both frontends.
///
/// Owns everything with a lifetime: the index, the event bus, the thumbnail
/// store, the event tap, and the two controllers. Nothing else in the app
/// creates these.
@MainActor
@Observable
public final class AppModel {

    public let permissions = PermissionsManager()
    public let preferences: PreferencesStore
    public let index = WindowIndex()
    public let thumbnails: ThumbnailProvider

    @ObservationIgnored private let eventBus = WindowEventBus()
    @ObservationIgnored private let hotkeys = HotkeyMonitor()
    @ObservationIgnored private let dockHover = DockHoverMonitor()
    @ObservationIgnored private lazy var switcher = SwitcherController(
        index: index,
        thumbnails: thumbnails,
        preferences: preferences
    )
    @ObservationIgnored private lazy var dockPreview = DockPreviewController(
        index: index,
        thumbnails: thumbnails,
        preferences: preferences
    )

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var memoryPressureSource: DispatchSourceMemoryPressure?
    @ObservationIgnored private var pendingRebuild = false
    @ObservationIgnored private var indexIsStale = false

    /// Last tile width the thumbnail cache was populated for, so a resize can
    /// be detected without re-capturing on every unrelated settings change.
    @ObservationIgnored private var lastAppliedTileWidth: Double?
    @ObservationIgnored private let logger = Logger(subsystem: "com.openswitchr.app", category: "AppModel")

    /// Reflects whether the engine actually came up, so the menu can say so.
    public private(set) var isRunning = false
    public private(set) var dockHoverActive = false

    /// Whether the event tap is actually installed. Creating a tap can fail
    /// even with the permission granted, and a switcher whose hotkey silently
    /// does nothing is indistinguishable from a broken app.
    public private(set) var switcherHotkeyActive = false

    public init() {
        let preferences = PreferencesStore()
        self.preferences = preferences
        thumbnails = ThumbnailProvider(
            store: ThumbnailStore(budgetBytes: Self.budgetBytes(preferences.thumbnailBudgetMB))
        )
    }

    private static func budgetBytes(_ megabytes: Int) -> Int {
        max(16, megabytes) * 1024 * 1024
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        permissions.refresh()
        guard permissions.isOperational else {
            logger.notice("Accessibility permission missing; staying idle")
            isRunning = false
            // Nothing here is usable without the permission, so wait for it
            // rather than making the user re-trigger startup by hand.
            permissions.onAccessibilityGranted = { [weak self] in
                self?.start()
            }
            permissions.watchForAccessibilityGrant()
            return
        }
        permissions.stopWatching()

        // The first accessibility message to each app is expensive, so the
        // initial index is built off the main thread. Everything else starts
        // immediately; the switcher simply has an empty list for a moment.
        rebuildTask = Task { [weak self] in
            await self?.index.rebuildConcurrently()
        }
        startEventBus()
        startHotkeys()
        startDockHover()
        startMemoryPressureWatch()
        isRunning = true
        logger.notice(
            "Started. Switcher hotkey: \(self.switcherHotkeyActive), Dock hover: \(self.dockHoverActive)"
        )
    }

    public func stop() {
        rebuildTask?.cancel()
        rebuildTask = nil
        eventBus.stop()
        hotkeys.stop()
        dockHover.stop()
        dockPreview.hide()
        switcher.close()
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        permissions.stopWatching()
        isRunning = false
        dockHoverActive = false
        switcherHotkeyActive = false
    }

    /// Applies preference changes that affect running subsystems.
    public func applyPreferences() {
        hotkeys.holdModifier = preferences.holdModifier

        let budget = Self.budgetBytes(preferences.thumbnailBudgetMB)
        let maxAge = preferences.thumbnailRefreshRate.maxAge
        Task { [store = thumbnails.store] in
            await store.setBudget(bytes: budget)
            await store.setMaxAge(maxAge)
        }

        // Cached captures were taken for the previous tile size. Reusing them
        // scales a small bitmap up, so the size setting would look like it
        // worked while every preview turned soft.
        if preferences.tileWidth != lastAppliedTileWidth {
            lastAppliedTileWidth = preferences.tileWidth
            thumbnails.invalidateForResize()
        }

        if preferences.switcherEnabled {
            switcherHotkeyActive = hotkeys.start()
        } else {
            switcher.close()
            hotkeys.stop()
            switcherHotkeyActive = false
        }

        if preferences.dockHoverEnabled {
            startDockHover()
        } else {
            dockPreview.hide()
            dockHover.stop()
            dockHoverActive = false
        }
    }

    // MARK: - Subsystems

    private func startEventBus() {
        eventBus.onEvent = { [weak self] event in
            self?.handle(event)
        }
        eventBus.start()
    }

    private func startHotkeys() {
        guard preferences.switcherEnabled else { return }
        hotkeys.holdModifier = preferences.holdModifier
        hotkeys.onAction = { [weak self] action in
            guard let self else { return }
            if !self.switcher.isVisible {
                self.refreshIfStale()
            }
            self.switcher.handle(action)
        }
        switcher.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.hotkeys.isOverlayVisible = visible
            // Window churn while the overlay is open would reshuffle the list
            // under the user's fingers, so rebuilds are deferred until it closes.
            if !visible && self.pendingRebuild {
                self.pendingRebuild = false
                self.scheduleRebuild()
            }
        }
        switcherHotkeyActive = hotkeys.start()
    }

    private func startDockHover() {
        guard preferences.dockHoverEnabled, !dockHoverActive else { return }
        dockHover.onHover = { [weak self] item in
            guard let self else { return }
            if item != nil {
                self.refreshIfStale()
            }
            self.dockPreview.hoverChanged(to: item)
        }
        dockPreview.onHidden = { [weak self] in
            self?.dockHover.forgetLastHover()
        }
        dockHoverActive = dockHover.start()
    }

    private func startMemoryPressureWatch() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.thumbnails.clear()
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - Event handling

    private func handle(_ event: WindowEventBus.Event) {
        // Idle CPU is a hard goal, and it is decided entirely by how often
        // these arrive, so the rate has to be observable in the field.
        logger.debug("Event: \(String(describing: event))")

        switch event {
        case .windowsChanged:
            scheduleRebuild()
        case .spaceChanged:
            // The index only ever describes the current Space, so a Space
            // change invalidates all of it, thumbnails included.
            thumbnails.clear()
            scheduleRebuild()
        case .appActivated(let pid):
            index.noteFocus(pid: pid)
            // Cheap place to notice a tap the system switched off behind our
            // back, and it needs no timer of its own.
            hotkeys.ensureEnabled()
            scheduleRebuild()
        case .focusedWindowChanged(let focused):
            index.noteFocus(pid: focused.pid, element: focused.element)
        }
    }

    /// Coalesces bursts of events into a single rebuild. Opening an app can
    /// easily produce a dozen notifications in a few milliseconds.
    private func scheduleRebuild() {
        guard !switcher.isVisible else {
            pendingRebuild = true
            return
        }

        // Nobody reads the index unless a frontend is on screen. A single
        // chatty app — one window retitling itself fifteen times a second is
        // enough — otherwise keeps rebuilding a list no one is looking at, and
        // that alone costs several percent CPU while "idle". Mark it stale and
        // pay for the rebuild when it is next shown.
        guard dockPreview.isVisible else {
            indexIsStale = true
            return
        }

        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, let self else { return }
            await self.index.rebuildConcurrently()
            guard !Task.isCancelled else { return }
            self.thumbnails.retain(only: Set(self.index.windows.map(\.id)))
        }
    }

    /// Called on the paths that put a frontend on screen. The rebuild is not
    /// awaited: the overlay renders from the previous index within ~25 ms and
    /// the refreshed one arrives ~10 ms later through observation, which is
    /// invisible and keeps the open path off the critical path.
    private func refreshIfStale() {
        guard indexIsStale else { return }
        indexIsStale = false

        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            guard let self else { return }
            let before = self.index.windows.count
            await self.index.rebuildConcurrently()
            guard !Task.isCancelled else { return }
            self.logger.debug("Stale rebuild on show: \(before) -> \(self.index.windows.count) windows")
            self.thumbnails.retain(only: Set(self.index.windows.map(\.id)))
        }
    }
}
