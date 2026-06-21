import Foundation
import Observation

/// The core domain model: one tunnel the user has created on this Mac.
///
/// It is an `@Observable` class so SwiftUI views update live as the process
/// status, public URL, and PID change. The *persisted* subset of its fields is
/// captured by `TunnelConfigDTO` (see `dto` / `init(dto:)`); runtime fields
/// (`status`, `pid`, `publicURL`, `lastError`) are intentionally not saved.
@Observable
final class TunnelItem: Identifiable {

    // MARK: Persisted configuration

    let id: UUID
    var name: String
    var mode: TunnelMode
    /// The local service to expose, e.g. `http://localhost:3000`.
    var localURL: String
    /// For `.named` tunnels: the public hostname, e.g. `app.dev.example.com`.
    var hostname: String?
    /// For `.named` tunnels: the cloudflared tunnel UUID returned by the API.
    var cfTunnelID: String?
    /// For `.named` tunnels: the Cloudflare zone the hostname belongs to.
    var zoneID: String?
    var autoRestart: Bool
    let createdAt: Date

    // MARK: Runtime state (not persisted)

    var status: TunnelStatus = .stopped
    var pid: Int32?
    /// The live public URL. For quick tunnels this is discovered from the process
    /// output (`*.trycloudflare.com`); for named tunnels it is `https://<hostname>`.
    var publicURL: String?
    var lastError: String?
    /// Number of consecutive auto-restart attempts (reset on a clean run).
    var restartAttempts: Int = 0

    init(
        id: UUID = UUID(),
        name: String,
        mode: TunnelMode,
        localURL: String,
        hostname: String? = nil,
        cfTunnelID: String? = nil,
        zoneID: String? = nil,
        autoRestart: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.localURL = localURL
        self.hostname = hostname
        self.cfTunnelID = cfTunnelID
        self.zoneID = zoneID
        self.autoRestart = autoRestart
        self.createdAt = createdAt
    }

    /// The best public URL to show/copy, falling back to the configured hostname.
    var displayURL: String? {
        if let publicURL, !publicURL.isEmpty { return publicURL }
        if let hostname, !hostname.isEmpty { return "https://\(hostname)" }
        return nil
    }

    // MARK: Persistence bridge

    var dto: TunnelConfigDTO {
        TunnelConfigDTO(
            id: id,
            name: name,
            mode: mode,
            localURL: localURL,
            hostname: hostname,
            cfTunnelID: cfTunnelID,
            zoneID: zoneID,
            autoRestart: autoRestart,
            createdAt: createdAt
        )
    }

    convenience init(dto: TunnelConfigDTO) {
        self.init(
            id: dto.id,
            name: dto.name,
            mode: dto.mode,
            localURL: dto.localURL,
            hostname: dto.hostname,
            cfTunnelID: dto.cfTunnelID,
            zoneID: dto.zoneID,
            autoRestart: dto.autoRestart,
            createdAt: dto.createdAt
        )
    }
}

/// Codable snapshot of a tunnel's persisted configuration.
struct TunnelConfigDTO: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var mode: TunnelMode
    var localURL: String
    var hostname: String?
    var cfTunnelID: String?
    var zoneID: String?
    var autoRestart: Bool
    var createdAt: Date
}
