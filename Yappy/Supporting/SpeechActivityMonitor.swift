// Monitors microphone input and emits speech activity changes.
import AppKit
import AVFoundation
import Foundation

enum SpeechMonitoringStartResult: Equatable {
    case started
    case permissionPending
    case denied
    case unavailable
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
}

protocol SpeechAudioInputNodeControlling: AnyObject {
    var liveFormat: SpeechAudioInputFormat { get }

    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock
    )
    func removeTap(onBus bus: AVAudioNodeBus)
}

protocol SpeechAudioEngineControlling: AnyObject {
    var configurationChangeNotificationObject: AnyObject { get }
    var inputNode: SpeechAudioInputNodeControlling { get }

    func prepare()
    func start() throws
    func stop()
    func reset()
}

private final class AVAudioInputNodeController: SpeechAudioInputNodeControlling {
    private let inputNode: AVAudioInputNode

    init(inputNode: AVAudioInputNode) {
        self.inputNode = inputNode
    }

    var liveFormat: SpeechAudioInputFormat {
        SpeechAudioInputFormat(inputNode.inputFormat(forBus: 0))
    }

    func installTap(
        onBus bus: AVAudioNodeBus,
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        block: @escaping AVAudioNodeTapBlock
    ) {
        inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format, block: block)
    }

    func removeTap(onBus bus: AVAudioNodeBus) {
        inputNode.removeTap(onBus: bus)
    }
}

private final class AVAudioEngineController: SpeechAudioEngineControlling {
    private let engine: AVAudioEngine
    let inputNode: SpeechAudioInputNodeControlling

    init(engine: AVAudioEngine) {
        self.engine = engine
        self.inputNode = AVAudioInputNodeController(inputNode: engine.inputNode)
    }

    var configurationChangeNotificationObject: AnyObject {
        engine
    }

    func prepare() {
        engine.prepare()
    }

    func start() throws {
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    func reset() {
        engine.reset()
    }
}

@MainActor
protocol SpeechActivityMonitoring: AnyObject {
    var onSpeechActivityChanged: ((Bool) -> Void)? { get set }
    var onLevelChanged: ((Float) -> Void)? { get set }
    var onPermissionResolved: ((Bool) -> Void)? { get set }
    var onEngineConfigurationChanged: (() -> Void)? { get set }

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
    var onEngineConfigurationChanged: (() -> Void)?

    private static let inputBus: AVAudioNodeBus = 0
    private static let tapBufferSize: AVAudioFrameCount = 1_024

    private let audioEngine: SpeechAudioEngineControlling
    private let permissionController: MicrophonePermissionControlling
    private let notificationCenter: NotificationCenter
    private var engineConfigurationObserver: NSObjectProtocol?
    private var gate: SpeechLevelGate
    private var meter: SpeechLevelMeter
    private var isPermissionRequestInFlight = false
    private var isRunning = false
    private var hasLoggedFirstNonZeroLevel = false

    convenience init(
        engine: AVAudioEngine = AVAudioEngine(),
        gate: SpeechLevelGate = SpeechLevelGate(),
        meter: SpeechLevelMeter = SpeechLevelMeter(),
        permissionController: MicrophonePermissionControlling = AVFoundationMicrophonePermissionController()
    ) {
        self.init(
            audioEngine: AVAudioEngineController(engine: engine),
            gate: gate,
            meter: meter,
            permissionController: permissionController
        )
    }

    init(
        audioEngine: SpeechAudioEngineControlling,
        gate: SpeechLevelGate = SpeechLevelGate(),
        meter: SpeechLevelMeter = SpeechLevelMeter(),
        permissionController: MicrophonePermissionControlling = AVFoundationMicrophonePermissionController(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.audioEngine = audioEngine
        self.permissionController = permissionController
        self.notificationCenter = notificationCenter
        self.gate = gate
        self.meter = meter
        engineConfigurationObserver = notificationCenter.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: audioEngine.configurationChangeNotificationObject,
            queue: nil
        ) { [weak self] _ in
            Self.writeDebugLog("audio engine configuration changed")
            Task { @MainActor [weak self] in
                self?.onEngineConfigurationChanged?()
            }
        }
    }

