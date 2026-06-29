import AppKit

// MARK: - Logger

final class Logger {
    static let shared = Logger()
    private(set) var entries: [String] = []
    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static let didAddEntry = Notification.Name("LoggerDidAddEntry")

    func log(_ message: String) {
        let timestamp = df.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        entries.append(entry)
        NSLog("[NTM] %@", message)
        NotificationCenter.default.post(name: Logger.didAddEntry, object: entry)
    }

    var text: String { entries.joined(separator: "\n") }
}

func log(_ msg: String) {
    Logger.shared.log(msg)
}
