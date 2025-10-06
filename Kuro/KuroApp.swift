//
//  KuroApp.swift
//  Kuro
//
//  Created by Max Dev on 29.09.25.
//

import SwiftUI
import FirebaseCore

@main
struct KuroApp: App {
    @StateObject private var firebaseService = FirebaseService()
    
    init() {
        FirebaseApp.configure()
        // Setup simple console logging (working version only)
        SimpleConsoleLogger.setupAutoCheck()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(firebaseService)
        }
    }
}
