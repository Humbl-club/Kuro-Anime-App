//
//  KuroApp.swift
//  Kuro
//
//  Created by Max Dev on 29.09.25.
//

import SwiftUI

@main
struct KuroApp: App {
    @StateObject private var supabaseService = SupabaseService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(supabaseService)
                .preferredColorScheme(.light)
        }
    }
}