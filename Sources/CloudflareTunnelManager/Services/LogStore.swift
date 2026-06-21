import Foundation
import Observation

enum LogLevel: String, Sendable {
    case info
    case success
    case warning
    case error
    case command

    var symbol: String {
        switch self {
        case .info: return "•"
        case .success: return "✓"
        case .warning: return "!"
        case .error: return "✗"
        case .command: return "$"
        }
    }
}

struct LogLine: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let tunnelID: UUID?
    let level: LogLevel
    let text: String
}

/// In-memory ring buffer of log lines, partitioned per tunnel plus a global feed.
/// MainActor-isolated: every mutation comes from `AppState` after hopping to main.
@MainActor
@Observable
final class LogStore {
    private(set) var lines: [UUID: [LogLine]] = [:]
    var bufferSize: Int = 2000

    func append(tunnelID: UUID?, level: LogLevel, _ text: String) {
        let key = tunnelID ?? Self.globalKey
        let line = LogLine(date: Date(), tunnelID: tunnelID, level: level, text: text)
        var bucket = lines[key] ?? []
        bucket.append(line)
        if bucket.count > bufferSize {
            bucket.removeFirst(bucket.count - bufferSize)
        }
        lines[key] = bucket
    }

    func lines(for tunnelID: UUID?) -> [LogLine] {
        lines[tunnelID ?? Self.globalKey] ?? []
    }

    func clear(tunnelID: UUID?) {
        lines[tunnelID ?? Self.globalKey] = []
    }

    func plainText(for tunnelID: UUID?) -> String {
        lines(for: tunnelID)
            .map { "[\(Self.formatter.string(from: $0.date))] \($0.text)" }
            .joined(separator: "\n")
    }

    static let globalKey = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
