import Foundation
import KuroLibrary

// MARK: - AppConfig
// Reads configuration from Info.plist or environment variables.
// Add the following keys to your target's Info.plist (or supply via scheme env vars):
// - SUPABASE_URL (String)
// - SUPABASE_ANON_KEY (String)
struct AppConfig {
    /// Public/native MAL registration is supplied by the operator after its callback and
    /// secret-free client type have been checked. Missing registration keeps OAuth unavailable.
    static var malNativeRegistration: MALNativeRegistration? {
        guard let clientId = configuredValue("MAL_CLIENT_ID"), clientId.utf8.count <= 256,
              let approved = configuredValue("MAL_REGISTRATION_APPROVED"),
              ["YES", "TRUE", "1"].contains(approved.uppercased()),
              let callback = configuredValue("MAL_REDIRECT_URI"),
              callback == "kuro://mal/callback",
              let redirectURL = URL(string: callback),
              let authorizationURL = URL(string: "https://myanimelist.net/v1/oauth2/authorize"),
              let tokenURL = URL(string: "https://myanimelist.net/v1/oauth2/token") else { return nil }
        return MALNativeRegistration(clientId: clientId, authorizationURL: authorizationURL,
            tokenURL: tokenURL, redirectURL: redirectURL, challengeMethod: .plain, qualified: true)
    }

    private static func configuredValue(_ key: String) -> String? {
        let candidates = [Bundle.main.object(forInfoDictionaryKey: key) as? String,
                          ProcessInfo.processInfo.environment[key]]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.contains("$(") }
    }

    static var supabaseURL: URL? {
        if let urlString = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: urlString), !urlString.isEmpty {
            return url
        }
        if let urlString = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let url = URL(string: urlString), !urlString.isEmpty {
            return url
        }
        return nil
    }

    static var supabaseAnonKey: String? {
        if let key = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"], !key.isEmpty {
            return key
        }
        return nil
    }
}
