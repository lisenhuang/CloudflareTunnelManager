import Foundation

// MARK: - Generic Cloudflare API envelope

/// Cloudflare's REST API wraps every response in `{ success, errors, messages, result }`.
struct CFResponse<Result: Decodable>: Decodable {
    let success: Bool
    let errors: [CFError]
    let messages: [CFMessage]?
    let result: Result?
}

struct CFError: Decodable, Sendable {
    let code: Int?
    let message: String
}

struct CFMessage: Decodable, Sendable {
    let code: Int?
    let message: String
}

/// Some list endpoints (zones, accounts) also include pagination info we ignore.
struct CFResultInfo: Decodable, Sendable {
    let page: Int?
    let count: Int?
    let totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case page, count
        case totalCount = "total_count"
    }
}

// MARK: - Token verification (/user/tokens/verify)

struct CFTokenVerification: Decodable, Sendable {
    let id: String
    let status: String
}

// MARK: - Accounts (/accounts)

struct CFAccount: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
}

// MARK: - Zones (/zones)

struct CFZone: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let status: String?
}

// MARK: - Cloudflared tunnels (/accounts/{id}/cfd_tunnel)

struct CFTunnel: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let status: String?
    /// The connector token is only present on the create response in some API
    /// versions; otherwise it is fetched from the `/token` endpoint.
    let token: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, token
    }
}

// MARK: - DNS records (/zones/{id}/dns_records)

struct CFDNSRecord: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let content: String
    let proxied: Bool?
}

// MARK: - Domain-level account summary shown in the UI

/// A flattened view of "who am I logged in as", assembled from the token
/// verification + first account.
struct CloudflareAccount: Equatable, Sendable {
    var tokenID: String
    var accountID: String
    var accountName: String

    var maskedToken: String { "Token …\(tokenID.suffix(6))" }
}

// MARK: - Errors surfaced to the UI

enum CloudflareAPIError: LocalizedError {
    case missingToken
    case http(status: Int, body: String)
    case cloudflare([CFError])
    case decoding(String)
    case noResult
    case noAccounts
    case zoneNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No Cloudflare API token is configured. Add one in Settings → Account."
        case let .http(status, body):
            return "Cloudflare API returned HTTP \(status). \(body)"
        case let .cloudflare(errors):
            return errors.map { "[\($0.code ?? 0)] \($0.message)" }.joined(separator: "; ")
        case let .decoding(detail):
            return "Could not parse Cloudflare response: \(detail)"
        case .noResult:
            return "Cloudflare returned no result."
        case .noAccounts:
            return "This token has no accounts. Check its permissions."
        case let .zoneNotFound(host):
            return "No Cloudflare zone (domain) found that covers \"\(host)\". Add the domain to Cloudflare first."
        }
    }
}