    deinit {
        if let engineConfigurationObserver {
            notificationCenter.removeObserver(engineConfigurationObserver)
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

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.liveFormat
        guard inputFormat.channelCount > 0 else {
            debugLog("microphone input unavailable: zero-channel hardware format")
            return .unavailable
        }

        guard inputFormat.sampleRate > 0 else {
            debugLog("microphone input unavailable: zero-sample-rate hardware format")
            return .unavailable
        }

        guard let tapFormat = inputFormat.audioFormat else {
            debugLog("microphone input unavailable: missing live input format")
            return .unavailable
        }

        _ = gate.reset()
        _ = meter.reset()
        hasLoggedFirstNonZeroLevel = false
        onLevelChanged?(0)
        inputNode.removeTap(onBus: Self.inputBus)

        var hasLoggedFirstTapCallback = false
        inputNode.installTap(onBus: Self.inputBus, bufferSize: Self.tapBufferSize, format: tapFormat) { [weak self] buffer, _ in
            guard let self else {
                return
            }

            if !hasLoggedFirstTapCallback {
                hasLoggedFirstTapCallback = true
                Self.writeDebugLog(
                    "first tap callback frameLength=\(buffer.frameLength) format=\(Self.describe(SpeechAudioInputFormat(buffer.format)))"
                )
            }

            let rms = Self.rms(from: buffer)
            Task { @MainActor in
                self.handle(rms: rms)
            }
        }

        debugLog("starting audio engine format=\(Self.describe(inputFormat)) bufferSize=\(Self.tapBufferSize)")
        audioEngine.prepare()

        do {
            try audioEngine.start()
            isRunning = true
            debugLog("audio engine started format=\(Self.describe(inputFormat)) bufferSize=\(Self.tapBufferSize)")
            return .started
        } catch {
            inputNode.removeTap(onBus: Self.inputBus)
            audioEngine.stop()
            audioEngine.reset()
            isRunning = false
            debugLog(
                "audio engine failed to start format=\(Self.describe(inputFormat)) error=\(error.localizedDescription)"
            )
            return .unavailable
        }
    }

    func stop() {
        let inputNode = audioEngine.inputNode
        if isRunning {
            inputNode.removeTap(onBus: Self.inputBus)
            audioEngine.stop()
            audioEngine.reset()
            isRunning = false
        }

        hasLoggedFirstNonZeroLevel = false
        _ = meter.reset()
        onLevelChanged?(0)

        if gate.reset() {
            onSpeechActivityChanged?(false)
        }

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

    private func handle(rms: Float) {
        let normalizedLevel = meter.process(rms: rms)
        onLevelChanged?(normalizedLevel)

        if normalizedLevel > 0, !hasLoggedFirstNonZeroLevel {
            hasLoggedFirstNonZeroLevel = true
            debugLog("first nonzero normalized level=\(normalizedLevel)")
        }

        if let isSpeechActive = gate.process(level: normalizedLevel) {
            onSpeechActivityChanged?(isSpeechActive)
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

    private static func rms(from buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return 0
        }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channels = buffer.floatChannelData else {
                return 0
            }
            let stride = Int(buffer.stride)
            if buffer.format.isInterleaved {
                let interleavedSamples = channels[0]
                return rms(
                    frameCount: frameCount,
                    channelCount: channelCount
                ) { channelIndex, frameIndex in
                    interleavedSamples[(frameIndex * stride) + channelIndex]
                }
            }
            return rms(
                frameCount: frameCount,
                channelCount: channelCount
            ) { channelIndex, frameIndex in
                channels[channelIndex][frameIndex * stride]
            }
        case .pcmFormatInt16:
            guard let channels = buffer.int16ChannelData else {
                return 0
            }
            let stride = Int(buffer.stride)
            if buffer.format.isInterleaved {
                let interleavedSamples = channels[0]
                return rms(
                    frameCount: frameCount,
                    channelCount: channelCount
                ) { channelIndex, frameIndex in
                    Float(interleavedSamples[(frameIndex * stride) + channelIndex]) / Float(Int16.max)
                }
            }
            return rms(
                frameCount: frameCount,
                channelCount: channelCount
            ) { channelIndex, frameIndex in
                Float(channels[channelIndex][frameIndex * stride]) / Float(Int16.max)
            }
        case .pcmFormatInt32:
            guard let channels = buffer.int32ChannelData else {
                return 0
            }
            let stride = Int(buffer.stride)
            if buffer.format.isInterleaved {
                let interleavedSamples = channels[0]
                return rms(
                    frameCount: frameCount,
                    channelCount: channelCount
                ) { channelIndex, frameIndex in
                    Float(interleavedSamples[(frameIndex * stride) + channelIndex]) / Float(Int32.max)
                }
            }
            return rms(
                frameCount: frameCount,
                channelCount: channelCount
            ) { channelIndex, frameIndex in
                Float(channels[channelIndex][frameIndex * stride]) / Float(Int32.max)
            }
        default:
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
