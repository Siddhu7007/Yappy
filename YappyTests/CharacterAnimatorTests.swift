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
    func speakingStartsOnACenteredOpenBeat() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .speaking)

        animator.updateSpeechLevel(0.85)

        assertPose(rig, matches: .center)
    }

    @Test
    func speakingCadenceAlternatesLeftCenterAndRight() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .speaking)
        animator.updateSpeechLevel(0.9)
        assertPose(rig, matches: .center)

        animator.advanceSpeechBeat()
        assertPose(rig, matches: .tiltLeft)

        animator.advanceSpeechBeat()
        assertPose(rig, matches: .center)

        animator.advanceSpeechBeat()
        assertPose(rig, matches: .tiltRight)

        animator.advanceSpeechBeat()
        assertPose(rig, matches: .center)
    }

    @Test
    func speechLevelUpdatesDoNotChangeTheHeldBeatPose() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .speaking)
        animator.updateSpeechLevel(0.88)
        animator.advanceSpeechBeat()

        let initialTilt = rig.upperHeadTiltDegrees
        let initialHorizontalOffset = rig.upperHeadHorizontalOffset
        let initialOffset = rig.upperHeadOffset
        let initialAnchorPoint = rig.upperHeadLayer.anchorPoint

        animator.updateSpeechLevel(0.23)
        animator.updateSpeechLevel(0.92)

        #expect(abs(rig.upperHeadTiltDegrees - initialTilt) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset - initialHorizontalOffset) < tolerance)
        #expect(abs(rig.upperHeadOffset - initialOffset) < tolerance)
        #expect(abs(rig.upperHeadLayer.anchorPoint.x - initialAnchorPoint.x) < tolerance)
        #expect(abs(rig.upperHeadLayer.anchorPoint.y - initialAnchorPoint.y) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .left)
    }

    @Test
    func droppingBelowSpeechThresholdStopsCadenceAndRestartsFromCenter() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .speaking)
        animator.updateSpeechLevel(0.9)
        animator.advanceSpeechBeat()
        assertPose(rig, matches: .tiltLeft)

        animator.updateSpeechLevel(0.01)

        #expect(rig.upperHeadLayer.position.y == rig.upperHeadListeningPositionY)
        #expect(abs(rig.upperHeadTiltDegrees) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .centered)

        animator.updateSpeechLevel(0.92)
        assertPose(rig, matches: .center)
    }

    @Test
    func returningToListeningRestoresTheFixedListeningOffset() {
        let (rig, animator) = makeAnimator()
        animator.apply(state: .speaking)
        animator.updateSpeechLevel(0.92)
        animator.advanceSpeechBeat()

        animator.apply(state: .listening)

        #expect(rig.upperHeadLayer.position.y == rig.upperHeadListeningPositionY)
        #expect(abs(rig.upperHeadTiltDegrees) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset) < tolerance)
        #expect(rig.upperHeadHingeAlignment == .centered)

        let listeningPositionY = rig.upperHeadLayer.position.y
        animator.advanceSpeechBeat()

        #expect(rig.upperHeadLayer.position.y == listeningPositionY)
        #expect(abs(rig.upperHeadTiltDegrees) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset) < tolerance)
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
    func activeCoverCanvasHasHeadroomForTheLiftedSpeakingPose() {
        let requiredHeight = (SplitHeadCharacterRig.canvasSize.height + SplitHeadCharacterRig.speakingCadenceCenterOffset)
            * SplitHeadCharacterRig.activeCoverScale

        #expect(SplitHeadCharacterRig.activeCoverCanvasSize.height > requiredHeight)
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

    @Test
    func blinkLayersStayInsideTheUpperHeadBounds() {
        let rig = SplitHeadCharacterRig()
        rig.layout(in: CGRect(origin: .zero, size: SplitHeadCharacterRig.canvasSize))

        #expect(rig.upperHeadLayer.bounds.contains(rig.leftEyeBlinkCoverLayer.frame))
        #expect(rig.upperHeadLayer.bounds.contains(rig.rightEyeBlinkCoverLayer.frame))
        #expect(rig.upperHeadLayer.bounds.contains(rig.leftEyeClosedLineLayer.frame))
        #expect(rig.upperHeadLayer.bounds.contains(rig.rightEyeClosedLineLayer.frame))
    }

    @Test
    func blinkAddsEyeAnimationsWithoutChangingTheHeadPose() {
        let rig = SplitHeadCharacterRig()
        rig.layout(in: CGRect(origin: .zero, size: SplitHeadCharacterRig.canvasSize))
        rig.setUpperHeadPose(
            offset: SplitHeadCharacterRig.speakingCadenceSideOffset,
            tiltDegrees: SplitHeadCharacterRig.speakingCadenceTiltDegrees,
            horizontalOffset: -SplitHeadCharacterRig.speakingCadenceHorizontalOffset,
            hingeAlignment: .left,
            animated: false,
            duration: 0
        )

        let initialOffset = rig.upperHeadOffset
        let initialTilt = rig.upperHeadTiltDegrees
        let initialHorizontalOffset = rig.upperHeadHorizontalOffset

        rig.blink()

        #expect(rig.leftEyeBlinkCoverLayer.animation(forKey: "blink.scale") != nil)
        #expect(rig.rightEyeBlinkCoverLayer.animation(forKey: "blink.scale") != nil)
        #expect(rig.leftEyeClosedLineLayer.animation(forKey: "blink.lineOpacity") != nil)
        #expect(rig.rightEyeClosedLineLayer.animation(forKey: "blink.lineOpacity") != nil)
        #expect(abs(rig.upperHeadOffset - initialOffset) < tolerance)
        #expect(abs(rig.upperHeadTiltDegrees - initialTilt) < tolerance)
        #expect(abs(rig.upperHeadHorizontalOffset - initialHorizontalOffset) < tolerance)
    }

    private func makeAnimator() -> (SplitHeadCharacterRig, CharacterAnimator) {
        let rig = SplitHeadCharacterRig()
        rig.layout(in: CGRect(origin: .zero, size: SplitHeadCharacterRig.canvasSize))
        let animator = CharacterAnimator(rig: rig, automaticallyAdvanceSpeechCadence: false)
        return (rig, animator)
    }

    private func assertPose(_ rig: SplitHeadCharacterRig, matches expectedPose: CharacterAnimator.SpeechPose) {
        switch expectedPose {
        case .center:
            #expect(abs(rig.upperHeadOffset - SplitHeadCharacterRig.speakingCadenceCenterOffset) < tolerance)
            #expect(abs(rig.upperHeadTiltDegrees) < tolerance)
            #expect(abs(rig.upperHeadHorizontalOffset) < tolerance)
            #expect(rig.upperHeadHingeAlignment == .centered)
            #expect(abs(rig.upperHeadLayer.anchorPoint.x - SplitHeadCharacterRig.upperHeadCenterAnchorPoint.x) < tolerance)
        case .tiltLeft:
            #expect(abs(rig.upperHeadOffset - SplitHeadCharacterRig.speakingCadenceSideOffset) < tolerance)
            #expect(abs(rig.upperHeadTiltDegrees - SplitHeadCharacterRig.speakingCadenceTiltDegrees) < tolerance)
            #expect(abs(rig.upperHeadHorizontalOffset + SplitHeadCharacterRig.speakingCadenceHorizontalOffset) < tolerance)
            #expect(rig.upperHeadHingeAlignment == .left)
            #expect(abs(rig.upperHeadLayer.anchorPoint.x - SplitHeadCharacterRig.upperHeadLeftHingeAnchorPoint.x) < tolerance)
        case .tiltRight:
            #expect(abs(rig.upperHeadOffset - SplitHeadCharacterRig.speakingCadenceSideOffset) < tolerance)
            #expect(abs(rig.upperHeadTiltDegrees + SplitHeadCharacterRig.speakingCadenceTiltDegrees) < tolerance)
            #expect(abs(rig.upperHeadHorizontalOffset - SplitHeadCharacterRig.speakingCadenceHorizontalOffset) < tolerance)
            #expect(rig.upperHeadHingeAlignment == .right)
            #expect(abs(rig.upperHeadLayer.anchorPoint.x - SplitHeadCharacterRig.upperHeadRightHingeAnchorPoint.x) < tolerance)
        }
    }
}
