//
//  DetailCopyTests.swift
//  KuroTests
//
//  The detail pages' shared EN/DE vocabulary (`DetailCopy`, DetailSharedComponents.swift): catalogue
//  formats and release states, club/friend list-status words (the Collection's `FolioStatus` words),
//  character roles, unit counts and the unknown fallback. Every case pins both languages explicitly.
//

import Testing
import KuroCore
@testable import Kuro

@MainActor
@Suite("Detail copy (EN/DE)")
struct DetailCopyTests {
    @Test("Formats read as words in both languages; empty input has no word")
    func formats() {
        #expect(DetailCopy.format("TV", german: false) == "TV")
        #expect(DetailCopy.format("MOVIE", german: true) == "Film")
        #expect(DetailCopy.format("LIGHT_NOVEL", german: false) == "Light novel")
        #expect(DetailCopy.format("LIGHT_NOVEL", german: true) == "Light Novel")
        #expect(DetailCopy.format("NOVEL", german: true) == "Roman")
        #expect(DetailCopy.format("TV_SHORT", german: true) == "TV-Kurzserie")
        #expect(DetailCopy.format("MUSIC", german: false) == "Music video")
        #expect(DetailCopy.format("SOME_NEW_FORMAT", german: false) == "Some new format")
        #expect(DetailCopy.format(nil, german: false) == nil)
        #expect(DetailCopy.format("  ", german: true) == nil)
    }

    @Test("Release states are reader words, never the raw server value")
    func releaseStates() {
        #expect(DetailCopy.releaseStatus("FINISHED", german: false) == "Finished")
        #expect(DetailCopy.releaseStatus("FINISHED", german: true) == "Abgeschlossen")
        #expect(DetailCopy.releaseStatus("RELEASING", german: true) == "Laufend")
        #expect(DetailCopy.releaseStatus("NOT_YET_RELEASED", german: false) == "Not yet released")
        #expect(DetailCopy.releaseStatus("CANCELLED", german: true) == "Eingestellt")
        #expect(DetailCopy.releaseStatus("HIATUS", german: false) == "On hiatus")
        #expect(DetailCopy.releaseStatus(nil, german: true) == nil)
    }

    @Test("Club and friend statuses use the Collection's words for the medium")
    func listStatuses() {
        #expect(DetailCopy.listStatus("CURRENT", medium: .anime, german: false) == "Watching")
        #expect(DetailCopy.listStatus("READING", medium: .manga, german: false) == "Reading")
        #expect(DetailCopy.listStatus("CURRENT", medium: .manga, german: true) == "Lese ich")
        #expect(DetailCopy.listStatus("WATCHING", medium: .anime, german: true) == "Schaue ich")
        #expect(DetailCopy.listStatus("PLANNING", medium: .anime, german: true) == "Geplant")
        #expect(DetailCopy.listStatus("ON_HOLD", medium: .anime, german: false) == "Paused")
        #expect(DetailCopy.listStatus("DROPPED", medium: .manga, german: true) == "Abgebrochen")
        #expect(DetailCopy.listStatus("completed", medium: .anime, german: true) == "Abgeschlossen")
        #expect(DetailCopy.listStatus("SOMETHING_ELSE", medium: .anime, german: false) == nil)
    }

    @Test("Character roles, units and the unknown fallback in both languages")
    func rolesUnitsUnknown() {
        #expect(DetailCopy.characterRole("MAIN", german: false) == "Main")
        #expect(DetailCopy.characterRole("SUPPORTING", german: true) == "Nebenrolle")
        #expect(DetailCopy.characterRole(" ", german: true) == nil)
        #expect(DetailCopy.characterRole("Narrator", german: true) == "Narrator")
        #expect(DetailCopy.episodes(22, german: false) == "22 eps")
        #expect(DetailCopy.episodes(1, german: true) == "1 Folge")
        #expect(DetailCopy.episodes(12, german: true) == "12 Folgen")
        #expect(DetailCopy.chapters(140, german: true) == "140 Kap.")
        #expect(DetailCopy.volumes(1, german: true) == "1 Band")
        #expect(DetailCopy.volumes(14, german: true) == "14 Bände")
        #expect(DetailCopy.volumes(14, german: false) == "14 vol")
        #expect(DetailCopy.unknown(german: false) == "Unknown")
        #expect(DetailCopy.unknown(german: true) == "Unbekannt")
    }

    @Test("No detail vocabulary uses an internal word (rulebook §9)")
    func noInternalWords() {
        let formats = ["TV", "TV_SHORT", "MOVIE", "OVA", "ONA", "SPECIAL", "MUSIC", "MANGA", "ONE_SHOT", "NOVEL", "LIGHT_NOVEL"]
        let states = ["FINISHED", "RELEASING", "NOT_YET_RELEASED", "CANCELLED", "HIATUS"]
        var words: [String] = []
        for german in [false, true] {
            words += formats.compactMap { DetailCopy.format($0, german: german) }
            words += states.compactMap { DetailCopy.releaseStatus($0, german: german) }
        }
        let banned = ["verif", "approved", "rpc", "bundle", "server", "mapping"]
        #expect(words.allSatisfy { word in !banned.contains { word.lowercased().contains($0) } }, "\(words)")
    }
}
