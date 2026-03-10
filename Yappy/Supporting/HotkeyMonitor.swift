// Listens for standalone Fn / Globe presses using low-level sources.
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hid

enum HotkeyEvent: Equatable {
    case pressed
    case released
}

enum HotkeyInputSource: String, CaseIterable {
    case hid
    case eventTap
    case polling
}

struct FunctionKeyElementMatch: Hashable {
    let usagePage: Int
    let usage: Int

    var dictionary: [String: Int] {
        [
            kIOHIDElementUsagePageKey as String: usagePage,
            kIOHIDElementUsageKey as String: usage,
        ]
    }
}

@MainActor
protocol HotkeyMonitoring: AnyObject {
    var onEvent: ((HotkeyEvent) -> Void)? { get set }
    var onObservation: ((HotkeyInputSource) -> Void)? { get set }
    var isRunning: Bool { get }

    func notePointerDown()
    func start() -> Bool
    func stop()
}

@MainActor
final class HotkeyMonitor: HotkeyMonitoring {
    var onEvent: ((HotkeyEvent) -> Void)?
    var onObservation: ((HotkeyInputSource) -> Void)?

    private static let fallbackFunctionElementMatch = FunctionKeyElementMatch(usagePage: 0x00FF, usage: 0x03)
    private static let functionVirtualKeyCode = Int64(kVK_Function)

    private let startHIDMonitorOverride: (() -> Bool)?
    private let startEventTapOverride: (() -> Bool)?
    private let currentFunctionStateProvider: () -> Bool
    private let eventTapReleaseConfirmationDelayNanoseconds: UInt64
    private let recentPointerDownEventTapReleaseConfirmationDelayNanoseconds: UInt64
    private let recentPointerDownWindowSeconds: TimeInterval
    private let interactionPollingWindowNanoseconds: UInt64
    private let interactionPollingIntervalNanoseconds: UInt64
    private var hidManager: IOHIDManager?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var functionElementMatches = Set<FunctionKeyElementMatch>()
    private var pendingEventTapReleaseTask: Task<Void, Never>?
    private var interactionStatePollingTask: Task<Void, Never>?
    private var observedSources = Set<HotkeyInputSource>()
    private var activeSource: HotkeyInputSource?
    private var hasLoggedFirstPublishedPress = false
    private var hasLoggedFirstPublishedRelease = false
    private var publishedIsDown = false
    private var hidFnIsDown = false
    private var eventTapFnIsDown = false
    private var hasSeenHIDForCurrentHold = false
    private var lastPointerDownUptime: TimeInterval = 0

    private(set) var isRunning = false

    init(
        startHIDMonitorOverride: (() -> Bool)? = nil,
        startEventTapOverride: (() -> Bool)? = nil,
        currentFunctionStateProvider: (() -> Bool)? = nil,
        eventTapReleaseConfirmationDelayNanoseconds: UInt64 = 50_000_000,
        recentPointerDownEventTapReleaseConfirmationDelayNanoseconds: UInt64 = 120_000_000,
        recentPointerDownWindowSeconds: TimeInterval = 0.20,
        interactionPollingWindowNanoseconds: UInt64 = 5_000_000_000,
        interactionPollingIntervalNanoseconds: UInt64 = 50_000_000
    ) {
        self.startHIDMonitorOverride = startHIDMonitorOverride
        self.startEventTapOverride = startEventTapOverride
        self.currentFunctionStateProvider = currentFunctionStateProvider ?? Self.currentFunctionStateFromSystem
        self.eventTapReleaseConfirmationDelayNanoseconds = eventTapReleaseConfirmationDelayNanoseconds
        self.recentPointerDownEventTapReleaseConfirmationDelayNanoseconds =
            recentPointerDownEventTapReleaseConfirmationDelayNanoseconds
        self.recentPointerDownWindowSeconds = recentPointerDownWindowSeconds
        self.interactionPollingWindowNanoseconds = interactionPollingWindowNanoseconds
        self.interactionPollingIntervalNanoseconds = interactionPollingIntervalNanoseconds
    }

