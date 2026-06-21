import Foundation

/// Persists the tunnel list and settings as JSON under Application Support.
/// No secrets are written here — API/connector tokens live in the Keychain.
struct TunnelStore {
    let directory: URL
    private let tunnelsURL: URL
    private let settingsURL: URL

    init(appName: String = "CloudflareTunnelManager") {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(appName, isDirectory: true)
        self.directory = base
        self.tunnelsURL = base.appendingPathComponent("tunnels.json")
        self.settingsURL = base.appendingPathComponent("settings.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // MARK: Tunnels

    func loadTunnels() -> [TunnelConfigDTO] {
        guard let data = try? Data(contentsOf: tunnelsURL) else { return [] }
        return (try? JSONDecoder().decode([TunnelConfigDTO].self, from: data)) ?? []
    }

    func saveTunnels(_ tunnels: [TunnelConfigDTO]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tunnels) else { return }
        try? data.write(to: tunnelsURL, options: .atomic)
    }

    // MARK: Settings

    func loadSettings() -> AppSettingsDTO? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(AppSettingsDTO.self, from: data)
    }

    func saveSettings(_ settings: AppSettingsDTO) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }
}
