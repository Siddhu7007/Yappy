// Verifies the microphone gate opens and closes with hysteresis.
import Testing
@testable import Yappy

struct SpeechLevelGateTests {
    @Test
    func backgroundNoiseDoesNotOpenTheGate() {
        var gate = SpeechLevelGate()

        #expect(gate.process(level: 0.02) == nil)
        #expect(gate.process(level: 0.05) == nil)
        #expect(gate.process(level: 0.08) == nil)
        #expect(gate.isSpeechActive == false)
    }

    @Test
    func quietSpeechStillOpensTheGateAfterTwoConsecutiveSamples() {
        var gate = SpeechLevelGate()

        #expect(gate.process(level: 0.13) == nil)
        #expect(gate.process(level: 0.15) == true)
        #expect(gate.isSpeechActive == true)
    }

    @Test
    func shortDipsDoNotChatterTheGateClosed() {
        var gate = SpeechLevelGate()

        _ = gate.process(level: 0.15)
        _ = gate.process(level: 0.18)
        #expect(gate.isSpeechActive == true)

        #expect(gate.process(level: 0.05) == nil)
        #expect(gate.process(level: 0.04) == nil)
        #expect(gate.process(level: 0.10) == nil)
        #expect(gate.isSpeechActive == true)

        #expect(gate.process(level: 0.04) == nil)
        #expect(gate.process(level: 0.05) == nil)
        #expect(gate.process(level: 0.03) == nil)
        #expect(gate.process(level: 0.04) == nil)
        #expect(gate.process(level: 0.05) == false)
        #expect(gate.isSpeechActive == false)
    }
}
