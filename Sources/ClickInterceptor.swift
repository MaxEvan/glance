import CoreGraphics

/// A session-level event tap for mouse clicks while Mission Control is open.
///
/// Mission Control swallows clicks before they reach our overlay panels, so the
/// overlay is purely visual and this tap does the hit-testing instead. When a
/// mouse-down is consumed, the matching drag/up events are swallowed too so
/// Mission Control never sees half a click.
final class ClickInterceptor {
    enum Button { case left, middle }

    /// Called on mouse-down with the location in global Accessibility/CG coordinates.
    /// Return `true` to consume the click.
    var onMouseDown: (CGPoint, Button) -> Bool = { _, _ in false }

    private var tap: CFMachPort?
    private var swallowing: Button?

    /// Creates the tap (disabled). Returns `false` if macOS refused it.
    func install() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .otherMouseDown, .otherMouseDragged, .otherMouseUp]
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

    /// Only enabled while Mission Control is open, so normal clicks never pass through us.
    func setEnabled(_ enabled: Bool) {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: enabled)
        if !enabled { swallowing = nil }
    }

    /// Returns `true` to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
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
        default:
            return false
        }
    }

    private func consumeIfHandled(_ event: CGEvent, _ button: Button) -> Bool {
        guard onMouseDown(event.location, button) else { return false }
        swallowing = button
        return true
    }
}
