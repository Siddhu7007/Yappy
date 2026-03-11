import CoreGraphics
import Testing
@testable import Yappy

@MainActor
struct AppCoordinatorTests {
    @Test
    func startRequestsMicrophoneAccessOnLaunch() {
        let speechMonitor = SpeechMonitorSpy()
        let coordinator = makeCoordinator(speechMonitor: speechMonitor)

        coordinator.start()

        #expect(speechMonitor.requestMicrophoneAccessCallCount == 1)
    }

    @Test
    func deniedLaunchPermissionShowsErrorWithoutOpeningMicrophoneSettings() {
        let panelController = OverlayPanelControllerSpy()
        let speechMonitor = SpeechMonitorSpy(requestMicrophoneAccessResult: false)
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            panelController: panelController
        )

        coordinator.start()

        #expect(panelController.appliedStates.last == .error)
        #expect(speechMonitor.openSystemSettingsCallCount == 0)
    }

    @Test
    func grantedPermissionCallbackWhileIdleDoesNotStartSpeechMonitoring() {
        let speechMonitor = SpeechMonitorSpy(requestMicrophoneAccessResult: nil)
        let coordinator = makeCoordinator(speechMonitor: speechMonitor)

        coordinator.start()
        speechMonitor.emitPermissionResolved(true)

        #expect(speechMonitor.startCallCount == 0)
    }

    @Test
    func grantedPermissionCallbackWhileFnIsHeldStartsSpeechMonitoring() {
        let speechMonitor = SpeechMonitorSpy(
            requestMicrophoneAccessResult: nil,
            startResults: [.permissionPending, .started]
        )
        let hotkeyMonitor = HotkeyMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitPermissionResolved(true)

        #expect(speechMonitor.startCallCount == 2)
    }

    @Test
    func missingInputMonitoringStillStartsHotkeyMonitoringAndLeavesRecoverableError() {
        let panelController = OverlayPanelControllerSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let inputMonitoringAccess = InputMonitoringAccessSpy(results: [false])
        let coordinator = makeCoordinator(
            speechMonitor: SpeechMonitorSpy(),
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor,
            inputMonitoringAccess: inputMonitoringAccess
        )

        coordinator.start()

        #expect(panelController.appliedStates.last == .error)
        #expect(inputMonitoringAccess.openSystemSettingsCallCount == 0)
        #expect(hotkeyMonitor.startCallCount == 1)
        #expect(hotkeyMonitor.stopCallCount == 0)
        #expect(hotkeyMonitor.isRunning == true)
    }

    @Test
    func advisoryInputMonitoringErrorReturnsToIdleAfterObservedFnInput() {
        let panelController = OverlayPanelControllerSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let inputMonitoringAccess = InputMonitoringAccessSpy(results: [false])
        let coordinator = makeCoordinator(
            speechMonitor: SpeechMonitorSpy(),
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor,
            inputMonitoringAccess: inputMonitoringAccess
        )

        coordinator.start()
        #expect(panelController.appliedStates.last == .error)

        hotkeyMonitor.emitObservation(.hid)
        #expect(panelController.appliedStates.last == .idle)
    }

    @Test
    func advisoryInputMonitoringErrorStillAllowsPublishedHotkeyPressToStartSpeechMonitoring() {
        let panelController = OverlayPanelControllerSpy()
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let inputMonitoringAccess = InputMonitoringAccessSpy(results: [false])
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor,
            inputMonitoringAccess: inputMonitoringAccess
        )

        coordinator.start()
        #expect(panelController.appliedStates.last == .error)

        hotkeyMonitor.emit(.pressed)

        #expect(speechMonitor.startCallCount == 1)
        #expect(panelController.appliedStates.last == .listening)
    }

    @Test
    func synthesizedReleaseAfterPressStopsSpeechMonitoringAndReturnsToIdle() {
        let panelController = OverlayPanelControllerSpy()
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let inputMonitoringAccess = InputMonitoringAccessSpy(results: [false])
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor,
            inputMonitoringAccess: inputMonitoringAccess
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.62)
        let stopCallCountBeforeRelease = speechMonitor.stopCallCount

        hotkeyMonitor.emit(.released)

        #expect(speechMonitor.stopCallCount == stopCallCountBeforeRelease + 1)
        #expect(panelController.appliedStates.last == .idle)
        #expect(panelController.speechLevels.last == 0)
    }

    @Test
    func hotkeyReleaseStopsSpeechMonitoringImmediatelyWhileListening() {
        let panelController = OverlayPanelControllerSpy()
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        hotkeyMonitor.emit(.released)

        #expect(speechMonitor.stopCallCount == 1)
        #expect(panelController.appliedStates.last == .idle)
        #expect(panelController.speechLevels.last == 0)
    }

    @Test
    func postReleaseLevelsDoNotMoveTheOverlayOrRestartListening() {
        let panelController = OverlayPanelControllerSpy()
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.62)
        hotkeyMonitor.emit(.released)

        let stateCountAfterRelease = panelController.appliedStates.count
        let levelCountAfterRelease = panelController.speechLevels.count
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.91)
        speechMonitor.emitSpeechActivity(false)

        #expect(speechMonitor.stopCallCount == 1)
        #expect(panelController.appliedStates.count == stateCountAfterRelease)
        #expect(panelController.speechLevels.count == levelCountAfterRelease)
        #expect(panelController.appliedStates.last == .idle)
        #expect(panelController.speechLevels.last == 0)
    }

    @Test
    func captureRuntimeIssueAfterFnReleaseDoesNotRestartSpeechMonitoring() async {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionRecoveryDelayNanoseconds: 20_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 250_000_000
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        hotkeyMonitor.emit(.released)
        let startCallCountAfterRelease = speechMonitor.startCallCount
        let stopCallCountAfterRelease = speechMonitor.stopCallCount

        speechMonitor.emitCaptureRuntimeIssue()
        try? await Task.sleep(nanoseconds: 120_000_000)

        #expect(speechMonitor.startCallCount == startCallCountAfterRelease)
        #expect(speechMonitor.stopCallCount == stopCallCountAfterRelease)
    }

    @Test
    func missingInputMonitoringWithoutAnyRunningMonitorRemainsHardError() {
        let panelController = OverlayPanelControllerSpy()
        let hotkeyMonitor = HotkeyMonitorSpy(startResult: false, runningAfterStart: false)
        let inputMonitoringAccess = InputMonitoringAccessSpy(results: [false])
        let coordinator = makeCoordinator(
            speechMonitor: SpeechMonitorSpy(),
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor,
            inputMonitoringAccess: inputMonitoringAccess
        )

        coordinator.start()

        #expect(panelController.appliedStates.last == .error)
        #expect(hotkeyMonitor.startCallCount == 1)
        #expect(hotkeyMonitor.stopCallCount == 1)
        #expect(inputMonitoringAccess.openSystemSettingsCallCount == 1)
    }

    @Test
    func pollingGrantedInputMonitoringClearsAdvisoryErrorWithoutRestartingHotkeyMonitoring() {
        let panelController = OverlayPanelControllerSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let inputMonitoringAccess = InputMonitoringAccessSpy(results: [false, true])
        let coordinator = makeCoordinator(
            speechMonitor: SpeechMonitorSpy(),
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor,
            inputMonitoringAccess: inputMonitoringAccess
        )

        coordinator.start()
        #expect(panelController.appliedStates.last == .error)
        #expect(hotkeyMonitor.startCallCount == 1)

        coordinator.pollInputMonitoringAccess()

        #expect(hotkeyMonitor.startCallCount == 1)
        #expect(hotkeyMonitor.stopCallCount == 0)
        #expect(panelController.appliedStates.last == .idle)
    }

    @Test
    func realHotkeyPressStartsSpeechMonitoringAndForwardsSpeechLevels() {
        let panelController = OverlayPanelControllerSpy()
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)

        #expect(speechMonitor.startCallCount == 1)
        #expect(panelController.appliedStates.last == .listening)

        speechMonitor.emitSpeechActivity(true)
        #expect(panelController.appliedStates.last == .speaking)

        speechMonitor.emitLevel(0.62)
        let forwardedLevel = panelController.speechLevels.last ?? -1
        #expect(abs(forwardedLevel - CGFloat(0.62)) < 0.0001)

        hotkeyMonitor.emit(.released)
        #expect(speechMonitor.stopCallCount == 1)
        #expect(panelController.appliedStates.last == .idle)
        #expect(panelController.speechLevels.last == 0)
    }

    @Test
    func unresolvedSpeechSourceKeepsTheOverlayListeningAndShowsAStatusWarning() {
        let panelController = OverlayPanelControllerSpy()
        let speechMonitor = SpeechMonitorSpy(
            startResults: [.unresolvedSource("Speech Sync: Can't match the selected dictation microphone")]
        )
        let hotkeyMonitor = HotkeyMonitorSpy()
        let statusItemController = StatusItemControllerSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor,
            statusItemController: statusItemController
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)

        #expect(speechMonitor.startCallCount == 1)
        #expect(panelController.appliedStates.last == .listening)
        #expect(statusItemController.warningMessages.last == "Speech Sync: Can't match the selected dictation microphone")
        #expect(speechMonitor.openSystemSettingsCallCount == 0)
    }

    @Test
    func successfulSpeechStartClearsAnExistingSpeechSyncWarning() {
        let speechMonitor = SpeechMonitorSpy(
            startResults: [.unresolvedSource("Speech Sync: Can't match the selected dictation microphone"), .started]
        )
        let hotkeyMonitor = HotkeyMonitorSpy()
        let statusItemController = StatusItemControllerSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            statusItemController: statusItemController
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        #expect(statusItemController.warningMessages.last == "Speech Sync: Can't match the selected dictation microphone")

        hotkeyMonitor.emit(.released)
        hotkeyMonitor.emit(.pressed)

        #expect(speechMonitor.startCallCount == 2)
        #expect(statusItemController.warningMessages.count == 3)
        #expect(statusItemController.warningMessages[2] == nil)
    }

    @Test
    func pointerInteractionWhileFnHeldDoesNotRestartSpeechMonitoringWhenSignalContinues() async {
        let panelController = OverlayPanelControllerSpy()
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            panelController: panelController,
            hotkeyMonitor: hotkeyMonitor,
            interactionMonitor: interactionMonitor,
            interactionRecoveryDelayNanoseconds: 50_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 250_000_000
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.62)

        interactionMonitor.emit(.pointerDown)
        try? await Task.sleep(nanoseconds: 10_000_000)
        speechMonitor.emitLevel(0.41)
        try? await Task.sleep(nanoseconds: 70_000_000)

        #expect(speechMonitor.stopCallCount == 0)
        #expect(speechMonitor.startCallCount == 1)
        #expect(panelController.appliedStates.last == .speaking)
        #expect(panelController.appliedStates.last != .idle)
    }

    @Test
    func activeApplicationChangeWhileFnHeldRestartsSpeechMonitoringAfterSignalLoss() async {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionMonitor: interactionMonitor,
            interactionRecoveryDelayNanoseconds: 20_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 250_000_000
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.62)

        interactionMonitor.emit(.activeApplicationChanged)
        #expect(speechMonitor.stopCallCount == 0)
        try? await Task.sleep(nanoseconds: 250_000_000)

        #expect(speechMonitor.stopCallCount == 1)
        #expect(speechMonitor.startCallCount == 2)
    }

    @Test
    func pointerInteractionWhileFnHeldWithoutActiveSpeechDoesNotRestartSpeechMonitoring() async {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionMonitor: interactionMonitor,
            interactionRecoveryDelayNanoseconds: 20_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 250_000_000
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        interactionMonitor.emit(.pointerDown)
        try? await Task.sleep(nanoseconds: 120_000_000)

        #expect(speechMonitor.startCallCount == 1)
        #expect(speechMonitor.stopCallCount == 0)
    }

    @Test
    func interactionEventsWhileIdleOrDisabledDoNothing() {
        let speechMonitor = SpeechMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let statusItemController = StatusItemControllerSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            statusItemController: statusItemController,
            interactionMonitor: interactionMonitor
        )

        coordinator.start()
        interactionMonitor.emit(.pointerDown)
        interactionMonitor.emit(.activeApplicationChanged)

        #expect(speechMonitor.startCallCount == 0)
        #expect(speechMonitor.stopCallCount == 0)

        statusItemController.onToggleEnabled?(false)
        interactionMonitor.emit(.pointerDown)
        interactionMonitor.emit(.activeApplicationChanged)

        #expect(speechMonitor.startCallCount == 0)
        #expect(speechMonitor.stopCallCount == 1)
    }

    @Test
    func pointerInteractionRecordsRecentClickForTheHotkeyMonitor() {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionMonitor: interactionMonitor
        )

        coordinator.start()
        interactionMonitor.emit(.pointerDown)

        #expect(hotkeyMonitor.notePointerDownCallCount == 1)
    }

    @Test
    func releasingFnBeforeTheVerificationFinishesCancelsInteractionRecoveryRetries() async {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionMonitor: interactionMonitor,
            interactionRecoveryDelayNanoseconds: 20_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 300_000_000
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.62)

        interactionMonitor.emit(.pointerDown)
        try? await Task.sleep(nanoseconds: 120_000_000)
        hotkeyMonitor.emit(.released)
        try? await Task.sleep(nanoseconds: 500_000_000)

        #expect(speechMonitor.startCallCount == 2)
        #expect(speechMonitor.stopCallCount == 2)
    }

    @Test
    func repeatedInteractionEventsWhileFnHeldOnlyTriggerOneRestart() async {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionMonitor: interactionMonitor,
            interactionRecoveryDelayNanoseconds: 50_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 250_000_000
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.62)

        interactionMonitor.emit(.pointerDown)
        try? await Task.sleep(nanoseconds: 10_000_000)
        interactionMonitor.emit(.activeApplicationChanged)
        try? await Task.sleep(nanoseconds: 160_000_000)

        #expect(speechMonitor.startCallCount == 2)
        #expect(speechMonitor.stopCallCount == 1)
    }

    @Test
    func pointerInteractionRetriesUntilRecoveryAttemptsAreExhaustedWhenNoSignalReturns() async {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionMonitor: interactionMonitor,
            interactionRecoveryDelayNanoseconds: 20_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 20_000_000,
            maxSpeechRecoveryAttempts: 3
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.62)
        interactionMonitor.emit(.pointerDown)

        try? await Task.sleep(nanoseconds: 400_000_000)

        #expect(speechMonitor.startCallCount == 4)
        #expect(speechMonitor.stopCallCount == 3)
    }

    @Test
    func lowRecoveredSignalCancelsFurtherSpeechRecoveryRetries() async {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let interactionMonitor = InteractionMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionMonitor: interactionMonitor,
            interactionRecoveryDelayNanoseconds: 20_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 200_000_000,
            speechRecoverySignalThreshold: 0.005,
            maxSpeechRecoveryAttempts: 3
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitSpeechActivity(true)
        speechMonitor.emitLevel(0.62)
        interactionMonitor.emit(.pointerDown)
        try? await Task.sleep(nanoseconds: 120_000_000)
        speechMonitor.emitLevel(0.007)
        try? await Task.sleep(nanoseconds: 350_000_000)

        #expect(speechMonitor.startCallCount == 2)
        #expect(speechMonitor.stopCallCount == 1)
    }

    @Test
    func captureRuntimeIssueWhileFnHeldUsesTheSameSpeechRecoveryFlow() async {
        let speechMonitor = SpeechMonitorSpy()
        let hotkeyMonitor = HotkeyMonitorSpy()
        let coordinator = makeCoordinator(
            speechMonitor: speechMonitor,
            hotkeyMonitor: hotkeyMonitor,
            interactionRecoveryDelayNanoseconds: 20_000_000,
            speechRecoverySignalVerificationDelayNanoseconds: 250_000_000
        )

        coordinator.start()
        hotkeyMonitor.emit(.pressed)
        speechMonitor.emitCaptureRuntimeIssue()

        #expect(speechMonitor.stopCallCount == 1)
        try? await Task.sleep(nanoseconds: 120_000_000)
        #expect(speechMonitor.startCallCount == 2)
    }

    private func makeCoordinator(
        speechMonitor: SpeechMonitorSpy,
        panelController: OverlayPanelControllerSpy? = nil,
        hotkeyMonitor: HotkeyMonitorSpy? = nil,
        inputMonitoringAccess: InputMonitoringAccessSpy? = nil,
        statusItemController: StatusItemControllerSpy? = nil,
        interactionMonitor: InteractionMonitorSpy? = nil,
        interactionRecoveryDelayNanoseconds: UInt64 = 150_000_000,
        speechRecoverySignalVerificationDelayNanoseconds: UInt64 = 1_250_000_000,
        speechRecoverySignalThreshold: Float = 0.005,
        maxSpeechRecoveryAttempts: Int = 3
    ) -> AppCoordinator {
        AppCoordinator(
            permissionAccess: inputMonitoringAccess ?? InputMonitoringAccessSpy(),
            speechMonitor: speechMonitor,
            panelController: panelController ?? OverlayPanelControllerSpy(),
            statusItemController: statusItemController ?? StatusItemControllerSpy(),
            hotkeyMonitor: hotkeyMonitor ?? HotkeyMonitorSpy(),
            interactionMonitor: interactionMonitor ?? InteractionMonitorSpy(),
            interactionRecoveryDelayNanoseconds: interactionRecoveryDelayNanoseconds,
            speechRecoverySignalVerificationDelayNanoseconds: speechRecoverySignalVerificationDelayNanoseconds,
            speechRecoverySignalThreshold: speechRecoverySignalThreshold,
            maxSpeechRecoveryAttempts: maxSpeechRecoveryAttempts
        )
    }
}

