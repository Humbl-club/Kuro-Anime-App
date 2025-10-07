//
//  KuroApp.swift
//  Kuro
//
//  Created by Max Dev on 29.09.25.
//

import SwiftUI

@main
struct KuroApp: App {
    @State private var supabaseService = SupabaseService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(supabaseService)
                .preferredColorScheme(.light)
        }
    }
}