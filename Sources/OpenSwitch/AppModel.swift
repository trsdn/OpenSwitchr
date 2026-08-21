import AppKit
import Foundation
import Observation
import OpenSwitchCore
import OpenSwitchUI
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
    public let preferences = PreferencesStore()
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
    @ObservationIgnored private let logger = Logger(subsystem: "com.openswitch.app", category: "AppModel")

    /// Reflects whether the engine actually came up, so the menu can say so.
    public private(set) var isRunning = false
    public private(set) var dockHoverActive = false

    public init() {
        thumbnails = ThumbnailProvider(
            store: ThumbnailStore(budgetBytes: max(16, PreferencesStore().thumbnailBudgetMB) * 1024 * 1024)
        )
    }

    // MARK: - Lifecycle

    public func start() {
        permissions.refresh()
        guard permissions.isOperational else {
            logger.notice("Accessibility permission missing; staying idle")
            isRunning = false
            return
        }

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
    }

    /// Applies preference changes that affect running subsystems.
    public func applyPreferences() {
        hotkeys.holdModifier = preferences.holdModifier

        if preferences.switcherEnabled {
            hotkeys.start()
        } else {
            switcher.close()
            hotkeys.stop()
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
            self?.switcher.handle(action)
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
        hotkeys.start()
    }

    private func startDockHover() {
        guard preferences.dockHoverEnabled, !dockHoverActive else { return }
        dockHover.onHover = { [weak self] item in
            self?.dockPreview.hoverChanged(to: item)
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
            scheduleRebuild()
        case .focusedWindowChanged(let pid):
            index.noteFocus(pid: pid)
        }
    }

    /// Coalesces bursts of events into a single rebuild. Opening an app can
    /// easily produce a dozen notifications in a few milliseconds.
    private func scheduleRebuild() {
        guard !switcher.isVisible else {
            pendingRebuild = true
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
}
