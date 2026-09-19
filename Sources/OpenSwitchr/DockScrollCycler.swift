import AppKit
import CoreGraphics
import Foundation
import OSLog
import OpenSwitchrCore

/// Cycles an application's windows when the pointer scrolls over its Dock icon.
///
/// This needs a scroll-wheel event tap, and a tap that sees every scroll event
/// is the inverse of the constraint this app is built around. So it exists only
/// while the pointer is on a Dock icon: created disabled, enabled on hover-enter,
/// disabled on hover-leave, and a disabled tap receives nothing. `AGENTS.md`
/// permits one mouse monitor, and only while a panel is on screen; this is the
/// version that stays inside that allowance.
///
/// The callback is kept trivial for the same reason the hotkey's is: it
/// classifies the event and hands off. It also checks the event's own location
/// against the hovered icon, so a hover-leave that was ever missed cannot leave
/// scrolling swallowed anywhere else.
@MainActor
final class DockScrollCycler {

    /// Called on the main actor with `1` or `-1`.
    var onStep: ((Int) -> Void)?

    private let core = ScrollTapCore()
    private var thread: Thread?
    private let logger = Logger(subsystem: "com.openswitchr.app", category: "DockScroll")

    /// Creates the tap, disabled. Returns `false` without the permission.
    @discardableResult
    func start() -> Bool {
        guard thread == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                callback: ScrollTapCore.callback,
                userInfo: Unmanaged.passUnretained(core).toOpaque()
            )
        else {
            logger.error("Could not create the scroll tap")
            return false
        }

        core.tap = tap
        core.emit = { [weak self] step in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.onStep?(step) }
            }
        }

        let thread = Thread { [core] in
            guard let tap = core.tap else { return }
            let runLoop = CFRunLoopGetCurrent()
            core.runLoop = runLoop
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(runLoop, source, .commonModes)
            // Deliberately not enabled: nothing is watched until a hover starts.
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRun()
        }
        thread.name = "com.openswitchr.scroll-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        return true
    }

    func stop() {
        hoverEnded()
        if let runLoop = core.runLoop { CFRunLoopStop(runLoop) }
        core.tap = nil
        core.runLoop = nil
        core.emit = nil
        thread = nil
    }

    /// The pointer is on a Dock icon whose frame is `frame`, in the global
    /// top-left coordinates both the accessibility API and event locations use.
    func hoverBegan(frame: CGRect) {
        core.beginHover(frame: frame.insetBy(dx: -2, dy: -2))
        if let tap = core.tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func hoverEnded() {
        core.endHover()
        if let tap = core.tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }
}

private final class ScrollTapCore: @unchecked Sendable {

    private let lock = NSLock()
    private var _stepper = ScrollStepper()
    private var _hoverFrame: CGRect?
    private var _tap: CFMachPort?
    private var _runLoop: CFRunLoop?
    private var _emit: ((Int) -> Void)?

    var tap: CFMachPort? {
        get { lock.withLock { _tap } }
        set { lock.withLock { _tap = newValue } }
    }

    var runLoop: CFRunLoop? {
        get { lock.withLock { _runLoop } }
        set { lock.withLock { _runLoop = newValue } }
    }

    var emit: ((Int) -> Void)? {
        get { lock.withLock { _emit } }
        set { lock.withLock { _emit = newValue } }
    }

    func beginHover(frame: CGRect) {
        lock.withLock {
            _hoverFrame = frame
            _stepper.reset()
        }
    }

    func endHover() {
        lock.withLock {
            _hoverFrame = nil
            _stepper.reset()
        }
    }

    static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let core = Unmanaged<ScrollTapCore>.fromOpaque(context).takeUnretainedValue()
        return core.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }

    /// Returns `true` when the scroll must not reach the Dock.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Re-enabled only while a hover is live; otherwise it was disabled on
            // purpose and must stay off.
            let (tap, hovering) = lock.withLock { (_tap, _hoverFrame != nil) }
            if let tap, hovering { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .scrollWheel else { return false }

        let delta = CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        let time = ProcessInfo.processInfo.systemUptime
        let location = event.location

        let (inside, step, emit) = lock.withLock { () -> (Bool, Int, ((Int) -> Void)?) in
            guard let frame = _hoverFrame, frame.contains(location) else { return (false, 0, nil) }
            return (true, _stepper.add(delta: delta, at: time), _emit)
        }
        guard inside else { return false }
        if step != 0 { emit?(step) }
        return true
    }
}
