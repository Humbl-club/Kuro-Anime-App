//
//  NavshellTests.swift
//  KuroTests
//
//  Navigation contract, shell lane (docs/superpowers/specs/2026-11-02-navigation-contract-design.md):
//  deep links collapse first and wait for onboarding (N10), the shell's journey pages (Profile, Search,
//  Concierge, Data sources, Clubs, Discover "See all") have stable distinct identities and push / pop
//  back inside their journey (N5), a covered page keeps working until it is popped or its journey ends,
//  Profile's lists say "Opens Collection" and collapse before the pager switches (N11), and onboarding's
//  Back step.
//

import Testing
import Foundation
import SwiftUI
import KuroCore
@testable import Kuro

@MainActor
@Suite("Navigation contract: app shell (deep links, header journeys, onboarding)")
struct NavshellTests {

    // MARK: Deep links (N10)

    @Test("Title and club links open a journey; page links switch the pager; join switches to Clubs")
    func linkTargets() {
        let action = { (link: DeepLink) in
            ShellLinkPolicy.action(for: link, onboardingOpen: false, conciergeInPager: false)
        }
        #expect(action(.anime(id: 7)) == .openJourney(.media(MediaRoute(kind: .anime, id: 7))))
        #expect(action(.manga(id: 7)) == .openJourney(.media(MediaRoute(kind: .manga, id: 7))))
        #expect(action(.anime(id: 7)) != action(.manga(id: 7)))
        #expect(action(.club(id: "c-1")) == .openJourney(.club(id: "c-1")))
        #expect(action(.collection) == .switchPage(.collection))
        #expect(action(.discover) == .switchPage(.discover))
        #expect(action(.joinClub(code: "AB12CD34")) == .joinClub(code: "AB12CD34"))
        #expect(action(.authCallback(AuthCallbackPayload(code: "x"))) == .none)
    }

