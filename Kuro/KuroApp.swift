//
//  KuroApp.swift
//  Kuro
//
//  Created by Max Dev on 29.09.25.
//

import KuroLibrary
import SwiftUI

@main
struct KuroApp: App {
    @State private var identity = AppComposition.shared.identity
    @State private var auth = AppComposition.shared.auth
    @State private var session = AppComposition.shared.session
    @State private var library = AppComposition.shared.library
    @State private var libraryActions = AppComposition.shared.libraryActions
    @State private var home = AppComposition.shared.home
    @State private var catalog = AppComposition.shared.catalog
    @State private var search = AppComposition.shared.search
    @State private var discovery = AppComposition.shared.discovery
    @State private var recommendations = AppComposition.shared.recommendations
    @State private var releases = AppComposition.shared.releases
    @State private var social = AppComposition.shared.social
    @State private var availability = AppComposition.shared.availability
    @State private var clubs = AppComposition.shared.clubs
    @State private var collection = AppComposition.shared.collection
    @State private var imports = AppComposition.shared.imports
    @State private var concierge = AppComposition.shared.concierge
    @State private var taste = AppComposition.shared.taste
    @State private var deviceIntelligence = AppComposition.shared.deviceIntelligence
    @State private var banner = AppComposition.shared.banner
    @State private var flags = AppComposition.shared.flags
    @State private var interactionTelemetry = AppComposition.shared.interactionTelemetry
    @State private var outboundLinks = AppComposition.shared.outboundLinks
    @State private var networkMonitor = NetworkMonitor()
    @State private var pendingDeepLink: DeepLink? = nil
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--kuro-skip-auth") {
            // The preview session has no user id: onboarding falls back to the device-level key.
            UserDefaults.standard.set(true, forKey: OnboardingCompletion.legacyDeviceKey)
        }
        #endif
        // Make image loading feel instant when revisiting screens.
        // AsyncImage uses URLSession/URLCache under the hood; we also leverage this in ImagePipeline.
        let mem = 64 * 1024 * 1024
        let disk = 256 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: mem, diskCapacity: disk, diskPath: "kuro_url_cache")
    }

    var body: some Scene {
        WindowGroup {
            RootView(pendingDeepLink: $pendingDeepLink)
                .environment(identity)
                .environment(auth)
                .environment(session)
                .environment(library)
                .environment(libraryActions)
                .environment(home)
                .environment(catalog)
                .environment(search)
                .environment(discovery)
                .environment(recommendations)
                .environment(releases)
                .environment(social)
                .environment(availability)
                .environment(clubs)
                .environment(collection)
                .environment(imports)
                .environment(concierge)
                .environment(taste)
                .environment(deviceIntelligence)
                .environment(banner)
                .environment(flags)
                .environment(interactionTelemetry)
                .environment(outboundLinks)
                .environment(networkMonitor)
                // The current design system is light-first (black-on-white editorial).
                // Until we have a full dark palette, keep system appearance stable.
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    guard identity.configError == nil else { return }
                    if let link = DeepLink.from(url: url) {
                        // Auth callbacks are handled immediately at the app level (before the auth
                        // gate), not passed to ContentView. The funnel decides whether the link may
                        // be applied (pending flow on this device, PKCE exchange; spec D12).
                        if case .authCallback(let payload) = link {
                            Task { await session.handleAuthCallback(payload) }
                        } else {
                            pendingDeepLink = link
                        }
                    }
                }
                .onChange(of: networkMonitor.isConnected) { _, connected in
                    if connected,identity.isAuthenticated {
                        // Permission signals missed while offline are not replayed by Realtime.
                        // Erase private copies before re-reading under current memberships.
                        clubs.invalidateSharedDisclosure()
                        Task { await home.drain() }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active,
                       identity.configError == nil,
                       identity.isAuthenticated {
                        clubs.invalidateSharedDisclosure()
                        Task { await session.refreshSessionIfNeeded(); await home.restorePendingProjection(); await home.drain() }
                    }
                }
        }
    }
}

private struct RootView: View {
    @Binding var pendingDeepLink: DeepLink?
    @Environment(IdentityStore.self) private var identity
    @Environment(NetworkMonitor.self) private var networkMonitor

    var body: some View {
        VStack(spacing: 0) {
            if !networkMonitor.isConnected {
                Text("Offline")
                    .kuroKicker()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.kuroCanvasQuiet)
                    .accessibilityLabel(KuroLocale.text("Offline", "Offline"))
                    .accessibilityAddTraits(.isStaticText)
            }

            Group {
                if let error = identity.configError {
                    ZStack {
                        Color.kuroCanvasPage.ignoresSafeArea()
                        VStack(spacing: 16) {
                            KuroWordmark()
                            Text(KuroLocale.text("Configuration error", "Konfigurationsfehler"))
                                .font(.kuroTitle())
                                .foregroundStyle(Color.kuroInk)
                                .accessibilityAddTraits(.isHeader)
                            Text(error)
                                .font(.kuroMeta())
                                .foregroundStyle(Color.kuroInkSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }
                } else if identity.isAuthBootstrapping {
                    // The welcome's own mark on the white page, so launch → welcome reads as one surface.
                    ZStack {
                        Color.kuroCanvasPage.ignoresSafeArea()
                        VStack(spacing: 18) {
                            KuroWordmark()
                            ProgressView()
                                .tint(Color.kuroInkQuiet)
                                .accessibilityLabel(KuroLocale.text("Loading", "Wird geladen"))
                        }
                    }
                } else if identity.isAuthenticated && identity.requiresPasswordUpdate {
                    // A password-reset link signed this account in: a new password comes first (D12).
                    AuthSetPasswordView()
                } else if identity.isAuthenticated {
                    // The signed-in subtree's identity is the account: a direct A-to-B switch rebuilds it, so no
                    // A drafts, conversations, selections or tasks survive (a same-user token refresh keeps the id).
                    ContentView(pendingDeepLink: $pendingDeepLink)
                        .id(identity.currentUserId ?? "")
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
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification
            ).map({ _ in () }) {
                AppComposition.shared.memoryPressure.trimCachesForMemoryPressure()
            }
        }
    }
}
