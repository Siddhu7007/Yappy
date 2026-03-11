import Foundation
import Testing
@testable import Yappy

struct DictationAudioSourceResolverTests {
    @Test
    func singleRunningFnProviderUsesUniqueIDMatch() {
        let resolver = makeResolver(
            providers: [
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Willow Voice",
                        bundleIdentifier: "com.seewillow.WillowMac",
                        isRunning: true,
                        isConfiguredForFn: true,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: "BuiltInMicrophoneDevice", localizedName: nil),
                        launchDate: Date(timeIntervalSince1970: 200)
                    )
                )
            ],
            devices: [
                SpeechCaptureDeviceDescriptor(localizedName: "MacBook Air Microphone", uniqueID: "BuiltInMicrophoneDevice")
            ]
        )

        #expect(
            resolver.resolveAudioSource()
                == .resolved(device: SpeechCaptureDeviceDescriptor(localizedName: "MacBook Air Microphone", uniqueID: "BuiltInMicrophoneDevice"))
        )
    }

    @Test
    func mostRecentActivationWinsWhenMultipleProvidersAreActive() {
        let wisprState = DictationAudioSourceProviderState(
            providerName: "Wispr Flow",
            bundleIdentifier: "com.electron.wispr-flow",
            isRunning: true,
            isConfiguredForFn: true,
            selectedMicrophone: DictationSelectedMicrophone(uniqueID: nil, localizedName: "MacBook Air Microphone"),
            launchDate: Date(timeIntervalSince1970: 100)
        )
        let willowState = DictationAudioSourceProviderState(
            providerName: "Willow Voice",
            bundleIdentifier: "com.seewillow.WillowMac",
            isRunning: true,
            isConfiguredForFn: true,
            selectedMicrophone: DictationSelectedMicrophone(uniqueID: "F0-A9-68-1B-CF-8A:input", localizedName: nil),
            launchDate: Date(timeIntervalSince1970: 90)
        )
        let resolver = makeResolver(
            providers: [
                StubDictationProvider(state: wisprState),
                StubDictationProvider(state: willowState)
            ],
            devices: [
                SpeechCaptureDeviceDescriptor(localizedName: "MacBook Air Microphone", uniqueID: "BuiltInMicrophoneDevice"),
                SpeechCaptureDeviceDescriptor(localizedName: "JBL LIVE500BT", uniqueID: "F0-A9-68-1B-CF-8A:input")
            ],
            activationDates: [
                "com.electron.wispr-flow": Date(timeIntervalSince1970: 1000),
                "com.seewillow.WillowMac": Date(timeIntervalSince1970: 2000)
            ]
        )

        #expect(
            resolver.resolveAudioSource()
                == .resolved(device: SpeechCaptureDeviceDescriptor(localizedName: "JBL LIVE500BT", uniqueID: "F0-A9-68-1B-CF-8A:input"))
        )
    }

    @Test
    func mostRecentLaunchDateWinsWhenActivationHistoryIsMissing() {
        let resolver = makeResolver(
            providers: [
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Wispr Flow",
                        bundleIdentifier: "com.electron.wispr-flow",
                        isRunning: true,
                        isConfiguredForFn: true,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: nil, localizedName: "MacBook Air Microphone"),
                        launchDate: Date(timeIntervalSince1970: 100)
                    )
                ),
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Willow Voice",
                        bundleIdentifier: "com.seewillow.WillowMac",
                        isRunning: true,
                        isConfiguredForFn: true,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: "F0-A9-68-1B-CF-8A:input", localizedName: nil),
                        launchDate: Date(timeIntervalSince1970: 200)
                    )
                )
            ],
            devices: [
                SpeechCaptureDeviceDescriptor(localizedName: "MacBook Air Microphone", uniqueID: "BuiltInMicrophoneDevice"),
                SpeechCaptureDeviceDescriptor(localizedName: "JBL LIVE500BT", uniqueID: "F0-A9-68-1B-CF-8A:input")
            ]
        )

        #expect(
            resolver.resolveAudioSource()
                == .resolved(device: SpeechCaptureDeviceDescriptor(localizedName: "JBL LIVE500BT", uniqueID: "F0-A9-68-1B-CF-8A:input"))
        )
    }

    @Test
    func ambiguousProviderSelectionFailsClosed() {
        let tiedLaunchDate = Date(timeIntervalSince1970: 100)
        let resolver = makeResolver(
            providers: [
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Wispr Flow",
                        bundleIdentifier: "com.electron.wispr-flow",
                        isRunning: true,
                        isConfiguredForFn: true,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: nil, localizedName: "MacBook Air Microphone"),
                        launchDate: tiedLaunchDate
                    )
                ),
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Willow Voice",
                        bundleIdentifier: "com.seewillow.WillowMac",
                        isRunning: true,
                        isConfiguredForFn: true,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: "F0-A9-68-1B-CF-8A:input", localizedName: nil),
                        launchDate: tiedLaunchDate
                    )
                )
            ],
            devices: [
                SpeechCaptureDeviceDescriptor(localizedName: "MacBook Air Microphone", uniqueID: "BuiltInMicrophoneDevice"),
                SpeechCaptureDeviceDescriptor(localizedName: "JBL LIVE500BT", uniqueID: "F0-A9-68-1B-CF-8A:input")
            ]
        )

        #expect(
            resolver.resolveAudioSource()
                == .unresolved(message: "Speech Sync: Multiple Fn dictation tools are active: Wispr Flow or Willow Voice")
        )
    }

    @Test
    func noRunningSupportedProviderFailsClosed() {
        let resolver = makeResolver(
            providers: [
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Wispr Flow",
                        bundleIdentifier: "com.electron.wispr-flow",
                        isRunning: false,
                        isConfiguredForFn: true,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: nil, localizedName: "MacBook Air Microphone"),
                        launchDate: nil
                    )
                )
            ],
            devices: [
                SpeechCaptureDeviceDescriptor(localizedName: "MacBook Air Microphone", uniqueID: "BuiltInMicrophoneDevice")
            ]
        )

        #expect(
            resolver.resolveAudioSource()
                == .unresolved(message: "Speech Sync: Open Wispr Flow to mirror the active Fn microphone")
        )
    }

    @Test
    func runningSupportedProviderWithoutFnConfigurationShowsActionableWarning() {
        let resolver = makeResolver(
            providers: [
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Willow Voice",
                        bundleIdentifier: "com.seewillow.WillowMac",
                        isRunning: true,
                        isConfiguredForFn: false,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: "BuiltInMicrophoneDevice", localizedName: nil),
                        launchDate: Date(timeIntervalSince1970: 100)
                    )
                )
            ],
            devices: [
                SpeechCaptureDeviceDescriptor(localizedName: "MacBook Air Microphone", uniqueID: "BuiltInMicrophoneDevice")
            ]
        )

        #expect(
            resolver.resolveAudioSource()
                == .unresolved(message: "Speech Sync: Set Fn as the hotkey in Willow Voice")
        )
    }

    @Test
    func nameBasedMatchingFailsClosedWhenNoCaptureDeviceMatches() {
        let resolver = makeResolver(
            providers: [
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Wispr Flow",
                        bundleIdentifier: "com.electron.wispr-flow",
                        isRunning: true,
                        isConfiguredForFn: true,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: nil, localizedName: "MacBook Air Microphone (Built-in)"),
                        launchDate: Date(timeIntervalSince1970: 100)
                    )
                )
            ],
            devices: [
                SpeechCaptureDeviceDescriptor(localizedName: "USB Podcast Mic", uniqueID: "usb-mic")
            ]
        )

        #expect(
            resolver.resolveAudioSource()
                == .unresolved(message: "Speech Sync: Can't match Wispr Flow microphone MacBook Air Microphone (Built-in)")
        )
    }

    @Test
    func nameBasedMatchingFailsClosedWhenMultipleCaptureDevicesNormalizeToSameName() {
        let resolver = makeResolver(
            providers: [
                StubDictationProvider(
                    state: DictationAudioSourceProviderState(
                        providerName: "Wispr Flow",
                        bundleIdentifier: "com.electron.wispr-flow",
                        isRunning: true,
                        isConfiguredForFn: true,
                        selectedMicrophone: DictationSelectedMicrophone(uniqueID: nil, localizedName: "JBL LIVE500BT (Bluetooth)"),
                        launchDate: Date(timeIntervalSince1970: 100)
                    )
                )
            ],
            devices: [
                SpeechCaptureDeviceDescriptor(localizedName: "JBL LIVE500BT", uniqueID: "jbl-a"),
                SpeechCaptureDeviceDescriptor(localizedName: "JBL LIVE500BT (Bluetooth)", uniqueID: "jbl-b")
            ]
        )

        #expect(
            resolver.resolveAudioSource()
                == .unresolved(message: "Speech Sync: Multiple mics match Wispr Flow microphone JBL LIVE500BT (Bluetooth)")
        )
    }
}

