import AppKit
import ApplicationServices

/// Closing a window, including one with native tabs.
///
/// A window's red button only closes its active tab. The next tab then comes back as a
/// new window, which Mission Control draws above the overview with no thumbnail. So a
/// tabbed window takes several steps, spread over the run loop because the event tap
/// shares the main thread:
///
/// 1. Close the background tabs, so nothing surfaces. A tab's own button did nothing when
///    tested on an inactive AppKit app, while still reporting success, so one that leaves
///    the tab count unchanged sends us to step 2.
/// 2. Press the red button, find the tab that surfaced, and repeat until none are left.
///    The surfaced tabs may show for a moment, but none stays behind.
///
/// The File menu is no alternative: "Close Window" follows the key window and is disabled
/// while the app is inactive, and "Close All" closes every window the app has.
extension AppWindow {
    /// Limits how long a slow app can hold up the main thread at each step.
    private static let stepTimeout: Float = 0.25
    private static let pollInterval = 0.02
    private static let tabCloseDeadline = 0.25
    private static let surfaceDeadline = 0.5

    private var logName: String { "\(app.localizedName ?? "?") / \"\(title)\"" }

    /// Closes the window and all its tabs, then calls `done`. Call on the main thread.
    func close(done: @escaping () -> Void) {
        AXUIElementSetMessagingTimeout(element, Self.stepTimeout)
        let tabs = element.nativeTabs ?? []
        guard tabs.count > 1 else {
            // A slow app gets the same time to respond as any other press.
            AXUIElementSetMessagingTimeout(element, 0)
            Log.write("Close \(logName): \(tabs.count) tab(s) seen; window children: \(childRoles)")
            let result = Self.pressCloseButton(of: element)
            Log.write("Close \(logName): AXError \(result.rawValue)")
            if result == .attributeUnsupported { minimize() }
            done()
            return
        }
        Log.write("Close \(logName): \(tabs.count) tabs: \(tabs.map { "\"\($0.title ?? "")\"" }.joined(separator: ", "))")
        closeBackgroundTabs(tabs, done: done)
    }

    /// Steam draws its own window buttons inside the page, where Accessibility can't reach
    /// them, and ignores Cmd+W. Minimizing still takes the window out of Mission Control.
    private func minimize() {
        let result = AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        Log.write("  no close button; minimized instead: AXError \(result.rawValue)")
    }

    private var childRoles: String {
        element.children.map { [$0.role ?? "?", $0.subrole].compactMap { $0 }.joined(separator: "/") }.joined(separator: ", ")
    }

    /// Step 1: one background tab at a time, checking that each press did something.
    private func closeBackgroundTabs(_ tabs: [AXUIElement], done: @escaping () -> Void) {
        guard tabs.count > 1 else {
            // Down to one tab, so the red button is the last step and nothing can surface.
            closeTabsOneByOne(window: element, otherTitles: [], done: done)
            return
        }
        guard tabs.contains(where: { $0.isSelectedTab }),
              let tab = tabs.first(where: { !$0.isSelectedTab }),
              let button = tab.tabCloseButton else {
            Log.write("  no background tab with a close button; tab children: \(tabs.map { $0.children.map(\.summary) })")
            closeTabsOneByOne(window: element, otherTitles: backgroundTitles(tabs), done: done)
            return
        }
        AXUIElementSetMessagingTimeout(button, Self.stepTimeout)
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        Log.write("  pressed close on background tab \"\(tab.title ?? "")\": AXError \(result.rawValue)")
        Self.poll(until: Date().addingTimeInterval(Self.tabCloseDeadline), check: { () -> [AXUIElement]? in
            guard let now = element.nativeTabs, now.count < tabs.count else { return nil }
            return now
        }, then: { remaining in
            if let remaining {
                closeBackgroundTabs(remaining, done: done)
            } else {
                Log.write("  still \(tabs.count) tab(s) after pressing; closing them one by one instead")
                closeTabsOneByOne(window: element, otherTitles: backgroundTitles(tabs), done: done)
            }
        })
    }

    private func backgroundTitles(_ tabs: [AXUIElement]) -> [String] {
        tabs.filter { !$0.isSelectedTab }.map { $0.title ?? "" }
    }

    /// Step 2: closes the active tab of `window`, then does the same to the tab that replaces it.
    private func closeTabsOneByOne(window: AXUIElement, otherTitles: [String], done: @escaping () -> Void) {
        // The window's own process: a bundled helper's windows are filed under the app.
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, Self.stepTimeout)
        AXUIElementSetMessagingTimeout(window, Self.stepTimeout)
        let openWindows = { (appElement.value(kAXWindowsAttribute) as? [AXUIElement]) ?? [] }
        let before = openWindows()

        let result = Self.pressCloseButton(of: window)
        Log.write("  pressed window close button: AXError \(result.rawValue), \(otherTitles.count) tab(s) to go")
        guard result == .success, !otherTitles.isEmpty else {
            if result != .success { Log.write("  stopped: \(otherTitles.count) tab(s) may remain") }
            done()
            return
        }

        let start = Date()
        let isNew = { (candidate: AXUIElement) in !before.contains { CFEqual($0, candidate) } }
        Self.poll(until: start.addingTimeInterval(Self.surfaceDeadline), check: { () -> AXUIElement? in
            openWindows().first { isNew($0) && otherTitles.contains($0.title ?? "") }
        }, then: { surfaced in
            guard let surfaced else {
                // Expected for an in-window tab view. For real tabs it means the app is asking
                // something first, such as whether to save, so the window has to stay.
                let newTitles = openWindows().filter(isNew).map { $0.title ?? "" }
                Log.write("  stopped: no next tab surfaced within \(Self.surfaceDeadline)s; expected one of \(otherTitles), new windows: \(newTitles)")
                done()
                return
            }
            var remaining = otherTitles
            if let index = remaining.firstIndex(of: surfaced.title ?? "") { remaining.remove(at: index) }
            Log.write("  tab \"\(surfaced.title ?? "")\" surfaced after \(Int(Date().timeIntervalSince(start) * 1000))ms")
            closeTabsOneByOne(window: surfaced, otherTitles: remaining, done: done)
        })
    }

    private static func pressCloseButton(of window: AXUIElement) -> AXError {
        guard let button = window.value(kAXCloseButtonAttribute), CFGetTypeID(button) == AXUIElementGetTypeID() else {
            return .attributeUnsupported
        }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    }

    /// Calls `check` on the run loop until it returns a value or `deadline` passes, without
    /// blocking the main thread between checks.
    private static func poll<Value>(until deadline: Date, check: @escaping () -> Value?, then: @escaping (Value?) -> Void) {
        if let value = check() {
            then(value)
        } else if Date() >= deadline {
            then(nil)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) {
                poll(until: deadline, check: check, then: then)
            }
        }
    }
}
