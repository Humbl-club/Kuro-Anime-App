import Foundation
import Supabase

// MARK: - Supabase Service
// Single source of truth for all database operations

@MainActor
class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    // Supabase client
    private let client: SupabaseClient
    
    // Published properties
    @Published var mediaItems: [Media] = []
    @Published var userLists: [UserList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init() {
        // Initialize Supabase client
        // TODO: Replace with your actual Supabase URL and anon key
        client = SupabaseClient(
            supabaseURL: URL(string: "https://your-project.supabase.co")!,
            supabaseKey: "your-anon-key"
        )
    }
    
    // MARK: - Authentication
    func signInAnonymously() async throws {
        // Supabase anonymous authentication
        try await client.auth.signInAnonymously()
        print("✅ Signed in anonymously to Supabase")
    }
    
    func signInWithEmail(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
        print("✅ Signed in with email")
    }
    
    // MARK: - Fetch Media
    func fetchMedia(type: MediaType? = nil, limit: Int = 50) async {
        isLoading = true
        errorMessage = nil
        
        do {
            var query = client.database
                .from("media")
                .select()
                .order("created_at", ascending: false)
                .limit(limit)
            
            if let type = type {
                query = query.eq("type", value: type.rawValue)
            }
            
            let response: [Media] = try await query.execute().value
            mediaItems = response
            print("✅ Fetched \(response.count) media items from Supabase")
        } catch {
            errorMessage = "Failed to fetch media: \(error.localizedDescription)"
            print("❌ Supabase error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Search
    func searchMedia(query: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response: [Media] = try await client.database
                .from("media")
                .select()
                .ilike("title", pattern: "%\(query)%")
                .execute()
                .value
            
            mediaItems = response
            print("✅ Found \(response.count) results")
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("❌ Search error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - User Lists
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
    
    // MARK: - Add to List
    func addToList(mediaId: String, listType: String) async {
        guard let userId = try? await client.auth.session.user.id else { return }
        
        do {
            let listData: [String: Any] = [
                "user_id": userId.uuidString,
                "media_id": mediaId,
                "list_type": listType,
                "created_at": ISO8601DateFormatter().string(from: Date())
            ]
            
            try await client.database
                .from("user_lists")
                .insert(listData)
                .execute()
            
            await fetchUserLists()
            print("✅ Added to list")
        } catch {
            errorMessage = "Failed to add to list: \(error.localizedDescription)"
            print("❌ Error: \(error)")
        }
    }
    
    // MARK: - Real-time Subscriptions
    func subscribeToMediaUpdates() {
        // Supabase real-time subscriptions
        Task {
            for await change in client.database
                .from("media")
                .on(.all) { event in
                    print("🔄 Real-time update: \(event)")
                    Task {
                        await self.fetchMedia()
                    }
                } {
                // Handle subscription
            }
        }
    }
}
