// MARK: - Deep Link Router
// Parses kuro:// scheme URLs into navigation actions.
// Universal links (applinks:kuro.app) will resolve through the same enum
// once the AASA file is served on the domain.

import Foundation

enum DeepLink: Equatable {
    case anime(id: Int)
    case manga(id: Int)
    case club(id: String)
    case joinClub(code: String)
    case collection
    case discover
    case concierge(prompt: String?)
    case authCallback(accessToken: String, refreshToken: String)

    /// Parse a `kuro://` URL into a `DeepLink`.
    ///
    /// Supported formats:
    /// - `kuro://anime/12345`
    /// - `kuro://manga/67890`
    /// - `kuro://club/uuid-string`
    /// - `kuro://join/AB12CD34`
    /// - `kuro://collection`
    /// - `kuro://discover`
    /// - `kuro://concierge`
    /// - `kuro://concierge?prompt=hello`
    /// - `kuro://auth/callback#access_token=...&refresh_token=...`  (Supabase fragment redirect)
    /// - `kuro://auth/callback?access_token=...&refresh_token=...`  (edge function fallback)
    static func from(url: URL) -> DeepLink? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "kuro" else { return nil }

        let host = url.host?.lowercased() ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        switch host {
        case "anime":
            guard let first = pathComponents.first,
                  let id = Int(first) else { return nil }
            return .anime(id: id)
        case "manga":
            guard let first = pathComponents.first,
                  let id = Int(first) else { return nil }
            return .manga(id: id)
        case "club":
            guard let first = pathComponents.first, !first.isEmpty else { return nil }
            return .club(id: first)
        case "join":
            // Invite codes are 6-12 alphanumeric characters, stored uppercased.
            guard let first = pathComponents.first else { return nil }
            let code = first.uppercased()
            guard code.range(of: "^[A-Z0-9]{6,12}$", options: .regularExpression) != nil else { return nil }
            return .joinClub(code: code)
        case "collection":
            return .collection
        case "discover":
            return .discover
        case "concierge":
            let prompt = queryItems?.first(where: { $0.name == "prompt" })?.value
            return .concierge(prompt: prompt)
        case "auth":
            guard pathComponents.first?.lowercased() == "callback" else { return nil }
            // Supabase sends tokens in the URL fragment (#access_token=...&refresh_token=...).
            // The edge function fallback sends them as query params (?access_token=...).
            // Parse both so either path works.
            let params = Self.parseAuthParams(fragment: url.fragment, queryItems: queryItems)
            guard let accessToken = params["access_token"],
                  let refreshToken = params["refresh_token"],
                  !accessToken.isEmpty, !refreshToken.isEmpty else { return nil }
            return .authCallback(accessToken: accessToken, refreshToken: refreshToken)
        default:
            return nil
        }
    }

    /// Extract key-value pairs from either the URL fragment or query items.
    /// Fragment takes priority (direct Supabase redirect), query is fallback (edge function).
    private static func parseAuthParams(fragment: String?, queryItems: [URLQueryItem]?) -> [String: String] {
        // Try fragment first (e.g. "access_token=abc&refresh_token=def&type=signup")
        if let fragment, !fragment.isEmpty {
            var params: [String: String] = [:]
            for pair in fragment.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2, let key = kv[0].removingPercentEncoding,
                   let value = kv[1].removingPercentEncoding {
                    params[key] = value
                }
            }
            if params["access_token"] != nil { return params }
        }
        // Fallback to query params
        var params: [String: String] = [:]
        for item in queryItems ?? [] {
            if let value = item.value { params[item.name] = value }
        }
        return params
    }
}
