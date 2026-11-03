//
//  DSsongsTests.swift
//  KuroTests
//
//  Songs + entities lane of the details-songs pass (docs/superpowers/specs/2026-11-03-details-songs-platform-
//  design.md §5.1, §5.2, §8, §9). Pure logic only:
//    - DSsongsTests: the edge-peek table, the branded tile's values, initials;
//    - SongShelfTests: episode spans, version collapse, parts, fold, veil (auto-reveal, NSFW), the row's
//      action, the Apple URL rules, copy and VoiceOver strings;
//    - EntityPagesTests: sorting, by-year grouping, facts and copy, description cleaning.
//

import Foundation
import KuroCore
import Testing
@testable import Kuro

// MARK: - Shared rules

@MainActor
@Suite("DS songs: edge peek and branded tile")
struct DSsongsTests {
    @Test("Edge peek: the spec §5.1 table")
    func peekTable() {
        let rows: [(visible: CGFloat, width: CGFloat, slice: CGFloat, whole: Int)] = [
            (366, 98, 30, 3), (370, 100, 28, 3), (304, 112, 52, 2), (410, 112, 32, 3), (660, 112, 30, 5),
        ]
        for row in rows {
            let width = EntityRailPeek.cardWidth(visible: row.visible)
            #expect(width == row.width, "visible \(row.visible)")
            let slice = row.visible - CGFloat(row.whole) * (width + EntityRailPeek.spacing)
            #expect(slice == row.slice, "visible \(row.visible)")
        }
        #expect(EntityRailPeek.cardWidth(visible: 0) == EntityRailPeek.preferredWidth)
        #expect(EntityRailPeek.coverHeight(width: 98) == 147)
    }

    @Test("Entity pages: the rail's visible width is the column minus the 24 pt gutter")
    func railVisible() {
        #expect(EntityPageLayout.gutter == 24)
        #expect(EntityPageLayout.railVisible(column: 390) == 366)
        #expect(EntityRailPeek.cardWidth(visible: EntityPageLayout.railVisible(column: 390)) == 98)
        #expect(EntityPageLayout.railVisible(column: 10) == 0)
        #expect(EntityPageLayout.studioNameSize(column: 320) == 34)
        #expect(EntityPageLayout.studioNameSize(column: 390) == 44)
    }

    @Test("Branded tile: the paper values are the prototype's D4 season tile")
    func tileValues() {
        #expect(EntityBrandedTile.Paper.fillTop == "FFFFFF")
        #expect(EntityBrandedTile.Paper.fillBottom == "EEF1EE")
        #expect(EntityBrandedTile.Paper.border == "D9DEDB")
        #expect(EntityBrandedTile.Paper.stripe == "232C24")
        #expect(EntityBrandedTile.Paper.stripeEvery == 6)
        #expect(EntityBrandedTile.Paper.mark == "7B847E")
        #expect(EntityBrandedTile.Paper.titleInk == "4F5A52")
        #expect(EntityBrandedTile.Paper.minTitleWidth == 60)
    }

    @Test("Initials: two words give first and last initial; one word its first two letters")
    func initials() {
        #expect(EntityBrandedTile.initials("Yuuki Kaji") == "YK")
        #expect(EntityBrandedTile.initials("Kana Hanazawa") == "KH")
        #expect(EntityBrandedTile.initials("MAPPA") == "MA")
        #expect(EntityBrandedTile.initials("Jean-Pierre Polnareff") == "JP")
        #expect(EntityBrandedTile.initials("  ") == nil)
        #expect(EntityBrandedTile.initials(nil) == nil)
    }
}

// MARK: - Songs

@MainActor
@Suite("DS songs: the song shelf")
struct SongShelfTests {
    static func apple(_ id: Int, preview: Bool = true) -> AppleSongMatch? {
        AppleSongMatch(trackId: id,
                       artwork: "https://is1-ssl.mzstatic.com/image/thumb/Music/a/\(id)/600x600bb.jpg",
                       preview: preview ? "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/\(id).m4a" : nil,
                       music: "https://music.apple.com/jp/album/x/\(id + 1)?i=\(id)", confidence: 0.95)
    }

    static func song(_ kind: ThemeSongKind, _ sequence: Int?, _ title: String, artist: String? = "Artist",
                     episodes: String? = nil, version: Int? = nil, spoiler: Bool = false, nsfw: Bool = false,
                     apple: AppleSongMatch? = nil) -> ThemeSong {
        ThemeSong(kind: kind, sequence: sequence, title: title, artist: artist, episodes: episodes, version: version,
                  isSpoiler: spoiler, isNSFW: nsfw, apple: apple)
    }

