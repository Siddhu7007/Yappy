import AVFoundation
import Testing
@testable import Yappy

@MainActor
struct SpeechActivityMonitorTests {
    @Test
    func launchBootstrapReturnsTrueWhenMicrophoneIsAlreadyAuthorized() {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let monitor = SpeechActivityMonitor(permissionController: permissionController)

        #expect(monitor.requestMicrophoneAccessIfNeeded() == true)
        #expect(permissionController.requestAccessCallCount == 0)
    }

    @Test
    func launchBootstrapReturnsFalseWhenMicrophoneIsAlreadyDenied() {
        let permissionController = TestMicrophonePermissionController(status: .denied)
        let monitor = SpeechActivityMonitor(permissionController: permissionController)

        #expect(monitor.requestMicrophoneAccessIfNeeded() == false)
        #expect(permissionController.requestAccessCallCount == 0)
    }

    @Test
    func launchBootstrapRequestsPermissionWhenStatusIsUndetermined() async {
        let permissionController = TestMicrophonePermissionController(status: .notDetermined)
        let monitor = SpeechActivityMonitor(permissionController: permissionController)
        var resolvedValues = [Bool]()
        monitor.onPermissionResolved = { resolvedValues.append($0) }

        #expect(monitor.requestMicrophoneAccessIfNeeded() == nil)
        #expect(permissionController.requestAccessCallCount == 1)

        permissionController.resolvePendingRequest(granted: true)
        await Task.yield()
        #expect(resolvedValues == [true])
    }

    @Test
    func startReturnsUnavailableWhenInputNodeHasZeroChannelCount() {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let inputNode = TestSpeechAudioInputNode(
            liveFormat: SpeechAudioInputFormat(
                sampleRate: 44_100,
                channelCount: 0,
                commonFormat: .pcmFormatFloat32,
                isInterleaved: false,
                audioFormat: nil
            )
        )
        let engine = TestSpeechAudioEngine(inputNode: inputNode)
        let monitor = SpeechActivityMonitor(audioEngine: engine, permissionController: permissionController)

        #expect(monitor.start() == .unavailable)
        #expect(inputNode.installTapCallCount == 0)
        #expect(engine.startCallCount == 0)
    }

    @Test
    func startReturnsUnavailableWhenInputNodeHasZeroSampleRate() {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let inputNode = TestSpeechAudioInputNode(
            liveFormat: SpeechAudioInputFormat(
                sampleRate: 0,
                channelCount: 1,
                commonFormat: .pcmFormatFloat32,
                isInterleaved: false,
                audioFormat: nil
            )
        )
        let engine = TestSpeechAudioEngine(inputNode: inputNode)
        let monitor = SpeechActivityMonitor(audioEngine: engine, permissionController: permissionController)

        #expect(monitor.start() == .unavailable)
        #expect(inputNode.installTapCallCount == 0)
        #expect(engine.startCallCount == 0)
    }

    @Test
    func int16TapBufferProducesNonzeroLevelAndOpensSpeechGate() async throws {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let audioFormat = try #require(makeAudioFormat(commonFormat: .pcmFormatInt16))
        let inputNode = TestSpeechAudioInputNode(
            liveFormat: SpeechAudioInputFormat(audioFormat)
        )
        let engine = TestSpeechAudioEngine(inputNode: inputNode)
        let monitor = SpeechActivityMonitor(audioEngine: engine, permissionController: permissionController)
        var levels = [Float]()
        var activityChanges = [Bool]()
        monitor.onLevelChanged = { levels.append($0) }
        monitor.onSpeechActivityChanged = { activityChanges.append($0) }

        #expect(monitor.start() == .started)
        #expect(inputNode.lastInstalledFormat == audioFormat)

        let buffer = try #require(makeInt16Buffer(samples: [20_000, -20_000, 18_000, -18_000], format: audioFormat))
        inputNode.emit(buffer: buffer)
        await Task.yield()
        inputNode.emit(buffer: buffer)
        await Task.yield()

        #expect(levels.contains(where: { $0 > 0 }))
        #expect(activityChanges == [true])
    }

