// Applies state-driven animation to the split-head layer rig.
import QuartzCore

@MainActor
final class CharacterAnimator {
    private let rig: SplitHeadCharacterRig
    private let motionProfile = SpeechMotionProfile()
    private var currentState: CharacterState = .idle
    private var currentSpeechLevel: CGFloat = 0

    init(rig: SplitHeadCharacterRig) {
        self.rig = rig
        apply(state: .idle)
    }

    func apply(state: CharacterState) {
        currentState = state
        clearAnimations()
        rig.applyBaseAppearance(for: state)

        switch state {
        case .idle:
            rig.setGlow(active: false, animated: true)
            rig.setUpperHeadOpen(false, animated: true)
        case .listening:
            rig.setGlow(active: true, animated: true)
            applySpeechLevel(currentSpeechLevel)
        case .speaking:
            rig.setGlow(active: true, animated: true)
            applySpeechLevel(currentSpeechLevel)
        case .disabled:
            rig.setGlow(active: false, animated: false)
            rig.setUpperHeadOpen(false, animated: false)
        case .error:
            rig.setGlow(active: false, error: true, animated: true)
            rig.setUpperHeadOpen(false, animated: true)
        }
    }

    func updateSpeechLevel(_ normalizedLevel: CGFloat) {
        currentSpeechLevel = max(0, min(1, normalizedLevel))

        switch currentState {
        case .listening, .speaking:
            applySpeechLevel(currentSpeechLevel)
        case .idle, .disabled, .error:
            return
        }
    }

    private func clearAnimations() {
        rig.upperHeadLayer.removeAllAnimations()
    }

    private func applySpeechLevel(_ normalizedLevel: CGFloat) {
        rig.setUpperHeadOffset(
            motionProfile.offset(for: normalizedLevel),
            animated: true,
            duration: SplitHeadCharacterRig.speechAnimationDuration
        )
    }
}
