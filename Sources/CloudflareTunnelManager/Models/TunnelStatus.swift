import Foundation
import SwiftUI

/// Runtime status of a tunnel's `cloudflared` process. Not persisted — a freshly
/// loaded app always starts every tunnel in `.stopped`.
enum TunnelStatus: Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case error(String)

    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .stopping: return "Stopping…"
        case .error: return "Error"
        }
    }

    /// True while the process is alive (or coming alive / going down).
    var isActive: Bool {
        switch self {
        case .running, .starting, .stopping: return true
        case .stopped, .error: return false
        }
    }

    var isBusy: Bool {
        switch self {
        case .starting, .stopping: return true
        default: return false
        }
    }

    var color: Color {
        switch self {
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .running: return .green
        case .error: return .red
        }
    }

    var errorMessage: String? {
        if case let .error(message) = self { return message }
        return nil
    }
}
