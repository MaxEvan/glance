import AppKit

/// Window levels to try for drawing above Mission Control. Which one works is part of what this test finds out.
enum OverlayLevel: Int, CaseIterable {
    case statusBar, popUpMenu, screenSaver, shielding

    var title: String {
        switch self {
        case .statusBar: return "Status bar"
        case .popUpMenu: return "Pop-up menu"
        case .screenSaver: return "Screen saver"
        case .shielding: return "Above everything (shielding)"
        }
    }

    var windowLevel: NSWindow.Level {
        switch self {
        case .statusBar: return .statusBar
        case .popUpMenu: return .popUpMenu
        case .screenSaver: return .screenSaver
        case .shielding: return NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        }
    }
}

/// A small borderless panel that stays on every Space and is not itself pulled into Mission Control.
private func makePanel(level: NSWindow.Level) -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = .none
    panel.level = level
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    return panel
}

/// The app icon drawn over one thumbnail.
private final class ThumbnailOverlay {
    let iconPanel: NSPanel
    let iconView = NSImageView()

    init(level: NSWindow.Level) {
        iconPanel = makePanel(level: level)
        iconPanel.ignoresMouseEvents = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconPanel.contentView = iconView
    }

    /// `axFrame` is the thumbnail in global Accessibility coordinates.
    func show(over axFrame: CGRect, window: AppWindow?, showIcon: Bool) {
        let frame = cocoaRect(fromAX: axFrame)
        if showIcon, let icon = window?.app.icon {
            let size = min(64, max(32, frame.height * 0.3))
            iconView.image = icon
            iconPanel.setFrame(NSRect(x: frame.midX - size / 2, y: frame.minY - size * 0.35, width: size, height: size), display: true)
            if !iconPanel.isVisible { fadeIn(iconPanel) }
        } else {
            iconPanel.orderOut(nil)
        }
    }

    /// Slow ease-in fade, so icons appear gently as Mission Control opens.
    private func fadeIn(_ panel: NSPanel) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        iconPanel.orderOut(nil)
    }

    func setLevel(_ level: NSWindow.Level) {
        iconPanel.level = level
    }
}

/// Keeps one ThumbnailOverlay per visible thumbnail.
final class OverlayController {
    var level: OverlayLevel = .shielding {
        didSet { overlays.forEach { $0.setLevel(level.windowLevel) } }
    }
    var showIcons = true

    private var overlays: [ThumbnailOverlay] = []

    /// Frames are in global Accessibility coordinates.
    func show(_ items: [(frame: CGRect, window: AppWindow?)]) {
        while overlays.count < items.count {
            overlays.append(ThumbnailOverlay(level: level.windowLevel))
        }
        for (overlay, item) in zip(overlays, items) {
            overlay.show(over: item.frame, window: item.window, showIcon: showIcons)
        }
        overlays.dropFirst(items.count).forEach { $0.hide() }
    }

    func hideAll() {
        overlays.forEach { $0.hide() }
    }
}
