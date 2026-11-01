//
//  RestyleLaneTests.swift
//  KuroTests
//
//  Prototype-fidelity Task 9 (remaining screens restyle and branded states): each restyled screen
//  decides its branded state through one pure rule that its view switches on (Clubs list, Club
//  detail, Discover, Browse, Profile's library), so a failure without content always draws the
//  branded error (`KuroErrorView`), never the empty invitation. Also pins the Clubs invitation and
//  Profile new-account copy (EN and DE), the zero-free Profile summary, the Folio key faces and the
//  club room's 320 metrics.
//  Pure: no network, no simulator state.
//

import Foundation
import KuroCore
import KuroLibrary
import Testing
@testable import Kuro

@MainActor
struct RestyleLaneTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func entry(_ kind: MediaKind, _ id: Int, _ status: ListStatus) -> LibraryEntry {
        LibraryEntry(key: MediaKey(kind: kind, id: id), rowId: id, status: status, progress: 0,
                     rating: nil, verdict: nil, createdAt: now, updatedAt: now, revision: 1, lifecycleId: UUID())
    }

    // MARK: Step 1: restyled screens use branded states

    @Test("restyled screens use branded states: a failed read with nothing on screen is the branded error")
    func restyledScreensUseBrandedStates() {
        // Clubs list: a non-transport failure while online, no clubs.
        let clubs = ClubsListRules.state(phase: .failed(transport: false), hasClubs: false, isConnected: true)
        #expect(clubs.brandedState == .failed(hasContent: false))
        // Club detail: a failed first load (not a membership answer).
        #expect(ClubDetailIssue.failed.brandedState == .failed(hasContent: false))
        #expect(ClubDetailIssue.timedOut.brandedState == .failed(hasContent: false))
        // Discover and Browse: a failed first load while online.
        #expect(DiscoverPageRules.brandedState(isLoading: false, hasContent: false, failed: true, isConnected: true)
                == .failed(hasContent: false))
        #expect(BrowsePageRules.brandedState(isLoading: false, hasResults: false, failed: true, isConnected: true)
                == .failed(hasContent: false))
        // Profile's library: the first read failed.
        #expect(ProfileListsPolicy.libraryState(entryCount: 0, loadState: .failed) == .failed(hasContent: false))
    }

    @Test("Clubs list: every list state maps to one branded state; a failure never becomes the invitation")
    func clubsListBrandedStates() {
        #expect(ClubsListState.loading.brandedState == .loading)
        #expect(ClubsListState.empty.brandedState == .empty)
        #expect(ClubsListState.offline.brandedState == .offline(hasContent: false))
        #expect(ClubsListState.list(notice: nil).brandedState == nil)
        #expect(ClubsListState.list(notice: .offline).brandedState == .offline(hasContent: true))
        #expect(ClubsListState.list(notice: .failed).brandedState == .failed(hasContent: true))
        // Offline with nothing read: offline, never the invitation.
        let cold = ClubsListRules.state(phase: .failed(transport: true), hasClubs: false, isConnected: false)
        #expect(cold.brandedState == .offline(hasContent: false))
        // Only a successful empty read is the invitation.
        let empty = ClubsListRules.state(phase: .loaded(at: Self.now), hasClubs: false, isConnected: true)
        #expect(empty.brandedState == .empty)
    }

    @Test("Club detail: offline is offline; a membership answer is a notice, not a branded failure")
    func clubDetailBrandedStates() {
        #expect(ClubDetailIssue.offline.brandedState == .offline(hasContent: false))
        for issue in [ClubDetailIssue.removed, .notYetMember, .left, .clubGone] {
            #expect(issue.brandedState == nil)
        }
    }

    @Test("Discover and Browse: content wins (offline band), then loading, then failure, then empty")
    func pageRules() {
        for rule in [DiscoverPageRules.brandedState, BrowsePageRules.brandedState] {
            #expect(rule(true, true, false, true) == nil, "content online: no overlay, even while refreshing")
            #expect(rule(false, true, true, true) == nil, "content stays after a failed refresh")
            #expect(rule(false, true, false, false) == .offline(hasContent: true), "content offline: the band")
            #expect(rule(true, false, false, true) == .loading)
            #expect(rule(false, false, true, false) == .offline(hasContent: false))
            #expect(rule(false, false, false, true) == .empty)
        }
    }

    // MARK: Profile (amendment 10)

    @Test("Profile new account shows Nothing saved yet with Import and Find, and no zero counts")
    func profileNewAccount() {
        #expect(ProfileListsPolicy.libraryState(entryCount: 0, loadState: .loaded) == .empty)
        #expect(ProfileListsPolicy.libraryState(entryCount: 0, loadState: .loading) == .loading)
        #expect(ProfileListsPolicy.libraryState(entryCount: 0, loadState: .notLoaded) == .loading)
        #expect(ProfileListsPolicy.libraryState(entryCount: 3, loadState: .failed) == nil, "rows on screen win")
        #expect(ProfileListsPolicy.newAccountHeadline(german: false) == "Nothing saved yet.")
        #expect(ProfileListsPolicy.newAccountHeadline(german: true) == "Noch nichts gespeichert.")
        #expect(ProfileListsPolicy.importTitle(german: false) == "Import")
        #expect(ProfileListsPolicy.importTitle(german: true) == "Importieren")
        #expect(ProfileListsPolicy.findTitle(german: false) == "Find")
        #expect(ProfileListsPolicy.findTitle(german: true) == "Finden")
        // An empty library has no summary line at all (no "0 anime · 0 manga · 0 completed").
        #expect(ProfileListsPolicy.summary([], german: false) == "")
    }

    @Test("Profile summary leaves out zero parts")
    func profileSummaryHasNoZeros() {
        let mangaOnly = [Self.entry(.manga, 1, .current), Self.entry(.manga, 2, .planning)]
        #expect(ProfileListsPolicy.summary(mangaOnly, german: false) == "2 manga")
        #expect(ProfileListsPolicy.summary(mangaOnly, german: true) == "2 Manga")
        let mixed = [Self.entry(.anime, 1, .completed), Self.entry(.manga, 2, .current)]
        #expect(ProfileListsPolicy.summary(mixed, german: false) == "1 anime · 1 manga · 1 completed")
        let animeNoneDone = [Self.entry(.anime, 1, .current)]
        #expect(ProfileListsPolicy.summary(animeNoneDone, german: false) == "1 anime")
    }

    // MARK: Clubs invitation (amendment 10)

    @Test("Clubs invitation copy: the club-room language with Create and Join, EN and DE")
    func clubsInvitationCopy() {
        #expect(ClubsEmptyCopy.headline(german: false) == "Watch together.\nPrivate by design.")
        #expect(ClubsEmptyCopy.headline(german: true) == "Gemeinsam schauen.\nPrivat von Anfang an.")
        #expect(ClubsEmptyCopy.create(german: false) == "Start a club")
        #expect(ClubsEmptyCopy.create(german: true) == "Einen Club gründen")
        #expect(ClubsEmptyCopy.join(german: false) == "Join with a code")
        #expect(ClubsEmptyCopy.join(german: true) == "Mit Code beitreten")
        #expect(ClubsEmptyCopy.footer(german: false) == "Shared stories. Your people.")
        #expect(ClubsEmptyCopy.footer(german: true) == "Geteilte Geschichten. Deine Leute.")
        // No internal words, no sample people (PROTOTYPE_SPEC §7.2).
        let all = [false, true].flatMap { g in
            [ClubsEmptyCopy.kicker(german: g), ClubsEmptyCopy.headline(german: g), ClubsEmptyCopy.line(german: g),
             ClubsEmptyCopy.create(german: g), ClubsEmptyCopy.join(german: g), ClubsEmptyCopy.footer(german: g),
             ClubsEmptyCopy.size(german: g)]
        }
        for word in ["Sunday Club", "Mina", "Jules", "verified", "server", "fallback"] {
            #expect(!all.contains { $0.localizedCaseInsensitiveContains(word) })
        }
    }

    // MARK: Folio keys

    @Test("Folio keys: light on anime, the solid manga-leaf key on manga (amendment 4)")
    func folioKeyStyles() {
        #expect(FolioPolicy.keyStyle(for: .anime) == .light)
        #expect(FolioPolicy.keyStyle(for: .manga) == .dark)
        let face = KuroKeyFace(style: FolioPolicy.keyStyle(for: .manga))
        #expect(face.size == 40 && face.radius == 6)
    }

    // MARK: Skeleton blocks

    @Test("Skeleton blocks stay visible on every canvas (Home, manga Home, detail paper)")
    func skeletonBlocksVisibleOnEveryCanvas() throws {
        for hex in ["#fffef8", "#f5f5f3", "#f5f5f4"] {
            let canvas = try #require(KuroRGB(hex: hex))
            let block = KuroSkeleton.block(on: canvas)
            // At least 12/255 darker on every channel than the canvas it lands on.
            #expect(canvas.r - block.r >= 12.0 / 255, "\(hex)")
            #expect(canvas.g - block.g >= 12.0 / 255, "\(hex)")
            #expect(canvas.b - block.b >= 12.0 / 255, "\(hex)")
        }
        #expect(KuroSkeleton.deepBlockInkOpacity > KuroSkeleton.blockInkOpacity)
    }

    // MARK: Club room metrics

    @Test("Club room tightens at 320 (PROTOTYPE_SPEC §5) and keeps the 390 metrics on wider rooms")
    func clubRoomMetricsByWidth() {
        // The room is the page width minus the 20 pt gutters: 280 at 320, 335 at 375, 350 at 390.
        #expect(ClubRoomMetrics.forRoomWidth(280) == .compact)
        #expect(ClubRoomMetrics.forRoomWidth(ClubRoomMetrics.compactRoomWidth) == .compact)
        #expect(ClubRoomMetrics.forRoomWidth(335) == .regular)
        #expect(ClubRoomMetrics.forRoomWidth(350) == .regular)
        #expect(ClubRoomMetrics.forRoomWidth(0) == .regular, "an unmeasured room keeps the 390 metrics")
        #expect(ClubRoomMetrics.compact == ClubRoomMetrics(horizontalPadding: 12, mastheadGap: 8, seal: 36,
                                                            headline: 19, notePadding: 13))
        #expect(ClubRoomMetrics.regular == ClubRoomMetrics(horizontalPadding: 16, mastheadGap: 10, seal: 43,
                                                            headline: 22, notePadding: 15))
    }
}
