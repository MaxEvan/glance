import AppKit
import ApplicationServices

/// A real application window, found through the app's own Accessibility tree.
struct AppWindow {
    let app: NSRunningApplication
    let title: String
    let element: AXUIElement
    /// Global Accessibility coordinates, read when the index was built.
    let frame: CGRect?
}

enum WindowIndex {
    /// How far apart a thumbnail's and a window's width/height ratios may be for an untitled
    /// match. Mission Control scales windows without distorting them.
    private static let aspectTolerance: CGFloat = 0.03

    /// Every window of every regular (Dock-visible) app.
    static func build() -> [AppWindow] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .flatMap { app -> [AppWindow] in
                let element = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(element, 0.25)
                let windows = (element.value(kAXWindowsAttribute) as? [AXUIElement]) ?? []
                return windows.map { AppWindow(app: app, title: $0.title ?? "", element: $0, frame: $0.frame) }
            }
    }

    /// Pairs each thumbnail with a window, matching on title. A window is used at most once
    /// so two thumbnails with the same title land on two different windows. Windows of apps
    /// that have exited since `windows` was built are skipped, or they could take the title
    /// match from a live window and send its actions to the wrong app.
    ///
    /// Some windows have no title, such as TablePlus's connection window, and the Dock shows
    /// their thumbnails untitled too. Once the titled ones are paired, each untitled thumbnail
    /// takes the untitled window closest to its shape, if one is close enough.
    static func match(_ thumbnails: [Thumbnail], to windows: [AppWindow]) -> [AppWindow?] {
        var available = windows.filter { !$0.app.isTerminated }
        var result = thumbnails.map { thumbnail -> AppWindow? in
            guard let title = thumbnail.title, !title.isEmpty else { return nil }
            let index = available.firstIndex { $0.title == title }
                ?? available.firstIndex { $0.app.localizedName == title }
                ?? available.firstIndex { !$0.title.isEmpty && (title.contains($0.title) || $0.title.contains(title)) }
            guard let index else { return nil }
            return available.remove(at: index)
        }
        for (i, thumbnail) in thumbnails.enumerated() where (thumbnail.title ?? "").isEmpty {
            let target = aspect(thumbnail.frame)
            let candidates = available.indices.compactMap { index -> (index: Int, distance: CGFloat)? in
                let window = available[index]
                guard window.title.isEmpty, let frame = window.frame, let ratio = aspect(frame) else { return nil }
                return target.map { (index, abs(ratio - $0) / $0) }
            }
            guard let best = candidates.min(by: { $0.distance < $1.distance }), best.distance <= aspectTolerance else { continue }
            result[i] = available.remove(at: best.index)
        }
        return result
    }

    private static func aspect(_ frame: CGRect) -> CGFloat? {
        frame.width > 0 && frame.height > 0 ? frame.width / frame.height : nil
    }
}