    // MARK: Spans

    @Test("Episode spans: hyphen, en dash, comma lists, single, open")
    func spans() {
        #expect(SongEpisodeSpan.parse("1-19") == SongEpisodeSpan(first: 1, last: 19, isOpen: false))
        #expect(SongEpisodeSpan.parse("1–12") == SongEpisodeSpan(first: 1, last: 12, isOpen: false))
        #expect(SongEpisodeSpan.parse("6-16, 18-19") == SongEpisodeSpan(first: 6, last: 19, isOpen: false))
        #expect(SongEpisodeSpan.parse("26") == SongEpisodeSpan(first: 26, last: 26, isOpen: false))
        #expect(SongEpisodeSpan.parse("13-") == SongEpisodeSpan(first: 13, last: nil, isOpen: true))
        #expect(SongEpisodeSpan.parse(" ") == nil)
        #expect(SongEpisodeSpan.parse(nil) == nil)
        #expect(SongEpisodeSpan.parse("TBA") == nil)
        #expect(SongEpisodeSpan.display("6-16, 18-19") == "6–16, 18–19")
    }

    // MARK: Versions

    @Test("Versions of one song collapse into one row with tags; v1 is never shown alone")
    func versions() throws {
        let songs = [
            Self.song(.opening, 2, "SPECIALZ", episodes: "6-16, 18-19", version: 1),
            Self.song(.opening, 2, "SPECIALZ", episodes: "20-22", version: 2),
            Self.song(.opening, 2, "Specialz (TV Size)", episodes: "23", version: 3),
            Self.song(.ending, 1, "Akari", episodes: "1-5"),
        ]
        let rows = SongShelfGrouping.collapse(songs)
        #expect(rows.count == 2)
        let op = try #require(rows.first)
        #expect(op.versions.count == 3)
        #expect(op.versionTags(german: false) == ["v1 Ep. 6–16, 18–19", "v2 Ep. 20–22", "v3 Ep. 23"])
        #expect(op.versionTags(german: true) == ["v1 F. 6–16, 18–19", "v2 F. 20–22", "v3 F. 23"])
        #expect(op.span == SongEpisodeSpan(first: 6, last: 23, isOpen: false))
        #expect(op.isTVSize)
        #expect(op.displayTitle == "SPECIALZ")
        #expect(rows.last?.versionTags(german: false) == [])
    }

    @Test("TV-size marker: detected, stripped from the shown title, collapse key ignores it")
    func tvSize() {
        #expect(SongShelfGrouping.hasTVSizeMarker("Gurenge (TV Size)"))
        #expect(SongShelfGrouping.hasTVSizeMarker("Gurenge TV ver."))
        #expect(SongShelfGrouping.hasTVSizeMarker("紅蓮華 TVサイズ"))
        #expect(!SongShelfGrouping.hasTVSizeMarker("Television"))
        #expect(SongShelfGrouping.strippingTVSizeMarker("Gurenge (TV Size)") == "Gurenge")
        #expect(SongShelfGrouping.strippingTVSizeMarker("Gurenge") == "Gurenge")
        #expect(SongShelfGrouping.normalisedTitle("Gurenge (TV Size)") == SongShelfGrouping.normalisedTitle("GURENGE"))
        #expect(SongShelfGrouping.normalisedTitle("Ninelie!") == SongShelfGrouping.normalisedTitle("ninelie"))
        #expect(SongShelfGrouping.normalisedTitle("Ninelie") != SongShelfGrouping.normalisedTitle("Ninelie 2"))
    }

    @Test("Different kinds or sequences never collapse")
    func noCrossCollapse() {
        let rows = SongShelfGrouping.collapse([
            Self.song(.opening, 1, "Same"), Self.song(.ending, 1, "Same"), Self.song(.opening, 2, "Same"),
        ])
        #expect(rows.count == 3)
    }

    // MARK: Parts

