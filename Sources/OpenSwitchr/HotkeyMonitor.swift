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

    /// Modifier the user holds to keep the switcher open.
    /// The modifier held down while pressing Tab.
    ///
    /// `⌘` is deliberately absent. The system app switcher is a WindowServer
    /// symbolic hotkey, which is dispatched before session event taps, so a
    /// `⌘-Tab` binding here would be accepted in the UI and then silently never
    /// fire. Taking it over needs either a HID-level tap (root only) or the
    /// private symbolic-hotkey API, and both are out of bounds. Offering a
    /// setting that cannot work is worse than not offering it.
    public enum HoldModifier: String, CaseIterable, Sendable {
        case option
        case control

        public var flag: CGEventFlags {
            switch self {
            case .option: .maskAlternate
            case .control: .maskControl
            }
        }

        public var symbol: String {
            switch self {
            case .option: "⌥"
            case .control: "⌃"
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
    public var isOverlayVisible = false

    public var holdModifier: HoldModifier = .option
    public var onAction: ((Action) -> Void)?

    /// Tracks whether the last Tab key-down was swallowed, so the matching
    /// key-up can be swallowed too and nothing else.
    private var swallowedTabKeyDown = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let logger = Logger(subsystem: "com.openswitchr.app", category: "HotkeyMonitor")

    public init() {}

    // MARK: - Lifecycle

    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
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
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Could not create event tap")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        return true
    }

    public func stop() {
        swallowedTabKeyDown = false
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Tap callback

    /// `CGEvent` is not `Sendable`, so it crosses the isolation boundary in a
    /// box and the decision comes back as a plain `Bool`.
    private struct EventBox: @unchecked Sendable {
        let event: CGEvent
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
        let box = EventBox(event: event)

        let swallow = MainActor.assumeIsolated {
            monitor.handle(type: type, event: box.event)
        }
        return swallow ? nil : Unmanaged.passUnretained(event)
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

        switch type {
        case .flagsChanged:
            if isOverlayVisible && !event.flags.contains(holdModifier.flag) {
                onAction?(.commit)
            }
            return false

        case .keyDown:
            return handleKeyDown(event)

        case .keyUp:
            // Only swallow the key-up of a Tab we actually swallowed on the
            // way down. Swallowing every Tab key-up would leak into apps that
            // never saw the hotkey, where plain Tab still moves focus.
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == kVK_Tab && swallowedTabKeyDown {
                swallowedTabKeyDown = false
                return true
            }
            return isOverlayVisible

        default:
            return false
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let reverse = flags.contains(.maskShift)

        if keyCode == kVK_Tab && flags.contains(holdModifier.flag) {
            onAction?(isOverlayVisible ? .advance(reverse: reverse) : .open(reverse: reverse))
            swallowedTabKeyDown = true
            return true
        }

        guard isOverlayVisible else { return false }

        switch keyCode {
        case kVK_Escape:
            onAction?(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onAction?(.commit)
        case kVK_LeftArrow:
            onAction?(.move(.left))
        case kVK_RightArrow:
            onAction?(.move(.right))
        case kVK_UpArrow:
            onAction?(.move(.up))
        case kVK_DownArrow:
            onAction?(.move(.down))
        case kVK_Delete:
            onAction?(.deleteBackward)
        default:
            if let text = Self.characters(from: event), !text.isEmpty {
                onAction?(.append(text))
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
