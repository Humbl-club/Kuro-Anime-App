// MARK: - Deep Link Router
// Parses kuro:// scheme URLs into navigation actions.
// Universal links (applinks:kuro.app) will resolve through the same enum
// once the AASA file is served on the domain.

import Foundation

/// What a `kuro://auth/callback` link carries (spec D12). Supabase's PKCE flow (the SDK default)
/// redirects with `?code=…`; the implicit flow with `#access_token=…&refresh_token=…&type=…`; a failed
/// or expired link with `error` / `error_code` / `error_description` (query or fragment). The router
/// only parses: `AuthCallbackGuard` decides what may be applied.
nonisolated struct AuthCallbackPayload: Equatable, Sendable {
    /// PKCE authorization code (`?code=`), exchanged with this device's code verifier.
    var code: String? = nil
    /// Implicit-flow token pair; both present or both nil.
    var accessToken: String? = nil
    var refreshToken: String? = nil
    /// The flow the link belongs to (`recovery`, `magiclink`, `signup`, ...), when the link says.
    var type: String? = nil
    /// GoTrue's machine code for a failed link (e.g. `otp_expired`), or the OAuth `error`.
    var errorCode: String? = nil
    var errorDescription: String? = nil

    /// True when the link reports a failure and carries nothing to apply.
    var isErrorOnly: Bool { errorCode != nil && code == nil && accessToken == nil }
    /// True when the link carries an implicit-flow token pair.
    var hasTokens: Bool { accessToken != nil && refreshToken != nil }
}

nonisolated enum DeepLink: Equatable {
    case anime(id: Int)
    case manga(id: Int)
    case club(id: String)
    case joinClub(code: String)
    case collection
    case discover
    case concierge(prompt: String?)
    case authCallback(AuthCallbackPayload)

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
    /// - `kuro://auth/callback?code=...`  (Supabase PKCE redirect, the SDK default)
    /// - `kuro://auth/callback#access_token=...&refresh_token=...&type=...`  (implicit fragment redirect)
    /// - `kuro://auth/callback?access_token=...&refresh_token=...`  (legacy edge function fallback)
    /// - `kuro://auth/callback?error=...&error_code=...&error_description=...`  (failed/expired link)
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
            let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment
            return Self.authCallbackPayload(fragment: fragment, queryItems: queryItems).map { .authCallback($0) }
        default:
            return nil
        }
    }

    /// The auth-callback payload, or nil when the link carries neither a code, a complete token
    /// pair nor an error. Query and fragment are both read through `URLComponents` (so values that
    /// contain `=` survive); a fragment value wins over the same query key. `fragment` is the
    /// percent-encoded fragment; one that is not valid percent-encoding is ignored (never trapped on).
    static func authCallbackPayload(fragment: String?, queryItems: [URLQueryItem]?) -> AuthCallbackPayload? {
        var params: [String: String] = [:]
        for item in queryItems ?? [] {
            if let value = item.value, !value.isEmpty { params[item.name] = value }
        }
        if let fragment, !fragment.isEmpty, let components = URLComponents(string: "kuro://callback?" + fragment) {
            for item in components.queryItems ?? [] {
                if let value = item.value, !value.isEmpty { params[item.name] = value }
            }
        }
        var payload = AuthCallbackPayload()
        payload.code = params["code"]
        if let access = params["access_token"], let refresh = params["refresh_token"] {
            payload.accessToken = access
            payload.refreshToken = refresh
        }
        payload.type = params["type"]?.lowercased()
        payload.errorCode = params["error_code"] ?? params["error"]
        payload.errorDescription = params["error_description"]
        guard payload.code != nil || payload.hasTokens || payload.errorCode != nil else { return nil }
        return payload
    }
}
