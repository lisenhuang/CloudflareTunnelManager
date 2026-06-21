import Foundation

/// The two fundamentally different ways Cloudflare Tunnel can expose a local service.
///
/// This distinction is the central architectural insight of the app:
/// - `.quick` is the true "ngrok-like" experience: zero config, no Cloudflare
///   account, no DNS, no auth. `cloudflared tunnel --url <local>` returns a random
///   `https://<name>.trycloudflare.com` URL that lives only while the process runs.
/// - `.named` is a persistent tunnel bound to a hostname on a domain (zone) you
///   already control on Cloudflare. It requires authentication (a scoped API token)
///   and a DNS route, but the hostname is stable and reusable.
enum TunnelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case quick
    case named

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "Quick Tunnel"
        case .named: return "Named Tunnel"
        }
    }

    var shortLabel: String {
        switch self {
        case .quick: return "Quick"
        case .named: return "Named"
        }
    }

    var subtitle: String {
        switch self {
        case .quick:
            return "Instant, throwaway *.trycloudflare.com URL. No account required."
        case .named:
            return "Persistent custom hostname on your Cloudflare domain. Requires an API token."
        }
    }

    var systemImage: String {
        switch self {
        case .quick: return "bolt.fill"
        case .named: return "globe"
        }
    }
}
