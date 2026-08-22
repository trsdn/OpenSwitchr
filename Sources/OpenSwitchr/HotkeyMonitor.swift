import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

/// Reads the switcher hotkey straight from the event stream.
///
/// A `CGEventTap` is the only mechanism that can do all three things the
/// switcher needs: notice that a modifier is being *held*, notice the moment it
/// is *released*, and swallow the Tab key so it never reaches the app
/// underneath. Carbon's `RegisterEventHotKey` can do none of those.
///
/// The callback is kept deliberately trivial — it classifies the event and
/// hands off. Slow tap callbacks get the tap disabled by the system.
@MainActor
public final class HotkeyMonitor {

    /// The modifier held down while pressing Tab.
    ///
    /// `⌘` is included, and it does replace the system app switcher. That was
    /// measured, not assumed: a session tap both sees `⌘-Tab` and suppresses
    /// it. Passing the same event through makes the Dock's switcher window
    /// appear, swallowing it does not, so the suppression is real rather than a
    /// detection artefact.
    public enum HoldModifier: String, CaseIterable, Sendable {
        case option
        case control
        case command

        public var flag: CGEventFlags {
            switch self {
            case .option: .maskAlternate
            case .control: .maskControl
            case .command: .maskCommand
            }
        }

        public var symbol: String {
            switch self {
            case .option: "⌥"
            case .control: "⌃"
            case .command: "⌘"
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case open(reverse: Bool)
        case advance(reverse: Bool)
        case move(Direction)
        case commit
        case cancel
        case append(String)
        case deleteBackward
    }

    public enum Direction: Sendable {
        case left, right, up, down
    }

    /// Set by the switcher controller. While true, the tap swallows keystrokes
    /// so typing filters the overlay instead of leaking into the focused app.
    public var isOverlayVisible = false {
        didSet { core.isOverlayVisible = isOverlayVisible }
    }

    public var holdModifier: HoldModifier = .option {
        didSet { core.holdModifier = holdModifier }
    }

    public var onAction: ((Action) -> Void)?

    private let core = TapCore()
    private var thread: Thread?
    private let logger = Logger(subsystem: "com.openswitchr.app", category: "HotkeyMonitor")

    public init() {}

    // MARK: - Lifecycle

    @discardableResult
    public func start() -> Bool {
        guard thread == nil else { return true }
        guard AXBridgeTrustProxy.isTrusted else {
            logger.notice("Not installing event tap: accessibility permission missing")
            return false
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: TapCore.callback,
            userInfo: Unmanaged.passUnretained(core).toOpaque()
        ) else {
            logger.error("Could not create event tap")
            return false
        }

        core.isOverlayVisible = isOverlayVisible
        core.holdModifier = holdModifier
        core.tap = tap
        core.emit = { [weak self] action in
            // Ordered, and never makes the tap thread wait on the main actor.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.onAction?(action)
                }
            }
        }

        // The tap gets its own thread. On the main run loop its callback queues
        // behind SwiftUI rendering and index work, and the system disables a tap
        // whose callback is late — which is exactly how the hotkey silently died
        // after a while, since the re-enable only rescues the *next* keystroke.
        let thread = Thread { [core] in
            guard let tap = core.tap else { return }
            let runLoop = CFRunLoopGetCurrent()
            core.runLoop = runLoop
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.openswitchr.hotkey-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
        return true
    }

    public func stop() {
        core.reset()
        if let tap = core.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = core.runLoop {
            CFRunLoopStop(runLoop)
        }
        core.tap = nil
        core.runLoop = nil
        core.emit = nil
        thread = nil
    }