    @Test("Parts: openings start parts; endings join the part that holds their first episode")
    func parts() {
        let songs = [
            Self.song(.ending, 1, "Akari", episodes: "1-5"),
            Self.song(.opening, 1, "Ao no Sumika", episodes: "1-5"),
            Self.song(.opening, 2, "SPECIALZ", episodes: "6-23"),
            Self.song(.ending, 2, "more than words", episodes: "6-23"),
            Self.song(.insert, nil, "Insert", episodes: "14"),
        ]
        let parts = SongShelfGrouping.parts(songs)
        #expect(parts.map(\.kind) == [.episodes(first: 1, last: 5), .episodes(first: 6, last: 23)])
        #expect(parts[0].rows.map(\.song.title) == ["Ao no Sumika", "Akari"])
        #expect(parts[1].rows.map(\.song.title) == ["SPECIALZ", "more than words", "Insert"])
        #expect(SongShelfCopy.partHeading(parts[0].kind, german: false) == "Ep. 1–5")
        #expect(SongShelfCopy.partHeading(parts[1].kind, german: true) == "F. 6–23")
        #expect(SongShelfCopy.partSpoken(parts[0].kind, german: false) == "Episodes 1 to 5")
        #expect(SongShelfCopy.partSpoken(parts[0].kind, german: true) == "Folgen 1 bis 5")
    }

    @Test("One part only: no headings; no openings with ranges: one list")
    func singlePart() {
        let one = SongShelfGrouping.parts([
            Self.song(.opening, 1, "Gurenge", episodes: "1-19"), Self.song(.ending, 1, "from the edge", episodes: "1-25"),
        ])
        #expect(one.map(\.kind) == [.all])
        let none = SongShelfGrouping.parts([
            Self.song(.ending, 1, "A", episodes: "1-12"), Self.song(.insert, nil, "B"), Self.song(.opening, 1, "C"),
        ])
        #expect(none.map(\.kind) == [.all])
        #expect(none.first?.rows.map(\.song.title) == ["C", "A", "B"])
        #expect(SongShelfCopy.partHeading(.all, german: false) == nil)
        #expect(SongShelfGrouping.parts([]).isEmpty)
    }

    @Test("Songs without a range go into a final Other songs part, only when other parts exist")
    func otherSongs() {
        let parts = SongShelfGrouping.parts([
            Self.song(.opening, 1, "A", episodes: "1-12"), Self.song(.insert, nil, "B"),
        ])
        #expect(parts.map(\.kind) == [.episodes(first: 1, last: 12), .other])
        #expect(SongShelfCopy.partHeading(.other, german: false) == "Other songs")
        #expect(SongShelfCopy.partHeading(.other, german: true) == "Weitere Songs")
    }

    @Test("Songs before the first opening join the first part; the last part stays open on an open range")
    func edges() {
        let parts = SongShelfGrouping.parts([
            Self.song(.ending, 1, "Early", episodes: "1"),
            Self.song(.opening, 1, "A", episodes: "2-12"),
            Self.song(.opening, 2, "B", episodes: "13-"),
        ])
        #expect(parts.map(\.kind) == [.episodes(first: 2, last: 12), .episodes(first: 13, last: nil)])
        #expect(parts[0].rows.map(\.song.title) == ["A", "Early"])
        #expect(SongShelfCopy.partHeading(parts[1].kind, german: false) == "Ep. 13–")
        #expect(SongShelfCopy.partSpoken(parts[1].kind, german: false) == "Episodes from 13")
    }

    @Test("Fold: the first six rows, counting parts in order")
    func fold() {
        let songs = (1...4).map { Self.song(.opening, $0, "OP\($0)", episodes: "\($0 * 10 - 9)-\($0 * 10)") }
            + (1...4).map { Self.song(.ending, $0, "ED\($0)", episodes: "\($0 * 10 - 9)-\($0 * 10)") }
        let parts = SongShelfGrouping.parts(songs)
        #expect(SongShelfGrouping.rowCount(parts) == 8)
        let folded = SongShelfGrouping.folded(parts, limit: DetailSongShelf.collapsedRows)
        #expect(SongShelfGrouping.rowCount(folded) == 6)
        #expect(folded.flatMap(\.rows).map(\.song.title) == ["OP1", "ED1", "OP2", "ED2", "OP3", "ED3"])
    }

    // MARK: Veil

