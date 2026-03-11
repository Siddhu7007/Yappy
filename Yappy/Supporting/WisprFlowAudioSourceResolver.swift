import AVFoundation
import Foundation

struct SpeechCaptureDeviceDescriptor: Equatable, Hashable {
    let localizedName: String
    let uniqueID: String
}

protocol SpeechCaptureDeviceListing {
    func availableAudioInputDevices() -> [SpeechCaptureDeviceDescriptor]
}

struct AVCaptureSpeechCaptureDeviceListing: SpeechCaptureDeviceListing {
    func availableAudioInputDevices() -> [SpeechCaptureDeviceDescriptor] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: supportedDeviceTypes(),
            mediaType: .audio,
            position: .unspecified
        ).devices.map {
            SpeechCaptureDeviceDescriptor(localizedName: $0.localizedName, uniqueID: $0.uniqueID)
        }
    }

    private func supportedDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        if #available(macOS 14.0, *) {
            return [.microphone, .external]
        }

        return [.builtInMicrophone, .externalUnknown]
    }
}

enum SpeechAudioSourceResolution: Equatable {
    case resolved(device: SpeechCaptureDeviceDescriptor)
    case unresolved(message: String)
}

protocol SpeechAudioSourceResolving {
    func resolveAudioSource() -> SpeechAudioSourceResolution
}

protocol TextFileReading {
    func readText(from url: URL) throws -> String
}

struct DefaultTextFileReader: TextFileReading {
    func readText(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

enum SpeechAudioDeviceNameNormalizer {
    static func normalize(_ rawName: String) -> String {
        let replacedQuotes = rawName
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let withoutParentheticals = replacedQuotes.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        let collapsedWhitespace = withoutParentheticals.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return collapsedWhitespace
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

struct WisprFlowAudioSourceProvider: DictationAudioSourceProviding {
    private struct Config: Decodable {
        struct Prefs: Decodable {
            struct User: Decodable {
                let overrideAudioDeviceId: String?
                let modifierShortcut: String?
                let shortcut: String?
                let shortcuts: [String: String]?
            }

            let user: User?
        }

        let prefs: Prefs?
    }

    private struct SnapshotEntry: Decodable {
        let name: String?
        let deviceId: String
        let label: String?
        let selected: Bool?
    }

    private struct SnapshotLine {
        let timestamp: Date
        let entries: [SnapshotEntry]
    }

    let bundleIdentifier = "com.electron.wispr-flow"
    let providerName = "Wispr Flow"

    private static let snapshotMarker = "Sending audio devices to main process: "
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private let configURL: URL
    private let logURLs: [URL]
    private let textFileReader: TextFileReading
    private let runningApplicationQuery: RunningApplicationQuerying

    init(
        configURL: URL = Self.defaultConfigURL,
        logURLs: [URL] = Self.defaultLogURLs,
        textFileReader: TextFileReading = DefaultTextFileReader(),
        runningApplicationQuery: RunningApplicationQuerying = WorkspaceRunningApplicationQuery()
    ) {
        self.configURL = configURL
        self.logURLs = logURLs
        self.textFileReader = textFileReader
        self.runningApplicationQuery = runningApplicationQuery
    }

    func currentState() -> DictationAudioSourceProviderState {
        let runningApplications = runningApplicationQuery.runningApplications(withBundleIdentifier: bundleIdentifier)
        let config = loadConfig()

        return DictationAudioSourceProviderState(
            providerName: providerName,
            bundleIdentifier: bundleIdentifier,
            isRunning: !runningApplications.isEmpty,
            isConfiguredForFn: isConfiguredForFn(config),
            selectedMicrophone: selectedMicrophone(config: config, snapshot: latestSnapshotLine()),
            launchDate: runningApplications.compactMap(\.launchDate).max()
        )
    }

    private func loadConfig() -> Config? {
        guard let configText = try? textFileReader.readText(from: configURL),
              let configData = configText.data(using: .utf8)
        else {
            return nil
        }

        return try? JSONDecoder().decode(Config.self, from: configData)
    }

    private func isConfiguredForFn(_ config: Config?) -> Bool {
        guard let user = config?.prefs?.user else {
            return false
        }

        if let shortcuts = user.shortcuts,
           shortcuts.contains(where: { shortcut, action in
               action == "ptt" && shortcut.split(separator: "+").contains("63")
           }) {
            return true
        }

        if user.modifierShortcut == "63" {
            return true
        }

        if let shortcut = user.shortcut,
           shortcut.split(separator: "+").contains("63") {
            return true
        }

        return false
    }

    private func selectedMicrophone(config: Config?, snapshot: SnapshotLine?) -> DictationSelectedMicrophone? {
        guard let snapshot else {
            return nil
        }

        let overrideAudioDeviceId = config?.prefs?.user?.overrideAudioDeviceId
        guard let selectedEntry = preferredSnapshotEntry(
            from: snapshot.entries,
            overrideAudioDeviceId: overrideAudioDeviceId
        ) else {
            return nil
        }

        return DictationSelectedMicrophone(
            uniqueID: nil,
            localizedName: selectedEntry.label ?? selectedEntry.name
        )
    }

    private func latestSnapshotLine() -> SnapshotLine? {
        logURLs.compactMap(parseLatestSnapshotLine).max(by: { $0.timestamp < $1.timestamp })
    }

    private func parseLatestSnapshotLine(from url: URL) -> SnapshotLine? {
        guard let logText = try? textFileReader.readText(from: url) else {
            return nil
        }

        for line in logText.split(whereSeparator: \.isNewline).reversed() {
            let textLine = String(line)
            guard textLine.contains(Self.snapshotMarker),
                  let snapshotLine = parseSnapshotLine(textLine)
            else {
                continue
            }

            return snapshotLine
        }

        return nil
    }

    private func parseSnapshotLine(_ line: String) -> SnapshotLine? {
        guard let markerRange = line.range(of: Self.snapshotMarker) else {
            return nil
        }

        let jsonText = String(line[markerRange.upperBound...])
        guard let jsonData = jsonText.data(using: .utf8),
              let entries = try? JSONDecoder().decode([SnapshotEntry].self, from: jsonData)
        else {
            return nil
        }

        let timestamp = parseTimestamp(from: line) ?? .distantPast
        return SnapshotLine(timestamp: timestamp, entries: entries)
    }

    private func parseTimestamp(from line: String) -> Date? {
        guard let openingBracket = line.firstIndex(of: "["),
              let closingBracket = line[openingBracket...].firstIndex(of: "]")
        else {
            return nil
        }

        let timestampText = String(line[line.index(after: openingBracket) ..< closingBracket])
        return Self.timestampFormatter.date(from: timestampText)
    }

    private func preferredSnapshotEntry(
        from entries: [SnapshotEntry],
        overrideAudioDeviceId: String?
    ) -> SnapshotEntry? {
        if let overrideAudioDeviceId,
           let matchedEntry = entries.first(where: { $0.deviceId == overrideAudioDeviceId }) {
            return matchedEntry
        }

        return entries.first(where: { $0.selected == true })
    }

    private static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Wispr Flow/config.json")
    }

    private static var defaultLogURLs: [URL] {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Wispr Flow", isDirectory: true)
        return [
            logsDirectory.appendingPathComponent("main.log"),
            logsDirectory.appendingPathComponent("main.old.log")
        ]
    }
}
