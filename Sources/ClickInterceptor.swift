import AppKit

/// A session-level event tap for mouse clicks and key presses while Mission Control is open.
///
/// Mission Control swallows clicks before they reach our overlay panels, so the
/// overlay is purely visual and this tap does the hit-testing instead. When a
/// mouse-down is consumed, the matching drag/up events are swallowed too so
/// Mission Control never sees half a click. Key presses work the same way: a
/// consumed key-down takes its auto-repeats and key-up with it.
final class ClickInterceptor {
    enum Button { case left, middle }
    enum Shortcut { case closeWindow, quitApp }

    /// Command + the letter a key produces on the current layout.
    private static let shortcuts: [String: Shortcut] = ["w": .closeWindow, "q": .quitApp]
    private static let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]

    /// Called on mouse-down with the location in global Accessibility/CG coordinates.
    /// Return `true` to consume the click.
    var onMouseDown: (CGPoint, Button) -> Bool = { _, _ in false }

    /// Called on a fresh press of a shortcut with the cursor location in the same coordinates.
    /// Return `true` to consume the keystroke.
    var onShortcut: (CGPoint, Shortcut) -> Bool = { _, _ in false }

    private var tap: CFMachPort?
    private var swallowing: Button?
    /// Keycodes of consumed presses still held down.
    private var swallowingKeys: Set<Int64> = []
    private var wanted = false

    /// Creates the tap (disabled). Returns `false` if macOS refused it.
    func install() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .otherMouseDown, .otherMouseDragged, .otherMouseUp,
                                    .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let interceptor = Unmanaged<ClickInterceptor>.fromOpaque(refcon!).takeUnretainedValue()
                return interceptor.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }

    /// Only enabled while Mission Control is open, so normal clicks and typing never pass through us.
    func setEnabled(_ enabled: Bool) {
        guard let tap else { return }
        wanted = enabled
        CGEvent.tapEnable(tap: tap, enable: enabled)
        if !enabled {
            swallowing = nil
            swallowingKeys = []
        }
    }

    /// Returns `true` to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Out-of-band: delivered whatever the mask says. A notice can arrive after
            // Mission Control has closed, and that must not turn the tap back on.
            if let tap, wanted { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown:
            return consumeIfHandled(event, .left)
        case .otherMouseDown where event.getIntegerValueField(.mouseEventButtonNumber) == 2:
            return consumeIfHandled(event, .middle)
        case .leftMouseDragged:
            return swallowing == .left
        case .otherMouseDragged:
            return swallowing == .middle
        case .leftMouseUp, .otherMouseUp:
            let button: Button = type == .leftMouseUp ? .left : .middle
            guard swallowing == button else { return false }
            swallowing = nil
            return true
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return swallowingKeys.remove(event.getIntegerValueField(.keyboardEventKeycode)) != nil
        default:
            return false
        }
    }

    private func consumeIfHandled(_ event: CGEvent, _ button: Button) -> Bool {
        guard onMouseDown(event.location, button) else { return false }
        swallowing = button
        return true
    }

    /// Cheap checks come first: this runs on every keystroke while Mission Control is open.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return swallowingKeys.contains(key)
        }
        // A fresh press, so any entry for this key is stale: the tap missed its key-up while disabled.
        swallowingKeys.remove(key)
        guard event.flags.intersection(Self.modifiers) == .maskCommand,
              // Lowercased because Caps Lock can still reach the character here.
              let letter = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(),
              let shortcut = Self.shortcuts[letter],
              // A new event carries the cursor position; a key event's own location isn't documented as valid.
              let cursor = CGEvent(source: nil)?.location,
              onShortcut(cursor, shortcut) else { return false }
        swallowingKeys.insert(key)
        return true
    }
}