    @Test("Spoilers auto-reveal once progress reached the first episode; NSFW never does")
    func veil() throws {
        let spoiler = try #require(SongShelfGrouping.collapse([Self.song(.ending, 2, "S", episodes: "12-13", spoiler: true)]).first)
        #expect(SongShelfGrouping.isVeiled(spoiler, revealed: false, progress: 0))
        #expect(SongShelfGrouping.isVeiled(spoiler, revealed: false, progress: 11))
        #expect(!SongShelfGrouping.isVeiled(spoiler, revealed: false, progress: 12))
        #expect(!SongShelfGrouping.isVeiled(spoiler, revealed: true, progress: 0))
        let nsfw = try #require(SongShelfGrouping.collapse([Self.song(.opening, 1, "N", episodes: "1-12", nsfw: true)]).first)
        #expect(SongShelfGrouping.isVeiled(nsfw, revealed: false, progress: 24))
        #expect(!SongShelfGrouping.isVeiled(nsfw, revealed: true, progress: 0))
        let plain = try #require(SongShelfGrouping.collapse([Self.song(.opening, 1, "P")]).first)
        #expect(!SongShelfGrouping.isVeiled(plain, revealed: false, progress: 0))
        let undated = try #require(SongShelfGrouping.collapse([Self.song(.ending, 1, "U", spoiler: true)]).first)
        #expect(SongShelfGrouping.isVeiled(undated, revealed: false, progress: 99))
    }

    // MARK: Action

    @Test("Row action: preview, Apple Music link, Listen, or nothing while veiled")
    func action() throws {
        let preview = try #require(SongShelfGrouping.collapse([Self.song(.opening, 1, "A", apple: Self.apple(11))]).first)
        guard case .preview(let song) = SongShelfGrouping.action(for: preview, veiled: false, previewFailed: false) else {
            Issue.record("expected a preview")
            return
        }
        #expect(song.apple?.trackId == 11)
        #expect(SongShelfGrouping.action(for: preview, veiled: true, previewFailed: false) == .none)
        if case .appleMusic(let url) = SongShelfGrouping.action(for: preview, veiled: false, previewFailed: true) {
            #expect(url.host() == "music.apple.com")
        } else {
            Issue.record("a failed preview falls back to Apple Music")
        }
        let noPreview = try #require(SongShelfGrouping.collapse([Self.song(.opening, 1, "B", apple: Self.apple(12, preview: false))]).first)
        if case .appleMusic = SongShelfGrouping.action(for: noPreview, veiled: false, previewFailed: false) {} else {
            Issue.record("a match without a preview offers Apple Music")
        }
        let unmatched = try #require(SongShelfGrouping.collapse([Self.song(.opening, 1, "C")]).first)
        #expect(SongShelfGrouping.action(for: unmatched, veiled: false, previewFailed: false) == .listen)
    }