    convenience init(
        startHIDMonitorOverride: (() -> Bool)?,
        startEventTapOverride: (() -> Bool)?,
        currentFunctionStateProvider: (() -> Bool)?,
        eventTapReleaseConfirmationDelayNanoseconds: UInt64
    ) {
        self.init(
            startHIDMonitorOverride: startHIDMonitorOverride,
            startEventTapOverride: startEventTapOverride,
            currentFunctionStateProvider: currentFunctionStateProvider,
            eventTapReleaseConfirmationDelayNanoseconds: eventTapReleaseConfirmationDelayNanoseconds,
            recentPointerDownEventTapReleaseConfirmationDelayNanoseconds: max(
                eventTapReleaseConfirmationDelayNanoseconds,
                120_000_000
            ),
            recentPointerDownWindowSeconds: 0.20,
            interactionPollingWindowNanoseconds: 5_000_000_000,
            interactionPollingIntervalNanoseconds: 50_000_000
        )
    }

    func notePointerDown() {
        lastPointerDownUptime = ProcessInfo.processInfo.systemUptime
        debugLog("pointer down recorded uptime=\(lastPointerDownUptime)")
        armInteractionStatePolling()
    }

    func start() -> Bool {
        guard !isRunning else {
            debugLog("start() called while already running")
            return true
        }

        let hidStarted = startHIDMonitorOverride?() ?? startHIDMonitor()
        let eventTapStarted = startEventTapOverride?() ?? startEventTap()
        resetState()

        isRunning = hidStarted || eventTapStarted
        debugLog(
            "startup result hidStarted=\(hidStarted) eventTapStarted=\(eventTapStarted) matches=\(formattedMatches())"
        )
        if isRunning {
            debugLog("monitor started; waiting for first live Fn event")
        }
        return hidStarted || eventTapStarted
    }

    func stop() {
        if let hidManager {
            IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(hidManager, 0)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        hidManager = nil
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        functionElementMatches = [Self.fallbackFunctionElementMatch]
        resetState()
        debugLog("stopped")
    }

    private func resetState() {
        cancelPendingEventTapRelease(reason: "state reset")
        cancelInteractionStatePolling(reason: "state reset")
        observedSources.removeAll()
        activeSource = nil
        hasLoggedFirstPublishedPress = false
        hasLoggedFirstPublishedRelease = false
        publishedIsDown = false
        hidFnIsDown = false
        eventTapFnIsDown = false
        hasSeenHIDForCurrentHold = false
        lastPointerDownUptime = 0
    }

    private func startEventTap() -> Bool {
        let eventMask = 1 << CGEventType.flagsChanged.rawValue

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            debugLog("event tap failed to start")
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        debugLog("event tap started")
        return true
    }

    private func startHIDMonitor() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)

