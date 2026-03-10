// Verifies the hotkey matcher deduplicates standalone Fn state transitions.
import Testing
@testable import Yappy

struct HotkeyMatcherTests {
    @Test
    func fnStatePublishesPressedThenReleased() {
        var matcher = HotkeyMatcher()

        #expect(matcher.handleFunctionState(true) == .pressed)
        #expect(matcher.handleFunctionState(false) == .released)
    }

    @Test
    func duplicateSamplesAreIgnoredWhileFnStateIsStable() {
        var matcher = HotkeyMatcher()

        #expect(matcher.handleFunctionState(true) == .pressed)
        #expect(matcher.handleFunctionState(true) == nil)
        #expect(matcher.handleFunctionState(false) == .released)
        #expect(matcher.handleFunctionState(false) == nil)
    }
}
