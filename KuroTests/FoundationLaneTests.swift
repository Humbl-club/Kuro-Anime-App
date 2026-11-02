//
//  FoundationLaneTests.swift
//  KuroTests
//
//  Lane F foundation (overnight 2026-11-01): flag override tolerance (spec D14), the Browse route
//  (spec D2), the locale decision point (spec D4), the Dynamic Type category mapping, and the pure
//  copy of the shared components (advance key, state view).
//

import Foundation
import KuroCore
import SwiftUI
import Synchronization
import Testing
@testable import Kuro

@MainActor
@Suite("Feature flags: override tolerance (D14)", .timeLimit(.minutes(1)))
struct FlagOverrideToleranceTests {
    @Test("Only cancellation stops the refresh; every other override failure keeps the cohort")
    func classification() {
        #expect(FeatureFlags.overridesFailure(for: CancellationError()) == .cancelled)
        #expect(FeatureFlags.overridesFailure(for: URLError(.cancelled)) == .cancelled)
        #expect(FeatureFlags.overridesFailure(for: URLError(.timedOut)) == .keepCachedCohort)
        #expect(FeatureFlags.overridesFailure(for: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x"))) == .keepCachedCohort)
        // The overrides table is live (2026-11-02): every build reads the account cohort.
        #expect(FeatureFlags.readsAccountOverrides)
    }

    @Test("The revision fence follows a server flip without the overrides lookup (the Release path)")
    func fenceFollowsServerWithoutOverrides() async throws {
        let server = StubServer()
        let rollout = Mutex(100)
        server.respond { request in
            request.resource == "feature_flags"
                ? .json("[\(flagRow("series_foundation_v1", rollout: rollout.withLock { $0 }))]")
                : .emptyArray
        }
        let store = try TestDefaults()
        defer { store.tearDown(); server.shutDown() }
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        let client = StubSupabase.makeClient(server: server)
        #expect(!flags.seriesFoundationFenceEnabled())
        // No user: the overrides branch is skipped in every build, as in Release.
        await flags.refresh(client: client, userId: nil)
        #expect(flags.seriesFoundationFenceEnabled(), "the fence follows the fetched flags")
        rollout.withLock { $0 = 0 }
        await flags.refresh(client: client, userId: nil)
        #expect(!flags.seriesFoundationFenceEnabled(), "a kill switch reaches the writer without a relaunch")
        #expect(server.requests.filter { $0.resource == "feature_flag_overrides" }.isEmpty)
    }

    @Test("A missing overrides table (PGRST205 / 404) never flips Home off mid-bootstrap")
    func missingOverridesTableKeepsHome() async throws {
        let server = StubServer()
        let account = AccountSessionCoordinator()
        let user = UUID().uuidString
        _ = account.begin(userId: user)
        // First refresh: the tester cohort arrives and is cached.
        let overridesMissing = Mutex(false)
        server.respond { request in
            if request.resource == "feature_flags" {
                return .json("[\(flagRow("series_foundation_v1", rollout: 0)),\(flagRow("series_home_native_v1", rollout: 0))]")
            }
            if request.resource == "feature_flag_overrides" {
                if overridesMissing.withLock({ $0 }) {
                    return .json(#"{"code":"PGRST205","details":null,"hint":null,"message":"Could not find the table"}"#, status: 404)
                }
                return .json("[{\"user_id\":\"\(user.lowercased())\",\"flag_name\":\"series_foundation_v1\",\"enabled\":true},{\"user_id\":\"\(user.lowercased())\",\"flag_name\":\"series_home_native_v1\",\"enabled\":true}]")
            }
            return .emptyArray
        }
        let store = try TestDefaults()
        defer { store.tearDown(); server.shutDown() }
        let flags = FeatureFlags(userDefaults: store.defaults, launchArguments: [])
        let client = StubSupabase.makeClient(server: server)
        await flags.refresh(client: client, userId: user, accountSession: account)
        flags.completeFoundationBootstrap(userId: user)
        #expect(flags.seriesHomeNativeV1Enabled)

        // Second refresh: the table is gone. Home stays on; the bootstrap is not reset.
        overridesMissing.withLock { $0 = true }
        await flags.refresh(client: client, userId: user, accountSession: account)
        #expect(flags.seriesHomeNativeV1Enabled, "an overrides error is non-destructive")
        #expect(flags.seriesFoundationFenceEnabled())
        #expect(server.requests.filter { $0.resource == "feature_flag_overrides" }.count == 2)
    }
}

@MainActor
@Suite("Routing: Browse route (D2)")
struct BrowseRouteTests {
    @Test("Browse has one identity and builds the catalogue sheet; a second tap changes nothing")
    func browseRoute() {
        #expect(AppRoute.browse.id == "browse")
        guard case .browse = RoutePolicy.destination(for: .browse) else {
            Issue.record("browse must build the catalogue sheet")
            return
        }
        #expect(RoutePolicy.update(current: .browse, requested: .browse) == nil)
        let replaced = RoutePolicy.update(current: .club(id: "c"), requested: .browse)
        #expect(replaced?.id == "browse")
    }
}

@MainActor
@Suite("Foundation: locale, type scale and component copy")
struct FoundationCopyTests {
    @Test("German is the first preferred language only")
    func locale() {
        #expect(KuroLocale.isGerman(preferredLanguages: ["de-DE", "en-US"]))
        #expect(KuroLocale.isGerman(preferredLanguages: ["de-AT"]))
        #expect(!KuroLocale.isGerman(preferredLanguages: ["en-GB", "de-DE"]))
        let calendar = KuroLocale.calendar(locale: Locale(identifier: "de_DE"),
                                           timeZone: TimeZone(identifier: "Europe/Berlin") ?? .current)
        #expect(calendar.timeZone.identifier == "Europe/Berlin")
    }

