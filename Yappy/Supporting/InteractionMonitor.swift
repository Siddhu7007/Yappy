import AppKit

enum InteractionEvent: String, Equatable {
    case pointerDown
    case activeApplicationChanged
    case captureRuntimeIssue
}

@MainActor
protocol InteractionMonitoring: AnyObject {
    var onEvent: ((InteractionEvent) -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
final class InteractionMonitor: InteractionMonitoring {
    var onEvent: ((InteractionEvent) -> Void)?

    private let workspaceNotificationCenter: NotificationCenter
    private var globalPointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var activeApplicationObserver: NSObjectProtocol?
    private var isRunning = false

    init(workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        debugLog("start()")
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.debugLog("observed pointerDown source=global")
                self?.onEvent?(.pointerDown)
            }
        }

        localPointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.debugLog("observed pointerDown source=local")
            self?.onEvent?(.pointerDown)
            return event
        }

        activeApplicationObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.debugLog("observed activeApplicationChanged")
                self?.onEvent?(.activeApplicationChanged)
            }
        }
    }

    func stop() {
        if let globalPointerMonitor {
            NSEvent.removeMonitor(globalPointerMonitor)
        }

        if let localPointerMonitor {
            NSEvent.removeMonitor(localPointerMonitor)
        }

        if let activeApplicationObserver {
            workspaceNotificationCenter.removeObserver(activeApplicationObserver)
        }

        globalPointerMonitor = nil
        localPointerMonitor = nil
        activeApplicationObserver = nil
        isRunning = false
        debugLog("stopped")
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        let line = "[InteractionMonitor] \(message)"
        print(line)
        DebugTrace.log(line)
        #endif
    }
}
