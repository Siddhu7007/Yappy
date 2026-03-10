// Checks and prompts for Input Monitoring so Yappy can observe the global hotkey.
import AppKit
import CoreGraphics

protocol InputMonitoringAccessing: AnyObject {
    func ensureAccess(requestIfNeeded: Bool) -> Bool
    func openSystemSettings()
}

final class InputMonitoringAccess: InputMonitoringAccessing {
    init() {}

    func ensureAccess(requestIfNeeded: Bool) -> Bool {
        if CGPreflightListenEventAccess() {
            return true
        }

        guard requestIfNeeded else {
            return false
        }

        return CGRequestListenEventAccess()
    }

    func openSystemSettings() {
        if let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"),
           NSWorkspace.shared.open(privacyURL) {
            return
        }

        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(at: settingsURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
