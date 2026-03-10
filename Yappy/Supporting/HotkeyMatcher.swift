// Deduplicates standalone Fn state changes before they reach the app coordinator.
import Foundation

struct HotkeyMatcher {
    private var isHotkeyActive = false

    mutating func reset() {
        isHotkeyActive = false
    }

    mutating func handleFunctionState(_ isFunctionDown: Bool) -> HotkeyEvent? {
        guard isFunctionDown != isHotkeyActive else {
            return nil
        }

        isHotkeyActive = isFunctionDown
        return isFunctionDown ? .pressed : .released
    }
}
