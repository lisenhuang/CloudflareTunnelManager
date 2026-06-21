import Foundation
import Observation
import AppKit
import ServiceManagement

/// The single source of truth and orchestrator for the whole app. MainActor so
/// all UI-facing state mutates on the main thread; background process events are
/// hopped onto the MainActor before touching anything here.
@MainActor
@Observable
final class AppState {

    // MARK: Published state
    var tunnels: [TunnelItem] = []
    let settings = AppSettings()
    var installation: CloudflaredInstallation = .notInstalled
    var account: CloudflareAccount?
    var selectedTunnelID: UUID?

    // Transient UI state
    var accountError: String?
    var actionError: String?
    var isVerifyingAccount = false
    var isInstalling = false
    var installLog: [String] = []

    // MARK: Services
    let logStore = LogStore()
    private let keychain = KeychainStore()
    private let store = TunnelStore()
    private let processService = CloudflaredProcessService()
    private let installer = InstallationService()
    private let apiClient: CloudflareAPIClient

    // Auto-restart bookkeeping
    private var userStopped = Set<UUID>()
    private let maxRestartAttempts = 5

    // MARK: Init

    init() {
        let kc = keychain
        self.apiClient = CloudflareAPIClient(tokenProvider: {
            kc.get(account: KeychainStore.apiTokenAccount)
        })

        processService.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }

        loadPersistedState()
    }

    // MARK: Lifecycle

    /// Called once at launch (after the scene appears).
    func bootstrap() async {
        refreshInstallation()
        logStore.bufferSize = settings.logBufferSize
        if hasAPIToken {
            await refreshAccount()
        }
        if settings.restoreRunningTunnelsOnLaunch {
            // (Restoration of previously-running tunnels would go here; the running
            // state is intentionally not persisted in the MVP.)
        }
    }

    /// Called on app termination — never orphan a connector process.
    func shutdown() {
        processService.stopAll()
    }

    // MARK: Installation

    var isCloudflaredInstalled: Bool { installation.isInstalled }
    var isHomebrewAvailable: Bool { installer.isHomebrewAvailable }

    func refreshInstallation() {
        installation = installer.detect(override: settings.cloudflaredPathOverride)
    }

    func installCloudflared() async {
        guard !isInstalling else { return }
        isInstalling = true
        installLog.removeAll()
        defer { isInstalling = false }

        let success = await installer.installViaHomebrew { [weak self] line in
            Task { @MainActor in self?.installLog.append(line) }
        }
        refreshInstallation()
        installLog.append(success && isCloudflaredInstalled
                          ? "✓ cloudflared installed: \(installation.version ?? "")"
                          : "✗ Installation did not complete.")
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(InstallationService.downloadPageURL)
    }

    // MARK: Account / token

    var hasAPIToken: Bool { keychain.has(account: KeychainStore.apiTokenAccount) }

    func saveAPIToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keychain.set(trimmed, account: KeychainStore.apiTokenAccount)
        await refreshAccount()
    }

    func refreshAccount() async {
        guard hasAPIToken else { account = nil; return }
        isVerifyingAccount = true
        accountError = nil
        defer { isVerifyingAccount = false }
        do {
            account = try await apiClient.accountSummary()
        } catch {
            account = nil
            accountError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        keychain.delete(account: KeychainStore.apiTokenAccount)
        account = nil
        accountError = nil
    }

    // MARK: Create tunnels

    /// Quick tunnel: zero-config, no auth. Adds and immediately starts it.
    func createQuickTunnel(name: String, localURL: String, start startNow: Bool = true) {
        let resolved = TunnelInputParsing.normalizeLocalURL(localURL) ?? localURL
        let item = TunnelItem(
            name: name.isEmpty ? "Quick Tunnel" : name,
            mode: .quick,
            localURL: resolved
        )
        tunnels.append(item)
        persistTunnels()
        if startNow { start(item) }
    }

    /// Named tunnel: API-driven (create tunnel → push ingress → DNS route), then
    /// runs the connector with `--token`. Throws so the UI can show errors.
    func createNamedTunnel(name: String, localURL: String, hostname: String, start startNow: Bool = true) async throws {
        let resolved = TunnelInputParsing.normalizeLocalURL(localURL) ?? localURL
        let host = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let summary = try await ensureAccount()

        let zones = try await apiClient.listZones()
        guard let zone = TunnelInputParsing.matchingZone(for: host, in: zones) else {
            throw CloudflareAPIError.zoneNotFound(host)
        }

        let cfTunnel = try await apiClient.createTunnel(
            accountID: summary.accountID,
            name: name.isEmpty ? host : name
        )
        let token: String
        if let inlineToken = cfTunnel.token, !inlineToken.isEmpty {
            token = inlineToken
        } else {
            token = try await apiClient.tunnelToken(accountID: summary.accountID, tunnelID: cfTunnel.id)
        }

        try await apiClient.putTunnelConfiguration(
            accountID: summary.accountID,
            tunnelID: cfTunnel.id,
            hostname: host,
            service: resolved
        )
        try await apiClient.createDNSRecord(zoneID: zone.id, hostname: host, tunnelID: cfTunnel.id)

        let item = TunnelItem(
            name: name.isEmpty ? host : name,
            mode: .named,
            localURL: resolved,
            hostname: host,
            cfTunnelID: cfTunnel.id,
            zoneID: zone.id
        )
        keychain.set(token, account: KeychainStore.connectorTokenAccount(for: item.id))
        tunnels.append(item)
        persistTunnels()
        logStore.append(tunnelID: item.id, level: .success, "Created named tunnel \(host) → \(resolved)")
        if startNow { start(item) }
    }

    private func ensureAccount() async throws -> CloudflareAccount {
        if let account { return account }
        let summary = try await apiClient.accountSummary()
        account = summary
        return summary
    }

    // MARK: Process control

    func start(_ tunnel: TunnelItem) {
        guard !tunnel.status.isActive else { return }
        guard let path = installation.path else {
            tunnel.status = .error("cloudflared is not installed.")
            logStore.append(tunnelID: tunnel.id, level: .error, "Cannot start: cloudflared not found.")
            return
        }

        userStopped.remove(tunnel.id)
        tunnel.lastError = nil
        tunnel.status = .starting

        let args: [String]
        switch tunnel.mode {
        case .quick:
            args = ["tunnel", "--url", tunnel.localURL, "--no-autoupdate"]
        case .named:
            guard let token = keychain.get(account: KeychainStore.connectorTokenAccount(for: tunnel.id)) else {
                tunnel.status = .error("Missing connector token — recreate this tunnel.")
                logStore.append(tunnelID: tunnel.id, level: .error, "No connector token in Keychain.")
                return
            }
            tunnel.publicURL = tunnel.hostname.map { "https://\($0)" }
            args = ["tunnel", "run", "--token", token, "--no-autoupdate"]
        }

        logStore.append(tunnelID: tunnel.id, level: .command, "cloudflared \(redact(args))")
        do {
            let pid = try processService.run(tunnelID: tunnel.id, executablePath: path, arguments: args)
            tunnel.pid = pid
            logStore.append(tunnelID: tunnel.id, level: .info, "Process started (pid \(pid)).")
        } catch {
            tunnel.status = .error(error.localizedDescription)
            tunnel.pid = nil
            logStore.append(tunnelID: tunnel.id, level: .error, "Launch failed: \(error.localizedDescription)")
        }
    }

    func stop(_ tunnel: TunnelItem) {
        guard tunnel.status.isActive else { return }
        userStopped.insert(tunnel.id)
        tunnel.status = .stopping
        processService.stop(tunnelID: tunnel.id)
        logStore.append(tunnelID: tunnel.id, level: .info, "Stopping…")
    }

    func restart(_ tunnel: TunnelItem) {
        let id = tunnel.id
        if tunnel.status.isActive {
            stop(tunnel)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if let t = self.tunnel(with: id) { self.start(t) }
            }
        } else {
            start(tunnel)
        }
    }

    func delete(_ tunnel: TunnelItem) {
        let id = tunnel.id
        if tunnel.status.isActive { stop(tunnel) }
        tunnels.removeAll { $0.id == id }
        if selectedTunnelID == id { selectedTunnelID = tunnels.first?.id }
        keychain.delete(account: KeychainStore.connectorTokenAccount(for: id))
        persistTunnels()

        // Best-effort remote cleanup for named tunnels.
        if tunnel.mode == .named, let cfID = tunnel.cfTunnelID, let acct = account?.accountID {
            let client = apiClient
            Task {
                try? await client.deleteTunnel(accountID: acct, tunnelID: cfID)
            }
        }
    }

    func toggle(_ tunnel: TunnelItem) {
        tunnel.status.isActive ? stop(tunnel) : start(tunnel)
    }

    // MARK: Clipboard / open

    func copyURL(_ tunnel: TunnelItem) {
        guard let url = tunnel.displayURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url, forType: .string)
    }

    func openInBrowser(_ tunnel: TunnelItem) {
        guard let urlString = tunnel.displayURL, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Settings persistence

    func persistSettings() {
        store.saveSettings(settings.dto)
        logStore.bufferSize = settings.logBufferSize
        refreshInstallation()
    }

    func updateLoginItem() {
        do {
            if settings.autoStartOnLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logStore.append(tunnelID: nil, level: .warning,
                            "Could not update login item: \(error.localizedDescription)")
        }
    }

    // MARK: Derived

    var runningCount: Int { tunnels.filter { $0.status == .running }.count }

    func tunnel(with id: UUID?) -> TunnelItem? {
        guard let id else { return nil }
        return tunnels.first { $0.id == id }
    }

    var selectedTunnel: TunnelItem? { tunnel(with: selectedTunnelID) }

    // MARK: Event handling (from background process)

    private func handle(_ event: ProcessEvent) {
        switch event {
        case let .line(id, level, text):
            logStore.append(tunnelID: id, level: level, text)
            guard let tunnel = tunnel(with: id) else { return }
            if tunnel.mode == .quick, let url = TunnelInputParsing.extractTryCloudflareURL(from: text) {
                tunnel.publicURL = url
                tunnel.status = .running
                tunnel.restartAttempts = 0
                logStore.append(tunnelID: id, level: .success, "Public URL ready: \(url)")
            } else if TunnelInputParsing.indicatesConnected(text) {
                if tunnel.status == .starting { tunnel.status = .running }
                tunnel.restartAttempts = 0
            }

        case let .exited(id, code):
            handleExit(id: id, code: code)
        }
    }

    private func handleExit(id: UUID, code: Int32) {
        guard let tunnel = tunnel(with: id) else { return }
        tunnel.pid = nil

        if userStopped.remove(id) != nil {
            tunnel.status = .stopped
            logStore.append(tunnelID: id, level: .info, "Stopped.")
            return
        }

        if code == 0 {
            tunnel.status = .stopped
            logStore.append(tunnelID: id, level: .info, "Process exited cleanly.")
        } else {
            tunnel.status = .error("cloudflared exited (code \(code))")
            tunnel.lastError = "Exited with code \(code)"
            logStore.append(tunnelID: id, level: .error, "Process exited unexpectedly (code \(code)).")
        }

        guard tunnel.autoRestart, tunnel.restartAttempts < maxRestartAttempts else { return }
        let attempt = tunnel.restartAttempts + 1
        tunnel.restartAttempts = attempt
        let delay = min(pow(2.0, Double(attempt)), 30.0)
        logStore.append(tunnelID: id, level: .warning,
                        "Auto-restarting in \(Int(delay))s (attempt \(attempt)/\(maxRestartAttempts))…")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let t = self.tunnel(with: id), !t.status.isActive,
                  !self.userStopped.contains(id) else { return }
            self.start(t)
        }
    }

    // MARK: Persistence helpers

    private func loadPersistedState() {
        if let dto = store.loadSettings() { settings.apply(dto) }
        logStore.bufferSize = settings.logBufferSize
        tunnels = store.loadTunnels().map(TunnelItem.init(dto:))
        selectedTunnelID = tunnels.first?.id
    }

    func persistTunnels() {
        store.saveTunnels(tunnels.map(\.dto))
    }

    private func redact(_ args: [String]) -> String {
        var out = args
        if let i = out.firstIndex(of: "--token"), i + 1 < out.count {
            out[i + 1] = "••••••••"
        }
        return out.joined(separator: " ")
    }
}
