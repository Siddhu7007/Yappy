// Verifies microphone RMS values are normalized and smoothed for live motion.
import Testing
@testable import Yappy

struct SpeechLevelMeterTests {
    @Test
    func silenceStaysAtZero() {
        var meter = SpeechLevelMeter()

        #expect(meter.process(rms: 0) == 0)
        #expect(meter.normalizedLevel == 0)
    }

    @Test
    func louderSamplesRaiseTheLevel() {
        var meter = SpeechLevelMeter()

        let quietLevel = meter.process(rms: 0.012)
        let loudLevel = meter.process(rms: 0.080)

        #expect(loudLevel > quietLevel)
    }

    @Test
    func releaseSmoothingFallsMoreSlowlyThanAttackRises() {
        var meter = SpeechLevelMeter(attackSmoothing: 0.5, releaseSmoothing: 0.2)

        let risingLevel = meter.process(rms: 0.100)
        let fallingLevel = meter.process(rms: 0.001)

        #expect(risingLevel > fallingLevel)
        #expect(fallingLevel > 0)
    }

    @Test
    func resetClearsTheCurrentLevel() {
        var meter = SpeechLevelMeter()

        _ = meter.process(rms: 0.080)
        #expect(meter.normalizedLevel > 0)

        _ = meter.reset()
        #expect(meter.normalizedLevel == 0)
    }
}
