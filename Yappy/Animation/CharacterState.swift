// Defines the M1 character states and external triggers that drive the animation loop.
import Foundation

enum CharacterState: String, CaseIterable, Equatable {
    case idle
    case listening
    case speaking
    case disabled
    case error
}

enum CharacterTrigger: Equatable {
    case hotkeyPressed
    case hotkeyReleased
    case speechActivityChanged(Bool)
    case permissionDenied
    case setEnabled(Bool)
}