@MainActor
private final class SpeechMonitorSpy: SpeechActivityMonitoring {
    var onSpeechActivityChanged: ((Bool) -> Void)?
    var onLevelChanged: ((Float) -> Void)?
    var onPermissionResolved: ((Bool) -> Void)?
    var onCaptureRuntimeIssue: (() -> Void)?

    private(set) var requestMicrophoneAccessCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var openSystemSettingsCallCount = 0

    private let requestMicrophoneAccessResult: Bool?
    private var startResults: [SpeechMonitoringStartResult]
    private var isSpeechActive = false

    init(
        requestMicrophoneAccessResult: Bool? = true,
        startResults: [SpeechMonitoringStartResult] = [.started]
    ) {
        self.requestMicrophoneAccessResult = requestMicrophoneAccessResult
        self.startResults = startResults
    }

    func requestMicrophoneAccessIfNeeded() -> Bool? {
        requestMicrophoneAccessCallCount += 1
        return requestMicrophoneAccessResult
    }

    func start() -> SpeechMonitoringStartResult {
        startCallCount += 1
        if startResults.isEmpty {
            return .started
        }

        return startResults.removeFirst()
    }

    func stop() {
        stopCallCount += 1
        if isSpeechActive {
            isSpeechActive = false
            onSpeechActivityChanged?(false)
        }
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }

