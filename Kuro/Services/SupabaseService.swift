import Foundation
import Supabase

// MARK: - Supabase Service
// Connects to your existing comprehensive database schema

@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()
    
    // Supabase client
    private let client: SupabaseClient
    
    // Observable properties (no @Published needed with @Observable)
    var animeItems: [Anime] = []
    var mangaItems: [Manga] = []
    var userLists: [UserList] = []
    var episodes: [Episode] = []
    var isLoading = false
    var errorMessage: String?
    
    init() {
        // Initialize Supabase client with your credentials
        client = SupabaseClient(
            supabaseURL: URL(string: "https://bkdifromsqxkndnllmdj.supabase.co")!,
            supabaseKey: "sb_secret_EWNiKfUMBcUtWJWsNkzDag_ao1RiZw2"
        )
        print("🔥 Supabase client initialized for project: bkdifromsqxkndnllmdj")
        
        // Auto-initialize on app launch
        Task {
            do {
                try await signInAnonymously()
                await fetchAnime(limit: 20) // Load initial data
            } catch {
                print("❌ Auto-initialization failed: \(error)")
            }
        }
    }
    
    // MARK: - Authentication
    func signInAnonymously() async throws {
        try await client.auth.signInAnonymously()
        print("✅ Signed in anonymously to Supabase")
    }
    
    // MARK: - Fetch Anime (from your existing table)
    func fetchAnime(limit: Int = 50) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response: [Anime] = try await client.database
                .from("anime")
                .select()
                .order("popularity", ascending: false)
                .limit(limit)
                .execute()
                .value
            
            animeItems = response
            print("✅ Fetched \(response.count) anime from your database")
        } catch {
            errorMessage = "Failed to fetch anime: \(error.localizedDescription)"
            print("❌ Supabase error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Fetch Manga (from your existing table)
    func fetchManga(limit: Int = 50) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response: [Manga] = try await client.database
                .from("manga")
                .select()
                .order("popularity", ascending: false)
                .limit(limit)
                .execute()
                .value
            
            mangaItems = response
            print("✅ Fetched \(response.count) manga from your database")
        } catch {
            errorMessage = "Failed to fetch manga: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Search (using your full-text search index)
    func searchContent(query: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Search anime using your full-text search index
            let animeResponse: [Anime] = try await client.database
                .from("anime")
                .select()
                .textSearch("title_english,title_romaji,description_normalized", query: query)
                .execute()
                .value
            
            // Search manga
            let mangaResponse: [Manga] = try await client.database
                .from("manga")
                .select()
                .textSearch("title_english,title_romaji,description", query: query)
                .execute()
                .value
            
            animeItems = animeResponse
            mangaItems = mangaResponse
            print("✅ Found \(animeResponse.count) anime, \(mangaResponse.count) manga")
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("❌ Search error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - User Lists (using your existing structure)
    func fetchUserLists() async {
        guard let userId = try? await client.auth.session.user.id else { return }
        
        do {
            let response: [UserList] = try await client.database
                .from("user_lists")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            userLists = response
            print("✅ Fetched \(response.count) user lists")
        } catch {
            errorMessage = "Failed to fetch lists: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
    }
    
    // MARK: - Add to List (using your existing structure)
    func addToList(mediaId: Int, mediaType: String, status: ListStatus) async {
        guard let userId = try? await client.auth.session.user.id else { return }
        
        do {
            // Create a proper Codable struct instead of [String: Any]
            struct ListData: Codable {
                let user_id: String
                let media_id: Int
                let media_type: String
                let status: String
                let progress: Int
                let `private`: Bool
            }
            
            let listData = ListData(
                user_id: userId.uuidString,
                media_id: mediaId,
                media_type: mediaType,
                status: status.rawValue,
                progress: 0,
                private: false
            )
            
            try await client.database
                .from("user_lists")
                .insert(listData)
                .execute()
            
            await fetchUserLists()
            print("✅ Added to \(status.displayName) list")
        } catch {
            errorMessage = "Failed to add to list: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
    }
    
    // MARK: - Filter by Genre (using your genres array)
    func filterByGenre(_ genre: String) async {
        isLoading = true
        
        do {
            let response: [Anime] = try await client.database
                .from("anime")
                .select()
                .contains("genres", value: [genre])
                .order("average_score", ascending: false)
                .limit(50)
                .execute()
                .value
            
            animeItems = response
            print("✅ Filtered by genre: \(genre)")
        } catch {
            errorMessage = "Filter failed: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Get by Mood (using your genre system)
    func getByMood(_ mood: String) -> [Anime] {
        switch mood {
        case "Contemplative":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Drama", "Psychological", "Mystery"].contains(genre)
                }) ?? false
            }
        case "Energetic":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Action", "Sports", "Adventure"].contains(genre)
                }) ?? false
            }
        case "Melancholic":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Drama", "Romance", "Slice of Life"].contains(genre)
                }) ?? false
            }
        case "Uplifting":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Comedy", "Adventure", "Music"].contains(genre)
                }) ?? false
            }
        case "Mysterious":
            return animeItems.filter { anime in
                anime.genres?.contains(where: { genre in
                    ["Thriller", "Horror", "Supernatural", "Mystery"].contains(genre)
                }) ?? false
            }
        default:
            return Array(animeItems.prefix(10))
        }
    }
    
    // MARK: - Real-time Subscriptions  
    func subscribeToUpdates() {
        // Simple polling approach - can be replaced with proper realtime when needed
        print("📡 Real-time subscription placeholder - implement based on your Supabase SDK version")
        
        // Alternative: Use a timer for periodic updates if realtime is not available
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor in
                await self.fetchAnime(limit: 20)
            }
        }
    }
}