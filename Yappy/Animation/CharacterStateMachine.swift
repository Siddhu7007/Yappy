// Applies the M1 hotkey and speech-activity rules for transitioning between overlay states.
import Foundation

@MainActor
final class CharacterStateMachine {
    private var isHotkeyDown = false
    private var isSpeechActive = false
    private var isEnabled = true

    var onStateChange: ((CharacterState) -> Void)?

    private(set) var state: CharacterState = .idle

    init() {}

    func handle(_ trigger: CharacterTrigger) {
        switch trigger {
        case .hotkeyPressed:
            handleHotkeyPressed()
        case .hotkeyReleased:
            handleHotkeyReleased()
        case let .speechActivityChanged(isSpeechActive):
            handleSpeechActivityChanged(isSpeechActive)
        case .permissionDenied:
            isHotkeyDown = false
            isSpeechActive = false
            transition(to: .error)
        case let .setEnabled(enabled):
            handleEnabledChange(enabled)
        }
    }

    private func handleHotkeyPressed() {
        guard isEnabled, !isHotkeyDown else {
            return
        }

        isHotkeyDown = true
        transition(to: isSpeechActive ? .speaking : .listening)
    }

    private func handleHotkeyReleased() {
        guard isHotkeyDown else {
            return
        }

        isHotkeyDown = false
        isSpeechActive = false

        guard isEnabled else {
            return
        }

        transition(to: .idle)
    }

    private func handleSpeechActivityChanged(_ isSpeechActive: Bool) {
        self.isSpeechActive = isSpeechActive

        guard isEnabled, isHotkeyDown else {
            return
        }

        transition(to: isSpeechActive ? .speaking : .listening)
    }

    private func handleEnabledChange(_ enabled: Bool) {
        isEnabled = enabled
        isHotkeyDown = false
        isSpeechActive = false

        if enabled {
            transition(to: .idle)
        } else {
            transition(to: .disabled)
        }
    }

    private func transition(to nextState: CharacterState) {
        guard state != nextState else {
            return
        }

        state = nextState
        onStateChange?(nextState)
    }
}