    @Test("A later version's match plays when the first version has none")
    func matchedVersion() throws {
        let row = try #require(SongShelfGrouping.collapse([
            Self.song(.opening, 1, "A", episodes: "1-12", version: 1),
            Self.song(.opening, 1, "A", episodes: "13-24", version: 2, apple: Self.apple(21)),
        ]).first)
        #expect(row.matched?.version == 2)
        if case .preview(let song) = SongShelfGrouping.action(for: row, veiled: false, previewFailed: false) {
            #expect(song.version == 2)
        } else {
            Issue.record("expected the v2 preview")
        }
    }

    // MARK: Apple URLs

    @Test("Apple rules: a low confidence or foreign host is never a match; previews only on Apple's hosts")
    func appleRules() {
        #expect(AppleSongMatch(trackId: 1, artwork: nil, preview: nil, music: "https://music.apple.com/x", confidence: 0.79) == nil)
        #expect(AppleSongMatch(trackId: 1, artwork: nil, preview: nil, music: "https://evil.example.com/x", confidence: 0.9) == nil)
        let foreign = AppleSongMatch(trackId: 1, artwork: "https://evil.example.com/a/600x600bb.jpg",
                                     preview: "https://evil.example.com/p.m4a", music: "https://music.apple.com/x", confidence: 0.9)
        #expect(foreign?.artworkURL == nil)
        #expect(foreign?.previewURL == nil)
        let song = Self.song(.opening, 1, "A", apple: foreign)
        #expect(!SongPreviewPlayer.canPreview(song))
        #expect(SongPreviewPlayer.canPreview(Self.song(.opening, 1, "A", apple: Self.apple(5))))
    }

    @Test("Artwork is resized to 132 px and re-checked to be on *.mzstatic.com")
    func artwork() throws {
        let url = try #require(URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/a/1/600x600bb.jpg"))
        #expect(SongShelfGrouping.artworkURL(url, side: 132)?.absoluteString
                == "https://is1-ssl.mzstatic.com/image/thumb/Music/a/1/132x132bb.jpg")
        let foreign = try #require(URL(string: "https://evil.example.com/600x600bb.jpg"))
        #expect(SongShelfGrouping.artworkURL(foreign, side: 132) == nil)
        #expect(SongShelfGrouping.artworkURL(nil, side: 132) == nil)
    }

    // MARK: Copy

    @Test("Row copy: kind word, spoken row with artist, TV size, version; veiled; artist not listed")
    func rowCopy() throws {
        let row = try #require(SongShelfGrouping.collapse([
            Self.song(.opening, 1, "Gurenge", artist: "LiSA", episodes: "1-19", version: 1),
            Self.song(.opening, 1, "Gurenge (TV Size)", artist: "LiSA", episodes: "20-26", version: 2),
        ]).first)
        #expect(SongShelfCopy.rowSpoken(row, german: false) == "Opening 1, Gurenge, by LiSA, TV size, version 2")
        #expect(SongShelfCopy.rowSpoken(row, german: true) == "Vorspann 1, Gurenge, von LiSA, TV-Version, Version 2")
        #expect(SongShelfCopy.veiledSpoken(row, german: false) == "Spoiler, Opening 1. Double tap to show.")
        #expect(SongShelfCopy.veiledSpoken(row, german: true) == "Spoiler, Vorspann 1. Zum Anzeigen doppeltippen.")
        let anonymous = try #require(SongShelfGrouping.collapse([Self.song(.ending, nil, "Refrain", artist: nil)]).first)
        #expect(SongShelfCopy.rowSpoken(anonymous, german: false) == "Ending, Refrain, Artist not listed")
        #expect(SongShelfCopy.artistNotListed(german: true) == "Künstler nicht angegeben")
        #expect(SongShelfCopy.tileWord(row.song) == "OP 1")
        #expect(SongShelfCopy.tileWord(anonymous.song) == "ED")
        #expect(SongShelfCopy.rowSpan(anonymous, german: false) == nil)
    }

    @Test("Shelf strings: EXISTING words unchanged; attribution identical to the data lane's")
    func shelfStrings() {
        #expect(SongShelfCopy.heading(german: false) == "The sound of it.")
        #expect(SongShelfCopy.heading(german: true) == "So klingt es.")
        #expect(SongShelfCopy.spoiler(german: false) == "Spoiler. Tap to show.")
        #expect(SongShelfCopy.showAll(9, german: false) == "Show all 9 songs")
        #expect(SongShelfCopy.showAll(9, german: true) == "Alle 9 Songs zeigen")
        #expect(SongShelfCopy.showFewer(german: true) == "Weniger zeigen")
        #expect(SongShelfCopy.attribution(german: KuroLocale.isGerman) == SongPreviewCopy.attribution)
        #expect(SongShelfCopy.openInAppleMusic(german: KuroLocale.isGerman) == SongPreviewCopy.openInAppleMusic)
        #expect(SongShelfCopy.attribution(german: false) == "Preview courtesy of Apple Music")
        #expect(SongShelfCopy.songListSource(german: true) == "Songliste: AnimeThemes")
        #expect(SongShelfCopy.playLabel("Akari", german: false) == "Play preview of Akari")
        #expect(SongShelfCopy.playLabel("Akari", german: true) == "Vorschau von Akari abspielen")
        #expect(SongShelfCopy.previewUnavailable(german: true) == "Vorschau nicht verfügbar.")
        #expect(SongShelfCopy.count(1, german: false) == "1 song")
        #expect(SongShelfCopy.count(4, german: true) == "4 Songs")
    }

    @Test("Preview clock: capped at 30 s; Reduce Motion steps whole seconds")
    func clock() {
        #expect(SongPreviewClock.shownSeconds(elapsed: 12.6, stepsWholeSeconds: false) == 12.6)
        #expect(SongPreviewClock.shownSeconds(elapsed: 12.6, stepsWholeSeconds: true) == 12)
        #expect(SongPreviewClock.shownSeconds(elapsed: 45, stepsWholeSeconds: false) == 30)
        #expect(SongPreviewClock.shownSeconds(elapsed: -3, stepsWholeSeconds: false) == 0)
        #expect(SongShelfCopy.clock(12) == "0:12")
        #expect(SongShelfCopy.clock(30) == "0:30")
        #expect(SongShelfCopy.clock(75) == "1:15")
    }
}

