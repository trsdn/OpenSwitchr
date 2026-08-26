import AppKit
import ApplicationServices
import Foundation
import OSLog

/// Turns system notifications into a single stream of window change events.
///
/// This is what keeps OpenSwitchr off the CPU when nothing happens. There is no
/// timer and no polling anywhere in this file: everything is driven by
/// `NSWorkspace` notifications and per-application accessibility observers
/// attached to the main run loop.
@MainActor
public final class WindowEventBus {

    public enum Event: Equatable, Sendable {
        /// The set of windows may have changed and the index should rebuild.
        case windowsChanged
        /// An app came to the front; used to advance MRU order.
        case appActivated(pid_t)
        /// An app moved focus to another of its windows, and said which one.
        case focusedWindowChanged(FocusedWindow)
        /// The user switched Spaces; the index is only valid for the current
        /// Space, so it must be rebuilt from scratch.
        case spaceChanged
    }

    /// The window an app just focused.
    ///
    /// `kAXFocusedWindowChangedNotification` delivers the newly focused window
    /// as the notification's own element — measured against Safari with three
    /// windows, where it arrived as an `AXWindow` carrying the title of the
    /// window that had just been raised. Passing it on costs nothing and is the
    /// only thing that identifies *which* window of a multi-window app was
    /// focused.
    public struct FocusedWindow: @unchecked Sendable, Equatable {
        public let pid: pid_t
        public let element: AXUIElement

        public init(pid: pid_t, element: AXUIElement) {
            self.pid = pid
            self.element = element
        }

        public static func == (lhs: FocusedWindow, rhs: FocusedWindow) -> Bool {
            lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
        }
    }

    public var onEvent: ((Event) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var isRunning = false
    private let logger = Logger(subsystem: "com.openswitchr.app", category: "WindowEventBus")

    private static let windowNotifications: [String] = [
        kAXWindowCreatedNotification as String,
        kAXUIElementDestroyedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXTitleChangedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXApplicationHiddenNotification as String,
        kAXApplicationShownNotification as String
    ]

    public init() {}

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        guard AXBridge.isTrusted else {
            logger.notice("Not starting event bus: accessibility permission missing")
            return
        }
        isRunning = true

        subscribeToWorkspace()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            attachObserver(to: app.processIdentifier)
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()

        for pid in observers.keys {
            detachObserver(from: pid)
        }
    }

    // MARK: - NSWorkspace

    private func subscribeToWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        func observe(_ name: NSNotification.Name, handler: @escaping @MainActor (NSRunningApplication?) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    handler(app)
                }
            }
            workspaceTokens.append(token)
        }

        observe(NSWorkspace.didLaunchApplicationNotification) { [weak self] app in
            guard let self, let app, app.activationPolicy == .regular else { return }
            self.attachObserver(to: app.processIdentifier)
            self.emit(.windowsChanged)
        }

        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            guard let self, let app else { return }
            self.detachObserver(from: app.processIdentifier)
            self.emit(.windowsChanged)
        }

        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            guard let self, let app else { return }
            // A newly activated app may not have had an observer yet, for
            // example when it changed its activation policy at runtime.
            self.attachObserver(to: app.processIdentifier)
            self.emit(.appActivated(app.processIdentifier))
        }

        observe(NSWorkspace.didHideApplicationNotification) { [weak self] _ in
            self?.emit(.windowsChanged)
        }

        observe(NSWorkspace.didUnhideApplicationNotification) { [weak self] _ in
            self?.emit(.windowsChanged)
        }

        let spaceToken = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { [weak self] in
                self?.emit(.spaceChanged)
            }
        }
        workspaceTokens.append(spaceToken)
    }

    // MARK: - Accessibility observers

    private func attachObserver(to pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observer: AXObserver?
        let result = AXObserverCreate(pid, Self.axCallback, &observer)
        guard result == .success, let observer else {
            logger.debug("Could not create AX observer for pid \(pid): \(result.rawValue)")
            return
        }

        let element = AXBridge.application(pid: pid)
        AXBridge.setTimeout(element, seconds: 0.25)
        let context = Unmanaged.passUnretained(self).toOpaque()

        var attached = false
        for notification in Self.windowNotifications {
            let status = AXObserverAddNotification(observer, element, notification as CFString, context)
            if status == .success { attached = true }
        }

        guard attached else {
            logger.debug("App \(pid) accepted no window notifications; skipping")
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observers[pid] = observer
    }

    private func detachObserver(from pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    // MARK: - Callback plumbing

    /// The accessibility observer callback is a plain C function pointer, so
    /// the bus is passed through as an opaque context pointer. The observer is
    /// attached to the main run loop, which is why hopping back onto the main
    /// actor here is sound rather than merely convenient.
    private static let axCallback: AXObserverCallback = { _, element, notification, context in
        guard let context else { return }
        let bus = Unmanaged<WindowEventBus>.fromOpaque(context).takeUnretainedValue()
        let name = notification as String

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        // The event is built here rather than on the other side of the hop: a
        // bare `AXUIElement` is not `Sendable` and cannot cross onto the main
        // actor, while `Event` — through `FocusedWindow` — can.
        let event: Event = name == kAXFocusedWindowChangedNotification as String
            // The pid comes from the element that actually changed. Reading the
            // frontmost application instead, as this once did, misattributes
            // every focus change made by an app that is not in front.
            ? .focusedWindowChanged(FocusedWindow(pid: pid, element: element))
            : .windowsChanged

        MainActor.assumeIsolated {
            bus.deliver(event, name: name, pid: pid)
        }
    }

    private func deliver(_ event: Event, name: String, pid: pid_t) {
        // Which app is chattering decides whether idle CPU is acceptable, and
        // that cannot be guessed from outside.
        logger.debug("AX \(name) from pid \(pid)")
        emit(event)
    }

    private func emit(_ event: Event) {
        guard isRunning else { return }
        onEvent?(event)
    }
}
