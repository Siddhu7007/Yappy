import Testing
@testable import Yappy

@MainActor
struct SpeechMotionProfileTests {
    @Test
    func zeroLevelUsesListeningOffset() {
        let profile = SpeechMotionProfile()

        #expect(profile.offset(for: 0) == SplitHeadCharacterRig.upperHeadListeningOffset)
    }

    @Test
    func lowNonZeroLevelStillProducesVisibleWobble() {
        let profile = SpeechMotionProfile()
        let offset = profile.offset(for: 0.01)

        #expect(offset > SplitHeadCharacterRig.upperHeadListeningOffset)
    }

    @Test
    func louderLevelsOpenFurther() {
        let profile = SpeechMotionProfile()
        let mediumOffset = profile.offset(for: 0.35)
        let loudOffset = profile.offset(for: 0.7)

        #expect(loudOffset > mediumOffset)
    }

    @Test
    func fullLevelClampsAtTheConfiguredMaximumOffset() {
        let profile = SpeechMotionProfile()

        #expect(profile.offset(for: 1) == SplitHeadCharacterRig.upperHeadOpenOffset)
        #expect(profile.offset(for: 5) == SplitHeadCharacterRig.upperHeadOpenOffset)
    }
}
