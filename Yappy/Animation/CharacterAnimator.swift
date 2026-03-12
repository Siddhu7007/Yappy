// Applies state-driven animation to the split-head layer rig.
import QuartzCore

@MainActor
final class CharacterAnimator {
    enum SpeechPose: Equatable {
        case center
        case tiltLeft(tiltDegrees: CGFloat, horizontalOffset: CGFloat)
        case tiltRight(tiltDegrees: CGFloat, horizontalOffset: CGFloat)

        private static let sideOpenLiftScale: CGFloat = 0.28

        var tiltDegrees: CGFloat {
            switch self {
            case .center:
                0
            case let .tiltLeft(degrees, _):
                abs(degrees)
            case let .tiltRight(degrees, _):
                -abs(degrees)
            }
        }

        var horizontalOffset: CGFloat {
            switch self {
            case .center:
                0
            case let .tiltLeft(_, horizontalOffset):
                -abs(horizontalOffset)
            case let .tiltRight(_, horizontalOffset):
                abs(horizontalOffset)
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

        func offset(for speakingOffset: CGFloat, listeningOffset: CGFloat) -> CGFloat {
            switch self {
            case .center:
                return speakingOffset
            case .tiltLeft, .tiltRight:
                let extraOpen = max(0, speakingOffset - listeningOffset)
                return listeningOffset + (extraOpen * Self.sideOpenLiftScale)
            }
        }

        static func random() -> Self {
            switch Int.random(in: 0..<5) {
            case 0:
                .center
            case 1, 2:
                .tiltLeft(
                    tiltDegrees: CGFloat.random(in: 10...15),
                    horizontalOffset: CGFloat.random(in: 0.1...0.7)
                )
            default:
                .tiltRight(
                    tiltDegrees: CGFloat.random(in: 10...15),
                    horizontalOffset: CGFloat.random(in: 0.1...0.7)
                )
            }
        }
    }

    private static let speechPulseOpenThreshold: CGFloat = 0.16
    private static let speechPulseCloseThreshold: CGFloat = 0.07
    private static let speechPoseRefreshRiseThreshold: CGFloat = 0.11
    private static let speechPoseRefreshMinimumLevel: CGFloat = 0.21

    private let rig: SplitHeadCharacterRig
    private let speechPoseSampler: () -> SpeechPose
    private var currentState: CharacterState = .idle
    private var currentSpeechLevel: CGFloat = 0
    private var isSpeechPulseOpen = false
    private var currentSpeechPose: SpeechPose?
    private var lowestSpeechLevelSincePoseSelection: CGFloat = 1

    init(rig: SplitHeadCharacterRig, speechPoseSampler: @escaping () -> SpeechPose = SpeechPose.random) {
        self.rig = rig
        self.speechPoseSampler = speechPoseSampler
        apply(state: .idle)
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
            applySpeechLevel(currentSpeechLevel, animated: true)
        case .idle, .listening, .disabled, .error:
            return
        }
    }

    private func renderCurrentState(animated: Bool) {
        clearAnimations()
        rig.applyBaseAppearance(for: currentState)

        if currentState != .speaking {
            resetSpeechPulse()
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
            applySpeechLevel(currentSpeechLevel, animated: animated)
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

    private func resetSpeechPulse() {
        isSpeechPulseOpen = false
        currentSpeechPose = nil
        lowestSpeechLevelSincePoseSelection = 1
    }

    private func updateSpeechPose(for normalizedLevel: CGFloat) {
        if isSpeechPulseOpen {
            guard normalizedLevel > Self.speechPulseCloseThreshold else {
                resetSpeechPulse()
                return
            }

            lowestSpeechLevelSincePoseSelection = min(lowestSpeechLevelSincePoseSelection, normalizedLevel)

            guard normalizedLevel >= Self.speechPoseRefreshMinimumLevel else {
                return
            }

            guard normalizedLevel - lowestSpeechLevelSincePoseSelection >= Self.speechPoseRefreshRiseThreshold else {
                return
            }

            currentSpeechPose = speechPoseSampler()
            lowestSpeechLevelSincePoseSelection = normalizedLevel
            return
        }

        guard normalizedLevel >= Self.speechPulseOpenThreshold else {
            return
        }

        isSpeechPulseOpen = true
        currentSpeechPose = speechPoseSampler()
        lowestSpeechLevelSincePoseSelection = normalizedLevel
    }

    private func applySpeechLevel(_ normalizedLevel: CGFloat, animated: Bool) {
        updateSpeechPose(for: normalizedLevel)
        let speakingOffset = rig.speakingOffset(for: normalizedLevel)
        let speechPose = currentSpeechPose
        rig.setUpperHeadPose(
            offset: speechPose?.offset(
                for: speakingOffset,
                listeningOffset: SplitHeadCharacterRig.upperHeadListeningOffset
            ) ?? speakingOffset,
            tiltDegrees: speechPose?.tiltDegrees ?? 0,
            horizontalOffset: speechPose?.horizontalOffset ?? 0,
            hingeAlignment: speechPose?.hingeAlignment ?? .centered,
            animated: animated,
            duration: SplitHeadCharacterRig.speechAnimationDuration
        )
    }
}
