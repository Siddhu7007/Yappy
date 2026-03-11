import Foundation
import Testing
@testable import Yappy

struct WillowVoiceAudioSourceProviderTests {
    @Test
    func selectedMicrophoneUIDResolvesWhenConfiguredForFn() throws {
        let workspace = try TestWillowFiles()
        try workspace.writePreferences(
            selectedMicrophoneUID: "uid:F0-A9-68-1B-CF-8A:input",
            selectedHotkey: "Fn",
            hotkeyKeyCode: 63
        )

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.isRunning)
        #expect(state.isConfiguredForFn)
        #expect(state.selectedMicrophone == DictationSelectedMicrophone(uniqueID: "F0-A9-68-1B-CF-8A:input", localizedName: nil))
    }

    @Test
    func nonFnHotkeyConfigurationIsIgnored() throws {
        let workspace = try TestWillowFiles()
        try workspace.writePreferences(
            selectedMicrophoneUID: "uid:BuiltInMicrophoneDevice",
            selectedHotkey: "Option",
            hotkeyKeyCode: 58
        )

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.isConfiguredForFn == false)
    }

    @Test
    func metaDefaultMicrophoneFailsClosed() throws {
        let workspace = try TestWillowFiles()
        try workspace.writePreferences(
            selectedMicrophoneUID: "meta:defaultInput",
            selectedHotkey: "Fn",
            hotkeyKeyCode: 63
        )

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.isConfiguredForFn)
        #expect(state.selectedMicrophone == nil)
    }

    @Test
    func malformedPreferencesFailClosed() throws {
        let workspace = try TestWillowFiles()
        try "{".write(to: workspace.preferencesURL, atomically: true, encoding: .utf8)

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.isConfiguredForFn == false)
        #expect(state.selectedMicrophone == nil)
    }
}

private struct TestWillowFiles {
    let rootURL: URL
    let preferencesURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let preferencesDirectory = rootURL.appendingPathComponent("Preferences", isDirectory: true)
        preferencesURL = preferencesDirectory.appendingPathComponent("preferences.json")
        try FileManager.default.createDirectory(at: preferencesDirectory, withIntermediateDirectories: true)
    }

    func writePreferences(
        selectedMicrophoneUID: String?,
        selectedHotkey: String?,
        hotkeyKeyCode: Int?
    ) throws {
        let json = """
        {
          "selectedMicrophoneUID": \(selectedMicrophoneUID.map { "\"\($0)\"" } ?? "null"),
          "selectedHotkey": \(selectedHotkey.map { "\"\($0)\"" } ?? "null"),
          "hotkeyData": {
            "keyCode": \(hotkeyKeyCode.map(String.init) ?? "null"),
            "keyName": \(selectedHotkey.map { "\"\($0)\"" } ?? "null")
          }
        }
        """
        try json.write(to: preferencesURL, atomically: true, encoding: .utf8)
    }

    func makeProvider(isRunning: Bool) -> WillowVoiceAudioSourceProvider {
        WillowVoiceAudioSourceProvider(
            preferencesURL: preferencesURL,
            runningApplicationQuery: WillowTestRunningApplicationQuery(
                bundleIdentifier: "com.seewillow.WillowMac",
                isRunning: isRunning
            )
        )
    }
}

private struct WillowTestRunningApplicationQuery: RunningApplicationQuerying {
    let bundleIdentifier: String
    let isRunning: Bool

    func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [RunningApplicationDescriptor] {
        guard isRunning, bundleIdentifier == self.bundleIdentifier else {
            return []
        }

        return [RunningApplicationDescriptor(bundleIdentifier: bundleIdentifier, launchDate: Date(timeIntervalSince1970: 200))]
    }
}
