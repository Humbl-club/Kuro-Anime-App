import Foundation

// MARK: - AppConfig
// Reads configuration from Info.plist or environment variables.
// Add the following keys to your target's Info.plist (or supply via scheme env vars):
// - SUPABASE_URL (String)
// - SUPABASE_ANON_KEY (String)
struct AppConfig {
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