        let callback: IOHIDValueCallback = { context, _, _, value in
            guard let context else {
                return
            }

            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.handleHIDValue(value)
            }
        }

        IOHIDManagerRegisterInputValueCallback(
            manager,
            callback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let openResult = IOHIDManagerOpen(manager, 0)
        guard openResult == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            debugLog("HID monitor failed to open: \(openResult)")
            return false
        }

        let resolvedMatches = resolvedFunctionElementMatches(for: manager)
        functionElementMatches = resolvedMatches
        IOHIDManagerSetInputValueMatchingMultiple(
            manager,
            resolvedMatches.map(\.dictionary) as CFArray
        )

        hidManager = manager
        debugLog("HID monitor started with matches=\(formattedMatches(resolvedMatches))")
        return true
    }

    private func resolvedFunctionElementMatches(for manager: IOHIDManager) -> Set<FunctionKeyElementMatch> {
        var reportedMatches = Set<FunctionKeyElementMatch>()

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return Self.preferredFunctionElementMatches(from: reportedMatches)
        }

        for device in devices {
            guard
                let usagePage = deviceProperty(named: "FnModifierUsagePage", on: device),
                let usage = deviceProperty(named: "FnModifierUsage", on: device)
            else {
                continue
            }

            reportedMatches.insert(FunctionKeyElementMatch(usagePage: usagePage, usage: usage))
        }

        return Self.preferredFunctionElementMatches(from: reportedMatches)
    }

    private func deviceProperty(named key: String, on device: IOHIDDevice) -> Int? {
        guard let property = IOHIDDeviceGetProperty(device, key as CFString) else {
            return nil
        }

        if let number = property as? NSNumber {
            return number.intValue
        }

        return nil
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let match = FunctionKeyElementMatch(
            usagePage: Int(IOHIDElementGetUsagePage(element)),
            usage: Int(IOHIDElementGetUsage(element))
        )

        guard functionElementMatches.contains(match) else {
            return
        }

        let isFunctionDown = decodedFunctionState(from: value)
        debugLog("HID Fn event usagePage=\(match.usagePage) usage=\(match.usage) down=\(isFunctionDown)")
        _ = receive(functionState: isFunctionDown, from: .hid)
    }

    private func decodedFunctionState(from value: IOHIDValue) -> Bool {
        let length = IOHIDValueGetLength(value)
        if length <= MemoryLayout<CFIndex>.size {
            return IOHIDValueGetIntegerValue(value) != 0
        }

        let bytes = IOHIDValueGetBytePtr(value)
        return (0 ..< length).contains { bytes[$0] != 0 }
    }

    @discardableResult
    func receive(functionState isFunctionDown: Bool, from source: HotkeyInputSource, recordsObservation: Bool = true) -> HotkeyEvent? {
        if recordsObservation {
            noteObservation(from: source)
        }

        switch source {
        case .hid:
            return handleHIDFnChanged(isDown: isFunctionDown)
        case .eventTap:
            return handleEventTapFnChanged(isDown: isFunctionDown)
        case .polling:
            return handlePolledFunctionState(isFunctionDown)
        }
    }

    private func handleHIDFnChanged(isDown: Bool) -> HotkeyEvent? {
        hidFnIsDown = isDown

        if isDown {
            hasSeenHIDForCurrentHold = true
            cancelPendingEventTapRelease(reason: "HID press observed")
            return publishPressedIfNeeded(from: .hid)
        }

        guard hasSeenHIDForCurrentHold else {
            debugLog("ignoring HID release because HID never reported a press for the current hold")
            return nil
        }

        return confirmAndPublishReleaseIfNeeded(authoritative: true, source: .hid)
    }

    private func handleEventTapFnChanged(isDown: Bool) -> HotkeyEvent? {
        if isDown {
            eventTapFnIsDown = true
            cancelPendingEventTapRelease(reason: "eventTap press observed")
            return publishPressedIfNeeded(from: .eventTap)
        }

        eventTapFnIsDown = false

        guard publishedIsDown else {
            return nil
        }

        armPendingEventTapRelease()
        return nil
    }

    private func armPendingEventTapRelease() {
        cancelPendingEventTapRelease(reason: "rescheduled eventTap release confirmation")
        let now = ProcessInfo.processInfo.systemUptime
        let justClicked = (now - lastPointerDownUptime) < recentPointerDownWindowSeconds
        let delayNanoseconds = justClicked
            ? recentPointerDownEventTapReleaseConfirmationDelayNanoseconds
            : eventTapReleaseConfirmationDelayNanoseconds
        debugLog("confirming eventTap release after \(delayNanoseconds / 1_000_000)ms")

        pendingEventTapReleaseTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }

            guard let self else {
                return
            }

            self.pendingEventTapReleaseTask = nil
            _ = self.confirmAndPublishReleaseIfNeeded(authoritative: false, source: .eventTap)
        }
    }

    private func cancelPendingEventTapRelease(reason: String) {
        if let pendingEventTapReleaseTask {
            pendingEventTapReleaseTask.cancel()
            self.pendingEventTapReleaseTask = nil
            debugLog("cancelled pending eventTap release reason=\(reason)")
        }
    }

    private func armInteractionStatePolling() {
        guard isRunning else {
            return
        }

        guard interactionPollingWindowNanoseconds > 0, interactionPollingIntervalNanoseconds > 0 else {
            return
        }

        cancelInteractionStatePolling(reason: "rescheduled by pointer down")
        let pollingWindowSeconds = TimeInterval(interactionPollingWindowNanoseconds) / 1_000_000_000
        let pollingStartUptime = ProcessInfo.processInfo.systemUptime
        debugLog(
            "starting interaction state polling windowMs=\(interactionPollingWindowNanoseconds / 1_000_000) intervalMs=\(interactionPollingIntervalNanoseconds / 1_000_000)"
        )

        interactionStatePollingTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            while (ProcessInfo.processInfo.systemUptime - pollingStartUptime) < pollingWindowSeconds {
                self.handlePolledFunctionState(self.currentFunctionStateProvider())

                do {
                    try await Task.sleep(nanoseconds: self.interactionPollingIntervalNanoseconds)
                } catch {
                    return
                }
            }

            self.interactionStatePollingTask = nil
            self.debugLog("interaction state polling window ended")
        }
    }

    private func cancelInteractionStatePolling(reason: String) {
        if let interactionStatePollingTask {
            interactionStatePollingTask.cancel()
            self.interactionStatePollingTask = nil
            debugLog("cancelled interaction state polling reason=\(reason)")
        }
    }

    @discardableResult
    private func handlePolledFunctionState(_ isFunctionDown: Bool) -> HotkeyEvent? {
        if isFunctionDown {
            eventTapFnIsDown = true
            cancelPendingEventTapRelease(reason: "polled Fn down")
            if !publishedIsDown {
                debugLog("publishing polled Fn press")
                return publishPressedIfNeeded(from: .polling)
            }
            return nil
        }

        eventTapFnIsDown = false

        guard publishedIsDown, !hidFnIsDown else {
            return nil
        }

        debugLog("polled Fn up while session is active")
        return confirmAndPublishReleaseIfNeeded(authoritative: false, source: .polling)
    }

    private func confirmAndPublishReleaseIfNeeded(authoritative: Bool, source: HotkeyInputSource) -> HotkeyEvent? {
        cancelPendingEventTapRelease(reason: "release confirmation resolved")

        guard publishedIsDown else {
            return nil
        }

        if hidFnIsDown {
            debugLog("ignoring \(source.rawValue) release because HID still reports Fn down")
            return nil
        }

        if !authoritative, hasSeenHIDForCurrentHold {
            debugLog("ignoring provisional \(source.rawValue) release until HID reports Fn up")
            return nil
        }

        if !authoritative, eventTapFnIsDown {
            debugLog("ignoring provisional \(source.rawValue) release because event tap still reports Fn down")
            return nil
        }

        if !authoritative {
            let isFunctionStillDown = currentFunctionStateProvider()
            debugLog("eventTap release confirmation currentState=\(isFunctionStillDown)")
            if isFunctionStillDown {
                eventTapFnIsDown = true
                return nil
            }
        }

        return publishReleasedIfNeeded(from: source)
    }

    private func noteObservation(from source: HotkeyInputSource) {
        guard observedSources.insert(source).inserted else {
            return
        }

        debugLog("first raw Fn callback source=\(source.rawValue)")
        onObservation?(source)
    }

    private func publishPressedIfNeeded(from source: HotkeyInputSource) -> HotkeyEvent? {
        guard !publishedIsDown else {
            return nil
        }

        publishedIsDown = true
        updateActiveSource(source)
        logFirstPublishedEventIfNeeded(.pressed, source: source)
        debugLog("published hotkey event=pressed source=\(source.rawValue)")
        onEvent?(.pressed)
        return .pressed
    }

    private func publishReleasedIfNeeded(from source: HotkeyInputSource) -> HotkeyEvent? {
        guard publishedIsDown else {
            return nil
        }

        publishedIsDown = false
        hidFnIsDown = false
        eventTapFnIsDown = false
        hasSeenHIDForCurrentHold = false
        updateActiveSource(source)
        logFirstPublishedEventIfNeeded(.released, source: source)
        debugLog("published hotkey event=released source=\(source.rawValue)")
        onEvent?(.released)
        return .released
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            _ = handleEventTapDisabled()

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let isSecondaryFnDown = event.flags.contains(.maskSecondaryFn)
            handleEventTapFlagsChanged(isFunctionDown: isSecondaryFnDown, keyCode: keyCode)

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    @discardableResult
    func handleEventTapFlagsChanged(isFunctionDown: Bool, keyCode: Int64) -> HotkeyEvent? {
        guard keyCode == Self.functionVirtualKeyCode else {
            debugLog(
                "ignoring event tap flagsChanged for non-Fn keyCode=\(keyCode) secondaryFn=\(isFunctionDown)"
            )
            return nil
        }

        debugLog("event tap flagsChanged keyCode=\(keyCode) secondaryFn=\(isFunctionDown)")
        return receive(functionState: isFunctionDown, from: .eventTap)
    }

    @discardableResult
    func handleEventTapDisabled() -> HotkeyEvent? {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }

        let isFunctionDown = currentFunctionStateProvider()
        cancelPendingEventTapRelease(reason: "event tap disabled")
        eventTapFnIsDown = isFunctionDown
        let event: HotkeyEvent?
        if isFunctionDown {
            event = publishPressedIfNeeded(from: .eventTap)
        } else {
            event = confirmAndPublishReleaseIfNeeded(authoritative: false, source: .eventTap)
        }
        let resultDescription = event.map { $0 == .pressed ? "pressed" : "released" } ?? "no-change"
        debugLog("event tap re-enabled after disable; resynced secondaryFn=\(isFunctionDown) result=\(resultDescription)")
        return event
    }

    private func formattedMatches(_ matches: Set<FunctionKeyElementMatch>? = nil) -> String {
        let matchesToFormat = matches ?? functionElementMatches
        if matchesToFormat.isEmpty {
            return "[]"
        }

        let formatted = matchesToFormat
            .sorted { lhs, rhs in
                if lhs.usagePage == rhs.usagePage {
                    return lhs.usage < rhs.usage
                }

                return lhs.usagePage < rhs.usagePage
            }
            .map { "\($0.usagePage):\($0.usage)" }
            .joined(separator: ",")
        return "[\(formatted)]"
    }

    private func updateActiveSource(_ source: HotkeyInputSource) {
        guard activeSource != source else {
            return
        }

        activeSource = source
        debugLog("active source=\(source.rawValue)")
    }

    private func logFirstPublishedEventIfNeeded(_ event: HotkeyEvent, source: HotkeyInputSource) {
        switch event {
        case .pressed:
            guard !hasLoggedFirstPublishedPress else {
                return
            }
            hasLoggedFirstPublishedPress = true
            debugLog("first published hotkey event=pressed source=\(source.rawValue)")
        case .released:
            guard !hasLoggedFirstPublishedRelease else {
                return
            }
            hasLoggedFirstPublishedRelease = true
            debugLog("first published hotkey event=released source=\(source.rawValue)")
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        let line = "[FnMonitor] \(message)"
        print(line)
        DebugTrace.log(line)
        #endif
    }

    static func preferredFunctionElementMatches(
        from reportedMatches: Set<FunctionKeyElementMatch>
    ) -> Set<FunctionKeyElementMatch> {
        guard !reportedMatches.isEmpty else {
            return [fallbackFunctionElementMatch]
        }

        return reportedMatches
    }

    private static func currentFunctionStateFromSystem() -> Bool {
        if CGEventSource.flagsState(.hidSystemState).contains(.maskSecondaryFn) {
            return true
        }

        if CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn) {
            return true
        }

        return NSEvent.modifierFlags.contains(.function)
    }
}
