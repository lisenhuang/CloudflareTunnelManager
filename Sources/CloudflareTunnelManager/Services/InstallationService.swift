import Foundation

struct CloudflaredInstallation: Equatable, Sendable {
    var path: String?
    var version: String?
    var isInstalled: Bool { path != nil }

    static let notInstalled = CloudflaredInstallation(path: nil, version: nil)
}

/// Detects `cloudflared` and can install it via Homebrew.
struct InstallationService {

    static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    static let downloadPageURL = URL(string: "https://github.com/cloudflare/cloudflared/releases/latest")!
    static let docsURL = URL(string: "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/")!

    /// Resolve the current installation, honouring a user path override.
    func detect(override: String = "") -> CloudflaredInstallation {
        guard let path = BinaryLocator.locate(override: override) else {
            return .notInstalled
        }
        return CloudflaredInstallation(path: path, version: BinaryLocator.version(at: path))
    }

    var isHomebrewAvailable: Bool {
        Self.brewPaths.contains(where: { BinaryLocator.isExecutable($0) })
    }

    var brewPath: String? {
        Self.brewPaths.first(where: { BinaryLocator.isExecutable($0) })
    }

    /// Install cloudflared via Homebrew, streaming output lines to `progress`.
    /// Returns true on success.
    func installViaHomebrew(progress: @escaping @Sendable (String) -> Void) async -> Bool {
        guard let brew = brewPath else {
            progress("Homebrew not found. Install Homebrew from https://brew.sh first.")
            return false
        }
        return await runStreaming(
            executable: brew,
            arguments: ["install", "cloudflared"],
            progress: progress
        )
    }

    // MARK: - Private

    private func runStreaming(
        executable: String,
        arguments: [String],
        progress: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = StreamLineAccumulator()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in buffer.append(data) {
                    progress(line)
                }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: proc.terminationStatus == 0)
            }

            progress("$ \(executable) \(arguments.joined(separator: " "))")
            do {
                try process.run()
            } catch {
                progress("Failed to launch installer: \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
        }
    }
}

/// Small line accumulator (the process service's LineBuffer is private to its file).
private final class StreamLineAccumulator {
    private var buffer = Data()
    func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        let newline = Data([0x0A])
        while let range = buffer.range(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                lines.append(line)
            }
        }
        return lines
    }
}