    @Test("Concierge links: the sheet in the Taste/Home orders, the pager page in the legacy order")
    func conciergeLinks() {
        #expect(ShellLinkPolicy.action(for: .concierge(prompt: "mood"), onboardingOpen: false, conciergeInPager: false)
                == .openConciergeSheet(prompt: "mood"))
        #expect(ShellLinkPolicy.action(for: .concierge(prompt: nil), onboardingOpen: false, conciergeInPager: true)
                == .openConciergePage(prompt: nil))
    }

    @Test("While onboarding shows, every app link waits for the cover (auth callbacks never reach the shell)")
    func onboardingFirst() {
        let links: [DeepLink] = [.anime(id: 1), .manga(id: 2), .club(id: "c"), .collection, .discover,
                                 .concierge(prompt: nil), .joinClub(code: "AB12CD34")]
        for link in links {
            #expect(ShellLinkPolicy.action(for: link, onboardingOpen: true, conciergeInPager: false) == .waitForOnboarding)
        }
        #expect(ShellLinkPolicy.action(for: .authCallback(AuthCallbackPayload(code: "x")),
                                       onboardingOpen: true, conciergeInPager: false) == .none)
    }

    @Test("Coordinator: a link while Search or Concierge is open closes the sheet, then opens the target")
    func collapseHeaderSheets() async throws {
        let navigation = KuroNavigationCoordinator(dismissalDelay: .zero)
        var searchOpen = true
        var conciergeOpen = false
        navigation.registerLayer("search", kind: .sheet, isPresented: { searchOpen }, close: { searchOpen = false })
        navigation.registerLayer("concierge", kind: .sheet, isPresented: { conciergeOpen }, close: { conciergeOpen = false })

        let target: JourneyPage = .media(MediaRoute(kind: .anime, id: 9))
        navigation.collapseThenOpen(target)
        #expect(!searchOpen)
        #expect(navigation.journey == nil)          // opens only after the dismissal
        try await Task.sleep(for: .milliseconds(50))
        #expect(navigation.journey?.root == target)

        // A link to what is already on top keeps that journey (brought to the front).
        let open = navigation.journey
        navigation.collapseThenOpen(.media(MediaRoute(kind: .anime, id: 9)))
        #expect(navigation.journey === open)

        // N11 / page links: the journey and the Concierge sheet collapse, then the pager switches.
        conciergeOpen = true
        var switched = false
        navigation.collapseThen { switched = true }
        #expect(!conciergeOpen)
        #expect(navigation.journey == nil)
        #expect(!switched)
        try await Task.sleep(for: .milliseconds(50))
        #expect(switched)
    }

    // MARK: Shell journey pages (N5)

    @Test("Shell pages have stable, distinct, kind-prefixed ids")
    func pageIdentity() {
        let pages: [(JourneyPage, String)] = [
            (ShellJourneyPages.search(), "custom:search"),
            (ShellJourneyPages.profile(onImportNavigation: { _ in }, onOpenCollection: {}), "custom:profile"),
            (ShellJourneyPages.concierge(onImportNavigation: nil), "custom:concierge"),
            (ShellJourneyPages.concierge(prompt: "list", review: true, onImportNavigation: nil), "custom:concierge:review"),
            (ShellJourneyPages.dataSources, "custom:profile:dataSources"),
            (ShellJourneyPages.clubs, "custom:profile:clubs"),
        ]
        for (page, id) in pages { #expect(page.id == id) }
        #expect(Set(pages.map(\.0)).count == pages.count)
        // The scope is payload: two Searches are the same page.
        #expect(ShellJourneyPages.search(scope: .anime) == ShellJourneyPages.search(scope: .manga))
    }

    @Test("Discover See all: one page per rail, prefixed seeAll:discover:")
    func seeAllIdentity() {
        let ids = EditorialDiscoverRoute.allCases.map { route in
            JourneyPage.seeAll(AnyJourneyPage(id: DiscoverSeeAllPolicy.pageID(route)) { EmptyView() }).id
        }
        #expect(Set(ids).count == EditorialDiscoverRoute.allCases.count)
        #expect(ids.allSatisfy { $0.hasPrefix("seeAll:discover:") })
        #expect(DiscoverSeeAllPolicy.pageID(.animeTrending) == "discover:animeTrending")
    }

    @Test("Inside Profile's journey: rows push, an open page is popped back to, ✕ collapses")
    func profileJourney() {
        let profile = ShellJourneyPages.profile(onImportNavigation: { _ in }, onOpenCollection: {})
        let navigator = JourneyNavigator(root: profile)
        var closed = 0
        navigator.dismissJourney = { closed += 1 }

        navigator.routes.openPage(ShellJourneyPages.search())          // Find
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 3))    // a result
        navigator.routes.openPage(ShellJourneyPages.search())          // Find again: back to Search
        #expect(navigator.path.map(\.id) == ["custom:search"])

        navigator.routes.openPage(ShellJourneyPages.clubs)
        navigator.routes.openClub("c-1")
        #expect(navigator.path.map(\.id) == ["custom:search", "custom:profile:clubs", "club:c-1"])
        navigator.routes.openClub("c-1")                               // double tap: nothing
        #expect(navigator.path.count == 3)

        navigator.pop()
        #expect(navigator.top.id == "custom:profile:clubs")
        navigator.open(profile)                                        // the root: pops everything
        #expect(navigator.path.isEmpty)

        navigator.routes.openPage(ShellJourneyPages.dataSources)
        navigator.close()
        #expect(closed == 1)
    }

    // MARK: Page lifetime

    @Test("A covered page stays alive; a popped page or an ended journey does not")
    func pageLifetime() {
        let profileID = "custom:\(ShellPageID.profile)"
        let conciergeID = "custom:\(ShellPageID.concierge)"
        let navigator = JourneyNavigator(root: ShellJourneyPages.profile(onImportNavigation: { _ in }, onOpenCollection: {}))
        let lifetime = ShellJourneyLifetime(navigator: navigator)
        #expect(lifetime.contains(pageID: profileID))
        #expect(!lifetime.contains(pageID: conciergeID))

        navigator.open(ShellJourneyPages.concierge(onImportNavigation: nil))
        navigator.open(JourneyPage.media(MediaRoute(kind: .anime, id: 1)))
        #expect(lifetime.contains(pageID: profileID))      // covered by pushes
        #expect(lifetime.contains(pageID: conciergeID))
        navigator.pop()
        navigator.pop()
        #expect(!lifetime.contains(pageID: conciergeID))   // popped: tears down

        var ran: [String] = []
        lifetime.onEnd(profileID) { ran.append("profile") }
        lifetime.onEnd(conciergeID) { ran.append("concierge") }
        lifetime.cancel(conciergeID)                        // it tore itself down when popped
        lifetime.end()
        lifetime.end()
        #expect(ran == ["profile"])
        #expect(!lifetime.contains(pageID: profileID))     // the sheet ended
        lifetime.onEnd("late") { ran.append("late") }       // registered after the end: runs at once
        #expect(ran == ["profile", "late"])

        #expect(ShellJourneyLifetime.isInStack(pageID: "custom:x", root: .custom(AnyJourneyPage(id: "x") { EmptyView() }), path: []))
    }

    @Test("Profile sets its import work up once per account; coming back from a push keeps it")
    func profileSetup() {
        #expect(ProfileLifecyclePolicy.needsSetup(setUpFor: nil, current: "u1", hasCoordinator: false))
        #expect(ProfileLifecyclePolicy.needsSetup(setUpFor: .some("u1"), current: "u1", hasCoordinator: false))
        #expect(!ProfileLifecyclePolicy.needsSetup(setUpFor: .some("u1"), current: "u1", hasCoordinator: true))
        #expect(ProfileLifecyclePolicy.needsSetup(setUpFor: .some("u1"), current: "u2", hasCoordinator: true))
        #expect(!ProfileLifecyclePolicy.needsSetup(setUpFor: .some(nil), current: nil, hasCoordinator: true))
        #expect(ProfileLifecyclePolicy.needsSetup(setUpFor: .some(nil), current: "u1", hasCoordinator: true))
    }

    // MARK: N11, onboarding

    @Test("Your lists says where it goes (EN/DE)")
    func opensCollection() {
        #expect(ProfileListsPolicy.opensCollection(german: false) == "Opens Collection")
        #expect(ProfileListsPolicy.opensCollection(german: true) == "Öffnet Sammlung")
    }

    @Test("Onboarding Back returns one step; the first step has no Back")
    func onboardingBack() {
        #expect(OnboardingStep.medium.previous == nil)
        #expect(OnboardingStep.list.previous == .medium)
        #expect(OnboardingStep.clubs.previous == .list)
        #expect(OnboardingStep.allCases == [.medium, .list, .clubs])
    }
}

@Suite("Pager tap gate: a swipe that starts on a card never opens it (N9)")
@MainActor
struct PagerTapGateTests {
    @Test("While the pager is mid-swipe every open and tool is dropped; afterwards they pass")
    func gatedRoutes() {
        var shown: [String] = []
        let base = KuroRoutes { shown.append($0.id) }
        let gate = KuroPagerTapGate()
        let routes = base.gated(by: gate)

        gate.isSuppressed = true
        routes.openMedia(MediaRoute(kind: .anime, id: 117))
        routes.openClub("c1")
        routes.openBrowse()
        routes.presentAddToClub(MediaKey(kind: .manga, id: 2))
        #expect(shown.isEmpty)

        gate.isSuppressed = false
        routes.openMedia(MediaRoute(kind: .anime, id: 117))
        routes.openClub("c1")
        #expect(shown == ["media:anime:117", "club:c1"])
    }
}