private struct StubDictationProvider: DictationAudioSourceProviding {
    let state: DictationAudioSourceProviderState

    var bundleIdentifier: String { state.bundleIdentifier }
    var providerName: String { state.providerName }

    func currentState() -> DictationAudioSourceProviderState {
        state
    }
}

private struct StaticSpeechCaptureDeviceListing: SpeechCaptureDeviceListing {
    let devices: [SpeechCaptureDeviceDescriptor]

    func availableAudioInputDevices() -> [SpeechCaptureDeviceDescriptor] {
        devices
    }
}

private struct StaticDictationAppActivationTracker: DictationAppActivationTracking {
    let activationDates: [String: Date]

    func lastActivationDate(for bundleIdentifier: String) -> Date? {
        activationDates[bundleIdentifier]
    }
}

private func makeResolver(
    providers: [DictationAudioSourceProviding],
    devices: [SpeechCaptureDeviceDescriptor],
    activationDates: [String: Date] = [:]
) -> DictationAudioSourceResolver {
    DictationAudioSourceResolver(
        providerRegistry: DictationAudioSourceProviderRegistry(
            providers: providers,
            activationTracker: StaticDictationAppActivationTracker(activationDates: activationDates)
        ),
        deviceLister: StaticSpeechCaptureDeviceListing(devices: devices)
    )
}
