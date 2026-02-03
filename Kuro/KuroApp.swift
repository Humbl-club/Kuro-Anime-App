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

    init() {
        // Make image loading feel instant when revisiting screens.
        // AsyncImage uses URLSession/URLCache under the hood; we also leverage this in ImagePipeline.
        let mem = 64 * 1024 * 1024
        let disk = 256 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: mem, diskCapacity: disk, diskPath: "kuro_url_cache")
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(supabaseService)
                .preferredColorScheme(.light)
        }
    }
}

private struct RootView: View {
    @Environment(SupabaseService.self) private var supabaseService

    var body: some View {
        Group {
            if supabaseService.isAuthBootstrapping {
                ZStack {
                    Color.white.ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text("KURO")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(1.5)
                            .foregroundColor(.black.opacity(0.3))
                        ProgressView()
                            .tint(.black.opacity(0.6))
                    }
                }
            } else if supabaseService.isAuthenticated {
                ContentView()
            } else {
                AuthView()
            }
        }
    }
}
