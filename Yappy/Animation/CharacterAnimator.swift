// Applies state-driven animation to the split-head layer rig.
import Foundation
import QuartzCore

@MainActor
final class CharacterAnimator {
    enum SpeechPose: Equatable {
        case center
        case tiltLeft
        case tiltRight

        var tiltDegrees: CGFloat {
            switch self {
            case .center:
                0
            case .tiltLeft:
                SplitHeadCharacterRig.speakingCadenceTiltDegrees
            case .tiltRight:
                -SplitHeadCharacterRig.speakingCadenceTiltDegrees
            }
        }

        var horizontalOffset: CGFloat {
            switch self {
            case .center:
                0
            case .tiltLeft:
                -SplitHeadCharacterRig.speakingCadenceHorizontalOffset
            case .tiltRight:
                SplitHeadCharacterRig.speakingCadenceHorizontalOffset
            }
        }

        var hingeAlignment: SplitHeadCharacterRig.UpperHeadHingeAlignment {
            switch self {
            case .center:
                .centered
            case .tiltLeft:
                .left
            case .tiltRight:
                .right
            }
        }

        var offset: CGFloat {
            switch self {
            case .center:
                SplitHeadCharacterRig.speakingCadenceCenterOffset
            case .tiltLeft, .tiltRight:
                SplitHeadCharacterRig.speakingCadenceSideOffset
            }
        }
    }

    private static let speechCadenceOpenThreshold: CGFloat = 0.16
    private static let speechCadenceCloseThreshold: CGFloat = 0.07
    private static let speechBeatSequence: [SpeechPose] = [.center, .tiltLeft, .center, .tiltRight]
    private static let idleBlinkIntervalRange: ClosedRange<TimeInterval> = 4.8...8.4
    private static let listeningBlinkIntervalRange: ClosedRange<TimeInterval> = 5.4...9.2

    private let rig: SplitHeadCharacterRig
    private let automaticallyAdvanceSpeechCadence: Bool
    private var currentState: CharacterState = .idle
    private var currentSpeechLevel: CGFloat = 0
    private var isSpeechCadenceActive = false
    private var currentSpeechBeatIndex = 0
    private var speechCadenceTimer: Timer?
    private var blinkTimer: Timer?

    init(rig: SplitHeadCharacterRig, automaticallyAdvanceSpeechCadence: Bool = true) {
        self.rig = rig
        self.automaticallyAdvanceSpeechCadence = automaticallyAdvanceSpeechCadence
        apply(state: .idle)
    }

    deinit {
        speechCadenceTimer?.invalidate()
        blinkTimer?.invalidate()
    }

    func apply(state: CharacterState) {
        currentState = state
        renderCurrentState(animated: true)
    }

    func syncLayout() {
        renderCurrentState(animated: false)
    }

    func updateSpeechLevel(_ normalizedLevel: CGFloat) {
        currentSpeechLevel = max(0, min(1, normalizedLevel))

        switch currentState {
        case .speaking:
            updateSpeechCadence(animated: true, refreshCurrentPose: false)
        case .idle, .listening, .disabled, .error:
            return
        }
    }

    func advanceSpeechBeat() {
        guard currentState == .speaking, isSpeechCadenceActive else {
            return
        }

        currentSpeechBeatIndex = (currentSpeechBeatIndex + 1) % Self.speechBeatSequence.count
        applyCurrentSpeechBeat(animated: true)
    }

    private func renderCurrentState(animated: Bool) {
        clearAnimations()
        rig.applyBaseAppearance(for: currentState)
        updateBlinkScheduling()

        if currentState != .speaking {
            stopSpeechCadence(resetBeatIndex: true)
        }

        switch currentState {
        case .idle:
            rig.setGlow(active: false, animated: animated)
            rig.setUpperHeadOpen(false, animated: animated)
        case .listening:
            rig.setGlow(active: true, animated: animated)
            rig.setUpperHeadListening(true, animated: animated)
        case .speaking:
            rig.setGlow(active: true, animated: animated)
            updateSpeechCadence(animated: animated, refreshCurrentPose: true)
        case .disabled:
            rig.setGlow(active: false, animated: false)
            rig.setUpperHeadOpen(false, animated: false)
        case .error:
            rig.setGlow(active: false, error: true, animated: animated)
            rig.setUpperHeadOpen(false, animated: animated)
        }
    }

    private func clearAnimations() {
        rig.upperHeadLayer.removeAllAnimations()
    }

    private func startSpeechCadence(animated: Bool) {
        isSpeechCadenceActive = true
        currentSpeechBeatIndex = 0
        applyCurrentSpeechBeat(animated: animated)
        scheduleSpeechCadenceTimerIfNeeded()
    }

    private func stopSpeechCadence(resetBeatIndex: Bool) {
        speechCadenceTimer?.invalidate()
        speechCadenceTimer = nil
        isSpeechCadenceActive = false
        if resetBeatIndex {
            currentSpeechBeatIndex = 0
        }
    }

    private func updateSpeechCadence(animated: Bool, refreshCurrentPose: Bool) {
        if isSpeechCadenceActive {
            guard currentSpeechLevel > Self.speechCadenceCloseThreshold else {
                stopSpeechCadence(resetBeatIndex: true)
                rig.setUpperHeadListening(true, animated: animated)
                return
            }

            if refreshCurrentPose {
                applyCurrentSpeechBeat(animated: animated)
            }

            scheduleSpeechCadenceTimerIfNeeded()
            return
        }

        guard currentSpeechLevel >= Self.speechCadenceOpenThreshold else {
            rig.setUpperHeadListening(true, animated: animated)
            return
        }

        startSpeechCadence(animated: animated)
    }

    private func applyCurrentSpeechBeat(animated: Bool) {
        let speechPose = Self.speechBeatSequence[currentSpeechBeatIndex]
        rig.setUpperHeadPose(
            offset: speechPose.offset,
            tiltDegrees: speechPose.tiltDegrees,
            horizontalOffset: speechPose.horizontalOffset,
            hingeAlignment: speechPose.hingeAlignment,
            animated: animated,
            duration: SplitHeadCharacterRig.speechAnimationDuration
        )
    }

    private func scheduleSpeechCadenceTimerIfNeeded() {
        guard automaticallyAdvanceSpeechCadence, speechCadenceTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: SplitHeadCharacterRig.speakingCadenceBeatDuration,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.advanceSpeechBeat()
            }
        }
        speechCadenceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateBlinkScheduling() {
        guard let intervalRange = blinkIntervalRange(for: currentState) else {
            blinkTimer?.invalidate()
            blinkTimer = nil
            return
        }

        guard blinkTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: TimeInterval.random(in: intervalRange),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.blinkTimer = nil
                guard self.blinkIntervalRange(for: self.currentState) != nil else {
                    return
                }

                self.rig.blink()
                self.updateBlinkScheduling()
            }
        }
        blinkTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func blinkIntervalRange(for state: CharacterState) -> ClosedRange<TimeInterval>? {
        switch state {
        case .idle:
            Self.idleBlinkIntervalRange
        case .listening:
            Self.listeningBlinkIntervalRange
        case .speaking, .disabled, .error:
            nil
        }
    }
}
