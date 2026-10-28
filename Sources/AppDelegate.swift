import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var permissionTimer: Timer?
    private let watcher = MissionControlWatcher()
    private let overlay = OverlayController()
    private let clicks = ClickInterceptor()
    private var windows: [AppWindow] = []
    /// What is on screen right now, for hit-testing clicks.
    private var visible: [(thumbnail: Thumbnail, window: AppWindow?)] = []
    private var lastMatchSummary = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("MCOverlay launched on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        setUpStatusItem()
        requestAccessibility()
    }

    // MARK: Accessibility permission

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            accessibilityGranted()
            return
        }
        Log.write("Waiting for Accessibility permission")
        updatePermissionItem(granted: false)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.accessibilityGranted()
        }
    }

    private func accessibilityGranted() {
        Log.write("Accessibility permission granted")
        updatePermissionItem(granted: true)

        if !TouchMonitor.shared.start() {
            Log.write("Touch monitor unavailable: three-finger click disabled")
        }
        clicks.onMouseDown = { [weak self] point, button in self?.handleClick(at: point, button) ?? false }
        if !clicks.install() {
            Log.write("Could not install click event tap: close buttons will not respond")
        }

        watcher.onBegin = { [weak self] mc in
            MissionControlWatcher.dumpTree(mc)
            self?.refreshWindows()
            self?.clicks.setEnabled(true)
        }
        watcher.onUpdate = { [weak self] thumbnails in self?.showOverlays(for: thumbnails) }
        watcher.onEnd = { [weak self] in
            self?.clicks.setEnabled(false)
            self?.visible = []
            self?.overlay.hideAll()
        }
        watcher.start()
    }

    // MARK: Mission Control

    private func refreshWindows() {
        windows = WindowIndex.build()
        lastMatchSummary = ""
        Log.write("Indexed \(windows.count) app window(s)")
    }

    private func showOverlays(for thumbnails: [Thumbnail]) {
        let matches = WindowIndex.match(thumbnails, to: windows)
        logMatchesIfChanged(thumbnails, matches)
        visible = Array(zip(thumbnails, matches))
        overlay.show(visible.map { ($0.thumbnail.frame, $0.window) })
    }

    /// Closes a window on: a click on its X, a middle-click on its thumbnail, or a
    /// three-finger trackpad click on its thumbnail. Returns `true` if the click was used.
    private func handleClick(at point: CGPoint, _ button: ClickInterceptor.Button) -> Bool {
        if button == .left, overlay.showCloseButtons,
           let hit = visible.first(where: { $0.window != nil && closeButtonFrame(forThumbnail: $0.thumbnail.frame).insetBy(dx: -4, dy: -4).contains(point) }) {
            Log.write("X clicked on \"\(hit.thumbnail.title ?? "")\"")
            close(hit.window!)
            return true
        }

        let threeFinger = button == .left && TouchMonitor.shared.isThreeFingerClick
        guard button == .middle || threeFinger,
              let hit = visible.first(where: { $0.thumbnail.frame.contains(point) }) else { return false }
        Log.write("\(threeFinger ? "Three-finger" : "Middle") click on \"\(hit.thumbnail.title ?? "")\"")
        guard let window = hit.window else {
            Log.write("  no matching window; ignoring")
            return false
        }
        close(window)
        return true
    }

    private func logMatchesIfChanged(_ thumbnails: [Thumbnail], _ matches: [AppWindow?]) {
        let lines = zip(thumbnails, matches).map { thumbnail, window in
            "  \"\(thumbnail.title ?? "")\" -> " + (window.map { "\($0.app.localizedName ?? "?") / \"\($0.title)\"" } ?? "NO MATCH")
        }
        let summary = lines.joined(separator: "\n")
        guard summary != lastMatchSummary else { return }
        lastMatchSummary = summary
        Log.write("Thumbnail matches:\n\(summary)")
    }

    private func close(_ window: AppWindow) {
        let result = window.close()
        Log.write("Close \(window.app.localizedName ?? "?") / \"\(window.title)\": AXError \(result.rawValue)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refreshWindows() }
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "MCOverlay")

        let menu = NSMenu()
        menu.addItem(permissionItem)
        menu.addItem(.separator())

        let icons = menu.addItem(withTitle: "Show App Icons", action: #selector(toggleIcons(_:)), keyEquivalent: "")
        icons.target = self
        icons.state = overlay.showIcons ? .on : .off
        let closeButtons = menu.addItem(withTitle: "Show Close Buttons", action: #selector(toggleCloseButtons(_:)), keyEquivalent: "")
        closeButtons.target = self
        closeButtons.state = overlay.showCloseButtons ? .on : .off

        let levelMenu = NSMenu()
        for level in OverlayLevel.allCases {
            let item = levelMenu.addItem(withTitle: level.title, action: #selector(selectLevel(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level.rawValue
            item.state = level == overlay.level ? .on : .off
        }
        menu.addItem(withTitle: "Overlay Level", action: nil, keyEquivalent: "").submenu = levelMenu

        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "l").target = self
        menu.addItem(withTitle: "Quit MCOverlay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updatePermissionItem(granted: Bool) {
        permissionItem.title = granted ? "Accessibility: granted" : "Accessibility: waiting for permission…"
    }

    @objc private func toggleIcons(_ sender: NSMenuItem) {
        overlay.showIcons.toggle()
        sender.state = overlay.showIcons ? .on : .off
    }

    @objc private func toggleCloseButtons(_ sender: NSMenuItem) {
        overlay.showCloseButtons.toggle()
        sender.state = overlay.showCloseButtons ? .on : .off
    }

    @objc private func selectLevel(_ sender: NSMenuItem) {
        guard let level = OverlayLevel(rawValue: sender.tag) else { return }
        overlay.level = level
        sender.menu?.items.forEach { $0.state = $0 == sender ? .on : .off }
        Log.write("Overlay level set to \(level.title)")
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }
}
