// Verifies the M1 state machine timing rules and disabled-state behavior.
import Testing
@testable import Yappy

@MainActor
struct CharacterStateMachineTests {
    @Test
    func pressingFnEntersListeningImmediately() {
        let machine = CharacterStateMachine()

        machine.handle(.hotkeyPressed)
        #expect(machine.state == .listening)
    }

    @Test
    func speechActivityPromotesListeningToSpeakingWhileFnIsHeld() {
        let machine = CharacterStateMachine()

        machine.handle(.hotkeyPressed)
        machine.handle(.speechActivityChanged(true))

        #expect(machine.state == .speaking)
    }

    @Test
    func speechActivityFallsBackToListeningWhenVoiceStops() {
        let machine = CharacterStateMachine()

        machine.handle(.hotkeyPressed)
        machine.handle(.speechActivityChanged(true))
        machine.handle(.speechActivityChanged(false))

        #expect(machine.state == .listening)
    }

    @Test
    func releasingFnReturnsToIdleImmediatelyEvenWhileSpeaking() {
        let machine = CharacterStateMachine()

        machine.handle(.hotkeyPressed)
        machine.handle(.speechActivityChanged(true))
        machine.handle(.hotkeyReleased)

        #expect(machine.state == .idle)
    }

    @Test
    func speechActivityIsIgnoredUnlessFnIsHeld() {
        let machine = CharacterStateMachine()

        machine.handle(.speechActivityChanged(true))

        #expect(machine.state == .idle)
    }

    @Test
    func disabledStateSuppressesHotkeyTransitionsUntilReenabled() {
        let machine = CharacterStateMachine()

        machine.handle(.setEnabled(false))
        machine.handle(.hotkeyPressed)

        #expect(machine.state == .disabled)

        machine.handle(.setEnabled(true))
        #expect(machine.state == .idle)
    }

    @Test
    func permissionErrorsCanRecoverOnTheNextFnPress() {
        let machine = CharacterStateMachine()

        machine.handle(.permissionDenied)
        #expect(machine.state == .error)

        machine.handle(.hotkeyPressed)
        #expect(machine.state == .listening)
    }
}
