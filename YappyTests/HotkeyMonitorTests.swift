// Verifies the Fn monitor prefers concrete Fn descriptors over generic vendor fallbacks.
import Testing
@testable import Yappy

@MainActor
struct HotkeyMonitorTests {
    @Test
    func usesReportedFnDescriptorWithoutUnioningFallbacks() {
        let reportedMatches: Set<FunctionKeyElementMatch> = [
            FunctionKeyElementMatch(usagePage: 12, usage: 77),
        ]

        let preferredMatches = HotkeyMonitor.preferredFunctionElementMatches(from: reportedMatches)

        #expect(preferredMatches == reportedMatches)
    }

    @Test
    func fallsBackToStandardAppleFnUsageWhenNoDescriptorIsReported() {
        let preferredMatches = HotkeyMonitor.preferredFunctionElementMatches(from: [])

        #expect(preferredMatches == [FunctionKeyElementMatch(usagePage: 0x00FF, usage: 0x03)])
    }

    @Test
    func startSucceedsWhenHIDMonitoringStarts() {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { true },
            startEventTapOverride: { false }
        )

        #expect(monitor.start() == true)
        #expect(monitor.isRunning == true)
    }

    @Test
    func startSucceedsWhenEventTapStarts() {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true }
        )

        #expect(monitor.start() == true)
        #expect(monitor.isRunning == true)
    }

    @Test
    func startFailsClosedWhenNoReliableSourceStarts() {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { false }
        )

        #expect(monitor.start() == false)
        #expect(monitor.isRunning == false)
    }

    @Test
    func hidSamplesPublishPressedThenReleasedWithoutDuplicateEvents() {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { true },
            startEventTapOverride: { false }
        )
        var observedSources = [HotkeyInputSource]()
        var events = [HotkeyEvent]()
        monitor.onObservation = { observedSources.append($0) }
        monitor.onEvent = { events.append($0) }

        monitor.receive(functionState: true, from: .hid)
        monitor.receive(functionState: true, from: .hid)
        monitor.receive(functionState: false, from: .hid)

        #expect(observedSources == [.hid])
        #expect(events == [.pressed, .released])
    }

    @Test
    func eventTapReleaseIsConfirmedBeforePublishing() async {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true },
            currentFunctionStateProvider: { false },
            eventTapReleaseConfirmationDelayNanoseconds: 1_000_000
        )
        var observedSources = [HotkeyInputSource]()
        var events = [HotkeyEvent]()
        monitor.onObservation = { observedSources.append($0) }
        monitor.onEvent = { events.append($0) }

        monitor.receive(functionState: true, from: .eventTap)
        monitor.receive(functionState: true, from: .eventTap)
        monitor.receive(functionState: false, from: .eventTap)
        #expect(observedSources == [.eventTap])
        #expect(events == [.pressed])

        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(events == [.pressed, .released])
    }

    @Test
    func eventTapFalseReleaseIsIgnoredWhenFnStillAppearsHeld() async {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true },
            currentFunctionStateProvider: { true },
            eventTapReleaseConfirmationDelayNanoseconds: 1_000_000
        )
        var events = [HotkeyEvent]()
        monitor.onEvent = { events.append($0) }

        monitor.receive(functionState: true, from: .eventTap)
        monitor.receive(functionState: false, from: .eventTap)
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(events == [.pressed])
    }

    @Test
    func nonFunctionEventTapFlagsChangedAreIgnored() async {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true },
            currentFunctionStateProvider: { false },
            eventTapReleaseConfirmationDelayNanoseconds: 1_000_000
        )
        var events = [HotkeyEvent]()
        monitor.onEvent = { events.append($0) }

        _ = monitor.handleEventTapFlagsChanged(isFunctionDown: true, keyCode: 63)
        _ = monitor.handleEventTapFlagsChanged(isFunctionDown: false, keyCode: 56)
        try? await Task.sleep(nanoseconds: 20_000_000)

        #expect(events == [.pressed])
    }

    @Test
    func recentPointerDownExtendsEventTapReleaseConfirmation() async {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true },
            currentFunctionStateProvider: { false },
            eventTapReleaseConfirmationDelayNanoseconds: 1_000_000,
            recentPointerDownEventTapReleaseConfirmationDelayNanoseconds: 40_000_000,
            recentPointerDownWindowSeconds: 1
        )
        var events = [HotkeyEvent]()
        monitor.onEvent = { events.append($0) }

        monitor.receive(functionState: true, from: .eventTap)
        monitor.notePointerDown()
        monitor.receive(functionState: false, from: .eventTap)
        try? await Task.sleep(nanoseconds: 15_000_000)

        #expect(events == [.pressed])

        try? await Task.sleep(nanoseconds: 60_000_000)

        #expect(events == [.pressed, .released])
    }

    @Test
    func pollingAfterPointerDownCanRecoverAMissedFnPress() async {
        var isFunctionDown = false
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true },
            currentFunctionStateProvider: { isFunctionDown },
            eventTapReleaseConfirmationDelayNanoseconds: 1_000_000,
            recentPointerDownEventTapReleaseConfirmationDelayNanoseconds: 40_000_000,
            recentPointerDownWindowSeconds: 1,
            interactionPollingWindowNanoseconds: 200_000_000,
            interactionPollingIntervalNanoseconds: 10_000_000
        )
        var events = [HotkeyEvent]()
        monitor.onEvent = { events.append($0) }

        #expect(monitor.start() == true)
        monitor.notePointerDown()
        try? await Task.sleep(nanoseconds: 30_000_000)

        isFunctionDown = true
        try? await Task.sleep(nanoseconds: 60_000_000)

        #expect(events == [.pressed])

        isFunctionDown = false
        try? await Task.sleep(nanoseconds: 60_000_000)

        #expect(events == [.pressed, .released])
    }

    @Test
    func tapDisableAfterPressWithReleasedStatePublishesSyntheticRelease() {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true },
            currentFunctionStateProvider: { false }
        )
        var events = [HotkeyEvent]()
        monitor.onEvent = { events.append($0) }

        monitor.receive(functionState: true, from: .eventTap)
        let recoveryEvent = monitor.handleEventTapDisabled()

        #expect(recoveryEvent == .released)
        #expect(events == [.pressed, .released])
    }

    @Test
    func tapDisableAfterPressWhileFnRemainsHeldPublishesNoExtraEvent() {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true },
            currentFunctionStateProvider: { true }
        )
        var events = [HotkeyEvent]()
        monitor.onEvent = { events.append($0) }

        monitor.receive(functionState: true, from: .eventTap)
        let recoveryEvent = monitor.handleEventTapDisabled()

        #expect(recoveryEvent == nil)
        #expect(events == [.pressed])
    }

    @Test
    func releaseWaitsUntilAllObservedSourcesReportFnUp() {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { true },
            startEventTapOverride: { true }
        )
        var events = [HotkeyEvent]()
        monitor.onEvent = { events.append($0) }

        monitor.receive(functionState: true, from: .hid)
        monitor.receive(functionState: true, from: .eventTap)
        monitor.receive(functionState: false, from: .eventTap)

        #expect(events == [.pressed])

        monitor.receive(functionState: false, from: .hid)

        #expect(events == [.pressed, .released])
    }

    @Test
    func tapDisableWhileIdlePublishesNoEvent() {
        let monitor = HotkeyMonitor(
            startHIDMonitorOverride: { false },
            startEventTapOverride: { true },
            currentFunctionStateProvider: { false }
        )
        var events = [HotkeyEvent]()
        monitor.onEvent = { events.append($0) }

        let recoveryEvent = monitor.handleEventTapDisabled()

        #expect(recoveryEvent == nil)
        #expect(events.isEmpty)
    }
}
