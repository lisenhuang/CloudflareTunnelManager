import Foundation
import Observation

/// User-configurable settings. Observable for live binding in the Settings UI;
/// persisted as `AppSettingsDTO` to Application Support.
@Observable
final class AppSettings {
    /// Default local port pre-filled in the Create sheet.
    var defaultLocalPort: Int
    /// Default zone/domain suffix for named tunnels, e.g. `dev.example.com`.
    var defaultDomainSuffix: String
    /// Register the app as a login item so tunnels can resume on boot.
    var autoStartOnLogin: Bool
    /// Explicit path to the `cloudflared` binary; empty means auto-detect.
    var cloudflaredPathOverride: String
    /// Maximum log lines retained per tunnel (ring buffer).
    var logBufferSize: Int
    /// Re-launch tunnels that were running when the app last quit.
    var restoreRunningTunnelsOnLaunch: Bool

    init(
        defaultLocalPort: Int = 3000,
        defaultDomainSuffix: String = "",
        autoStartOnLogin: Bool = false,
        cloudflaredPathOverride: String = "",
        logBufferSize: Int = 2000,
        restoreRunningTunnelsOnLaunch: Bool = false
    ) {
        self.defaultLocalPort = defaultLocalPort
        self.defaultDomainSuffix = defaultDomainSuffix
        self.autoStartOnLogin = autoStartOnLogin
        self.cloudflaredPathOverride = cloudflaredPathOverride
        self.logBufferSize = logBufferSize
        self.restoreRunningTunnelsOnLaunch = restoreRunningTunnelsOnLaunch
    }

    var dto: AppSettingsDTO {
        AppSettingsDTO(
            defaultLocalPort: defaultLocalPort,
            defaultDomainSuffix: defaultDomainSuffix,
            autoStartOnLogin: autoStartOnLogin,
            cloudflaredPathOverride: cloudflaredPathOverride,
            logBufferSize: logBufferSize,
            restoreRunningTunnelsOnLaunch: restoreRunningTunnelsOnLaunch
        )
    }

    func apply(_ dto: AppSettingsDTO) {
        defaultLocalPort = dto.defaultLocalPort
        defaultDomainSuffix = dto.defaultDomainSuffix
        autoStartOnLogin = dto.autoStartOnLogin
        cloudflaredPathOverride = dto.cloudflaredPathOverride
        logBufferSize = dto.logBufferSize
        restoreRunningTunnelsOnLaunch = dto.restoreRunningTunnelsOnLaunch
    }
}

struct AppSettingsDTO: Codable, Sendable {
    var defaultLocalPort: Int
    var defaultDomainSuffix: String
    var autoStartOnLogin: Bool
    var cloudflaredPathOverride: String
    var logBufferSize: Int
    var restoreRunningTunnelsOnLaunch: Bool
}
