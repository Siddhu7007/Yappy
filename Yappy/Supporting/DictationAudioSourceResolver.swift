import AppKit
import Foundation

struct DictationSelectedMicrophone: Equatable {
    let uniqueID: String?
    let localizedName: String?
}

struct DictationAudioSourceProviderState: Equatable {
    let providerName: String
    let bundleIdentifier: String
    let isRunning: Bool
    let isConfiguredForFn: Bool
    let selectedMicrophone: DictationSelectedMicrophone?
    let launchDate: Date?
}

protocol DictationAudioSourceProviding {
    var bundleIdentifier: String { get }
    var providerName: String { get }

    func currentState() -> DictationAudioSourceProviderState
}

struct RunningApplicationDescriptor: Equatable {
    let bundleIdentifier: String
    let launchDate: Date?
}

protocol RunningApplicationQuerying {
    func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [RunningApplicationDescriptor]
}

struct WorkspaceRunningApplicationQuery: RunningApplicationQuerying {
    func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [RunningApplicationDescriptor] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map {
            RunningApplicationDescriptor(bundleIdentifier: bundleIdentifier, launchDate: $0.launchDate)
        }
    }
}

protocol DictationAppActivationTracking {
    func lastActivationDate(for bundleIdentifier: String) -> Date?
}

final class WorkspaceDictationAppActivationTracker: DictationAppActivationTracking {
    private let supportedBundleIdentifiers: Set<String>
    private let dateProvider: () -> Date
    private let notificationCenter: NotificationCenter
    private var activationDates = [String: Date]()
    private var observer: NSObjectProtocol?

    init(
        supportedBundleIdentifiers: Set<String>,
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter? = nil,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.supportedBundleIdentifiers = supportedBundleIdentifiers
        self.notificationCenter = notificationCenter ?? workspace.notificationCenter
        self.dateProvider = dateProvider

        if let bundleIdentifier = workspace.frontmostApplication?.bundleIdentifier,
           supportedBundleIdentifiers.contains(bundleIdentifier) {
            activationDates[bundleIdentifier] = dateProvider()
        }

        observer = self.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handle(notification: notification)
        }
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    func lastActivationDate(for bundleIdentifier: String) -> Date? {
        activationDates[bundleIdentifier]
    }

    private func handle(notification: Notification) {
        guard let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleIdentifier = runningApplication.bundleIdentifier,
              supportedBundleIdentifiers.contains(bundleIdentifier)
        else {
            return
        }

        activationDates[bundleIdentifier] = dateProvider()
    }
}

enum DictationProviderSelectionResolution: Equatable {
    case selected(DictationAudioSourceProviderState)
    case unresolved(message: String)
}

struct DictationAudioSourceProviderRegistry {
    private let providers: [DictationAudioSourceProviding]
    private let activationTracker: DictationAppActivationTracking

    init(
        providers: [DictationAudioSourceProviding],
        activationTracker: DictationAppActivationTracking
    ) {
        self.providers = providers
        self.activationTracker = activationTracker
    }

    func resolveActiveProvider() -> DictationProviderSelectionResolution {
        let providerStates = providers.map { $0.currentState() }
        let runningStates = providerStates.filter(\.isRunning)
        let candidateStates = runningStates.filter(\.isConfiguredForFn)

        guard !candidateStates.isEmpty else {
            if runningStates.isEmpty {
                return .unresolved(
                    message: "Speech Sync: Open \(supportedProviderNames) to mirror the active Fn microphone"
                )
            }

            return .unresolved(
                message: "Speech Sync: Set Fn as the hotkey in \(providerNames(from: runningStates))"
            )
        }

        if candidateStates.count == 1, let selectedState = candidateStates.first {
            return .selected(selectedState)
        }

        if let activatedState = uniquelyMostRecentState(from: candidateStates, by: { state in
            activationTracker.lastActivationDate(for: state.bundleIdentifier)
        }) {
            return .selected(activatedState)
        }

        if let launchedState = uniquelyMostRecentState(from: candidateStates, by: \.launchDate) {
            return .selected(launchedState)
        }

        return .unresolved(
            message: "Speech Sync: Multiple Fn dictation tools are active: \(providerNames(from: candidateStates))"
        )
    }