    func emitPermissionResolved(_ granted: Bool) {
        onPermissionResolved?(granted)
    }

    func emitSpeechActivity(_ isSpeechActive: Bool) {
        self.isSpeechActive = isSpeechActive
        onSpeechActivityChanged?(isSpeechActive)
    }

    func emitLevel(_ normalizedLevel: Float) {
        onLevelChanged?(normalizedLevel)
    }

    func emitCaptureRuntimeIssue() {
        onCaptureRuntimeIssue?()
    }
}

@MainActor
private final class InteractionMonitorSpy: InteractionMonitoring {
    var onEvent: ((InteractionEvent) -> Void)?

    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func emit(_ event: InteractionEvent) {
        onEvent?(event)
    }
}

@MainActor
private final class OverlayPanelControllerSpy: OverlayPanelControlling {
    private(set) var showCallCount = 0
    private(set) var appliedStates = [CharacterState]()
    private(set) var speechLevels = [CGFloat]()
    private(set) var recenterCallCount = 0

    func show() {
        showCallCount += 1
    }

    func apply(state: CharacterState) {
        appliedStates.append(state)
    }

    func apply(speechLevel: CGFloat) {
        speechLevels.append(speechLevel)
    }

    func recenter() {
        recenterCallCount += 1
    }
}

