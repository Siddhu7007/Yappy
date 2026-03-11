// Monitors microphone input and emits speech activity changes.
import AppKit
import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation

enum SpeechMonitoringStartResult: Equatable {
    case started
    case permissionPending
    case denied
    case unavailable
    case unresolvedSource(String)
}

protocol MicrophonePermissionControlling {
    func authorizationStatus() -> AVAuthorizationStatus
    func requestAccess(completion: @escaping (Bool) -> Void)
}

struct AVFoundationMicrophonePermissionController: MicrophonePermissionControlling {
    func authorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }
}

struct SpeechAudioInputFormat {
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
    let commonFormat: AVAudioCommonFormat
    let isInterleaved: Bool
    let audioFormat: AVAudioFormat?

    init(
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        commonFormat: AVAudioCommonFormat,
        isInterleaved: Bool,
        audioFormat: AVAudioFormat?
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.commonFormat = commonFormat
        self.isInterleaved = isInterleaved
        self.audioFormat = audioFormat
    }

    init(_ format: AVAudioFormat) {
        self.init(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            commonFormat: format.commonFormat,
            isInterleaved: format.isInterleaved,
            audioFormat: format
        )
    }

    init?(streamDescription: AudioStreamBasicDescription) {
        guard streamDescription.mFormatID == kAudioFormatLinearPCM else {
            return nil
        }

        let formatFlags = streamDescription.mFormatFlags
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0
        let isInterleaved = (formatFlags & kAudioFormatFlagIsNonInterleaved) == 0

        let commonFormat: AVAudioCommonFormat
        switch (isFloat, streamDescription.mBitsPerChannel) {
        case (true, 32):
            commonFormat = .pcmFormatFloat32
        case (true, 64):
            commonFormat = .pcmFormatFloat64
        case (false, 16):
            commonFormat = .pcmFormatInt16
        case (false, 32):
            commonFormat = .pcmFormatInt32
        default:
            return nil
        }

        self.init(
            sampleRate: streamDescription.mSampleRate,
            channelCount: streamDescription.mChannelsPerFrame,
            commonFormat: commonFormat,
            isInterleaved: isInterleaved,
            audioFormat: nil
        )
    }
}

struct SpeechAudioSample {
    let rms: Float
    let format: SpeechAudioInputFormat
    let frameLength: Int
}

protocol SpeechAudioCapturing: AnyObject {
    var onAudioSample: ((SpeechAudioSample) -> Void)? { get set }
    var onCaptureRuntimeIssue: (() -> Void)? { get set }

    func startCapturing(device: SpeechCaptureDeviceDescriptor) -> Bool
    func stopCapturing()
}

private final class AVCaptureSpeechAudioCaptureController: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, SpeechAudioCapturing {
    var onAudioSample: ((SpeechAudioSample) -> Void)?
    var onCaptureRuntimeIssue: (() -> Void)?

    private let notificationCenter: NotificationCenter
    private let sampleBufferQueue = DispatchQueue(label: "dev.local.Yappy.speechCapture.audio")
    private let stateQueue = DispatchQueue(label: "dev.local.Yappy.speechCapture.state")
    private var captureSession: AVCaptureSession?
    private var runtimeObservers = [NSObjectProtocol]()
    private var activeSessionToken: UUID?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func startCapturing(device: SpeechCaptureDeviceDescriptor) -> Bool {
        stopCapturing()

        let matchingDevices = discoverAudioInputDevices().filter { $0.uniqueID == device.uniqueID }

        guard matchingDevices.count == 1, let selectedDevice = matchingDevices.first else {
            return false
        }

        let session = AVCaptureSession()
        let sessionToken = UUID()
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)

