import CoreGraphics
import Testing
@testable import Yappy

@MainActor
struct CharacterAnimatorTests {
    private let tolerance: CGFloat = 0.0001

    @Test
    func listeningStateUsesAFixedSlightlyOpenPose() {
        let (rig, animator) = makeAnimator()

        animator.apply(state: .listening)

        #expect(SplitHeadCharacterRig.upperHeadListeningOffset == 5)
        #expect(rig.upperHeadLayer.position.y == rig.upperHeadListeningPositionY)
        #expect(abs(rig.upperHeadTiltDegrees) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .centered)
    }

    @Test
    func speechLevelsDoNotMoveTheMouthWhileListening() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .listening)
        let listeningPositionY = rig.upperHeadLayer.position.y

        animator.updateSpeechLevel(0.85)

        #expect(rig.upperHeadLayer.position.y == listeningPositionY)
        #expect(abs(rig.upperHeadTiltDegrees) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .centered)
    }

    @Test
    func speakingPulseKeepsTheSameTiltUntilTheHeadCloses() {
        let (rig, animator) = makeAnimator(
            speechPoses: [
                .tiltLeft(tiltDegrees: 9, horizontalOffset: 3),
                .tiltRight(tiltDegrees: 11, horizontalOffset: 4)
            ]
        )
        animator.apply(state: .speaking)

        animator.updateSpeechLevel(0.85)
        let firstTilt = rig.upperHeadTiltDegrees
        let firstHorizontalOffset = rig.upperHeadHorizontalOffset
        let fullSpeakingOffset = rig.speakingOffset(for: 0.85)
        let leftClosedPositionY = closedPositionY(
            in: rig.upperHeadLayer.bounds,
            anchorPoint: SplitHeadCharacterRig.upperHeadLeftHingeAnchorPoint
        )

        animator.updateSpeechLevel(0.32)

        #expect(rig.upperHeadLayer.position.y > rig.upperHeadListeningPositionY)
        #expect(firstTilt > 0)
        #expect(firstHorizontalOffset < 0)
        #expect(rig.upperHeadHingeAlignment == .left)
        #expect(abs(rig.upperHeadLayer.anchorPoint.x - SplitHeadCharacterRig.upperHeadLeftHingeAnchorPoint.x) < tolerance)
        #expect(rig.upperHeadLayer.position.y < leftClosedPositionY + fullSpeakingOffset)
        #expect(abs(rig.upperHeadTiltDegrees - firstTilt) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset - firstHorizontalOffset) < tolerance)
    }

    @Test
    func closingAndReopeningSamplesANewTiltPose() {
        let (rig, animator) = makeAnimator(
            speechPoses: [
                .tiltLeft(tiltDegrees: 9, horizontalOffset: 3),
                .tiltRight(tiltDegrees: 11, horizontalOffset: 4)
            ]
        )
        animator.apply(state: .speaking)

        animator.updateSpeechLevel(0.9)
        let firstTilt = rig.upperHeadTiltDegrees

        animator.updateSpeechLevel(0.01)

        #expect(firstTilt > 0)
        #expect(abs(rig.upperHeadTiltDegrees) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .centered)

        animator.updateSpeechLevel(0.92)

        #expect(rig.upperHeadTiltDegrees < 0)
        #expect(abs(rig.upperHeadTiltDegrees + 11) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset - 4) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .right)
        #expect(abs(rig.upperHeadLayer.anchorPoint.x - SplitHeadCharacterRig.upperHeadRightHingeAnchorPoint.x) < tolerance)
    }

    @Test
    func sustainedSpeechCanRepickPoseOnANewRiseWithoutFullyClosing() {
        let (rig, animator) = makeAnimator(
            speechPoses: [
                .tiltLeft(tiltDegrees: 9, horizontalOffset: 3),
                .tiltRight(tiltDegrees: 10, horizontalOffset: 4)
            ]
        )
        animator.apply(state: .speaking)

        animator.updateSpeechLevel(0.88)
        let initialTilt = rig.upperHeadTiltDegrees

        animator.updateSpeechLevel(0.23)
        animator.updateSpeechLevel(0.38)

        #expect(initialTilt > 0)
        #expect(rig.upperHeadTiltDegrees < 0)
        #expect(abs(rig.upperHeadTiltDegrees + 10) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset - 4) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .right)
    }

    @Test
    func sideHingedSpeechKeepsTheSeamSideCloserToClosedThanACenteredOpen() {
        let (rig, animator) = makeAnimator(speechPoses: [.tiltRight(tiltDegrees: 12, horizontalOffset: 2)])
        animator.apply(state: .speaking)

        animator.updateSpeechLevel(0.9)

        let rightClosedPositionY = closedPositionY(
            in: rig.upperHeadLayer.bounds,
            anchorPoint: SplitHeadCharacterRig.upperHeadRightHingeAnchorPoint
        )
        let fullSpeakingOffset = rig.speakingOffset(for: 0.9)

        #expect(rig.upperHeadHingeAlignment == .right)
        #expect(rig.upperHeadLayer.position.y > rightClosedPositionY + SplitHeadCharacterRig.upperHeadListeningOffset)
        #expect(rig.upperHeadLayer.position.y < rightClosedPositionY + fullSpeakingOffset)
    }

    @Test
    func returningToListeningRestoresTheFixedListeningOffset() {
        let (rig, animator) = makeAnimator(speechPoses: [.tiltLeft(tiltDegrees: 10, horizontalOffset: 4)])
        animator.apply(state: .speaking)
        animator.updateSpeechLevel(0.92)

        animator.apply(state: .listening)

        #expect(rig.upperHeadLayer.position.y == rig.upperHeadListeningPositionY)
        #expect(abs(rig.upperHeadTiltDegrees) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .centered)
    }

    @Test
    func activeCoverUsesARootLayerScaleTransform() {
        let rig = SplitHeadCharacterRig()
        rig.layout(in: CGRect(origin: .zero, size: SplitHeadCharacterRig.canvasSize))

        rig.setDisplayScale(SplitHeadCharacterRig.activeCoverScale, animated: false)

        #expect(abs(rig.displayScale - SplitHeadCharacterRig.activeCoverScale) < tolerance)
        #expect(abs(rig.rootLayer.transform.m11 - SplitHeadCharacterRig.activeCoverScale) < tolerance)
        #expect(abs(rig.rootLayer.transform.m22 - SplitHeadCharacterRig.activeCoverScale) < tolerance)
    }

    @Test
    func rootLayerRemainsBottomAnchoredWhileScaling() {
        let rig = SplitHeadCharacterRig()
        let frame = CGRect(x: 46, y: 0, width: SplitHeadCharacterRig.canvasSize.width, height: SplitHeadCharacterRig.canvasSize.height)
        rig.layout(in: frame)

        rig.setDisplayScale(SplitHeadCharacterRig.activeCoverScale, animated: false)

        #expect(abs(rig.rootLayer.anchorPoint.x - 0.5) < tolerance)
        #expect(abs(rig.rootLayer.anchorPoint.y) < tolerance)
        #expect(abs(rig.rootLayer.position.x - frame.midX) < tolerance)
        #expect(abs(rig.rootLayer.position.y - frame.minY) < tolerance)
    }

    private func makeAnimator(speechPoses: [CharacterAnimator.SpeechPose] = [.center]) -> (SplitHeadCharacterRig, CharacterAnimator) {
        let rig = SplitHeadCharacterRig()
        rig.layout(in: CGRect(origin: .zero, size: SplitHeadCharacterRig.canvasSize))
        var remainingPoses = speechPoses
        let animator = CharacterAnimator(rig: rig) {
            guard !remainingPoses.isEmpty else {
                return .center
            }

            return remainingPoses.removeFirst()
        }
        return (rig, animator)
    }

    private func closedPositionY(in bounds: CGRect, anchorPoint: CGPoint) -> CGFloat {
        bounds.minY + (bounds.height * anchorPoint.y)
    }
}
