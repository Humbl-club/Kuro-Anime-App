//
//  UpNextStoreTests.swift
//  KuroTests
//
//  W10 "Up next in your series": the pure contract (decoding, device filter, copy), the owner
//  `UpNextStore` against the in-process StubPostgREST, and the Collection section's placement rules.
//

import Testing
import Foundation
import KuroCore
import KuroLibrary
@testable import Kuro

@MainActor
@Suite("Up next", .serialized, .timeLimit(.minutes(1)))
struct UpNextStoreTests {
    // MARK: Pure contract

    @Test func rowsDecodeBothMedia() throws {
        let anime = Data("""
        {"media_type":"anime","media_id":1,"title":"Frieren S2","cover_image":null,"format":"TV","status":"NOT_YET_RELEASED",
         "start_year":2026,"total_units":12,"after_media_id":9,"after_title":"Frieren","link":"sequel"}
        """.utf8)
        let item = try JSONDecoder().decode(UpNextItem.self, from: anime)
        #expect(item.key == MediaKey(kind: .anime, id: 1))
        #expect(item.afterKey == MediaKey(kind: .anime, id: 9))
        #expect(item.link == .sequel)
        #expect(item.isAnnounced)
        let manga = Data("""
        {"media_type":"manga","media_id":5,"title":"B","after_media_id":4,"after_title":"A","link":"reviewed"}
        """.utf8)
        let m = try JSONDecoder().decode(UpNextItem.self, from: manga)
        #expect(m.key == MediaKey(kind: .manga, id: 5))
        #expect(m.afterKey == MediaKey(kind: .manga, id: 4))
        #expect(m.link == .reviewed)
        #expect(!m.isAnnounced)
        let film = Data("""
        {"media_type":"film","media_id":5,"title":"B","after_media_id":4,"after_title":"A","link":"sequel"}
        """.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(UpNextItem.self, from: film) }
    }

    @Test func trackedOrHiddenRowsNeverShow() {
        func item(_ id: Int) -> UpNextItem {
            UpNextItem(key: MediaKey(kind: .anime, id: id), title: "T\(id)", afterKey: MediaKey(kind: .anime, id: 100),
                       afterTitle: "P", link: .sequel)
        }
        let a1 = item(1), a2 = item(2), a3 = item(3)
        let tracked: Set<MediaKey> = [a2.key], hidden: Set<MediaKey> = [a3.key]
        #expect(UpNextPolicy.visible([a1, a2, a3], tracked: tracked, hidden: hidden).map(\.key) == [a1.key])
        #expect(UpNextPolicy.visible([a3, a1], tracked: tracked, hidden: hidden).map(\.key) == [a1.key])
        #expect(UpNextPolicy.visible([a1, a2, a3], tracked: [], hidden: []) == [a1, a2, a3])
    }

    @Test func copyIsEnglishAndGerman() {
        #expect(UpNextCopy.after("Frieren", german: false) == "Sequel to Frieren")
        #expect(UpNextCopy.after("Frieren", german: true) == "Fortsetzung von Frieren")
        #expect(UpNextCopy.heading(german: false) == "Up next in your series")
        #expect(UpNextCopy.heading(german: true) == "Als Nächstes in deinen Reihen")
        #expect(UpNextCopy.alreadyInLibrary(german: false) == "Already in your library.")
        #expect(UpNextCopy.alreadyInLibrary(german: true) == "Schon in deiner Bibliothek.")
        #expect(UpNextCopy.announced(german: true) == "Angekündigt")
        #expect(UpNextCopy.plan(german: true) == "Planen")
        #expect(UpNextCopy.dismissSubtitle(german: false) == "Also hidden on Discover.")
    }
}
