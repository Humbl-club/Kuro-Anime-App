import Foundation

/// Thrown by the public-data owners (`CatalogStore`, `DiscoveryStore`, `SearchStore`,
/// `RecommendationsReader`) and the personal-data owners (`ReminderScheduler`, `ReleasesStore`,
/// `SocialActivityStore`, `ProviderAvailabilityStore`) when the app has no SDK client
/// (SUPABASE_URL / SUPABASE_ANON_KEY missing): each request then takes its transport-failure path
/// (empty result, nil or a thrown error).
struct MissingSupabaseConfiguration: LocalizedError {
    var errorDescription: String? { "Missing Supabase configuration." }
}
