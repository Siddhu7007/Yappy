// Shapes live microphone level into visible mouth motion for the split-head rig.
import CoreGraphics
import Foundation

struct SpeechMotionProfile {
    let listeningOffset: CGFloat
    let maxSpeakingOffset: CGFloat
    let minimumVisibleLevel: CGFloat
    let exponent: CGFloat

    init(
        listeningOffset: CGFloat = SplitHeadCharacterRig.upperHeadListeningOffset,
        maxSpeakingOffset: CGFloat = SplitHeadCharacterRig.upperHeadOpenOffset,
        minimumVisibleLevel: CGFloat = 0.07,
        exponent: CGFloat = 1.08
    ) {
        self.listeningOffset = listeningOffset
        self.maxSpeakingOffset = maxSpeakingOffset
        self.minimumVisibleLevel = minimumVisibleLevel
        self.exponent = exponent
    }

    func offset(for normalizedLevel: CGFloat) -> CGFloat {
        let clampedLevel = max(0, min(1, normalizedLevel))
        guard clampedLevel > 0 else {
            return listeningOffset
        }

        let curvedLevel = CGFloat(pow(Double(clampedLevel), Double(exponent)))
        let visibleLevel = min(1, max(minimumVisibleLevel, curvedLevel))
        return listeningOffset + ((maxSpeakingOffset - listeningOffset) * visibleLevel)
    }
}
