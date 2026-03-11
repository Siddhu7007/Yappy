import AVFoundation
import Testing
@testable import Yappy

@MainActor
struct SpeechActivityMonitorTests {
    @Test
    func launchBootstrapReturnsTrueWhenMicrophoneIsAlreadyAuthorized() {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let monitor = SpeechActivityMonitor(
            audioSourceResolver: TestSpeechAudioSourceResolver(),
            audioCapture: TestSpeechAudioCaptureController(),
            permissionController: permissionController
        )

        #expect(monitor.requestMicrophoneAccessIfNeeded() == true)
        #expect(permissionController.requestAccessCallCount == 0)
    }

    @Test
    func launchBootstrapReturnsFalseWhenMicrophoneIsAlreadyDenied() {
        let permissionController = TestMicrophonePermissionController(status: .denied)
        let monitor = SpeechActivityMonitor(
            audioSourceResolver: TestSpeechAudioSourceResolver(),
            audioCapture: TestSpeechAudioCaptureController(),
            permissionController: permissionController
        )

        #expect(monitor.requestMicrophoneAccessIfNeeded() == false)
        #expect(permissionController.requestAccessCallCount == 0)
    }

    @Test
    func launchBootstrapRequestsPermissionWhenStatusIsUndetermined() async {
        let permissionController = TestMicrophonePermissionController(status: .notDetermined)
        let monitor = SpeechActivityMonitor(
            audioSourceResolver: TestSpeechAudioSourceResolver(),
            audioCapture: TestSpeechAudioCaptureController(),
            permissionController: permissionController
        )
        var resolvedValues = [Bool]()
        monitor.onPermissionResolved = { resolvedValues.append($0) }

        #expect(monitor.requestMicrophoneAccessIfNeeded() == nil)
        #expect(permissionController.requestAccessCallCount == 1)

        permissionController.resolvePendingRequest(granted: true)
        await Task.yield()
        #expect(resolvedValues == [true])
    }

    @Test
    func startReturnsUnresolvedSourceWhenWisprSourceCannotBeResolved() {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let resolver = TestSpeechAudioSourceResolver(result: .unresolved(message: "Speech Sync: Can't match the selected dictation microphone"))
        let capture = TestSpeechAudioCaptureController()
        let monitor = SpeechActivityMonitor(
            audioSourceResolver: resolver,
            audioCapture: capture,
            permissionController: permissionController
        )

        #expect(monitor.start() == .unresolvedSource("Speech Sync: Can't match the selected dictation microphone"))
        #expect(capture.startCapturingCallCount == 0)
    }

    @Test
    func startReturnsUnavailableWhenCaptureCannotStart() {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let capture = TestSpeechAudioCaptureController(startResult: false)
        let monitor = SpeechActivityMonitor(
            audioSourceResolver: TestSpeechAudioSourceResolver(result: .resolved(device: makeCaptureDevice())),
            audioCapture: capture,
            permissionController: permissionController
        )

        #expect(monitor.start() == .unavailable)
        #expect(capture.startCapturingCallCount == 1)
        #expect(capture.lastStartedDevice == makeCaptureDevice())
    }

    @Test
    func captureSamplesProduceNonzeroLevelAndOpenSpeechGate() async {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let capture = TestSpeechAudioCaptureController()
        let monitor = SpeechActivityMonitor(
            audioSourceResolver: TestSpeechAudioSourceResolver(result: .resolved(device: makeCaptureDevice())),
            audioCapture: capture,
            permissionController: permissionController
        )
        var levels = [Float]()
        var activityChanges = [Bool]()
        monitor.onLevelChanged = { levels.append($0) }
        monitor.onSpeechActivityChanged = { activityChanges.append($0) }

        #expect(monitor.start() == .started)

        let sample = SpeechAudioSample(
            rms: 0.62,
            format: makeAudioFormat(),
            frameLength: 1_024
        )
        capture.emit(sample: sample)
        await Task.yield()
        capture.emit(sample: sample)
        await Task.yield()

        #expect(levels.contains(where: { $0 > 0 }))
        #expect(activityChanges == [true])
    }

