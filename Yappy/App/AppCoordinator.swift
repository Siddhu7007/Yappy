// Coordinates the overlay window, status item, hotkey monitor, and state machine for M1.
import AppKit

private enum CoordinatorErrorCause {
    case inputMonitoring
    case hotkeyMonitoring
    case speechMonitoring
}

@MainActor
final class AppCoordinator {
    private enum SpeechRecoveryDefaults {
        static let signalVerificationDelayNanoseconds: UInt64 = 1_250_000_000
        static let signalThreshold: Float = 0.005
        static let maxAttempts = 3
    }

    private enum OverlayCoverDefaults {
        static let releaseGraceNanoseconds: UInt64 = 1_500_000_000
    }

    private let panelController: OverlayPanelControlling
    private let permissionAccess: InputMonitoringAccessing
    private let speechMonitor: SpeechActivityMonitoring
    private let statusItemController: StatusItemControlling
    private let stateMachine: CharacterStateMachine
    private let hotkeyMonitor: HotkeyMonitoring
    private let interactionMonitor: InteractionMonitoring
    private let interactionRecoveryDelayNanoseconds: UInt64
    private let speechRecoverySignalVerificationDelayNanoseconds: UInt64
    private let speechRecoverySignalThreshold: Float
    private let maxSpeechRecoveryAttempts: Int
    private let overlayCoverReleaseGraceNanoseconds: UInt64

    private var isEnabled = true
    private var isHotkeyHeld = false
    private var permissionPollingTimer: Timer?
    private var currentErrorCause: CoordinatorErrorCause?
    private var isAwaitingRecoveredHotkeyObservation = false
    private var interactionObservationTask: Task<Void, Never>?
    private var speechRecoveryRestartTask: Task<Void, Never>?
    private var speechRecoverySignalVerificationTask: Task<Void, Never>?
    private var speechRecoveryAttemptCount = 0
    private var isAwaitingInteractionSignal = false
    private var isAwaitingSpeechRecoverySignal = false
    private var lastMeasuredSpeechLevel: Float = 0
    private var overlayCoverResetTask: Task<Void, Never>?

