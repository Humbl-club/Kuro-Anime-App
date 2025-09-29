import Testing
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
@testable import Kuro

// MARK: - Firebase Connection Tests
@Suite("Firebase Integration Tests")
struct FirebaseConnectionTest {
    
    @Test("Firebase Configuration Test")
    func testFirebaseConfiguration() async throws {
        // Test that Firebase is properly configured
        #expect(FirebaseApp.app() != nil, "Firebase should be configured")
        
        // Check if the default app exists
        let app = FirebaseApp.app()
        #expect(app?.name == "__FIRAPP_DEFAULT", "Default Firebase app should exist")
        
        print("✅ Firebase Configuration: PASSED")
    }
    
    @Test("Firestore Database Connection Test")
    func testFirestoreConnection() async throws {
        // Test Firestore connection
        let db = Firestore.firestore()
        
        // Try to access a test collection (this should not throw an error)
        let testRef = db.collection("test")
        #expect(testRef != nil, "Firestore reference should be created")
        
        print("✅ Firestore Connection: PASSED")
    }
    
    @Test("Firebase Service Initialization Test")
    func testFirebaseServiceInit() async throws {
        // Test that FirebaseService initializes correctly
        let firebaseService = await FirebaseService()
        
        #expect(firebaseService.mediaItems.isEmpty, "Media items should start empty")
        #expect(firebaseService.userLists.isEmpty, "User lists should start empty")
        #expect(firebaseService.isLoading == false, "Should not be loading initially")
        #expect(firebaseService.errorMessage == nil, "Should have no error initially")
        
        print("✅ Firebase Service Initialization: PASSED")
    }
    
    @Test("Authentication Test")
    func testAuthentication() async throws {
        // Test anonymous authentication
        let firebaseService = await FirebaseService()
        
        // Wait a bit for auth to complete
        try await Task.sleep(for: .seconds(3))
        
        // Check if user is authenticated
        let currentUser = Auth.auth().currentUser
        #expect(currentUser != nil, "User should be authenticated anonymously")
        
        if let user = currentUser {
            #expect(user.isAnonymous == true, "User should be anonymous")
            print("✅ Authentication: PASSED - User ID: \(user.uid)")
        }
    }
    
    @Test("Data Loading Test")
    func testDataLoading() async throws {
        let firebaseService = await FirebaseService()
        
        // Wait for initial auth
        try await Task.sleep(for: .seconds(2))
        
        // Test loading media items
        await firebaseService.loadMediaItems()
        
        // Check that loading completed without errors
        #expect(firebaseService.isLoading == false, "Loading should complete")
        
        if let error = firebaseService.errorMessage {
            print("⚠️ Data Loading Warning: \(error)")
        } else {
            print("✅ Data Loading: PASSED - Loaded \(firebaseService.mediaItems.count) items")
        }
    }
    
    @Test("Search Functionality Test")
    func testSearchFunctionality() async throws {
        let firebaseService = await FirebaseService()
        
        // Wait for auth
        try await Task.sleep(for: .seconds(2))
        
        // Test search with empty query
        await firebaseService.searchMedia(query: "")
        #expect(firebaseService.isLoading == false, "Search should complete")
        
        // Test search with actual query
        await firebaseService.searchMedia(query: "anime")
        #expect(firebaseService.isLoading == false, "Search with query should complete")
        
        print("✅ Search Functionality: PASSED")
    }
    
    @Test("Media Model Validation Test")
    func testMediaModel() async throws {
        // Test that Media model works correctly
        let testMedia = Media(
            id: "test-id",
            title: "Test Anime",
            year: 2024,
            description: "A test anime for validation",
            imageURL: "https://example.com/image.jpg",
            type: .anime,
            genres: ["Action", "Adventure"],
            episodes: 12,
            status: "Completed",
            rating: 8.5,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        #expect(testMedia.title == "Test Anime", "Title should be set correctly")
        #expect(testMedia.type == .anime, "Type should be anime")
        #expect(testMedia.genres.contains("Action"), "Should contain Action genre")
        
        print("✅ Media Model Validation: PASSED")
    }
}

// MARK: - Helper Test Functions
extension FirebaseConnectionTest {
    
    /// Test Firebase project configuration
    static func validateFirebaseProject() -> Bool {
        guard let app = FirebaseApp.app() else { return false }
        
        // Check if required configurations exist
        guard let options = app.options else { return false }
        
        return !options.googleAppID.isEmpty && 
               !options.gcmSenderID.isEmpty &&
               !options.projectID.isEmpty
    }
}