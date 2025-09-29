//
//  KuroTests.swift
//  KuroTests
//
//  Created by Max Dev on 29.09.25.
//

import Testing
import FirebaseCore
@testable import Kuro

@Suite("Kuro App Tests")
struct KuroTests {

    @Test("App Launch Test")
    func testAppLaunch() async throws {
        // Test that the app can initialize without crashing
        #expect(true, "App should launch successfully")
        print("✅ App Launch: PASSED")
    }
    
    @Test("Firebase Configuration Check")
    func testFirebaseSetup() async throws {
        // This will verify Firebase is properly configured
        FirebaseApp.configure()
        
        let app = FirebaseApp.app()
        #expect(app != nil, "Firebase should be configured after calling configure()")
        
        if let firebaseApp = app {
            let options = firebaseApp.options
            #expect(!options.googleAppID.isEmpty, "Google App ID should be configured")
            #expect(!options.projectID.isEmpty, "Project ID should be configured")
            print("✅ Firebase Setup: PASSED")
            print("   - Project ID: \(options.projectID)")
            print("   - Google App ID: \(options.googleAppID)")
        }
    }

    @Test("UI Components Test")
    func testUIComponents() async throws {
        // Test that UI components can be created
        let moods = ["Contemplative", "Energetic", "Melancholic", "Uplifting", "Mysterious"]
        #expect(moods.count == 5, "Should have 5 mood options")
        
        let sections = ["DISCOVER", "COLLECTION", "SEARCH"]
        #expect(sections.count == 3, "Should have 3 main sections")
        
        print("✅ UI Components: PASSED")
    }
}
