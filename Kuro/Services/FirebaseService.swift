import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - Firebase Service
@MainActor
class FirebaseService: ObservableObject {
    private let db = Firestore.firestore()
    
    // Published properties
    @Published var mediaItems: [Media] = []
    @Published var userLists: [UserList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Collections
    private let mediaCollection = "media"
    private let listsCollection = "user_lists"
    
    init() {
        setupAuth()
    }
    
    // MARK: - Authentication
    private func setupAuth() {
        // Sign in anonymously for now
        Auth.auth().signInAnonymously { [weak self] result, error in
            if let error = error {
                self?.errorMessage = "Auth error: \(error.localizedDescription)"
            } else {
                print("✅ Signed in anonymously")
                Task {
                    await self?.loadInitialData()
                }
            }
        }
    }
    
    // MARK: - Load Data
    func loadInitialData() async {
        await loadMediaItems()
        await loadUserLists()
    }
    
    func loadMediaItems() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let snapshot = try await db.collection(mediaCollection)
                .order(by: "created_at", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            let items = snapshot.documents.compactMap { doc in
                self.convertDocumentToMedia(doc)
            }
            
            mediaItems = items
            print("✅ Loaded \(items.count) media items")
        } catch {
            errorMessage = "Failed to load media: \(error.localizedDescription)"
            print("❌ Error loading media: \(error)")
        }
        
        isLoading = false
    }
    
    func loadUserLists() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection(listsCollection)
                .whereField("user_id", isEqualTo: userId)
                .getDocuments()
            
            let lists = snapshot.documents.compactMap { doc in
                self.convertDocumentToUserList(doc)
            }
            