    /// A tap can also be disabled by user input, and that arrives as an event
    /// the tap itself may never see. Checking on application activation costs
    /// nothing and needs no timer, since those notifications already arrive.
    public func ensureEnabled() {
        guard let tap = core.tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        logger.notice("Event tap was found disabled; re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

}

/// Everything the tap callback needs, deliberately free of actor isolation.
///
/// The callback runs on the tap's own thread, so it must not touch main-actor
/// state. It reads a small locked snapshot, decides whether to swallow the
/// event, and hands the resulting action to the main actor asynchronously.
private final class TapCore: @unchecked Sendable {

    private let lock = NSLock()
    private var _isOverlayVisible = false
    private var _holdModifier: HotkeyMonitor.HoldModifier = .option
    /// Tracks whether the last Tab key-down was swallowed, so the matching
    /// key-up can be swallowed too and nothing else.
    private var _swallowedTabKeyDown = false
    private var _tap: CFMachPort?
    private var _runLoop: CFRunLoop?
    private var _emit: ((HotkeyMonitor.Action) -> Void)?

    var isOverlayVisible: Bool {
        get { lock.withLock { _isOverlayVisible } }
        set { lock.withLock { _isOverlayVisible = newValue } }
    }

    var holdModifier: HotkeyMonitor.HoldModifier {
        get { lock.withLock { _holdModifier } }
        set { lock.withLock { _holdModifier = newValue } }
    }

    var tap: CFMachPort? {
        get { lock.withLock { _tap } }
        set { lock.withLock { _tap = newValue } }
    }

    var runLoop: CFRunLoop? {
        get { lock.withLock { _runLoop } }
        set { lock.withLock { _runLoop = newValue } }
    }

    var emit: ((HotkeyMonitor.Action) -> Void)? {
        get { lock.withLock { _emit } }
        set { lock.withLock { _emit = newValue } }
    }

    func reset() {
        lock.withLock { _swallowedTabKeyDown = false }
    }

    private let logger = Logger(subsystem: "com.openswitchr.app", category: "HotkeyMonitor")

    static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let core = Unmanaged<TapCore>.fromOpaque(context).takeUnretainedValue()
        return core.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }

    /// Returns `true` when the event must not reach the app underneath.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // The system disables a tap that took too long or that the user
        // interrupted. Re-enabling is mandatory; otherwise the hotkey silently
        // stops working for the rest of the session.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                logger.notice("Event tap was disabled by the system; re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return false
        }

        let (overlayVisible, modifier, swallowedTab) = lock.withLock {
            (_isOverlayVisible, _holdModifier, _swallowedTabKeyDown)
        }

        switch type {
        case .flagsChanged:
            if overlayVisible && !event.flags.contains(modifier.flag) {
                emit?(.commit)
            }
            return false

        case .keyDown:
            return handleKeyDown(event, overlayVisible: overlayVisible, modifier: modifier)

        case .keyUp:
            // Only swallow the key-up of a Tab we actually swallowed on the
            // way down. Swallowing every Tab key-up would leak into apps that
            // never saw the hotkey, where plain Tab still moves focus.
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == kVK_Tab && swallowedTab {
                lock.withLock { _swallowedTabKeyDown = false }
                return true
            }
            return overlayVisible

        default:
            return false
        }
    }

    private func handleKeyDown(
        _ event: CGEvent,
        overlayVisible: Bool,
        modifier: HotkeyMonitor.HoldModifier
    ) -> Bool {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let reverse = flags.contains(.maskShift)

        if keyCode == kVK_Tab && flags.contains(modifier.flag) {
            emit?(overlayVisible ? .advance(reverse: reverse) : .open(reverse: reverse))
            lock.withLock { _swallowedTabKeyDown = true }
            return true
        }

        guard overlayVisible else { return false }

        switch keyCode {
        case kVK_Escape:
            emit?(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            emit?(.commit)
        case kVK_LeftArrow:
            emit?(.move(.left))
        case kVK_RightArrow:
            emit?(.move(.right))
        case kVK_UpArrow:
            emit?(.move(.up))
        case kVK_DownArrow:
            emit?(.move(.down))
        case kVK_Delete:
            emit?(.deleteBackward)
        default:
            if let text = Self.characters(from: event), !text.isEmpty {
                emit?(.append(text))
            }
        }
        return true
    }

    private static func characters(from event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }

        var buffer = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &buffer)
        let text = String(utf16CodeUnits: buffer, count: length)
        return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } ? text : nil
    }
}

/// Tiny indirection so this file does not need to import the core module just
/// for a trust check.
private enum AXBridgeTrustProxy {
    static var isTrusted: Bool { AXIsProcessTrusted() }
}