        do {
            let input = try AVCaptureDeviceInput(device: selectedDevice)
            session.beginConfiguration()

            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                return false
            }

            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
        } catch {
            return false
        }

        updateActiveSessionToken(sessionToken)
        captureSession = session
        installRuntimeObservers(for: session, sessionToken: sessionToken)
        session.startRunning()

        guard session.isRunning else {
            stopCapturing()
            return false
        }

        return true
    }

    func stopCapturing() {
        clearActiveSessionToken()
        removeRuntimeObservers()

        guard let captureSession else {
            return
        }

        self.captureSession = nil
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard hasActiveCaptureSession,
              let sample = Self.makeSample(from: sampleBuffer)
        else {
            return
        }

        onAudioSample?(sample)
    }

    private func discoverAudioInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes(),
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private func supportedDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        if #available(macOS 14.0, *) {
            return [.microphone, .external]
        }

        return [.builtInMicrophone, .externalUnknown]
    }

    private func installRuntimeObservers(for session: AVCaptureSession, sessionToken: UUID) {
        runtimeObservers = [
            notificationCenter.addObserver(
                forName: NSNotification.Name.AVCaptureSessionRuntimeError,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.notifyCaptureRuntimeIssueIfCurrent(sessionToken: sessionToken)
            },
            notificationCenter.addObserver(
                forName: NSNotification.Name.AVCaptureSessionWasInterrupted,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.notifyCaptureRuntimeIssueIfCurrent(sessionToken: sessionToken)
            }
        ]
    }

    private func removeRuntimeObservers() {
        runtimeObservers.forEach(notificationCenter.removeObserver)
        runtimeObservers.removeAll(keepingCapacity: false)
    }

    private func notifyCaptureRuntimeIssueIfCurrent(sessionToken: UUID) {
        guard isCurrentSessionToken(sessionToken) else {
            return
        }

        onCaptureRuntimeIssue?()
    }

    private var hasActiveCaptureSession: Bool {
        stateQueue.sync { activeSessionToken != nil }
    }

    private func updateActiveSessionToken(_ token: UUID) {
        stateQueue.sync {
            activeSessionToken = token
        }
    }

    private func clearActiveSessionToken() {
        stateQueue.sync {
            activeSessionToken = nil
        }
    }

    private func isCurrentSessionToken(_ token: UUID) -> Bool {
        stateQueue.sync { activeSessionToken == token }
    }

    private static func makeSample(from sampleBuffer: CMSampleBuffer) -> SpeechAudioSample? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return nil
        }

        let streamDescription = streamDescriptionPointer.pointee
        guard let format = SpeechAudioInputFormat(streamDescription: streamDescription) else {
            return nil
        }

        let frameLength = Int(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameLength > 0 else {
            return SpeechAudioSample(rms: 0, format: format, frameLength: 0)
        }

        let bufferListSize = MemoryLayout<AudioBufferList>.size
            + (max(1, Int(format.channelCount)) - 1) * MemoryLayout<AudioBuffer>.size
        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { bufferListPointer.deallocate() }

        let audioBufferList = bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            return nil
        }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let rms = rms(from: buffers, format: format, frameLength: frameLength)
        return SpeechAudioSample(rms: rms, format: format, frameLength: frameLength)
    }

    private static func rms(
        from buffers: UnsafeMutableAudioBufferListPointer,
        format: SpeechAudioInputFormat,
        frameLength: Int
    ) -> Float {
        let channelCount = Int(format.channelCount)
        guard channelCount > 0, frameLength > 0 else {
            return 0
        }

        switch format.commonFormat {
        case .pcmFormatFloat32:
            if format.isInterleaved, let buffer = buffers.first, let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                return rms(frameCount: frameLength, channelCount: channelCount) { channelIndex, frameIndex in
                    data[(frameIndex * channelCount) + channelIndex]
                }
            }

            return rms(frameCount: frameLength, channelCount: channelCount) { channelIndex, frameIndex in
                guard channelIndex < buffers.count,
                      let data = buffers[channelIndex].mData?.assumingMemoryBound(to: Float.self)
                else {
                    return 0
                }

                return data[frameIndex]
            }
        case .pcmFormatFloat64:
            if format.isInterleaved, let buffer = buffers.first, let data = buffer.mData?.assumingMemoryBound(to: Double.self) {
                return rms(frameCount: frameLength, channelCount: channelCount) { channelIndex, frameIndex in
                    Float(data[(frameIndex * channelCount) + channelIndex])
                }
            }

            return rms(frameCount: frameLength, channelCount: channelCount) { channelIndex, frameIndex in
                guard channelIndex < buffers.count,
                      let data = buffers[channelIndex].mData?.assumingMemoryBound(to: Double.self)
                else {
                    return 0
                }

                return Float(data[frameIndex])
            }
        case .pcmFormatInt16:
            if format.isInterleaved, let buffer = buffers.first, let data = buffer.mData?.assumingMemoryBound(to: Int16.self) {
                return rms(frameCount: frameLength, channelCount: channelCount) { channelIndex, frameIndex in
                    Float(data[(frameIndex * channelCount) + channelIndex]) / Float(Int16.max)
                }
            }

            return rms(frameCount: frameLength, channelCount: channelCount) { channelIndex, frameIndex in
                guard channelIndex < buffers.count,
                      let data = buffers[channelIndex].mData?.assumingMemoryBound(to: Int16.self)
                else {
                    return 0
                }

                return Float(data[frameIndex]) / Float(Int16.max)
            }
        case .pcmFormatInt32:
            if format.isInterleaved, let buffer = buffers.first, let data = buffer.mData?.assumingMemoryBound(to: Int32.self) {
                return rms(frameCount: frameLength, channelCount: channelCount) { channelIndex, frameIndex in
                    Float(data[(frameIndex * channelCount) + channelIndex]) / Float(Int32.max)
                }
            }

            return rms(frameCount: frameLength, channelCount: channelCount) { channelIndex, frameIndex in
                guard channelIndex < buffers.count,
                      let data = buffers[channelIndex].mData?.assumingMemoryBound(to: Int32.self)
                else {
                    return 0
                }

                return Float(data[frameIndex]) / Float(Int32.max)
            }
        case .otherFormat:
            return 0
        @unknown default:
            return 0
        }
    }

    private static func rms(
        frameCount: Int,
        channelCount: Int,
        sampleAt: (_ channelIndex: Int, _ frameIndex: Int) -> Float
    ) -> Float {
        var sumSquares: Float = 0

        for channelIndex in 0 ..< channelCount {
            var channelSum: Float = 0
            for frameIndex in 0 ..< frameCount {
                let sample = sampleAt(channelIndex, frameIndex)
                channelSum += sample * sample
            }

            sumSquares += channelSum / Float(frameCount)
        }

        return sqrt(sumSquares / Float(channelCount))
    }
}

