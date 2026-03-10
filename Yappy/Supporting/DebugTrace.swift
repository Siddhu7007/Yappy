import Foundation

enum DebugTrace {
    #if DEBUG
    private static let logURL = URL(fileURLWithPath: "/tmp/yappy-debug.log")
    private static let queue = DispatchQueue(label: "Yappy.DebugTrace")
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var logPath: String {
        logURL.path
    }

    static func resetSession(reason: String) {
        queue.async {
            let banner = "\n=== \(timestamp()) \(reason) ===\n"
            try? Data(banner.utf8).write(to: logURL, options: .atomic)
        }
    }

    static func log(_ message: String) {
        queue.async {
            let line = "\(timestamp()) \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL)
            {
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    try? handle.close()
                }
                return
            }

            try? data.write(to: logURL, options: .atomic)
        }
    }

    private static func timestamp() -> String {
        timestampFormatter.string(from: Date())
    }
    #else
    static var logPath: String { "/tmp/yappy-debug.log" }
    static func resetSession(reason _: String) {}
    static func log(_: String) {}
    #endif
}