    @Test("Every Dynamic Type size maps to its UIKit category")
    func typeScaleMapping() {
        #expect(KuroTypeScale.category(for: .large) == .large)
        #expect(KuroTypeScale.category(for: .xSmall) == .extraSmall)
        #expect(KuroTypeScale.category(for: .xxxLarge) == .extraExtraExtraLarge)
        #expect(KuroTypeScale.category(for: .accessibility5) == .accessibilityExtraExtraExtraLarge)
        #expect(KuroTypeRole.body.pointSize <= KuroTypeRole.body.spec.cap)
        #expect(KuroTypeRole.display.spec.cap == 72)
    }

    @Test("Advance key labels: unit, title, position; unknown totals omitted")
    func advanceCopy() {
        #expect(KuroAdvanceCopy.label(medium: .anime, nextUnit: 12, title: "Cowboy Bebop", current: 11, total: 26, german: false)
                == "Mark episode 12 of Cowboy Bebop watched, 11 of 26")
        #expect(KuroAdvanceCopy.label(medium: .manga, nextUnit: 8, title: "Berserk", german: true)
                == "Kapitel 8 von Berserk als gelesen markieren")
        #expect(KuroAdvanceCopy.label(medium: .anime, nextUnit: 3, title: " ", current: 2, total: nil, german: false)
                == "Mark episode 3 watched, at 2")
        #expect(KuroAdvanceCopy.caughtUpLabel(title: "Frieren", german: true) == "Bei Frieren auf dem neuesten Stand")
    }

    @Test("State copy: failure, offline and denial never read as an empty success")
    func stateCopy() {
        let empty = KuroStateCopy.copy(for: .empty, german: false)
        let kinds: [KuroStateView.Kind] = [.failed(hasCachedContent: false), .failed(hasCachedContent: true),
                                           .offline(hasCachedContent: false), .offline(hasCachedContent: true), .denied]
        for kind in kinds {
            #expect(KuroStateCopy.copy(for: kind, german: false) != empty)
            #expect(KuroStateCopy.copy(for: kind, german: true) != KuroStateCopy.copy(for: kind, german: false))
        }
        // Only a caller that still shows earlier content may say so.
        #expect(KuroStateCopy.copy(for: .offline(hasCachedContent: true), german: true).message == "Du siehst den letzten Stand.")
        #expect(KuroStateCopy.copy(for: .offline(hasCachedContent: false), german: false).message == "Connect to load this.")
        #expect(KuroStateCopy.copy(for: .failed(hasCachedContent: false), german: false).title == "Couldn't load this.")
        #expect(KuroStateCopy.copy(for: .failed(hasCachedContent: true), german: false).message == "What you had is still here.")
        #expect(KuroStateCopy.retryTitle(german: false) == "Try again")
    }
}
