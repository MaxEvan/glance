import Foundation
import ServiceManagement

/// The settings shared by the menu bar menu and the settings window.
final class Settings {
    static let shared = Settings()

    /// Called after any setting changes, so every place showing one can catch up.
    var onChange: (() -> Void)?

    var showAppIcons = UserDefaults.standard.object(forKey: "showIcons") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showAppIcons, forKey: "showIcons")
            onChange?()
        }
    }

    var showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon")
            onChange?()
        }
    }

    /// Lives in the system's login items rather than in defaults, so it can also change from System Settings.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.write("Launch at Login change failed: \(error)")
            }
            onChange?()
        }
    }
}
