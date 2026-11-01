import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var permissionTimer: Timer?
    private let watcher = MissionControlWatcher()
    private let overlay = OverlayController()
    private let clicks = ClickInterceptor()
    private var windows: [AppWindow] = []
    /// What is on screen right now, for hit-testing clicks and shortcuts.
    private var visible: [(thumbnail: Thumbnail, window: AppWindow?)] = []
    private var lastMatchSummary = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.trimIfLarge()
        Log.write("Glance launched on macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
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
        clicks.onShortcut = { [weak self] point, shortcut in self?.handleShortcut(at: point, shortcut) ?? false }
        if !clicks.install() {
            Log.write("Could not install event tap: middle-click, three-finger click, Cmd+W and Cmd+Q will not work")
        }

        watcher.onBegin = { [weak self] in
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

    /// Closes a window on a middle-click or a three-finger trackpad click on its thumbnail.
    /// Returns `true` if the click was used.
    private func handleClick(at point: CGPoint, _ button: ClickInterceptor.Button) -> Bool {
        let threeFinger = button == .left && TouchMonitor.shared.isThreeFingerClick
        guard button == .middle || threeFinger,
              let window = hoveredWindow(at: point, action: "\(threeFinger ? "Three-finger" : "Middle") click") else { return false }
        close(window)
        return true
    }

    /// Runs a keyboard shortcut on the thumbnail under the cursor.
    /// Returns `true` if the keystroke was used.
    private func handleShortcut(at point: CGPoint, _ shortcut: ClickInterceptor.Shortcut) -> Bool {
        switch shortcut {
        case .closeWindow:
            guard let window = hoveredWindow(at: point, action: "Cmd+W") else { return false }
            close(window)
            return true
        case .quitApp:
            guard let window = hoveredWindow(at: point, action: "Cmd+Q") else { return false }
            quit(window.app)
            return true
        }
    }

    /// The window whose thumbnail is under `point`, logging the action that landed there.
    private func hoveredWindow(at point: CGPoint, action: String) -> AppWindow? {
        guard let hit = visible.first(where: { $0.thumbnail.frame.contains(point) }) else { return nil }
        Log.write("\(action) on \"\(hit.thumbnail.title ?? "")\"")
        if hit.window == nil { Log.write("  no matching window; ignoring") }
        return hit.window
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

    /// Deferred so the event tap callback returns before the Accessibility round trip to
    /// the app, which can be slow: macOS disables a tap that holds up input for too long.
    private func close(_ window: AppWindow) {
        DispatchQueue.main.async { [weak self] in
            window.close {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refreshWindows() }
            }
        }
    }

    /// Asks the app to quit normally, so it can save or prompt. Deferred like `close(_:)`.
    /// Finder is left running: it has no Quit by default, and quitting it leaves the desktop without one.
    private func quit(_ app: NSRunningApplication) {
        DispatchQueue.main.async { [weak self] in
            let name = app.localizedName ?? "?"
            guard app.bundleIdentifier != "com.apple.finder" else {
                Log.write("Quit \(name): skipped, Finder stays running")
                return
            }
            let result = app.terminate()
            Log.write("Quit \(name): \(result)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.refreshWindows() }
        }
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Glance")

        let menu = NSMenu()
        menu.addItem(permissionItem)
        menu.addItem(.separator())

        let icons = menu.addItem(withTitle: "Show App Icons", action: #selector(toggleIcons(_:)), keyEquivalent: "")
        icons.target = self
        icons.state = overlay.showIcons ? .on : .off

        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "About Glance", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "l").target = self
        menu.addItem(withTitle: "Quit Glance", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updatePermissionItem(granted: Bool) {
        permissionItem.title = granted ? "Accessibility: granted" : "Accessibility: waiting for permission…"
    }

    @objc private func toggleIcons(_ sender: NSMenuItem) {
        overlay.showIcons.toggle()
        sender.state = overlay.showIcons ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            Log.write("Launch at Login change failed: \(error)")
        }
        sender.state = service.status == .enabled ? .on : .off
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }
}