    init(
        positionStore: OverlayPositionStore? = nil,
        permissionAccess: InputMonitoringAccessing? = nil,
        speechMonitor: SpeechActivityMonitoring? = nil,
        panelController: OverlayPanelControlling? = nil,
        statusItemController: StatusItemControlling? = nil,
        hotkeyMonitor: HotkeyMonitoring? = nil,
        stateMachine: CharacterStateMachine? = nil,
        interactionMonitor: InteractionMonitoring? = nil,
        interactionRecoveryDelayNanoseconds: UInt64 = 150_000_000,
        speechRecoverySignalVerificationDelayNanoseconds: UInt64 = SpeechRecoveryDefaults.signalVerificationDelayNanoseconds,
        speechRecoverySignalThreshold: Float = SpeechRecoveryDefaults.signalThreshold,
        maxSpeechRecoveryAttempts: Int = SpeechRecoveryDefaults.maxAttempts,
        overlayCoverReleaseGraceNanoseconds: UInt64 = OverlayCoverDefaults.releaseGraceNanoseconds
    ) {
        let resolvedPositionStore = positionStore ?? OverlayPositionStore()
        let resolvedPermissionAccess = permissionAccess ?? InputMonitoringAccess()
        let resolvedSpeechMonitor = speechMonitor ?? SpeechActivityMonitor()
        let resolvedPanelController = panelController ?? OverlayPanelController(positionStore: resolvedPositionStore)
        let resolvedStatusItemController = statusItemController ?? StatusItemController()
        let resolvedHotkeyMonitor = hotkeyMonitor ?? HotkeyMonitor()
        let resolvedStateMachine = stateMachine ?? CharacterStateMachine()
        let resolvedInteractionMonitor = interactionMonitor ?? InteractionMonitor()

        self.panelController = resolvedPanelController
        self.permissionAccess = resolvedPermissionAccess
        self.speechMonitor = resolvedSpeechMonitor
        self.statusItemController = resolvedStatusItemController
        self.stateMachine = resolvedStateMachine
        self.hotkeyMonitor = resolvedHotkeyMonitor
        self.interactionMonitor = resolvedInteractionMonitor
        self.interactionRecoveryDelayNanoseconds = interactionRecoveryDelayNanoseconds
        self.speechRecoverySignalVerificationDelayNanoseconds = speechRecoverySignalVerificationDelayNanoseconds
        self.speechRecoverySignalThreshold = speechRecoverySignalThreshold
        self.maxSpeechRecoveryAttempts = maxSpeechRecoveryAttempts
        self.overlayCoverReleaseGraceNanoseconds = overlayCoverReleaseGraceNanoseconds

        resolvedStateMachine.onStateChange = { [weak self] state in
            self?.panelController.apply(state: state)
        }

        resolvedHotkeyMonitor.onEvent = { [weak self] event in
            self?.handleHotkey(event)
        }

        resolvedHotkeyMonitor.onObservation = { [weak self] source in
            self?.handleHotkeyObservation(from: source)
        }

        resolvedInteractionMonitor.onEvent = { [weak self] event in
            self?.handleInteraction(event)
        }

        resolvedSpeechMonitor.onSpeechActivityChanged = { [weak self] isSpeechActive in
            self?.handleSpeechActivityChanged(isSpeechActive)
        }

        resolvedSpeechMonitor.onLevelChanged = { [weak self] normalizedLevel in
            self?.handleSpeechLevelChanged(normalizedLevel)
        }

        resolvedSpeechMonitor.onPermissionResolved = { [weak self] granted in
            self?.handleSpeechPermissionResolved(granted)
        }

        resolvedSpeechMonitor.onCaptureRuntimeIssue = { [weak self] in
            self?.handleSpeechRecoveryTrigger(.captureRuntimeIssue)
        }

        resolvedStatusItemController.onToggleEnabled = { [weak self] enabled in
            self?.setEnabled(enabled, requestAccessIfNeeded: false)
        }

        resolvedStatusItemController.onRecenter = { [weak self] in
            self?.panelController.recenter()
        }

        resolvedStatusItemController.onOpenInputMonitoring = { [weak self] in
            self?.permissionAccess.openSystemSettings()
        }

        resolvedStatusItemController.onQuit = {
            NSApplication.shared.terminate(nil)
        }
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)
        DebugTrace.resetSession(reason: "app start")
        debugLog("start()")
        debugLog("trace file=\(DebugTrace.logPath)")
        debugLog("bundle id=\(Bundle.main.bundleIdentifier ?? "unknown") app path=\(Bundle.main.bundleURL.path)")