    private func uniquelyMostRecentState(
        from states: [DictationAudioSourceProviderState],
        by timestamp: (DictationAudioSourceProviderState) -> Date?
    ) -> DictationAudioSourceProviderState? {
        let timestampedStates = states.compactMap { state -> (DictationAudioSourceProviderState, Date)? in
            guard let timestamp = timestamp(state) else {
                return nil
            }
            return (state, timestamp)
        }

        guard let latestTimestamp = timestampedStates.map(\.1).max() else {
            return nil
        }

        let matchingStates = timestampedStates.filter { $0.1 == latestTimestamp }
        guard matchingStates.count == 1 else {
            return nil
        }

        return matchingStates[0].0
    }

    private var supportedProviderNames: String {
        providerNames(providers.map(\.providerName))
    }

    private func providerNames(from states: [DictationAudioSourceProviderState]) -> String {
        providerNames(states.map(\.providerName))
    }

    private func providerNames(_ names: [String]) -> String {
        var orderedUniqueNames = [String]()
        for name in names where !orderedUniqueNames.contains(name) {
            orderedUniqueNames.append(name)
        }

        return orderedUniqueNames.joined(separator: " or ")
    }
}

final class DictationAudioSourceResolver: SpeechAudioSourceResolving {
    private let providerRegistry: DictationAudioSourceProviderRegistry
    private let deviceLister: SpeechCaptureDeviceListing

    init(
        providerRegistry: DictationAudioSourceProviderRegistry,
        deviceLister: SpeechCaptureDeviceListing = AVCaptureSpeechCaptureDeviceListing()
    ) {
        self.providerRegistry = providerRegistry
        self.deviceLister = deviceLister
    }

    func resolveAudioSource() -> SpeechAudioSourceResolution {
        let availableDevices = deviceLister.availableAudioInputDevices()
        guard !availableDevices.isEmpty else {
            return .unresolved(message: "Speech Sync: No audio inputs are available")
        }

        switch providerRegistry.resolveActiveProvider() {
        case let .unresolved(message):
            return .unresolved(message: message)
        case let .selected(providerState):
            guard let selectedMicrophone = providerState.selectedMicrophone else {
                return .unresolved(
                    message: "Speech Sync: Can't read \(providerState.providerName) microphone selection"
                )
            }

            return resolveCaptureDevice(
                providerState: providerState,
                selectedMicrophone: selectedMicrophone,
                availableDevices: availableDevices
            )
        }
    }

    private func resolveCaptureDevice(
        providerState: DictationAudioSourceProviderState,
        selectedMicrophone: DictationSelectedMicrophone,
        availableDevices: [SpeechCaptureDeviceDescriptor]
    ) -> SpeechAudioSourceResolution {
        if let uniqueID = selectedMicrophone.uniqueID,
           !uniqueID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let matchedDevices = availableDevices.filter { $0.uniqueID == uniqueID }
            return resolution(
                for: matchedDevices,
                providerName: providerState.providerName,
                selectedMicrophone: selectedMicrophone
            )
        }

        let candidateNames = [selectedMicrophone.localizedName]
            .compactMap { $0 }
            .map(SpeechAudioDeviceNameNormalizer.normalize)
            .filter { !$0.isEmpty }

        guard !candidateNames.isEmpty else {
            return .unresolved(message: "Speech Sync: Can't read \(providerState.providerName) microphone selection")
        }

