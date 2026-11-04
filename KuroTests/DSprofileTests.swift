import CoreGraphics
import Foundation
import Testing
@testable import Kuro

/// Details-songs Profile + import + finishes lane: the edge-peek table (spec §5.1), the Discover All
/// changes (§14.2), the reminders row result mapping (§11.4) and the About lines (§15).
@Suite("Details-songs profile lane: finishes and reminders")
@MainActor
struct DSprofileTests {
    @Test("Edge peek: the spec's value table, pinned", arguments: [
        (CGFloat(366), 3, CGFloat(98), CGFloat(30)),
        (CGFloat(370), 3, CGFloat(100), CGFloat(28)),
        (CGFloat(304), 2, CGFloat(112), CGFloat(52)),
        (CGFloat(410), 3, CGFloat(112), CGFloat(32)),
        (CGFloat(660), 5, CGFloat(112), CGFloat(30))
    ])
    func peekTable(visible: CGFloat, shown: Int, width: CGFloat, slice: CGFloat) {
        let card = KuroRailPeek.cardWidth(visible: visible)
        #expect(card == width)
        let spacing = KuroRailPeek.spacing
        let fully = Int(((visible + spacing) / (card + spacing)).rounded(.down))
        #expect(fully == shown)
        let next = visible - CGFloat(fully) * (card + spacing)
        #expect(next == slice)
        #expect(next >= KuroRailPeek.peekMin)
    }

    @Test("Edge peek: covers are 2 : 3; an unmeasured rail uses the preferred width")
    func peekShapes() {
        #expect(KuroRailPeek.coverHeight(width: 100) == 150)
        #expect(KuroRailPeek.coverHeight(width: 98) == 147)
        #expect(KuroRailPeek.coverHeight(width: 112) == 168)
        #expect(KuroRailPeek.cardWidth(visible: 0) == 100)
    }

    @Test("Discover rails: the visible width is the column plus the trailing gutter (390, 320, 430, iPad)")
    func discoverRail() {
        #expect(DiscoverIssueLayout.railCover(column: 390 - 40, gutter: 20).width == 100)
        #expect(DiscoverIssueLayout.railCover(column: 320 - 32, gutter: 16).width == 112)
        #expect(DiscoverIssueLayout.railCover(column: 430 - 40, gutter: 20).width == 112)
        #expect(DiscoverIssueLayout.railCover(column: 680 - 40, gutter: 20).width == 112)
        #expect(DiscoverIssueLayout.railCap == 10)
    }

    @Test("Discover All: Manga new to you is a rail and Essential manga is the first More list; Anime and Manga unchanged")
    func discoverAll() {
        typealias Sections = DiscoverIssueSections
        let all = Sections.Inputs(issue: .all, realmRails: false, newToYou: true, essentials: true,
                                  mangaNewToYou: true, trending: true, essentialsManga: true, classicsManga: true)
        #expect(Sections.main(all) == [.newToYou, .essentials, .mangaNewToYou, .trending])
        // Usability spec D17: the fold is retired; Essential manga is the first More-lists link on All.
        #expect(Sections.moreLists(all, dropped: []).first == .route(.mangaEssentials))
        var manga = all
        manga.issue = .manga
        #expect(Sections.main(manga) == [.mangaNewToYou, .essentialsManga, .classicsManga])
        #expect(!Sections.moreLists(manga, dropped: []).contains(.route(.mangaEssentials)))
        var anime = all
        anime.issue = .anime
        #expect(!Sections.main(anime).contains(.essentialsManga))
        #expect(!Sections.moreLists(anime, dropped: []).contains(.route(.mangaEssentials)))
        // Without Essential manga content there is no link for it.
        var noEssentials = all
        noEssentials.essentialsManga = false
        #expect(!Sections.moreLists(noEssentials, dropped: []).contains(.route(.mangaEssentials)))
    }

    @Test("Reminders row: only a refusal leaves a line; on, off and signed out say nothing")
    func reminderNotice() {
        #expect(ProfileReminderNotice(.permissionDenied) == .denied)
        #expect(ProfileReminderNotice(.enabled) == nil)
        #expect(ProfileReminderNotice(.disabled) == nil)
        #expect(ProfileReminderNotice(.signedOut) == nil)
        #expect(ProfileReminderNotice.denied.line(german: false) == "Notifications are off for Kuro. Turn them on in Settings.")
        #expect(ProfileReminderNotice.denied.line(german: true)
                == "Mitteilungen für Kuro sind aus. Du kannst sie in den Einstellungen einschalten.")
    }

    @Test("About: the Apple Music preview line and the on-device line, EN and DE")
    func dataSources() {
        #expect(DataSourcesCopy.appleMusic(german: false).contains("Apple sees your IP address"))
        #expect(DataSourcesCopy.appleMusic(german: true).contains("sieht Apple deine IP-Adresse"))
        // The artwork loads when the songs are shown (as the privacy policy §4.16 says), not only on ▶.
        #expect(DataSourcesCopy.appleMusic(german: false).contains("artwork loads from Apple when the songs are shown"))
        #expect(DataSourcesCopy.appleMusic(german: true).contains("sobald die Songs angezeigt werden"))
        #expect(DataSourcesCopy.onDevice(german: false) == "Widgets and release reminders stay on this device.")
        #expect(DataSourcesCopy.onDevice(german: true) == "Widgets und Erinnerungen an Neuerscheinungen bleiben auf diesem Gerät.")
    }

    @Test("VoiceOver: the year card speaks as one element with full words")
    func yearSpoken() {
        let year = ProfileStats.Year(year: 2026, titles: 38, completed: 11, mostTime: nil)
        #expect(ProfileStatsCopy.yearSpoken(year, german: false)
                == "Year 2026. 38 titles saved or changed. 11 of them now completed")
        #expect(ProfileStatsCopy.yearSpoken(year, german: true)
                == "Jahr 2026. 38 Titel gespeichert oder geändert. 11 davon abgeschlossen")
    }
}