// MARK: - Entity pages

@MainActor
@Suite("DS songs: entity pages")
struct EntityPagesTests {
    private func media(_ id: Int, _ kind: MediaKind = .anime, year: String = "2020", rating: Double? = nil,
                       format: String? = "TV") -> Media {
        Media(id: id, kind: kind, title: "Title \(id)", imageURL: nil, year: year, displayDescription: "",
              episodes: 12, chapters: nil, rating: rating, genres: nil, statusRaw: nil, formatRaw: format,
              popularityValue: nil, trendingValue: nil, createdAtValue: nil)
    }

    @Test("Sorting: rating high first, year newest first, era then year; ties keep the reader's order")
    func sorting() {
        let works = [media(1, year: "2010", rating: 80), media(2, year: "2022", rating: 90),
                     media(3, year: "1998", rating: 90), media(4, year: "2024", rating: nil)]
        #expect(EntityWorks.sorted(works, mode: .rating) { $0 }.map(\.id) == [2, 3, 1, 4])
        #expect(EntityWorks.sorted(works, mode: .year) { $0 }.map(\.id) == [4, 2, 1, 3])
        #expect(EntityWorks.sorted(works, mode: .era) { $0 }.map(\.id) == [4, 2, 1, 3])
    }

    @Test("By year: newest first, order kept inside a year, unknown years left out; inline up to three")
    func byYear() {
        let works = [media(1, year: "2023"), media(2, year: "2020"), media(3, year: "2023"), media(4, year: ""),
                     media(5, year: "2023"), media(6, year: "2023")]
        let groups = EntityWorks.byYear(works)
        #expect(groups.map(\.year) == [2023, 2020])
        #expect(groups.first?.works.map(\.id) == [1, 3, 5, 6])
        #expect(groups.first?.isInline == false)
        #expect(groups.last?.isInline == true)
        #expect(EntityWorks.byYear([]).isEmpty)
    }

    @Test("Character copy: eyebrow, appearances, gender and age only when present")
    func characterCopy() {
        #expect(EntityPageCopy.characterEyebrow(title: "Jujutsu Kaisen", german: false) == "CHARACTER · JUJUTSU KAISEN")
        #expect(EntityPageCopy.characterEyebrow(title: "Jujutsu Kaisen", german: true) == "FIGUR · JUJUTSU KAISEN")
        #expect(EntityPageCopy.characterEyebrow(title: nil, german: false) == "CHARACTER")
        #expect(EntityPageCopy.appearances(4, german: false) == "4 appearances in Kuro")
        #expect(EntityPageCopy.appearances(1, german: true) == "1 Auftritt in Kuro")
        #expect(EntityPageCopy.gender("Female", german: true) == "Weiblich")
        #expect(EntityPageCopy.gender(nil, german: false) == nil)
        #expect(EntityPageCopy.age("17", german: false) == "Age 17")
        #expect(EntityPageCopy.age("", german: false) == nil)
    }

    @Test("Voice copy: the count part only once known; roles facts leave out a zero list count")
    func voiceCopy() {
        #expect(EntityPageCopy.voiceActorLine(roles: nil, german: false) == "Voice actor")
        #expect(EntityPageCopy.voiceActorLine(roles: 4, german: false) == "Voice actor · 4 roles in Kuro")
        #expect(EntityPageCopy.voiceActorLine(roles: 4, german: true) == "Sprecher·in · 4 Rollen in Kuro")
        #expect(EntityPageCopy.rolesFacts(roles: 4, inList: 1, german: false) == "4 roles in Kuro · 1 in your list")
        #expect(EntityPageCopy.rolesFacts(roles: 4, inList: 0, german: false) == "4 roles in Kuro")
        #expect(EntityPageCopy.rolesFacts(roles: 2, inList: 1, german: true) == "2 Rollen in Kuro · 1 in deiner Liste")
        #expect(EntityPageCopy.japaneseVoice(german: true) == "JAPANISCHE STIMME")
        #expect(EntityPageCopy.voiceEyebrow(german: false) == "VOICE · JAPANESE")
    }