    @Test
    func stopRemovesTapResetsLevelAndClosesSpeechActivity() async throws {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let audioFormat = try #require(makeAudioFormat(commonFormat: .pcmFormatFloat32))
        let inputNode = TestSpeechAudioInputNode(
            liveFormat: SpeechAudioInputFormat(audioFormat)
        )
        let engine = TestSpeechAudioEngine(inputNode: inputNode)
        let monitor = SpeechActivityMonitor(audioEngine: engine, permissionController: permissionController)
        var levels = [Float]()
        var activityChanges = [Bool]()
        monitor.onLevelChanged = { levels.append($0) }
        monitor.onSpeechActivityChanged = { activityChanges.append($0) }

        #expect(monitor.start() == .started)

        let buffer = try #require(makeFloat32Buffer(samples: [0.7, -0.7, 0.6, -0.6], format: audioFormat))
        inputNode.emit(buffer: buffer)
        await Task.yield()
        inputNode.emit(buffer: buffer)
        await Task.yield()

        monitor.stop()

        #expect(inputNode.removeTapCallCount == 2)
        #expect(engine.stopCallCount == 1)
        #expect(engine.resetCallCount == 1)
        #expect(levels.last == 0)
        #expect(activityChanges.last == false)
    }

    @Test
    func engineConfigurationChangeForwardsTheCallback() async {
        let permissionController = TestMicrophonePermissionController(status: .authorized)
        let inputNode = TestSpeechAudioInputNode(
            liveFormat: SpeechAudioInputFormat(
                sampleRate: 44_100,
                channelCount: 1,
                commonFormat: .pcmFormatFloat32,
                isInterleaved: false,
                audioFormat: nil
            )
        )
        let engine = TestSpeechAudioEngine(inputNode: inputNode)
        let notificationCenter = NotificationCenter()
        let monitor = SpeechActivityMonitor(
            audioEngine: engine,
            permissionController: permissionController,
            notificationCenter: notificationCenter
        )
        var callbackCount = 0
        monitor.onEngineConfigurationChanged = { callbackCount += 1 }

        engine.emitConfigurationChange(notificationCenter: notificationCenter)
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

private final class TestSpeechAudioInputNode: SpeechAudioInputNodeControlling {
    var liveFormat: SpeechAudioInputFormat

    private(set) var installTapCallCount = 0
    private(set) var removeTapCallCount = 0
    private(set) var lastInstalledFormat: AVAudioFormat?
    private var tapBlock: AVAudioNodeTapBlock?

    init(liveFormat: SpeechAudioInputFormat) {
        self.liveFormat = liveFormat
    }

    func installTap(
        onBus _: AVAudioNodeBus,
        bufferSize _: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock
    ) {
        installTapCallCount += 1
        lastInstalledFormat = format
        tapBlock = block
    }

    func removeTap(onBus _: AVAudioNodeBus) {
        removeTapCallCount += 1
        tapBlock = nil
    }

    func emit(buffer: AVAudioPCMBuffer) {
        tapBlock?(buffer, AVAudioTime())
    }
}

private final class TestSpeechAudioEngine: SpeechAudioEngineControlling {
    let configurationChangeNotificationObject: AnyObject
    let inputNode: SpeechAudioInputNodeControlling

    private(set) var prepareCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var resetCallCount = 0
    var startError: (any Error)?

    init(inputNode: SpeechAudioInputNodeControlling) {
        self.configurationChangeNotificationObject = NSObject()
        self.inputNode = inputNode
    }

    func prepare() {
        prepareCallCount += 1
    }

    func start() throws {
        startCallCount += 1
        if let startError {
            throw startError
        }
    }

    func stop() {
        stopCallCount += 1
    }

    func reset() {
        resetCallCount += 1
    }

    func emitConfigurationChange(notificationCenter: NotificationCenter) {
        notificationCenter.post(
            name: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: configurationChangeNotificationObject
        )
    }
}

private func makeAudioFormat(
    commonFormat: AVAudioCommonFormat,
    sampleRate: Double = 44_100,
    channels: AVAudioChannelCount = 1,
    interleaved: Bool = false
) -> AVAudioFormat? {
    AVAudioFormat(
        commonFormat: commonFormat,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: interleaved
    )
}

private func makeFloat32Buffer(samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
    )
    buffer?.frameLength = AVAudioFrameCount(samples.count)

    guard let channelData = buffer?.floatChannelData else {
        return nil
    }

    for (index, sample) in samples.enumerated() {
        channelData[0][index] = sample
    }

    return buffer
}

private func makeInt16Buffer(samples: [Int16], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(samples.count)
    )
    buffer?.frameLength = AVAudioFrameCount(samples.count)

    guard let channelData = buffer?.int16ChannelData else {
        return nil
    }

    for (index, sample) in samples.enumerated() {
        channelData[0][index] = sample
    }

    return buffer
}