@MainActor
protocol SpeechActivityMonitoring: AnyObject {
    var onSpeechActivityChanged: ((Bool) -> Void)? { get set }
    var onLevelChanged: ((Float) -> Void)? { get set }
    var onPermissionResolved: ((Bool) -> Void)? { get set }
    var onCaptureRuntimeIssue: (() -> Void)? { get set }

    func requestMicrophoneAccessIfNeeded() -> Bool?
    func start() -> SpeechMonitoringStartResult
    func stop()
    func openSystemSettings()
}

enum SpeechMonitorDebugTrace {
    static func logInteractionRecoveryScheduled(trigger: InteractionEvent, delayMilliseconds: UInt64) {
        write("interaction recovery scheduled trigger=\(trigger.rawValue) delayMs=\(delayMilliseconds)")
    }

    static func logInteractionRecoveryCancelled(reason: String) {
        write("interaction recovery cancelled reason=\(reason)")
    }

    static func logInteractionRecoveryCompleted(trigger: InteractionEvent, restarted: Bool) {
        write("interaction recovery completed trigger=\(trigger.rawValue) restarted=\(restarted)")
    }

    private static func write(_ message: String) {
        #if DEBUG
        let line = "[SpeechMonitor] \(message)"
        print(line)
        DebugTrace.log(line)
        #endif
    }
}

@MainActor
final class SpeechActivityMonitor: SpeechActivityMonitoring {
    var onSpeechActivityChanged: ((Bool) -> Void)?
    var onLevelChanged: ((Float) -> Void)?
    var onPermissionResolved: ((Bool) -> Void)?
    var onCaptureRuntimeIssue: (() -> Void)?

    private let audioSourceResolver: SpeechAudioSourceResolving
    private let audioCapture: SpeechAudioCapturing
    private let permissionController: MicrophonePermissionControlling
    private var gate: SpeechLevelGate
    private var meter: SpeechLevelMeter
    private var isPermissionRequestInFlight = false
    private var isRunning = false
    private var hasLoggedFirstSample = false
    private var hasLoggedFirstNonZeroLevel = false

    convenience init(
        gate: SpeechLevelGate = SpeechLevelGate(),
        meter: SpeechLevelMeter = SpeechLevelMeter(),
        permissionController: MicrophonePermissionControlling = AVFoundationMicrophonePermissionController()
    ) {
        let providers: [DictationAudioSourceProviding] = [
            WisprFlowAudioSourceProvider(),
            WillowVoiceAudioSourceProvider()
        ]
        let activationTracker = WorkspaceDictationAppActivationTracker(
            supportedBundleIdentifiers: Set(providers.map(\.bundleIdentifier))
        )
        self.init(
            audioSourceResolver: DictationAudioSourceResolver(
                providerRegistry: DictationAudioSourceProviderRegistry(
                    providers: providers,
                    activationTracker: activationTracker
                )
            ),
            audioCapture: AVCaptureSpeechAudioCaptureController(),
            gate: gate,
            meter: meter,
            permissionController: permissionController
        )
    }