        panelController.show()
        panelController.apply(sizeMode: .idle, animated: false)
        panelController.apply(state: stateMachine.state)
        statusItemController.updateEnabled(isEnabled)
        statusItemController.updateSpeechSourceWarning(nil)
        interactionMonitor.start()
        startMonitoring(requestAccessIfNeeded: true)
        bootstrapMicrophoneAccess()
    }

    func stop() {
        stopPermissionPolling()
        cancelSpeechRecovery(reason: "app stop", resetAttemptState: true)
        cancelOverlayCoverReset(reason: "app stop", resetToIdle: true)
        resetHotkeySessionTracking()
        clearCoordinatorErrorState()
        speechMonitor.stop()
        hotkeyMonitor.stop()
        interactionMonitor.stop()
    }

    private func handleHotkey(_ event: HotkeyEvent) {
        clearInputMonitoringErrorIfNeeded(trigger: "published hotkey \(event == .pressed ? "pressed" : "released")")

        switch event {
        case .pressed:
            guard !isHotkeyHeld else {
                return
            }

            cancelSpeechRecovery(reason: "fresh hotkey press", resetAttemptState: true)
            cancelOverlayCoverReset(reason: "fresh hotkey press", resetToIdle: false)
            debugLog("received hotkey pressed")
            isHotkeyHeld = true
            panelController.apply(sizeMode: .activeCover, animated: true)
            resetSpeechTracking()
            resetSpeechLevelDisplay()
            stateMachine.handle(.hotkeyPressed)
            startSpeechMonitoring()
        case .released:
            guard isHotkeyHeld else {
                return
            }

            finalizeHotkeyRelease()
        }
    }

    private func handleHotkeyObservation(from source: HotkeyInputSource) {
        debugLog("observed live Fn input source=\(source.rawValue)")
        clearInputMonitoringErrorIfNeeded(trigger: "raw Fn input from \(source.rawValue)")
    }

    private func setEnabled(_ enabled: Bool, requestAccessIfNeeded: Bool) {
        isEnabled = enabled
        statusItemController.updateEnabled(enabled)

        if enabled {
            enableCoordinator(requestAccessIfNeeded: requestAccessIfNeeded)
            return
        }

        disableCoordinator()
    }

    private func enableCoordinator(requestAccessIfNeeded: Bool) {
        interactionMonitor.start()
        stopPermissionPolling()
        let monitoringStarted = startMonitoring(requestAccessIfNeeded: requestAccessIfNeeded)
        guard monitoringStarted else {
            return
        }

        clearCoordinatorErrorState()
        stateMachine.handle(.setEnabled(true))
    }

    private func disableCoordinator() {
        interactionMonitor.stop()
        cancelSpeechRecovery(reason: "disabled", resetAttemptState: true)
        cancelOverlayCoverReset(reason: "disabled", resetToIdle: true)
        stopPermissionPolling()
        resetHotkeySessionTracking()
        clearCoordinatorErrorState()
        stopSpeechMonitoringAndResetVisuals()
        hotkeyMonitor.stop()
        stateMachine.handle(.setEnabled(false))
    }

    @discardableResult
    private func startMonitoring(requestAccessIfNeeded: Bool) -> Bool {
        guard isEnabled else {
            return false
        }

        let hasInputMonitoringAccess = permissionAccess.ensureAccess(requestIfNeeded: requestAccessIfNeeded)
        let primaryMonitorStarted = hotkeyMonitor.start()
        debugLog("hotkey monitor start result primary=\(primaryMonitorStarted) running=\(hotkeyMonitor.isRunning)")
        guard primaryMonitorStarted, hotkeyMonitor.isRunning else {
            if hasInputMonitoringAccess {
                handleHotkeyMonitoringFailure(
                    "Yappy could not start reliable Fn monitoring even though Input Monitoring appears granted."
                )
            } else {
                handleInputMonitoringAccessFailure(
                    inputMonitoringAccessMessage()
                )
            }
            return false
        }

        guard hasInputMonitoringAccess else {
            handleInputMonitoringAccessWarning(
                inputMonitoringAccessMessage()
            )
            return false
        }

        if isAwaitingRecoveredHotkeyObservation {
            debugLog("hotkey monitoring restarted after Input Monitoring grant; waiting for first live Fn event")
        }
        return true
    }

    private func handleInputMonitoringAccessWarning(_ message: String) {
        debugLog("Input Monitoring preflight missing; keeping hotkey monitoring active until a live Fn event or explicit grant")
        setCoordinatorErrorState(.inputMonitoring)
        resetHotkeySessionTracking()
        stopSpeechMonitoringAndResetVisuals()
        stateMachine.handle(.permissionDenied)
        startPermissionPolling()
        print(message)
    }

    private func handleInputMonitoringAccessFailure(_ message: String) {
        debugLog("Input Monitoring missing; failing closed until access is granted")
        setCoordinatorErrorState(.inputMonitoring)
        resetHotkeySessionTracking()
        stopSpeechMonitoringAndResetVisuals()
        hotkeyMonitor.stop()
        stateMachine.handle(.permissionDenied)
        permissionAccess.openSystemSettings()
        startPermissionPolling()
        print(message)
    }

    private func handleHotkeyMonitoringFailure(_ message: String) {
        setCoordinatorErrorState(.hotkeyMonitoring)
        resetHotkeySessionTracking()
        stopSpeechMonitoringAndResetVisuals()
        hotkeyMonitor.stop()
        stateMachine.handle(.permissionDenied)
        print(message)
    }

    private func startPermissionPolling() {
        guard permissionPollingTimer == nil else {
            return
        }

        permissionPollingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollInputMonitoringAccess()
            }
        }
    }

    func pollInputMonitoringAccess() {
        guard isEnabled else {
            stopPermissionPolling()
            return
        }

        guard permissionAccess.ensureAccess(requestIfNeeded: false) else {
            return
        }

        stopPermissionPolling()
        guard currentErrorCause == .inputMonitoring else {
            return
        }

        guard !hotkeyMonitor.isRunning else {
            debugLog("Input Monitoring access granted while hotkey monitoring is already running; clearing warning without restart")
            clearInputMonitoringErrorIfNeeded(trigger: "Input Monitoring grant polling")
            return
        }

        restartHotkeyMonitoringAfterInputMonitoringGrant()
    }

    private func stopPermissionPolling() {
        permissionPollingTimer?.invalidate()
        permissionPollingTimer = nil
    }

    private func handleSpeechActivityChanged(_ isSpeechActive: Bool) {
        guard isHotkeyHeld else {
            return
        }

        stateMachine.handle(.speechActivityChanged(isSpeechActive))
    }

    private func handleInteraction(_ event: InteractionEvent) {
        if event == .pointerDown {
            hotkeyMonitor.notePointerDown()
        }

        handleSpeechRecoveryTrigger(event)
    }

    private func handleSpeechRecoveryTrigger(_ trigger: InteractionEvent) {
        guard isEnabled, isHotkeyHeld else {
            return
        }

        switch trigger {
        case .captureRuntimeIssue:
            beginSpeechRecovery(trigger, restartDelayNanoseconds: interactionRecoveryDelayNanoseconds)
        case .pointerDown, .activeApplicationChanged:
            guard stateMachine.state == .speaking || lastMeasuredSpeechLevel > speechRecoverySignalThreshold else {
                debugLog("ignoring interaction trigger=\(trigger.rawValue) because no live speech was present")
                return
            }

            guard !hasActiveSpeechRecovery else {
                debugLog("ignoring interaction trigger=\(trigger.rawValue) while recovery is already active")
                return
            }

            armInteractionSignalObservation(trigger: trigger)
        }
    }

    private func handleSpeechLevelChanged(_ normalizedLevel: Float) {
        guard isHotkeyHeld else {
            return
        }

        lastMeasuredSpeechLevel = normalizedLevel
        panelController.apply(speechLevel: CGFloat(normalizedLevel))

        if isAwaitingInteractionSignal, normalizedLevel > speechRecoverySignalThreshold {
            cancelSpeechRecovery(reason: "interaction signal observed", resetAttemptState: false)
        }

        guard isAwaitingSpeechRecoverySignal, normalizedLevel > speechRecoverySignalThreshold else {
            return
        }

        debugLog(
            "speech recovery verified trigger level=\(normalizedLevel) attempt=\(speechRecoveryAttemptCount)"
        )
        cancelSpeechRecovery(reason: "signal verified", resetAttemptState: true)
    }

    private func handleSpeechPermissionResolved(_ granted: Bool) {
        debugLog("speech permission resolved granted=\(granted) hotkeyHeld=\(isHotkeyHeld)")
        if granted {
            if isHotkeyHeld {
                startSpeechMonitoring()
            }
            return
        }

        handleSpeechMonitoringFailure(
            microphoneAccessMessage,
            openSystemSettings: isHotkeyHeld
        )
    }

    private func bootstrapMicrophoneAccess() {
        switch speechMonitor.requestMicrophoneAccessIfNeeded() {
        case true:
            debugLog("microphone already authorized on launch")
            return
        case false:
            debugLog("microphone denied on launch")
            handleSpeechMonitoringFailure(
                microphoneAccessMessage,
                openSystemSettings: false
            )
        case nil:
            debugLog("requested microphone access on launch")
            print(microphonePermissionRequestMessage)
        }
    }

    @discardableResult
    private func startSpeechMonitoring() -> SpeechMonitoringStartResult {
        let result = speechMonitor.start()
        debugLog("startSpeechMonitoring result=\(result)")

        switch result {
        case .started:
            statusItemController.updateSpeechSourceWarning(nil)
            return result
        case .permissionPending:
            statusItemController.updateSpeechSourceWarning(nil)
            print(microphonePermissionRequestMessage)
        case .denied:
            statusItemController.updateSpeechSourceWarning(nil)
            handleSpeechMonitoringFailure(
                microphoneAccessMessage,
                openSystemSettings: true
            )
        case .unavailable:
            statusItemController.updateSpeechSourceWarning(nil)
            handleSpeechMonitoringFailure(
                microphoneUnavailableMessage,
                openSystemSettings: false
            )
        case let .unresolvedSource(message):
            statusItemController.updateSpeechSourceWarning(message)
            debugLog("speech source unresolved message=\(message)")
        }

        return result
    }

    private func handleSpeechMonitoringFailure(_ message: String, openSystemSettings: Bool) {
        cancelSpeechRecovery(reason: "speech monitoring failure", resetAttemptState: true)
        statusItemController.updateSpeechSourceWarning(nil)
        setCoordinatorErrorState(.speechMonitoring)
        resetHotkeySessionTracking()
        stopSpeechMonitoringAndResetVisuals()
        stateMachine.handle(.permissionDenied)

        if openSystemSettings {
            speechMonitor.openSystemSettings()
        }

        print(message)
    }

    private func restartHotkeyMonitoringAfterInputMonitoringGrant() {
        debugLog("Input Monitoring access granted; restarting hotkey monitoring")
        hotkeyMonitor.stop()
        isAwaitingRecoveredHotkeyObservation = true
        _ = startMonitoring(requestAccessIfNeeded: false)
    }

    private func clearInputMonitoringErrorIfNeeded(trigger: String) {
        guard currentErrorCause == .inputMonitoring else {
            return
        }

        debugLog("clearing input-monitoring error after \(trigger)")
        clearCoordinatorErrorState()

        guard isEnabled, !isHotkeyHeld else {
            return
        }

        stateMachine.handle(.setEnabled(true))
    }

    private var hasActiveSpeechRecovery: Bool {
        speechRecoveryRestartTask != nil || speechRecoverySignalVerificationTask != nil || isAwaitingSpeechRecoverySignal
    }

    private func finalizeHotkeyRelease() {
        cancelSpeechRecovery(reason: "hotkey released", resetAttemptState: true)
        debugLog("confirmed hotkey released; stopping capture immediately")
        resetHotkeySessionTracking()
        stateMachine.handle(.hotkeyReleased)
        stopSpeechMonitoringAndResetVisuals()
        scheduleOverlayCoverResetAfterRelease()
    }

    private func resetHotkeySessionTracking() {
        isHotkeyHeld = false
        resetSpeechTracking()
    }

    private func resetSpeechTracking() {
        lastMeasuredSpeechLevel = 0
    }

    private func resetSpeechLevelDisplay() {
        panelController.apply(speechLevel: 0)
    }

    private func stopSpeechMonitoringAndResetVisuals() {
        speechMonitor.stop()
        resetSpeechLevelDisplay()
    }

    private func scheduleOverlayCoverResetAfterRelease() {
        cancelOverlayCoverReset(reason: "schedule overlay reset", resetToIdle: false)
        let delay = overlayCoverReleaseGraceNanoseconds
        debugLog("overlay cover reset armed timeoutMs=\(delay / 1_000_000)")
        overlayCoverResetTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            self.overlayCoverResetTask = nil
            self.debugLog("overlay cover reset fired")
            self.panelController.apply(sizeMode: .idle, animated: true)
        }
    }

    private func cancelOverlayCoverReset(reason: String, resetToIdle: Bool) {
        if let overlayCoverResetTask {
            overlayCoverResetTask.cancel()
            self.overlayCoverResetTask = nil
            debugLog("overlay cover reset cancelled reason=\(reason)")
        }

        guard resetToIdle else {
            return
        }

        panelController.apply(sizeMode: .idle, animated: false)
    }

    private func setCoordinatorErrorState(_ cause: CoordinatorErrorCause) {
        currentErrorCause = cause
        isAwaitingRecoveredHotkeyObservation = false
    }

    private func clearCoordinatorErrorState() {
        currentErrorCause = nil
        isAwaitingRecoveredHotkeyObservation = false
    }

    private func armInteractionSignalObservation(trigger: InteractionEvent) {
        cancelInteractionSignalObservation(reason: "rescheduled by \(trigger.rawValue)")
        isAwaitingInteractionSignal = true
        let delayNanoseconds = interactionRecoveryDelayNanoseconds
        debugLog(
            "interaction signal observation armed trigger=\(trigger.rawValue) timeoutMs=\(delayNanoseconds / 1_000_000)"
        )

        interactionObservationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.interactionObservationTask = nil
            guard self.isEnabled, self.isHotkeyHeld, self.isAwaitingInteractionSignal else {
                self.cancelInteractionSignalObservation(reason: "interaction observation context lost")
                return
            }

            self.isAwaitingInteractionSignal = false
            self.debugLog("interaction signal timed out trigger=\(trigger.rawValue); starting recovery")
            self.beginSpeechRecovery(trigger, restartDelayNanoseconds: 0)
        }
    }

    private func beginSpeechRecovery(_ trigger: InteractionEvent, restartDelayNanoseconds: UInt64) {
        let startsNewBurst = !hasActiveSpeechRecovery
        if startsNewBurst {
            speechRecoveryAttemptCount = 0
        }

        debugLog(
            "speech recovery trigger=\(trigger.rawValue) active=\(hasActiveSpeechRecovery) attemptCount=\(speechRecoveryAttemptCount)"
        )
        cancelSpeechRecovery(reason: "rescheduled by \(trigger.rawValue)", resetAttemptState: false)
        speechMonitor.stop()
        panelController.apply(speechLevel: 0)
        scheduleSpeechRecoveryRestart(trigger: trigger, delayNanoseconds: restartDelayNanoseconds)
    }

    private func scheduleSpeechRecoveryRestart(trigger: InteractionEvent, delayNanoseconds: UInt64) {
        SpeechMonitorDebugTrace.logInteractionRecoveryScheduled(
            trigger: trigger,
            delayMilliseconds: delayNanoseconds / 1_000_000
        )

        speechRecoveryRestartTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.speechRecoveryRestartTask = nil
            guard self.isEnabled, self.isHotkeyHeld else {
                SpeechMonitorDebugTrace.logInteractionRecoveryCompleted(trigger: trigger, restarted: false)
                self.cancelSpeechRecovery(reason: "recovery context lost", resetAttemptState: true)
                return
            }

            self.speechRecoveryAttemptCount += 1
            SpeechMonitorDebugTrace.logInteractionRecoveryCompleted(trigger: trigger, restarted: true)
            self.debugLog(
                "speech recovery restart started trigger=\(trigger.rawValue) attempt=\(self.speechRecoveryAttemptCount)"
            )
            let result = self.startSpeechMonitoring()
            guard result == .started else {
                self.cancelSpeechRecovery(reason: "recovery start failed", resetAttemptState: true)
                return
            }

            self.armSpeechRecoverySignalVerification(trigger: trigger)
        }
    }

    private func armSpeechRecoverySignalVerification(trigger: InteractionEvent) {
        isAwaitingSpeechRecoverySignal = true
        let verificationDelay = speechRecoverySignalVerificationDelayNanoseconds
        let attemptNumber = speechRecoveryAttemptCount
        debugLog(
            "speech recovery verification armed trigger=\(trigger.rawValue) attempt=\(attemptNumber) timeoutMs=\(verificationDelay / 1_000_000)"
        )

        speechRecoverySignalVerificationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: verificationDelay)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.speechRecoverySignalVerificationTask = nil
            guard self.isEnabled, self.isHotkeyHeld, self.isAwaitingSpeechRecoverySignal else {
                self.cancelSpeechRecovery(reason: "verification context lost", resetAttemptState: true)
                return
            }

            self.isAwaitingSpeechRecoverySignal = false

            let shouldRetry = self.speechRecoveryAttemptCount < self.maxSpeechRecoveryAttempts
            self.debugLog(
                "speech recovery verification timed out trigger=\(trigger.rawValue) attempt=\(attemptNumber) shouldRetry=\(shouldRetry)"
            )

            guard shouldRetry else {
                self.cancelSpeechRecovery(reason: "recovery attempts exhausted", resetAttemptState: true)
                return
            }

            self.speechMonitor.stop()
            self.panelController.apply(speechLevel: 0)
            self.scheduleSpeechRecoveryRestart(
                trigger: trigger,
                delayNanoseconds: self.interactionRecoveryDelayNanoseconds
            )
        }
    }

    private func cancelInteractionSignalObservation(reason: String) {
        if let interactionObservationTask {
            interactionObservationTask.cancel()
            self.interactionObservationTask = nil
            debugLog("interaction signal observation cancelled reason=\(reason)")
        }

        isAwaitingInteractionSignal = false
    }

    private func cancelSpeechRecovery(reason: String, resetAttemptState: Bool) {
        cancelInteractionSignalObservation(reason: reason)
        if let speechRecoveryRestartTask {
            speechRecoveryRestartTask.cancel()
            self.speechRecoveryRestartTask = nil
            SpeechMonitorDebugTrace.logInteractionRecoveryCancelled(reason: reason)
        }

        if let speechRecoverySignalVerificationTask {
            speechRecoverySignalVerificationTask.cancel()
            self.speechRecoverySignalVerificationTask = nil
            debugLog("speech recovery verification cancelled reason=\(reason)")
        }

        isAwaitingSpeechRecoverySignal = false
        if resetAttemptState {
            speechRecoveryAttemptCount = 0
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        let line = "[AppCoordinator] \(message)"
        print(line)
        DebugTrace.log(line)
        #endif
    }

    private var microphoneAccessMessage: String {
        "Yappy needs Microphone access to drive the head motion from your live voice. Enable Microphone in System Settings > Privacy & Security > Microphone."
    }

    private var microphonePermissionRequestMessage: String {
        "Yappy requested Microphone access so the head can follow your live voice while Fn is held."
    }

    private var microphoneUnavailableMessage: String {
        "Yappy could not start microphone monitoring for live head motion."
    }

    private func inputMonitoringAccessMessage() -> String {
        let appPath = Bundle.main.bundleURL.path
        return """
        Yappy needs Input Monitoring to detect Fn reliably. Enable Input Monitoring in System Settings > Privacy & Security > Input Monitoring for:
        \(appPath)
        If you are running a Xcode “Sign to Run Locally” build, macOS may treat each rebuild as a new app. In that case, set a real Development Team for Yappy, rebuild, re-enable Input Monitoring for the rebuilt app, and relaunch.
        """
    }
}
