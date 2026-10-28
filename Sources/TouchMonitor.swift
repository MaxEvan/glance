import Foundation

/// Counts fingers on the trackpad through Apple's private MultitouchSupport framework,
/// so a click can be recognised as a three-finger click.
final class TouchMonitor {
    static let shared = TouchMonitor()

    private let lock = NSLock()
    private var current = 0
    /// Most fingers seen during the current (or most recent) touch.
    private var peak = 0
    private var lastTouch = Date.distantPast
    private var devices: CFArray?

    private typealias ContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>
    private typealias RegisterCallback = @convention(c) (UnsafeRawPointer?, ContactCallback) -> Void
    private typealias StartDevice = @convention(c) (UnsafeRawPointer?, Int32) -> Void

    /// Returns `false` if the framework or its symbols are unavailable.
    func start() -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createList = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let startDevice = dlsym(handle, "MTDeviceStart") else { return false }

        // Kept alive for the life of the app; releasing the list stops the callbacks.
        let list = unsafeBitCast(createList, to: CreateList.self)().takeRetainedValue()
        devices = list
        let callback: ContactCallback = { _, _, fingers, _, _ in
            TouchMonitor.shared.update(Int(fingers))
            return 0
        }
        for i in 0..<CFArrayGetCount(list) {
            let device = CFArrayGetValueAtIndex(list, i)
            unsafeBitCast(register, to: RegisterCallback.self)(device, callback)
            unsafeBitCast(startDevice, to: StartDevice.self)(device, 0)
        }
        Log.write("Touch monitor watching \(CFArrayGetCount(list)) trackpad(s)")
        return true
    }

    private func update(_ fingers: Int) {
        lock.withLock {
            peak = current == 0 ? fingers : max(peak, fingers)
            current = fingers
            if fingers > 0 { lastTouch = Date() }
        }
    }

    /// True when the click happening now was made with three fingers on the trackpad.
    /// The recency check keeps a later click from an external mouse from counting.
    var isThreeFingerClick: Bool {
        lock.withLock { peak == 3 && Date().timeIntervalSince(lastTouch) < 0.5 }
    }
}