    init(
        audioSourceResolver: SpeechAudioSourceResolving,
        audioCapture: SpeechAudioCapturing,
        gate: SpeechLevelGate = SpeechLevelGate(),
        meter: SpeechLevelMeter = SpeechLevelMeter(),
        permissionController: MicrophonePermissionControlling = AVFoundationMicrophonePermissionController()
    ) {
        self.audioSourceResolver = audioSourceResolver
        self.audioCapture = audioCapture
        self.permissionController = permissionController
        self.gate = gate
        self.meter = meter

        audioCapture.onAudioSample = { [weak self] sample in
            Task { @MainActor [weak self] in
                self?.handle(sample: sample)
            }
        }

        audioCapture.onCaptureRuntimeIssue = { [weak self] in
            Self.writeDebugLog("capture runtime issue")
            Task { @MainActor [weak self] in
                self?.onCaptureRuntimeIssue?()
            }
        }
    }

    func requestMicrophoneAccessIfNeeded() -> Bool? {
        switch permissionController.authorizationStatus() {
        case .authorized:
            isPermissionRequestInFlight = false
            debugLog("microphone access already authorized")
            return true
        case .notDetermined:
            debugLog("microphone access not determined; requesting")
            requestPermissionIfNeeded()
            return nil
        default:
            isPermissionRequestInFlight = false
            debugLog("microphone access denied or restricted")
            return false
        }
    }

    func start() -> SpeechMonitoringStartResult {
        guard let hasPermission = requestMicrophoneAccessIfNeeded() else {
            return .permissionPending
        }

        guard hasPermission else {
            return .denied
        }

        guard !isRunning else {
            return .started
        }

        switch audioSourceResolver.resolveAudioSource() {
        case let .unresolved(message):
            resetLevelState()
            debugLog("speech source unresolved message=\(message)")
            return .unresolvedSource(message)
        case let .resolved(device):
            resetLevelState()
            debugLog("starting audio capture device=\(device.localizedName) id=\(device.uniqueID)")

            guard audioCapture.startCapturing(device: device) else {
                audioCapture.stopCapturing()
                isRunning = false
                debugLog("audio capture failed to start device=\(device.localizedName) id=\(device.uniqueID)")
                return .unavailable
            }

            isRunning = true
            debugLog("audio capture started device=\(device.localizedName) id=\(device.uniqueID)")
            return .started
        }
    }

    func stop() {
        if isRunning {
            audioCapture.stopCapturing()
            isRunning = false
        }

        resetLevelState()
        debugLog("stopped")
    }

    func openSystemSettings() {
        if let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"),
           NSWorkspace.shared.open(privacyURL) {
            return
        }

        let settingsURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.openApplication(at: settingsURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private func handle(sample: SpeechAudioSample) {
        if !hasLoggedFirstSample {
            hasLoggedFirstSample = true
            Self.writeDebugLog(
                "first capture sample frameLength=\(sample.frameLength) format=\(Self.describe(sample.format))"
            )
        }

        let normalizedLevel = meter.process(rms: sample.rms)
        onLevelChanged?(normalizedLevel)

        if normalizedLevel > 0, !hasLoggedFirstNonZeroLevel {
            hasLoggedFirstNonZeroLevel = true
            debugLog("first nonzero normalized level=\(normalizedLevel)")
        }

        if let isSpeechActive = gate.process(level: normalizedLevel) {
            onSpeechActivityChanged?(isSpeechActive)
        }
    }

    private func resetLevelState() {
        hasLoggedFirstSample = false
        hasLoggedFirstNonZeroLevel = false
        _ = meter.reset()
        onLevelChanged?(0)

        if gate.reset() {
            onSpeechActivityChanged?(false)
        }
    }

    private func requestPermissionIfNeeded() {
        guard !isPermissionRequestInFlight else {
            return
        }

        isPermissionRequestInFlight = true

        permissionController.requestAccess { [weak self] granted in
            guard let self else {
                return
            }

            Task { @MainActor [self] in
                self.isPermissionRequestInFlight = false
                self.debugLog("microphone request resolved granted=\(granted)")
                self.onPermissionResolved?(granted)
            }
        }
    }

    private func debugLog(_ message: String) {
        Self.writeDebugLog(message)
    }

    private nonisolated static func writeDebugLog(_ message: String) {
        #if DEBUG
        let line = "[SpeechMonitor] \(message)"
        print(line)
        DebugTrace.log(line)
        #endif
    }

    private static func describe(_ format: SpeechAudioInputFormat) -> String {
        let commonFormat: String
        switch format.commonFormat {
        case .pcmFormatFloat32:
            commonFormat = "float32"
        case .pcmFormatFloat64:
            commonFormat = "float64"
        case .pcmFormatInt16:
            commonFormat = "int16"
        case .pcmFormatInt32:
            commonFormat = "int32"
        case .otherFormat:
            commonFormat = "other"
        @unknown default:
            commonFormat = "unknown"
        }

        return "sampleRate=\(format.sampleRate) channels=\(format.channelCount) format=\(commonFormat) interleaved=\(format.isInterleaved)"
    }
}
