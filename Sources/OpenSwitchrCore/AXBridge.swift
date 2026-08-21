import ApplicationServices
import Foundation

/// The only place in OpenSwitchr that touches the raw AXUIElement C API.
///
/// Everything here is deliberately non-throwing: the accessibility API fails
/// constantly and normally (windows disappear between two calls, apps refuse
/// to respond, sandboxed processes deny attributes). Callers treat a `nil`
/// result as "not available right now" and move on.
public enum AXBridge {

    // MARK: - Trust

    /// Whether this process is currently trusted for accessibility.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Checks trust and, if requested, shows the system prompt that sends the
    /// user to System Settings.
    public static func checkTrust(prompt: Bool) -> Bool {
        // Spelled out rather than read from `kAXTrustedCheckOptionPrompt`,
        // which the SDK exposes as a mutable global and is therefore not
        // usable under strict concurrency.
        let options = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Elements

    public static func application(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    public static func systemWide() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    // MARK: - Attribute reads

    public static func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    public static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyValue(element, attribute) as? String
    }

    public static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copyValue(element, attribute) as? Bool
    }

    public static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    public static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        copyValue(element, attribute) as? [AXUIElement] ?? []
    }

    public static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    public static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    /// Window frame in Core Graphics coordinates (origin top-left), matching
    /// what `CGWindowListCopyWindowInfo` reports.
    public static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute as String),
              let size = size(element, kAXSizeAttribute as String) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }

    // MARK: - Batched attribute reads

    /// Reads several attributes in a single round trip to the target process.
    ///
    /// Every accessibility read is synchronous inter-process messaging, so the
    /// cost is dominated by the number of round trips rather than the amount of
    /// data. Rebuilding the window index one attribute at a time costs roughly
    /// five messages per window; batching cuts that to one.
    ///
    /// Attributes the element does not expose come back as `nil` in place,
    /// keeping the result aligned with `attributes`.
    public static func values(_ element: AXUIElement, _ attributes: [String]) -> [CFTypeRef?] {
        var raw: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(),
            &raw
        )

        guard status == .success, let values = raw as? [CFTypeRef], values.count == attributes.count else {
            // Not every app implements the batched call; fall back to
            // individual reads so behaviour degrades in speed, not function.
            return attributes.map { copyValue(element, $0) }
        }

        return values.map { value in
            // Missing attributes are reported as an AXValue wrapping an error.
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
                return nil
            }
            return value
        }
    }

    public static func string(_ value: CFTypeRef?) -> String? {
        value as? String
    }

    public static func bool(_ value: CFTypeRef?) -> Bool? {
        value as? Bool
    }

    public static func point(_ value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    public static func size(_ value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    // MARK: - Attribute writes and actions

    @discardableResult
    public static func setValue(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    public static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> Bool {
        setValue(element, attribute, value as CFBoolean)
    }

    @discardableResult
    public static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// Raises the window's close button and presses it. Used instead of a
    /// direct close action, which most apps do not expose on windows.
    @discardableResult
    public static func pressCloseButton(_ window: AXUIElement) -> Bool {
        guard let button = element(window, kAXCloseButtonAttribute as String) else { return false }
        return perform(button, kAXPressAction as String)
    }

    // MARK: - Timeouts

    /// Caps how long a single AX call may block. Unresponsive apps otherwise
    /// stall the main thread for the system default of six seconds.
    public static func setTimeout(_ element: AXUIElement, seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }
}