    @Test("Studio and work lines")
    func workCopy() {
        #expect(EntityPageCopy.studioFacts(titles: 5, animation: true, german: false) == "Animation studio · 5 titles in Kuro")
        #expect(EntityPageCopy.studioFacts(titles: 5, animation: true, german: true) == "Animationsstudio · 5 Titel in Kuro")
        #expect(EntityPageCopy.studioFacts(titles: 1, animation: false, german: false) == "1 title in Kuro")
        #expect(EntityPageCopy.mediumYear(kind: .anime, year: "2020", german: false) == "Anime · 2020")
        #expect(EntityPageCopy.mediumYear(kind: .manga, year: "0", german: false) == "Manga")
        #expect(EntityPageCopy.workLine(formatRaw: "TV", kind: .anime, role: "Director", german: false) == "TV · Director")
        #expect(EntityPageCopy.workLine(formatRaw: nil, kind: .manga, role: nil, german: false) == "Manga")
        #expect(EntityPageCopy.formatWord("MOVIE", german: false) == "Film")
        #expect(EntityPageCopy.formatWord("TV_SHORT", german: true) == "TV-Kurzserie")
        #expect(EntityPageCopy.formatWord("NOVEL", german: false) == "Light novel")
        #expect(EntityPageCopy.formatWord("WEIRD", german: false) == nil)
        #expect(EntityCover.kindWord(kind: .anime, formatRaw: "TV", german: false) == "Anime · TV")
        #expect(EntityCover.kindWord(kind: .manga, formatRaw: "MANGA", german: false) == "Manga")
        #expect(EntityCover.kindWord(kind: .manga, formatRaw: "NOVEL", german: false) == "Light novel")
        #expect(EntityPageCopy.roleLine(title: "Jujutsu Kaisen", role: "MAIN", year: 2020, german: false)
                == "Jujutsu Kaisen · Main · 2020")
        #expect(EntityPageCopy.roleLine(title: "X", role: "MAIN", year: nil, german: true) == "X · Hauptrolle")
    }

    @Test("Progress words: none before the first unit; totals when known")
    func progressCopy() {
        #expect(EntityPageCopy.progress(0, total: 23, kind: .anime, german: false) == nil)
        #expect(EntityPageCopy.progress(6, total: 23, kind: .anime, german: false) == "Ep. 6 / 23")
        #expect(EntityPageCopy.progress(6, total: nil, kind: .anime, german: true) == "F. 6")
        #expect(EntityPageCopy.progress(68, total: nil, kind: .manga, german: true) == "Kap. 68")
        #expect(EntityPageCopy.inYourList(title: "Jujutsu Kaisen", detail: "Ep. 6 / 23", german: false)
                == "In your list: Jujutsu Kaisen · Ep. 6 / 23")
        #expect(EntityPageCopy.inYourList(title: "X", detail: nil, german: true) == "In deiner Liste: X")
    }

    @Test("Description: HTML, spoiler blocks and bold markers removed; empty becomes nil")
    func description() {
        let raw = "__Height:__ 190cm<br><br>A teacher. ~!He is the\nstrongest.!~ Kind.<i>!</i>"
        let cleaned = EntityPageCopy.description(raw) ?? ""
        #expect(cleaned.hasPrefix("Height: 190cm"))
        #expect(cleaned.contains("A teacher."))
        #expect(cleaned.contains("Kind."))
        #expect(!cleaned.contains("strongest"))
        #expect(!cleaned.contains("<"))
        #expect(!cleaned.contains("__"))
        #expect(!cleaned.contains("\n\n\n"))
        #expect(EntityPageCopy.description("~!all spoiler!~") == nil)
        #expect(EntityPageCopy.description(nil) == nil)
        #expect(!EntityDescription.needsFold("Short."))
        #expect(EntityDescription.needsFold(String(repeating: "a ", count: 200)))
    }

    @Test("Occupation eyebrow: up to three words, upper case; nil when none")
    func occupations() {
        #expect(EntityPageCopy.occupationEyebrow(["Director", "Storyboard"]) == "DIRECTOR · STORYBOARD")
        #expect(EntityPageCopy.occupationEyebrow([" "]) == nil)
        #expect(EntityPageCopy.occupationEyebrow(nil) == nil)
    }

    @Test("Studio year page: a stable journey id per studio and year")
    func yearPageID() {
        #expect(EntityYearPage.id(studioName: "MAPPA", year: 2023) == "studio-year:MAPPA:2023")
        let group = EntityYearGroup(year: 2023, works: [media(1, year: "2023")])
        #expect(EntityYearPage.page(studioName: "MAPPA", group: group).id == "seeAll:studio-year:MAPPA:2023")
    }
}