        let matchedDevices = availableDevices.filter { descriptor in
            let normalizedDeviceName = SpeechAudioDeviceNameNormalizer.normalize(descriptor.localizedName)
            return candidateNames.contains(normalizedDeviceName)
        }
        return resolution(
            for: matchedDevices,
            providerName: providerState.providerName,
            selectedMicrophone: selectedMicrophone
        )
    }

    private func resolution(
        for matchedDevices: [SpeechCaptureDeviceDescriptor],
        providerName: String,
        selectedMicrophone: DictationSelectedMicrophone
    ) -> SpeechAudioSourceResolution {
        switch matchedDevices.count {
        case 1:
            return .resolved(device: matchedDevices[0])
        case 0:
            return .unresolved(
                message: "Speech Sync: Can't match \(providerName) microphone\(microphoneSuffix(for: selectedMicrophone))"
            )
        default:
            return .unresolved(
                message: "Speech Sync: Multiple mics match \(providerName) microphone\(microphoneSuffix(for: selectedMicrophone))"
            )
        }
    }

    private func microphoneSuffix(for selectedMicrophone: DictationSelectedMicrophone) -> String {
        guard let localizedName = selectedMicrophone.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !localizedName.isEmpty else {
            return ""
        }

        return " \(localizedName)"
    }
}

struct WillowVoiceAudioSourceProvider: DictationAudioSourceProviding {
    private struct Preferences: Decodable {
        struct HotkeyData: Decodable {
            let keyCode: Int?
            let keyName: String?
        }

        let selectedMicrophoneUID: String?
        let selectedHotkey: String?
        let hotkeyData: HotkeyData?
    }

    let bundleIdentifier = "com.seewillow.WillowMac"
    let providerName = "Willow Voice"

    private let preferencesURL: URL
    private let textFileReader: TextFileReading
    private let runningApplicationQuery: RunningApplicationQuerying

    init(
        preferencesURL: URL = Self.defaultPreferencesURL,
        textFileReader: TextFileReading = DefaultTextFileReader(),
        runningApplicationQuery: RunningApplicationQuerying = WorkspaceRunningApplicationQuery()
    ) {
        self.preferencesURL = preferencesURL
        self.textFileReader = textFileReader
        self.runningApplicationQuery = runningApplicationQuery
    }

    func currentState() -> DictationAudioSourceProviderState {
        let runningApplications = runningApplicationQuery.runningApplications(withBundleIdentifier: bundleIdentifier)
        let preferences = loadPreferences()

        return DictationAudioSourceProviderState(
            providerName: providerName,
            bundleIdentifier: bundleIdentifier,
            isRunning: !runningApplications.isEmpty,
            isConfiguredForFn: isConfiguredForFn(preferences),
            selectedMicrophone: selectedMicrophone(from: preferences),
            launchDate: runningApplications.compactMap(\.launchDate).max()
        )
    }

    private func loadPreferences() -> Preferences? {
        guard let text = try? textFileReader.readText(from: preferencesURL),
              let data = text.data(using: .utf8)
        else {
            return nil
        }

        return try? JSONDecoder().decode(Preferences.self, from: data)
    }

    private func isConfiguredForFn(_ preferences: Preferences?) -> Bool {
        if let selectedHotkey = preferences?.selectedHotkey,
           selectedHotkey.caseInsensitiveCompare("Fn") == .orderedSame {
            return true
        }

        if preferences?.hotkeyData?.keyCode == 63 {
            return true
        }

        if let keyName = preferences?.hotkeyData?.keyName,
           keyName.caseInsensitiveCompare("Fn") == .orderedSame {
            return true
        }

        return false
    }

    private func selectedMicrophone(from preferences: Preferences?) -> DictationSelectedMicrophone? {
        guard let normalizedUniqueID = normalizeStoredUniqueID(preferences?.selectedMicrophoneUID) else {
            return nil
        }

        return DictationSelectedMicrophone(uniqueID: normalizedUniqueID, localizedName: nil)
    }

    private func normalizeStoredUniqueID(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if trimmedValue.hasPrefix("uid:") {
            return String(trimmedValue.dropFirst(4))
        }

        if trimmedValue.hasPrefix("meta:") {
            return nil
        }

        return trimmedValue
    }

    private static var defaultPreferencesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.seewillow.WillowMac/Preferences/preferences.json")
    }
}
