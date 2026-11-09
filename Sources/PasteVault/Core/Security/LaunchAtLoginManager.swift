import Foundation
import ServiceManagement

public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()

    public static let legacyLaunchAgentURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.pastevault.app.plist")
    }()

    public static func cleanupLegacyLaunchAgent() {
        let path = legacyLaunchAgentURL.path
        if FileManager.default.fileExists(atPath: path) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            proc.arguments = ["bootout", "gui/\(getuid())", path]
            try? proc.run()
            proc.waitUntilExit()

            try? FileManager.default.removeItem(atPath: path)
            NSLog("[LaunchAtLoginManager] Legacy LaunchAgent removed: %@", path)
        }
    }

    public var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            } else {
                return false
            }
        }
        set {
            setLaunchAtLogin(newValue)
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        Self.cleanupLegacyLaunchAgent()

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                NSLog("[LaunchAtLoginManager] SMAppService error: %@", error.localizedDescription)
            }
        }
    }
}
