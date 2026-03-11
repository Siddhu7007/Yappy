// Provides a minimal menu bar control surface for enabling, recentering, and quitting Yappy.
import AppKit

@MainActor
protocol StatusItemControlling: AnyObject {
    var onToggleEnabled: ((Bool) -> Void)? { get set }
    var onRecenter: (() -> Void)? { get set }
    var onOpenInputMonitoring: (() -> Void)? { get set }
    var onQuit: (() -> Void)? { get set }

    func updateEnabled(_ enabled: Bool)
    func updateSpeechSourceWarning(_ message: String?)
}

@MainActor
final class StatusItemController: NSObject, StatusItemControlling {
    var onToggleEnabled: ((Bool) -> Void)?
    var onRecenter: (() -> Void)?
    var onOpenInputMonitoring: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let enabledItem = NSMenuItem(title: "Enabled", action: nil, keyEquivalent: "")
    private let speechSourceWarningItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let speechSourceWarningSeparator = NSMenuItem.separator()
    private var isEnabled = true

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Yappy")
            button.imagePosition = .imageOnly
        }

        enabledItem.target = self
        enabledItem.action = #selector(toggleEnabled)
        speechSourceWarningItem.isEnabled = false
        speechSourceWarningItem.isHidden = true
        speechSourceWarningSeparator.isHidden = true

        let recenterItem = NSMenuItem(title: "Recenter Overlay", action: #selector(recenterOverlay), keyEquivalent: "")
        recenterItem.target = self

        let permissionsItem = NSMenuItem(title: "Open Input Monitoring Settings", action: #selector(openInputMonitoring), keyEquivalent: "")
        permissionsItem.target = self

        let quitItem = NSMenuItem(title: "Quit Yappy", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        let menu = NSMenu()
        menu.addItem(enabledItem)
        menu.addItem(speechSourceWarningItem)
        menu.addItem(speechSourceWarningSeparator)
        menu.addItem(recenterItem)
        menu.addItem(permissionsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateEnabled(true)
    }

    func updateEnabled(_ enabled: Bool) {
        isEnabled = enabled
        enabledItem.state = enabled ? .on : .off
    }

    func updateSpeechSourceWarning(_ message: String?) {
        let resolvedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        speechSourceWarningItem.title = resolvedMessage ?? ""
        let isVisible = !(resolvedMessage?.isEmpty ?? true)
        speechSourceWarningItem.isHidden = !isVisible
        speechSourceWarningSeparator.isHidden = !isVisible
    }

    @objc
    private func toggleEnabled() {
        isEnabled.toggle()
        updateEnabled(isEnabled)
        onToggleEnabled?(isEnabled)
    }

    @objc
    private func recenterOverlay() {
        onRecenter?()
    }

    @objc
    private func openInputMonitoring() {
        onOpenInputMonitoring?()
    }

    @objc
    private func quit() {
        onQuit?()
    }
}