            userLists = lists
            print("✅ Loaded \(lists.count) user lists")
        } catch {
            errorMessage = "Failed to load lists: \(error.localizedDescription)"
            print("❌ Error loading lists: \(error)")
        }
    }
    
    // MARK: - Search & Filter
    func searchMedia(query: String, filters: SearchFilters = SearchFilters()) async {
        isLoading = true
        errorMessage = nil
        
        do {
            var firestoreQuery: Query = db.collection(mediaCollection)
            
            // Apply filters
            if let type = filters.type {
                firestoreQuery = firestoreQuery.whereField("type", isEqualTo: type.rawValue)
            }
            
            if !filters.genres.isEmpty {
                firestoreQuery = firestoreQuery.whereField("genres", arrayContainsAny: filters.genres)
            }
            
            if let yearRange = filters.yearRange {
                firestoreQuery = firestoreQuery.whereField("year", isGreaterThanOrEqualTo: yearRange.lowerBound)
                    .whereField("year", isLessThanOrEqualTo: yearRange.upperBound)
            }
            
            if let rating = filters.rating {
                firestoreQuery = firestoreQuery.whereField("rating", isGreaterThanOrEqualTo: rating)
            }
            
            if let status = filters.status {
                firestoreQuery = firestoreQuery.whereField("status", isEqualTo: status)
            }
            
            // Text search (if query provided)
            if !query.isEmpty {
                // Note: For better search, consider using Algolia or similar
                // For now, we'll do client-side filtering
                let snapshot = try await firestoreQuery.getDocuments()
                let allItems = snapshot.documents.compactMap { doc in
                    self.convertDocumentToMedia(doc)
                }
                
                // Client-side text search
                mediaItems = allItems.filter { media in
                    media.title.localizedCaseInsensitiveContains(query) ||
                    media.description.localizedCaseInsensitiveContains(query) ||
                    media.genres.contains { $0.localizedCaseInsensitiveContains(query) }
                }
            } else {
                let snapshot = try await firestoreQuery.limit(to: 50).getDocuments()
                mediaItems = snapshot.documents.compactMap { doc in
                    self.convertDocumentToMedia(doc)
                }
            }
            
            print("✅ Found \(mediaItems.count) media items")
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("❌ Search error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - List Management
    func addToList(mediaId: String, listType: ListType, customListName: String? = nil) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let listName = customListName ?? listType.displayName
            let listId = "\(userId)_\(listType.rawValue)_\(listName)"
            
            let listData: [String: Any] = [
                "name": listName,
                "type": listType.rawValue,
                "media_items": FieldValue.arrayUnion([mediaId]),
                "created_at": Timestamp(date: Date()),
                "updated_at": Timestamp(date: Date())
            ]
            
            try await db.collection(listsCollection).document(listId).setData(listData, merge: true)
            await loadUserLists()
            print("✅ Added media to list: \(listName)")
        } catch {
            errorMessage = "Failed to add to list: \(error.localizedDescription)"
            print("❌ Error adding to list: \(error)")
        }
    }
    
    func removeFromList(mediaId: String, listId: String) async {
        do {
            try await db.collection(listsCollection).document(listId).updateData([
                "media_items": FieldValue.arrayRemove([mediaId]),
                "updated_at": Timestamp(date: Date())
            ])
            await loadUserLists()
            print("✅ Removed media from list")
        } catch {
            errorMessage = "Failed to remove from list: \(error.localizedDescription)"
            print("❌ Error removing from list: \(error)")
        }
    }
    
    // MARK: - Real-time Updates
    func startListening() {
        // Listen for media changes
        db.collection(mediaCollection)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    self?.errorMessage = "Real-time error: \(error.localizedDescription)"
                    return
                }
                
                guard let snapshot = snapshot else { return }
                
                let items = snapshot.documents.compactMap { doc in
                    self?.convertDocumentToMedia(doc)
                }.compactMap { $0 }
                
                self?.mediaItems = items
                print("🔄 Real-time update: \(items.count) media items")
            }
    }
    
    func stopListening() {
        // Remove listeners when needed
    }
    
    // MARK: - Helper Methods
    private func convertDocumentToMedia(_ doc: QueryDocumentSnapshot) -> Media? {
        let data = doc.data()
        
        guard let title = data["title"] as? String,
              let year = data["year"] as? Int,
              let description = data["description"] as? String,
              let typeString = data["type"] as? String,
              let type = MediaType(rawValue: typeString),
              let genres = data["genres"] as? [String] else {
            return nil
        }
        
        let imageURL = data["image_url"] as? String
        let episodes = data["episodes"] as? Int
        let status = data["status"] as? String ?? "Unknown"
        let rating = data["rating"] as? Double
        
        // Convert timestamps
        let createdAt: Date
        let updatedAt: Date
        
        if let createdTimestamp = data["created_at"] as? Timestamp {
            createdAt = createdTimestamp.dateValue()
        } else {
            createdAt = Date()
        }
        
        if let updatedTimestamp = data["updated_at"] as? Timestamp {
            updatedAt = updatedTimestamp.dateValue()
        } else {
            updatedAt = Date()
        }
        
        return Media(
            id: doc.documentID,
            title: title,
            year: year,
            description: description,
            imageURL: imageURL,
            type: type,
            genres: genres,
            episodes: episodes,
            status: status,
            rating: rating,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    private func convertDocumentToUserList(_ doc: QueryDocumentSnapshot) -> UserList? {
        let data = doc.data()
        
        guard let name = data["name"] as? String,
              let typeString = data["type"] as? String,
              let type = ListType(rawValue: typeString),
              let mediaItems = data["media_items"] as? [String] else {
            return nil
        }
        
        // Convert timestamps
        let createdAt: Date
        let updatedAt: Date
        
        if let createdTimestamp = data["created_at"] as? Timestamp {
            createdAt = createdTimestamp.dateValue()
        } else {
            createdAt = Date()
        }
        
        if let updatedTimestamp = data["updated_at"] as? Timestamp {
            updatedAt = updatedTimestamp.dateValue()
        } else {
            updatedAt = Date()
        }
        
        return UserList(
            id: doc.documentID,
            name: name,
            type: type,
            mediaItems: mediaItems,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
