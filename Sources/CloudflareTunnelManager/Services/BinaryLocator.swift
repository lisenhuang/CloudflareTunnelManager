import Foundation

/// Locates the `cloudflared` binary. GUI apps launched from Finder do **not**
/// inherit the shell `PATH`, so we cannot rely on `cloudflared` being resolvable
/// by name — we must search known absolute locations (and honour a user override).
struct BinaryLocator {

    /// Common install locations, in priority order.
    static let candidatePaths = [
        "/opt/homebrew/bin/cloudflared",   // Homebrew on Apple Silicon
        "/usr/local/bin/cloudflared",      // Homebrew on Intel
        "/opt/local/bin/cloudflared",      // MacPorts
        "/usr/bin/cloudflared"
    ]

    /// Resolve the binary path, preferring an explicit override.
    /// - Parameter override: a user-specified absolute path (may be empty).
    static func locate(override: String = "") -> String? {
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, isExecutable(trimmed) {
            return trimmed
        }
        for path in candidatePaths where isExecutable(path) {
            return path
        }
        // Last resort: ask a login shell to resolve it (covers exotic installs).
        if let viaShell = resolveViaLoginShell(), isExecutable(viaShell) {
            return viaShell
        }
        return nil
    }

    static func isExecutable(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && !isDir.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    /// Run `cloudflared --version` and return the trimmed output.
    static func version(at path: String) -> String? {
        guard isExecutable(path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }

    /// Use the user's login shell to resolve `cloudflared` from their real PATH.
    private static func resolveViaLoginShell() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v cloudflared"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }
}
