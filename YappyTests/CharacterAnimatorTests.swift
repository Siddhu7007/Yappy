import CoreGraphics
import Testing
@testable import Yappy

@MainActor
struct CharacterAnimatorTests {
    @Test
    func listeningStateUsesAFixedSlightlyOpenPose() {
        let (rig, animator) = makeAnimator()

        animator.apply(state: .listening)

        #expect(rig.upperHeadLayer.position.y == rig.upperHeadListeningPositionY)
    }

    @Test
    func speechLevelsDoNotMoveTheMouthWhileListening() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .listening)
        let listeningPositionY = rig.upperHeadLayer.position.y

        animator.updateSpeechLevel(0.85)

        #expect(rig.upperHeadLayer.position.y == listeningPositionY)
    }

    @Test
    func speechLevelsMoveTheMouthWhileSpeaking() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .speaking)

        animator.updateSpeechLevel(0.85)

        #expect(rig.upperHeadLayer.position.y > rig.upperHeadListeningPositionY)
    }

    @Test
    func returningToListeningRestoresTheFixedListeningOffset() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .speaking)
        animator.updateSpeechLevel(0.92)

        animator.apply(state: .listening)

        #expect(rig.upperHeadLayer.position.y == rig.upperHeadListeningPositionY)
    }

    private func makeAnimator() -> (SplitHeadCharacterRig, CharacterAnimator) {
        let rig = SplitHeadCharacterRig()
        rig.layout(in: CGRect(origin: .zero, size: SplitHeadCharacterRig.canvasSize))
        let animator = CharacterAnimator(rig: rig)
        return (rig, animator)
    }
}
