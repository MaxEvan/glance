import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var permissionTimer: Timer?
    private let watcher = MissionControlWatcher()

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
        watcher.onBegin = { mc in MissionControlWatcher.dumpTree(mc) }
        watcher.start()
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "MCOverlay")

        let menu = NSMenu()
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "l").target = self
        menu.addItem(withTitle: "Quit MCOverlay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updatePermissionItem(granted: Bool) {
        permissionItem.title = granted ? "Accessibility: granted" : "Accessibility: waiting for permission…"
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.url)
    }
}
