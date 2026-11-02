import AppKit

/// The app's settings, reachable even with the menu bar icon hidden.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let contentWidth: CGFloat = 380

    private let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let stack = NSStackView()
    private lazy var iconsCheckbox = NSButton(checkboxWithTitle: "Show app icons in Mission Control", target: self, action: #selector(toggleIcons(_:)))
    private lazy var menuBarCheckbox = NSButton(checkboxWithTitle: "Show menu bar icon", target: self, action: #selector(toggleMenuBarIcon(_:)))
    private lazy var loginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(toggleLaunchAtLogin(_:)))
    private let permissionLabel = NSTextField(labelWithString: "")
    private lazy var permissionButton = NSButton(title: "Open System Settings…", target: self, action: #selector(openAccessibilitySettings))

    var accessibilityGranted = false {
        didSet { refresh() }
    }
    var onAbout: (() -> Void)?
    var onOpenLog: (() -> Void)?

    override init() {
        super.init()
        window.title = "Glance"
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Comes to the current Space, even a full-screen one, instead of pulling you to where it
        // was left. Transient keeps it out of Mission Control, where its thumbnail would only be
        // matched by title to some other app's window, and Cmd+W on it would close that one.
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        window.contentView = makeContent()
        refresh()
        window.center()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Catches up with settings changed from the menu or System Settings.
    func refresh() {
        let settings = Settings.shared
        iconsCheckbox.state = settings.showAppIcons ? .on : .off
        menuBarCheckbox.state = settings.showMenuBarIcon ? .on : .off
        loginCheckbox.state = settings.launchAtLogin ? .on : .off
        permissionLabel.stringValue = accessibilityGranted ? "Accessibility: granted" : "Accessibility: not granted yet"
        permissionButton.isHidden = accessibilityGranted
        stack.layoutSubtreeIfNeeded()
        window.setContentSize(stack.fittingSize)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    private func makeContent() -> NSView {
        let hint = NSTextField(wrappingLabelWithString: "With the icon hidden, open Glance again from Applications, Raycast or Alfred to get back here.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = Self.contentWidth - 18

        // Lines the hint up with the checkbox title above it.
        let hintRow = NSStackView(views: [hint])
        hintRow.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)

        let permissionRow = NSStackView(views: [permissionLabel, permissionButton])
        permissionRow.spacing = 12

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [
            NSButton(title: "About Glance", target: self, action: #selector(about)),
            NSButton(title: "Open Log", target: self, action: #selector(openLog)),
            spacer,
            NSButton(title: "Quit Glance", target: NSApp, action: #selector(NSApplication.terminate(_:))),
        ])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        for view in [iconsCheckbox, menuBarCheckbox, hintRow, loginCheckbox, separator(), permissionRow, separator(), buttonRow] {
            stack.addArrangedSubview(view)
        }
        stack.setCustomSpacing(4, after: menuBarCheckbox)
        buttonRow.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        // Leading-aligned rows don't hold the stack's trailing inset open on their own.
        stack.widthAnchor.constraint(equalToConstant: Self.contentWidth + 40).isActive = true
        return stack
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        return box
    }

    @objc private func toggleIcons(_ sender: NSButton) {
        Settings.shared.showAppIcons = sender.state == .on
    }

    @objc private func toggleMenuBarIcon(_ sender: NSButton) {
        Settings.shared.showMenuBarIcon = sender.state == .on
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        Settings.shared.launchAtLogin = sender.state == .on
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func about() {
        onAbout?()
    }

    @objc private func openLog() {
        onOpenLog?()
    }
}
