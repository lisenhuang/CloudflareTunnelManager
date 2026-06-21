import Foundation

/// Minimal async client for the Cloudflare REST API (`/client/v4`).
///
/// Auth model (important): Cloudflare does **not** offer an end-user OAuth2 flow
/// for REST API access. We authenticate with a **scoped API token** (Bearer),
/// stored in the Keychain. Required token permissions:
///   • Account → Cloudflare Tunnel → Edit
///   • Zone → DNS → Edit
///   • Zone → Zone → Read
final class CloudflareAPIClient {
    private let baseURL = URL(string: "https://api.cloudflare.com/client/v4")!
    private let session: URLSession
    /// Supplies the current API token (read from the Keychain on each call so a
    /// token change takes effect immediately).
    private let tokenProvider: @Sendable () -> String?

    init(session: URLSession = .shared, tokenProvider: @escaping @Sendable () -> String?) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - High-level operations

    /// Verify the token and resolve the primary account in one shot.
    func accountSummary() async throws -> CloudflareAccount {
        let verification = try await verifyToken()
        let accounts = try await listAccounts()
        guard let account = accounts.first else { throw CloudflareAPIError.noAccounts }
        return CloudflareAccount(
            tokenID: verification.id,
            accountID: account.id,
            accountName: account.name
        )
    }

    func verifyToken() async throws -> CFTokenVerification {
        try await request(method: "GET", path: "/user/tokens/verify", as: CFTokenVerification.self)
    }

    func listAccounts() async throws -> [CFAccount] {
        try await request(method: "GET", path: "/accounts?per_page=50", as: [CFAccount].self)
    }

    func listZones() async throws -> [CFZone] {
        try await request(method: "GET", path: "/zones?per_page=50", as: [CFZone].self)
    }

    /// Create a remotely-managed (`config_src: cloudflare`) named tunnel.
    /// Remote config lets us push ingress rules via the API and run the connector
    /// with just `--token`, so no local cert.pem or credentials file is needed.
    func createTunnel(accountID: String, name: String) async throws -> CFTunnel {
        let body: [String: Any] = ["name": name, "config_src": "cloudflare"]
        return try await request(
            method: "POST",
            path: "/accounts/\(accountID)/cfd_tunnel",
            body: body,
            as: CFTunnel.self
        )
    }

    /// Fetch the connector token used to run the tunnel (`cloudflared tunnel run --token`).
    func tunnelToken(accountID: String, tunnelID: String) async throws -> String {
        try await request(
            method: "GET",
            path: "/accounts/\(accountID)/cfd_tunnel/\(tunnelID)/token",
            as: String.self
        )
    }

    /// Push the ingress configuration (which hostname maps to which local service).
    func putTunnelConfiguration(
        accountID: String,
        tunnelID: String,
        hostname: String,
        service: String
    ) async throws {
        let body: [String: Any] = [
            "config": [
                "ingress": [
                    ["hostname": hostname, "service": service],
                    ["service": "http_status:404"]
                ]
            ]
        ]
        try await requestVoid(
            method: "PUT",
            path: "/accounts/\(accountID)/cfd_tunnel/\(tunnelID)/configurations",
            body: body
        )
    }

    /// Create the proxied CNAME that routes `hostname` → `<tunnelID>.cfargotunnel.com`.
    @discardableResult
    func createDNSRecord(zoneID: String, hostname: String, tunnelID: String) async throws -> CFDNSRecord {
        let body: [String: Any] = [
            "type": "CNAME",
            "name": hostname,
            "content": "\(tunnelID).cfargotunnel.com",
            "proxied": true,
            "comment": "Created by Cloudflare Tunnel Manager"
        ]
        return try await request(
            method: "POST",
            path: "/zones/\(zoneID)/dns_records",
            body: body,
            as: CFDNSRecord.self
        )
    }

    func deleteTunnel(accountID: String, tunnelID: String) async throws {
        try await requestVoid(
            method: "DELETE",
            path: "/accounts/\(accountID)/cfd_tunnel/\(tunnelID)",
            body: nil
        )
    }

    // MARK: - Request plumbing

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]? = nil,
        as type: T.Type
    ) async throws -> T {
        let (data, status) = try await perform(method: method, path: path, body: body)
        try Self.throwIfHTTPError(status: status, data: data)

        let decoder = JSONDecoder()
        let envelope: CFResponse<T>
        do {
            envelope = try decoder.decode(CFResponse<T>.self, from: data)
        } catch {
            throw CloudflareAPIError.decoding("\(error)")
        }
        guard envelope.success else { throw CloudflareAPIError.cloudflare(envelope.errors) }
        guard let result = envelope.result else { throw CloudflareAPIError.noResult }
        return result
    }

    private func requestVoid(method: String, path: String, body: [String: Any]?) async throws {
        let (data, status) = try await perform(method: method, path: path, body: body)
        try Self.throwIfHTTPError(status: status, data: data)
        // We still parse the envelope to surface logical (success=false) errors.
        if let envelope = try? JSONDecoder().decode(CFResponse<EmptyResult>.self, from: data),
           !envelope.success {
            throw CloudflareAPIError.cloudflare(envelope.errors)
        }
    }

    private func perform(
        method: String,
        path: String,
        body: [String: Any]?
    ) async throws -> (Data, Int) {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw CloudflareAPIError.missingToken
        }
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw CloudflareAPIError.http(status: 0, body: "Bad URL: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private static func throwIfHTTPError(status: Int, data: Data) throws {
        guard !(200...299).contains(status) else { return }
        // Prefer Cloudflare's structured errors if present.
        if let envelope = try? JSONDecoder().decode(CFResponse<EmptyResult>.self, from: data),
           !envelope.errors.isEmpty {
            throw CloudflareAPIError.cloudflare(envelope.errors)
        }
        let bodyText = String(data: data, encoding: .utf8) ?? ""
        throw CloudflareAPIError.http(status: status, body: String(bodyText.prefix(300)))
    }

    private struct EmptyResult: Decodable {}
}
