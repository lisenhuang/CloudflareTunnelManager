import Foundation

/// Events emitted by a running `cloudflared` process. Sendable so they can cross
/// from the background pipe queue to the MainActor consumer.
enum ProcessEvent: Sendable {
    case line(tunnelID: UUID, level: LogLevel, text: String)
    case exited(tunnelID: UUID, code: Int32)
}

/// Accumulates raw pipe bytes and yields whole lines. A single `FileHandle`'s
/// `readabilityHandler` is invoked serially on one queue, so per-handle use is
/// race-free without extra locking.
private final class LineBuffer {
    private var buffer = Data()

    func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        let newline = Data([0x0A])  // "\n"
        while let range = buffer.range(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
            }
        }
        return lines
    }

    func flush() -> String? {
        guard !buffer.isEmpty, let s = String(data: buffer, encoding: .utf8) else { return nil }
        buffer.removeAll()
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Launches and supervises `cloudflared` child processes — one per tunnel.
/// Not MainActor-isolated: process I/O happens on background queues. State is
/// guarded by a private serial queue. Status/log updates are delivered to the
/// MainActor via the `onEvent` callback (set by `AppState`).
final class CloudflaredProcessService {

    /// Called for every log line and on process exit. Set by the consumer to
    /// hop onto the MainActor.
    var onEvent: (@Sendable (ProcessEvent) -> Void)?

    private let stateQueue = DispatchQueue(label: "com.cloudflaretunnelmanager.process.state")
    private var processes: [UUID: Process] = [:]

    /// Launch `cloudflared` for the given tunnel.
    /// - Returns: the OS process identifier.
    @discardableResult
    func run(
        tunnelID: UUID,
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> Int32 {
        // Ensure any previous process for this tunnel is gone.
        stop(tunnelID: tunnelID)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment ?? Self.defaultEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let emit = onEvent
        attach(pipe: stdoutPipe, tunnelID: tunnelID, defaultLevel: .info, emit: emit)
        attach(pipe: stderrPipe, tunnelID: tunnelID, defaultLevel: .info, emit: emit)

        process.terminationHandler = { proc in
            // Tear down handlers to release the pipes.
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            emit?(.exited(tunnelID: tunnelID, code: proc.terminationStatus))
        }

        try process.run()
        stateQueue.sync { processes[tunnelID] = process }
        return process.processIdentifier
    }

    /// Stop a tunnel's process. Sends SIGINT for a graceful cloudflared shutdown,
    /// falling back to SIGTERM.
    func stop(tunnelID: UUID) {
        let process: Process? = stateQueue.sync {
            let p = processes[tunnelID]
            processes[tunnelID] = nil
            return p
        }
        guard let process, process.isRunning else { return }
        // SIGINT == graceful for cloudflared.
        process.interrupt()
    }

    func isRunning(tunnelID: UUID) -> Bool {
        stateQueue.sync { processes[tunnelID]?.isRunning ?? false }
    }

    /// Stop everything — used on app termination so we never orphan a connector.
    func stopAll() {
        let all: [Process] = stateQueue.sync {
            let values = Array(processes.values)
            processes.removeAll()
            return values
        }
        for process in all where process.isRunning {
            process.interrupt()
        }
    }

    // MARK: - Private

    private func attach(
        pipe: Pipe,
        tunnelID: UUID,
        defaultLevel: LogLevel,
        emit: (@Sendable (ProcessEvent) -> Void)?
    ) {
        let lineBuffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                if let remainder = lineBuffer.flush() {
                    emit?(.line(tunnelID: tunnelID, level: defaultLevel, text: remainder))
                }
                return
            }
            for line in lineBuffer.append(data) where !line.isEmpty {
                let level = Self.classify(line)
                emit?(.line(tunnelID: tunnelID, level: level, text: line))
            }
        }
    }

    private static func classify(_ line: String) -> LogLevel {
        if TunnelInputParsing.indicatesError(line) { return .error }
        if TunnelInputParsing.indicatesConnected(line) { return .success }
        let l = line.lowercased()
        if l.contains("level=warn") || l.contains("warning") { return .warning }
        return .info
    }

    /// A clean environment with a PATH that includes Homebrew, plus HOME so
    /// cloudflared can find `~/.cloudflared`.
    private static func defaultEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        if let existing = env["PATH"], !existing.isEmpty {
            env["PATH"] = extraPaths + ":" + existing
        } else {
            env["PATH"] = extraPaths
        }
        return env
    }
}
