//
//  NavclubsTests.swift
//  KuroTests
//
//  Navigation contract, clubs lane (docs/superpowers/specs/2026-11-02-navigation-contract-design.md):
//  the club page as a journey (rail items and "This week" entries push titles, a pushed club shows
//  Back, the shrinking bar's start), create-then-open, the season overview journey, and the tools'
//  unsaved-input rules (N7: create club / rail / poll, tracking editor, contact, import Stop).
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
import SwiftUI
@testable import Kuro

@MainActor
@Suite("Navigation contract: clubs lane")
struct NavclubsTests {

    // MARK: Club journey (§1, N5, N9)

    @Test("A club journey pushes its rail items and This-week titles; the same title twice is one page")
    func clubJourneyPushesTitles() {
        let navigator = JourneyNavigator(root: .club(id: "c1"))
        let rail = ClubActivityTarget.key(mediaType: "ANIME", mediaId: 7)
        navigator.routes.openMedia(MediaRoute(rail))
        navigator.routes.openMedia(MediaRoute(rail))
        #expect(navigator.path == [.media(MediaRoute(kind: .anime, id: 7))])

        let week = ClubActivityTarget.key(mediaType: "manga", mediaId: 9)
        navigator.routes.openMedia(MediaRoute(week))
        #expect(navigator.path.count == 2)
        // Back to the club from the title: the club (the root) is popped to, never pushed again.
        navigator.routes.openClub("c1")
        #expect(navigator.path.isEmpty)
    }

