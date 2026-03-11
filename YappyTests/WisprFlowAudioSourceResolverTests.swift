import Foundation
import Testing
@testable import Yappy

struct WisprFlowAudioSourceProviderTests {
    @Test
    func explicitOverrideIdTakesPrecedenceOverSelectedFlag() throws {
        let workspace = try TestWisprFlowFiles()
        try workspace.writeConfig(
            overrideAudioDeviceId: "built-in-id",
            shortcuts: ["63": "ptt"]
        )
        try workspace.writeLog(
            named: "main.log",
            lines: [
                workspace.snapshotLine(
                    timestamp: "2026-03-11 08:15:00.000",
                    devices: [
                        .init(name: "JBL LIVE500BT (Bluetooth)", deviceId: "jbl-id", label: "JBL LIVE500BT (Bluetooth)", selected: true),
                        .init(name: "Built-in mic (recommended)", deviceId: "built-in-id", label: "MacBook Air Microphone (Built-in)", selected: false)
                    ]
                )
            ]
        )

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.isRunning)
        #expect(state.isConfiguredForFn)
        #expect(state.selectedMicrophone == DictationSelectedMicrophone(uniqueID: nil, localizedName: "MacBook Air Microphone (Built-in)"))
    }

    @Test
    func selectedSnapshotDeviceResolvesWhenNoOverrideExists() throws {
        let workspace = try TestWisprFlowFiles()
        try workspace.writeConfig(
            overrideAudioDeviceId: nil,
            shortcuts: ["63": "ptt"]
        )
        try workspace.writeLog(
            named: "main.log",
            lines: [
                workspace.snapshotLine(
                    timestamp: "2026-03-11 08:15:00.000",
                    devices: [
                        .init(name: "Built-in mic (recommended)", deviceId: "built-in-id", label: "MacBook Air Microphone (Built-in)", selected: false),
                        .init(name: "JBL LIVE500BT (Bluetooth)", deviceId: "jbl-id", label: "JBL LIVE500BT (Bluetooth)", selected: true)
                    ]
                )
            ]
        )

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.isConfiguredForFn)
        #expect(state.selectedMicrophone == DictationSelectedMicrophone(uniqueID: nil, localizedName: "JBL LIVE500BT (Bluetooth)"))
    }

    @Test
    func newestSnapshotAcrossMainAndOldLogsWins() throws {
        let workspace = try TestWisprFlowFiles()
        try workspace.writeConfig(
            overrideAudioDeviceId: nil,
            shortcuts: ["63": "ptt"]
        )
        try workspace.writeLog(
            named: "main.old.log",
            lines: [
                workspace.snapshotLine(
                    timestamp: "2026-03-10 18:15:00.000",
                    devices: [
                        .init(name: "Built-in mic (recommended)", deviceId: "built-in-id", label: "MacBook Air Microphone (Built-in)", selected: true)
                    ]
                )
            ]
        )
        try workspace.writeLog(
            named: "main.log",
            lines: [
                workspace.snapshotLine(
                    timestamp: "2026-03-11 08:15:00.000",
                    devices: [
                        .init(name: "JBL LIVE500BT (Bluetooth)", deviceId: "jbl-id", label: "JBL LIVE500BT (Bluetooth)", selected: true)
                    ]
                )
            ]
        )

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.selectedMicrophone == DictationSelectedMicrophone(uniqueID: nil, localizedName: "JBL LIVE500BT (Bluetooth)"))
    }

    @Test
    func nonFnShortcutConfigurationIsIgnored() throws {
        let workspace = try TestWisprFlowFiles()
        try workspace.writeConfig(
            overrideAudioDeviceId: nil,
            shortcuts: ["59": "ptt"]
        )

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.isConfiguredForFn == false)
    }

    @Test
    func missingLogFailsClosedByLeavingSelectedMicrophoneNil() throws {
        let workspace = try TestWisprFlowFiles()
        try workspace.writeConfig(
            overrideAudioDeviceId: nil,
            shortcuts: ["63": "ptt"]
        )

        let state = workspace.makeProvider(isRunning: true).currentState()

        #expect(state.isConfiguredForFn)
        #expect(state.selectedMicrophone == nil)
    }
}

private struct TestWisprFlowFiles {
    struct SnapshotDevice {
        let name: String
        let deviceId: String
        let label: String
        let selected: Bool
    }

    let rootURL: URL
    let configURL: URL
    let logsDirectoryURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        configURL = rootURL.appendingPathComponent("config.json")
        logsDirectoryURL = rootURL.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
    }

    func writeConfig(
        overrideAudioDeviceId: String?,
        shortcuts: [String: String]? = nil,
        modifierShortcut: String? = nil,
        shortcut: String? = nil
    ) throws {
        let shortcutsJSON: String
        if let shortcuts {
            let shortcutPairs = shortcuts
                .sorted(by: { $0.key < $1.key })
                .map { "\"\($0.key)\":\"\($0.value)\"" }
                .joined(separator: ",")
            shortcutsJSON = "{\(shortcutPairs)}"
        } else {
            shortcutsJSON = "null"
        }

        let configJSON = """
        {
          "prefs": {
            "user": {
              "overrideAudioDeviceId": \(overrideAudioDeviceId.map { "\"\($0)\"" } ?? "null"),
              "modifierShortcut": \(modifierShortcut.map { "\"\($0)\"" } ?? "null"),
              "shortcut": \(shortcut.map { "\"\($0)\"" } ?? "null"),
              "shortcuts": \(shortcutsJSON)
            }
          }
        }
        """
        try configJSON.write(to: configURL, atomically: true, encoding: .utf8)
    }

    func writeLog(named name: String, lines: [String]) throws {
        let url = logsDirectoryURL.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    func snapshotLine(timestamp: String, devices: [SnapshotDevice]) -> String {
        let deviceObjects = devices.map {
            """
            {"name":"\($0.name)","deviceId":"\($0.deviceId)","label":"\($0.label)","selected":\($0.selected ? "true" : "false")}
            """
        }.joined(separator: ",")

        return "[\(timestamp)] [info]  Sending audio devices to main process: [\(deviceObjects)]"
    }

    func makeProvider(isRunning: Bool) -> WisprFlowAudioSourceProvider {
        WisprFlowAudioSourceProvider(
            configURL: configURL,
            logURLs: [
                logsDirectoryURL.appendingPathComponent("main.log"),
                logsDirectoryURL.appendingPathComponent("main.old.log")
            ],
            runningApplicationQuery: WisprTestRunningApplicationQuery(
                bundleIdentifier: "com.electron.wispr-flow",
                isRunning: isRunning
            )
        )
    }
}

private struct WisprTestRunningApplicationQuery: RunningApplicationQuerying {
    let bundleIdentifier: String
    let isRunning: Bool

    func runningApplications(withBundleIdentifier bundleIdentifier: String) -> [RunningApplicationDescriptor] {
        guard isRunning, bundleIdentifier == self.bundleIdentifier else {
            return []
        }

        return [RunningApplicationDescriptor(bundleIdentifier: bundleIdentifier, launchDate: Date(timeIntervalSince1970: 100))]
    }
}
