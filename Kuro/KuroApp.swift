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
    @State private var networkMonitor = NetworkMonitor()
    @State private var pendingDeepLink: DeepLink? = nil
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Make image loading feel instant when revisiting screens.
        // AsyncImage uses URLSession/URLCache under the hood; we also leverage this in ImagePipeline.
        let mem = 64 * 1024 * 1024
        let disk = 256 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: mem, diskCapacity: disk, diskPath: "kuro_url_cache")
    }

    var body: some Scene {
        WindowGroup {
            RootView(pendingDeepLink: $pendingDeepLink)
                .environment(supabaseService)
                .environment(networkMonitor)
                // The current design system is light-first (black-on-white editorial).
                // Until we have a full dark palette, keep system appearance stable.
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    pendingDeepLink = DeepLink.from(url: url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        break
                    case .background:
                        break
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}

private struct RootView: View {
    @Binding var pendingDeepLink: DeepLink?
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(NetworkMonitor.self) private var networkMonitor

    var body: some View {
        VStack(spacing: 0) {
            if !networkMonitor.isConnected {
                Text("OFFLINE")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
            }

            Group {
                if supabaseService.isAuthBootstrapping {
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        VStack(spacing: 14) {
                            Text("KURO")
                                .font(.system(size: 11, weight: .regular))
                                .tracking(1.5)
                                .foregroundColor(.secondary)
                            ProgressView()
                                .tint(.secondary)
                        }
                    }
                } else if supabaseService.isAuthenticated {
                    ContentView(pendingDeepLink: $pendingDeepLink)
                } else {
                    AuthView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onChange(of: networkMonitor.isConnected) { _, connected in
            if connected {
                ConciergeAnalytics.shared.flushIfNeeded()
            }
        }
    }
}