@MainActor
private final class HotkeyMonitorSpy: HotkeyMonitoring {
    var onEvent: ((HotkeyEvent) -> Void)?
    var onObservation: ((HotkeyInputSource) -> Void)?
    var isRunning: Bool

    private(set) var notePointerDownCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private let startResult: Bool
    private let runningAfterStart: Bool

    init(startResult: Bool = true, isRunning: Bool = false, runningAfterStart: Bool = true) {
        self.startResult = startResult
        self.isRunning = isRunning
        self.runningAfterStart = runningAfterStart
    }

    func notePointerDown() {
        notePointerDownCallCount += 1
    }

    func start() -> Bool {
        startCallCount += 1
        isRunning = startResult && runningAfterStart
        return startResult
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
    }

    func emit(_ event: HotkeyEvent) {
        onEvent?(event)
    }

    func emitObservation(_ source: HotkeyInputSource) {
        onObservation?(source)
    }
}

private final class InputMonitoringAccessSpy: InputMonitoringAccessing {
    private(set) var ensureAccessArguments = [Bool]()
    private(set) var openSystemSettingsCallCount = 0
    private var results: [Bool]

    init(results: [Bool] = [true]) {
        self.results = results
    }

    func ensureAccess(requestIfNeeded: Bool) -> Bool {
        ensureAccessArguments.append(requestIfNeeded)
        if results.count > 1 {
            return results.removeFirst()
        }

        return results.first ?? true
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

@MainActor
private final class StatusItemControllerSpy: StatusItemControlling {
    var onToggleEnabled: ((Bool) -> Void)?
    var onRecenter: (() -> Void)?
    var onOpenInputMonitoring: (() -> Void)?
    var onQuit: (() -> Void)?

    private(set) var enabledValues = [Bool]()
    private(set) var warningMessages = [String?]()

    func updateEnabled(_ enabled: Bool) {
        enabledValues.append(enabled)
    }

    func updateSpeechSourceWarning(_ message: String?) {
        warningMessages.append(message)
    }
}