    @Test("A tool opened from the club page never changes the club's stack (N7)")
    func clubToolKeepsStack() {
        let navigator = JourneyNavigator(root: .club(id: "c1"))
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 7))
        navigator.routes.presentAddToClub(MediaKey(kind: .anime, id: 7))
        #expect(navigator.path == [.media(MediaRoute(kind: .anime, id: 7))])
        #expect(navigator.tool?.id == "addToClub:anime:7")
    }

    @Test("A club opened from a page starts a new journey with the club as its root")
    func clubFromPageIsJourney() {
        let slot = PresentationSlot()
        slot.routes.openClub("c-new")
        guard case .journey(let navigator)? = slot.presented else {
            Issue.record("expected a journey")
            return
        }
        #expect(navigator.root == .club(id: "c-new"))
        #expect(navigator.path.isEmpty)
    }

    @Test("This-week entries open the right medium (any case of MANGA is manga)")
    func activityTarget() {
        #expect(ClubActivityTarget.key(mediaType: "MANGA", mediaId: 3) == MediaKey(kind: .manga, id: 3))
        #expect(ClubActivityTarget.key(mediaType: "manga", mediaId: 3) == MediaKey(kind: .manga, id: 3))
        #expect(ClubActivityTarget.key(mediaType: "ANIME", mediaId: 3) == MediaKey(kind: .anime, id: 3))
        #expect(ClubActivityTarget.key(mediaType: "", mediaId: 3) == MediaKey(kind: .anime, id: 3))
    }

    // MARK: Club chrome (N1, H1–H3)

    @Test("Back only on a pushed club; controls leave the room half way; the bar starts before the room ends")
    func clubChrome() {
        #expect(ClubChromeRules.showsBack(isPushed: true))
        #expect(!ClubChromeRules.showsBack(isPushed: false))
        #expect(ClubChromeRules.controlsOnRoom(0))
        #expect(ClubChromeRules.controlsOnRoom(0.49))
        #expect(!ClubChromeRules.controlsOnRoom(0.5))
        #expect(ClubChromeRules.collapseStart(heroHeight: 400) == 260)
        #expect(ClubChromeRules.collapseStart(heroHeight: 100) == 0)
        // Tied to the offset (no jump): half way through the collapse distance is half drawn.
        let start = ClubChromeRules.collapseStart(heroHeight: 400)
        let half = KuroCollapse.progress(offset: start + ClubChromeRules.collapseDistance / 2,
                                         start: start, distance: ClubChromeRules.collapseDistance)
        #expect(abs(half - 0.5) < 0.0001)
    }

    // MARK: Create, then open

    @Test("The created club opens after the sheet closes, for the same account only; Cancel opens nothing")
    func createThenOpen() {
        #expect(ClubCreationFollowUp.clubToOpen(created: "c9", isCurrent: true) == "c9")
        #expect(ClubCreationFollowUp.clubToOpen(created: "c9", isCurrent: false) == nil)
        #expect(ClubCreationFollowUp.clubToOpen(created: nil, isCurrent: true) == nil)
        #expect(ClubCreationFollowUp.clubToOpen(created: "", isCurrent: true) == nil)
    }

    // MARK: Season overview (N8)

    @Test("The season overview is a journey page; its rows push titles and the root is never pushed")
    func seasonOverviewJourney() {
        let id = HomeSeasonJourney.pageID(mediaId: 21)
        let root = JourneyPage.seasonOverview(AnyJourneyPage(id: id, title: "Frieren") { EmptyViewProbe() })
        #expect(root.id == "season:home:21")
        #expect(root.title == "Frieren")
        let navigator = JourneyNavigator(root: root)
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 22))
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 23))
        navigator.routes.openMedia(MediaRoute(kind: .anime, id: 22))
        #expect(navigator.path == [.media(MediaRoute(kind: .anime, id: 22))])
        navigator.routes.openPage(root)
        #expect(navigator.path.isEmpty)
    }

    // MARK: Unsaved input (N7)

    @Test("Discard guard: a clean form closes, a dirty one asks; swipe-down blocked while dirty or busy")
    func discardGuard() {
        #expect(KuroDiscardGuard.cancelStep(isDirty: false) == .close)
        #expect(KuroDiscardGuard.cancelStep(isDirty: true) == .confirm)
        #expect(!KuroDiscardGuard.blocksInteractiveDismiss(isDirty: false, isBusy: false))
        #expect(KuroDiscardGuard.blocksInteractiveDismiss(isDirty: true, isBusy: false))
        #expect(KuroDiscardGuard.blocksInteractiveDismiss(isDirty: false, isBusy: true))
        #expect(KuroDiscardGuard.title(german: false) == "Discard changes?")
        #expect(KuroDiscardGuard.title(german: true) == "Änderungen verwerfen?")
        #expect(KuroDiscardGuard.discardTitle(german: true) == "Verwerfen")
        #expect(KuroDiscardGuard.keepTitle(german: false) == "Keep editing")
    }

    @Test("Club forms: what counts as unsaved input")
    func clubForms() {
        #expect(!ClubFormRules.createClubIsDirty(name: "", description: "  ", sharingLevel: ClubFormRules.defaultSharingLevel))
        #expect(ClubFormRules.createClubIsDirty(name: "Fri", description: "", sharingLevel: "status"))
        #expect(ClubFormRules.createClubIsDirty(name: "", description: "x", sharingLevel: "status"))
        #expect(ClubFormRules.createClubIsDirty(name: "", description: "", sharingLevel: "private"))

        #expect(!ClubFormRules.createRailIsDirty(title: " ", description: ""))
        #expect(ClubFormRules.createRailIsDirty(title: "Watch", description: ""))
        #expect(ClubFormRules.createRailIsDirty(title: "", description: "line"))

        #expect(!ClubFormRules.createPollIsDirty(question: "", options: ["", " "]))
        #expect(ClubFormRules.createPollIsDirty(question: "Next?", options: ["", ""]))
        #expect(ClubFormRules.createPollIsDirty(question: "", options: ["A", ""]))
        #expect(ClubFormRules.createPollIsDirty(question: "", options: ["", "", ""]))
    }

    @Test("Tracking editor: changes against the filled draft; whitespace-only notes are no change")
    func trackingDraftChanges() {
        let baseline = TrackingDraft(entry: nil)
        var draft = baseline
        #expect(!draft.hasChanges(from: baseline))
        draft.notes = "   "
        #expect(!draft.hasChanges(from: baseline))
        draft.notes = "great"
        #expect(draft.hasChanges(from: baseline))
        draft = baseline
        draft.status = .current
        #expect(draft.hasChanges(from: baseline))
        draft = baseline
        draft.score = 8
        #expect(draft.hasChanges(from: baseline))
        draft = baseline
        draft.progress = 3
        #expect(draft.hasChanges(from: baseline))
    }

    @Test("Contact: the prefilled e-mail is never dirty, typed input is, a sent message is not")
    func contactDiscard() {
        let opened = ContactDraft(email: "a@example.com")
        let baseline = ContactDiscardRule.baseline(opening: opened)
        #expect(!ContactDiscardRule.isDirty(draft: opened, baseline: baseline, state: .idle))
        var typed = opened
        typed.message = "Hello"
        #expect(ContactDiscardRule.isDirty(draft: typed, baseline: baseline, state: .idle))
        #expect(!ContactDiscardRule.isDirty(draft: typed, baseline: baseline, state: .sent))
        #expect(!ContactDiscardRule.isDirty(draft: typed, baseline: nil, state: .idle))
        // A draft kept from an earlier visit is the user's input: closing would discard it.
        var kept = ContactDraft(email: "a@example.com")
        kept.message = "Earlier"
        let keptBaseline = ContactDiscardRule.baseline(opening: kept)
        #expect(ContactDiscardRule.isDirty(draft: kept, baseline: keptBaseline, state: .idle))
        var topic = opened
        topic.topic = .reportContent
        #expect(ContactDiscardRule.isDirty(draft: topic, baseline: baseline, state: .idle))
    }

    @Test("Import chooser: Close when idle, Stop while importing, never Stop half an Undo")
    func importChooserControl() {
        #expect(ImportChooserTopControl.resolve(busy: false, undoing: false) == .close)
        #expect(ImportChooserTopControl.resolve(busy: true, undoing: false) == .stop)
        #expect(ImportChooserTopControl.resolve(busy: true, undoing: true) == .closeDisabled)
        #expect(ImportChooserTopControl.stopAction(german: true) == "Anhalten")
        #expect(ImportChooserTopControl.stopAction(german: false) == "Stop")
    }
}

/// A page body for identity tests (the builder is payload; it is never rendered here).
private struct EmptyViewProbe: View {
    var body: some View { EmptyView() }
}