    @Test
    func stopStopsCaptureResetsLevelAndClosesSpeechActivity() async {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let capture = TestSpeechAudioCaptureController()
        let monitor = SpeechActivityMonitor(
            audioSourceResolver: TestSpeechAudioSourceResolver(result: .resolved(device: makeCaptureDevice())),
            audioCapture: capture,
            permissionController: permissionController
        )
        var levels = [Float]()
        var activityChanges = [Bool]()
        monitor.onLevelChanged = { levels.append($0) }
        monitor.onSpeechActivityChanged = { activityChanges.append($0) }

        #expect(monitor.start() == .started)
        capture.emit(sample: SpeechAudioSample(rms: 0.7, format: makeAudioFormat(), frameLength: 1_024))
        await Task.yield()
        capture.emit(sample: SpeechAudioSample(rms: 0.7, format: makeAudioFormat(), frameLength: 1_024))
        await Task.yield()

        monitor.stop()

        #expect(capture.stopCapturingCallCount == 1)
        #expect(levels.last == 0)
        #expect(activityChanges.last == false)
    }

    @Test
    func captureRuntimeIssueForwardsTheCallback() async {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let capture = TestSpeechAudioCaptureController()
        let monitor = SpeechActivityMonitor(
            audioSourceResolver: TestSpeechAudioSourceResolver(result: .resolved(device: makeCaptureDevice())),
            audioCapture: capture,
            permissionController: permissionController
        )
        var callbackCount = 0
        monitor.onCaptureRuntimeIssue = { callbackCount += 1 }

        capture.emitRuntimeIssue()
        await Task.yield()

        #expect(callbackCount == 1)
    }
}

private final class TestMicrophonePermissionController: MicrophonePermissionControlling {
    var status: AVAuthorizationStatus
    private(set) var requestAccessCallCount = 0
    private var completion: ((Bool) -> Void)?

    init(status: AVAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() -> AVAuthorizationStatus {
        status
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        requestAccessCallCount += 1
        self.completion = completion
    }

    func resolvePendingRequest(granted: Bool) {
        status = granted ? .authorized : .denied
        completion?(granted)
        completion = nil
    }
}

private struct TestSpeechAudioSourceResolver: SpeechAudioSourceResolving {
    let result: SpeechAudioSourceResolution

    init(result: SpeechAudioSourceResolution = .resolved(device: makeCaptureDevice())) {
        self.result = result
    }

    func resolveAudioSource() -> SpeechAudioSourceResolution {
        result
    }
}

private final class TestSpeechAudioCaptureController: SpeechAudioCapturing {
    var onAudioSample: ((SpeechAudioSample) -> Void)?
    var onCaptureRuntimeIssue: (() -> Void)?

    private(set) var startCapturingCallCount = 0
    private(set) var stopCapturingCallCount = 0
    private(set) var lastStartedDevice: SpeechCaptureDeviceDescriptor?

    private let startResult: Bool

    init(startResult: Bool = true) {
        self.startResult = startResult
    }

    func startCapturing(device: SpeechCaptureDeviceDescriptor) -> Bool {
        startCapturingCallCount += 1
        lastStartedDevice = device
        return startResult
    }

    func stopCapturing() {
        stopCapturingCallCount += 1
    }

    func emit(sample: SpeechAudioSample) {
        onAudioSample?(sample)
    }

    func emitRuntimeIssue() {
        onCaptureRuntimeIssue?()
    }
}

private func makeAudioFormat() -> SpeechAudioInputFormat {
    SpeechAudioInputFormat(
        sampleRate: 44_100,
        channelCount: 1,
        commonFormat: .pcmFormatFloat32,
        isInterleaved: false,
        audioFormat: nil
    )
}

private func makeCaptureDevice() -> SpeechCaptureDeviceDescriptor {
    SpeechCaptureDeviceDescriptor(
        localizedName: "MacBook Air Microphone",
        uniqueID: "BuiltInMicrophoneDevice"
    )
}
