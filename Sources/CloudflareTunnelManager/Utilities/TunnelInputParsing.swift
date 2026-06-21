import Foundation

/// Pure helpers for validating and normalising user input and for parsing
/// `cloudflared` output. Kept free of side effects so they are trivially testable.
enum TunnelInputParsing {

    /// Normalise a user-entered local target into a full URL string.
    /// Accepts: `3000`, `:3000`, `localhost:3000`, `http://localhost:3000`,
    /// `127.0.0.1:8080`, `https://localhost:8443`.
    static func normalizeLocalURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Bare port, e.g. "3000" or ":3000"
        if let port = barePort(trimmed) {
            return "http://localhost:\(port)"
        }

        // Already has a scheme.
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed) != nil ? trimmed : nil
        }

        // host:port without scheme.
        let candidate = "http://\(trimmed)"
        return URL(string: candidate) != nil ? candidate : nil
    }

    /// Returns the port if the string is just a bare port (optionally `:` prefixed).
    static func barePort(_ raw: String) -> Int? {
        var s = raw
        if s.hasPrefix(":") { s.removeFirst() }
        guard !s.isEmpty, s.allSatisfy(\.isNumber), let port = Int(s),
              (1...65535).contains(port) else { return nil }
        return port
    }

    /// Validate a hostname like `app.dev.example.com`.
    static func isValidHostname(_ raw: String) -> Bool {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        let labels = host.split(separator: ".")
        guard labels.count >= 2 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        for label in labels {
            if label.isEmpty || label.count > 63 { return false }
            if label.hasPrefix("-") || label.hasSuffix("-") { return false }
            if label.unicodeScalars.contains(where: { !allowed.contains($0) }) { return false }
        }
        return true
    }

    /// Given a hostname and a list of zones, find the zone whose name is a suffix.
    /// `app.dev.example.com` matches zone `example.com`. Prefers the longest match.
    static func matchingZone(for hostname: String, in zones: [CFZone]) -> CFZone? {
        let host = hostname.lowercased()
        return zones
            .filter { host == $0.name.lowercased() || host.hasSuffix("." + $0.name.lowercased()) }
            .max(by: { $0.name.count < $1.name.count })
    }

    /// Extract a `*.trycloudflare.com` URL from a line of cloudflared output.
    static func extractTryCloudflareURL(from line: String) -> String? {
        firstMatch(in: line, pattern: #"https://[a-zA-Z0-9-]+\.trycloudflare\.com"#)
    }

    /// Heuristic: does this output line indicate the tunnel is connected/ready?
    static func indicatesConnected(_ line: String) -> Bool {
        let l = line.lowercased()
        return l.contains("registered tunnel connection")
            || l.contains("connection registered")
            || (l.contains("connection") && l.contains("registered"))
            || l.contains("each HA connection".lowercased())
    }

    /// Heuristic: does this output line indicate a fatal error worth surfacing?
    static func indicatesError(_ line: String) -> Bool {
        let l = line.lowercased()
        return l.contains("error=") || l.contains("level=fatal") || l.contains("failed to")
            || l.contains("unauthorized") || l.contains("permission denied")
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r])
    }
}
