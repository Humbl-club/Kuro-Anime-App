// MARK: - Deep Link Router
// Parses kuro:// scheme URLs into navigation actions.
// Universal links (applinks:kuro.app) will resolve through the same enum
// once the AASA file is served on the domain.

import Foundation

enum DeepLink: Equatable {
    case anime(id: Int)
    case manga(id: Int)
    case club(id: String)
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
    /// - `kuro://collection`
    /// - `kuro://discover`
    /// - `kuro://concierge`
    /// - `kuro://concierge?prompt=hello`
    /// - `kuro://auth/callback?access_token=...&refresh_token=...`
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
        case "collection":
            return .collection
        case "discover":
            return .discover
        case "concierge":
            let prompt = queryItems?.first(where: { $0.name == "prompt" })?.value
            return .concierge(prompt: prompt)
        case "auth":
            guard pathComponents.first?.lowercased() == "callback",
                  let accessToken = queryItems?.first(where: { $0.name == "access_token" })?.value,
                  let refreshToken = queryItems?.first(where: { $0.name == "refresh_token" })?.value,
                  !accessToken.isEmpty, !refreshToken.isEmpty else { return nil }
            return .authCallback(accessToken: accessToken, refreshToken: refreshToken)
        default:
            return nil
        }
    }
}
