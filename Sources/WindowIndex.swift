import AppKit
import ApplicationServices

/// A real application window, found through the app's own Accessibility tree.
struct AppWindow {
    let app: NSRunningApplication
    let title: String
    let element: AXUIElement
}

enum WindowIndex {
    /// Every window of every regular (Dock-visible) app.
    static func build() -> [AppWindow] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .flatMap { app -> [AppWindow] in
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(element, 0.25)
                let windows = (element.value(kAXWindowsAttribute) as? [AXUIElement]) ?? []
                return windows.map { AppWindow(app: app, title: $0.title ?? "", element: $0) }
            }
    }

    /// Pairs each thumbnail with a window, matching on title. A window is used at most once
    /// so two thumbnails with the same title land on two different windows. Windows of apps
    /// that have exited since `windows` was built are skipped, or they could take the title
    /// match from a live window and send its actions to the wrong app.
    static func match(_ thumbnails: [Thumbnail], to windows: [AppWindow]) -> [AppWindow?] {
        var available = windows.filter { !$0.app.isTerminated }
        return thumbnails.map { thumbnail in
            guard let title = thumbnail.title, !title.isEmpty else { return nil }
            let index = available.firstIndex { $0.title == title }
                ?? available.firstIndex { $0.app.localizedName == title }
                ?? available.firstIndex { !$0.title.isEmpty && (title.contains($0.title) || $0.title.contains(title)) }
            guard let index else { return nil }
            return available.remove(at: index)
        }
    }
}
