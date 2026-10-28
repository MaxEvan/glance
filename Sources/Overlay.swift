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
    panel.level = level
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = true
    return panel
}

/// Round "×" button drawn like Exposé's close button.
final class CloseButtonView: NSView {
    var onClick: () -> Void = {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { onClick() }

    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        NSColor(white: 0.15, alpha: 0.9).setFill()
        circle.fill()
        NSColor(white: 1, alpha: 0.9).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let inset = bounds.width * 0.32
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: inset, y: inset))
        cross.line(to: NSPoint(x: bounds.maxX - inset, y: bounds.maxY - inset))
        cross.move(to: NSPoint(x: inset, y: bounds.maxY - inset))
        cross.line(to: NSPoint(x: bounds.maxX - inset, y: inset))
        cross.lineWidth = 2
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }
}

/// The app icon and close button drawn over one thumbnail.
private final class ThumbnailOverlay {
    let iconPanel: NSPanel
    let iconView = NSImageView()
    let closePanel: NSPanel
    let closeView = CloseButtonView()
    var window: AppWindow?

    init(level: NSWindow.Level, onClose: @escaping (AppWindow) -> Void) {
        iconPanel = makePanel(level: level)
        iconPanel.ignoresMouseEvents = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconPanel.contentView = iconView

        closePanel = makePanel(level: level)
        closePanel.contentView = closeView
        closeView.onClick = { [unowned self] in
            if let window = self.window { onClose(window) }
        }
    }

    /// `frame` is the thumbnail in Cocoa screen coordinates.
    func show(over frame: NSRect, window: AppWindow?, showIcon: Bool, showClose: Bool) {
        self.window = window

        if showIcon, let icon = window?.app.icon {
            let size = min(64, max(32, frame.height * 0.3))
            iconView.image = icon
            iconPanel.setFrame(NSRect(x: frame.midX - size / 2, y: frame.minY - size * 0.35, width: size, height: size), display: true)
            iconPanel.orderFrontRegardless()
        } else {
            iconPanel.orderOut(nil)
        }

        if showClose, window != nil {
            let size: CGFloat = 24
            closePanel.setFrame(NSRect(x: frame.minX - size / 2 + 4, y: frame.maxY - size / 2 - 4, width: size, height: size), display: true)
            closePanel.orderFrontRegardless()
        } else {
            closePanel.orderOut(nil)
        }
    }

    func hide() {
        iconPanel.orderOut(nil)
        closePanel.orderOut(nil)
    }

    func setLevel(_ level: NSWindow.Level) {
        iconPanel.level = level
        closePanel.level = level
    }
}

/// Keeps one ThumbnailOverlay per visible thumbnail.
final class OverlayController {
    var level: OverlayLevel = .shielding {
        didSet { overlays.forEach { $0.setLevel(level.windowLevel) } }
    }
    var showIcons = true
    var showCloseButtons = true
    var onClose: (AppWindow) -> Void = { _ in }

    private var overlays: [ThumbnailOverlay] = []

    func show(_ items: [(frame: NSRect, window: AppWindow?)]) {
        while overlays.count < items.count {
            overlays.append(ThumbnailOverlay(level: level.windowLevel) { [weak self] in self?.onClose($0) })
        }
        for (overlay, item) in zip(overlays, items) {
            overlay.show(over: item.frame, window: item.window, showIcon: showIcons, showClose: showCloseButtons)
        }
        overlays.dropFirst(items.count).forEach { $0.hide() }
    }

    func hideAll() {
        overlays.forEach { $0.hide() }
    }
}
