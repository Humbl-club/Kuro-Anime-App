//
//  DetailsSongsDataTests.swift
//  KuroTests
//
//  DATA lane of the 2026-11-03 details/songs pass: the characters decode fix, the cast and voice-
//  actor readers (prepared RPCs with silent fallback), "More like this" card rows (per account),
//  the optional Apple fields on theme songs, and the one-at-a-time song preview player. HTTP tests
//  run the real supabase-swift client against StubPostgREST (in-process, no network).
//

import AVFoundation
import Foundation
import KuroCore
import Testing
import UIKit
@testable import Kuro

private enum DataLaneJSON {
    static let pgrst202 = StubResponse.json(
        #"{"code":"PGRST202","message":"Could not find the function in the schema cache","details":null,"hint":null}"#,
        status: 404)
    static let serverError = StubResponse.json(#"{"code":"XX000","message":"boom","details":null,"hint":null}"#, status: 500)

    static let castRows = StubResponse.json("""
        [{"character_id":1,"character_anilist_id":40,"character_name_full":"Eren Yeager","character_name_native":"エレン",
          "character_image_large":null,"role":"MAIN","staff_id":7,"staff_anilist_id":95672,"staff_name_full":"Yuuki Kaji",
          "staff_name_native":"梶裕貴","staff_image_large":"https://s4.anilist.co/v.jpg","language":"JAPANESE"},
         {"character_id":2,"character_anilist_id":41,"character_name_full":"Extra","character_name_native":null,
          "character_image_large":null,"role":"BACKGROUND","staff_id":null,"staff_anilist_id":null,"staff_name_full":null,
          "staff_name_native":null,"staff_image_large":null,"language":null}]
        """)

    /// `anime_characters` embed rows, one with a numeric age (the integer column).
    static let characterJoins = StubResponse.json("""
        [{"role":"BACKGROUND","characters":{"id":3,"anilist_id":3,"name_full":"Background Guy","name_native":null,"image_large":null,"gender":null,"age":null}},
         {"role":"MAIN","characters":{"id":1,"anilist_id":1,"name_full":"Hero","name_native":null,"image_large":null,"gender":"Male","age":17}},
         {"role":"SUPPORTING","characters":{"id":2,"anilist_id":2,"name_full":"Friend","name_native":null,"image_large":null,"gender":null,"age":"16"}}]
        """)

    static func similarAnimeRows(_ ids: [Int]) -> StubResponse {
        let rows = ids.enumerated().map { index, id in
            #"{"media_type":"ANIME","rank":\#(index + 1),"similarity_score":90.5,"id":\#(id),"title_english":"Similar \#(id)","cover_image_large":"https://s4.anilist.co/\#(id).jpg","format":"TV","episodes":12,"chapters":null,"volumes":null,"is_adult":false,"genres":["Drama"],"created_at":"2026-01-01T00:00:00+00:00","updated_at":"2026-01-01T00:00:00+00:00"}"#
        }
        return .json("[" + rows.joined(separator: ",") + "]")
    }

    static func similarMangaRows(_ ids: [Int]) -> StubResponse {
        let rows = ids.map { id in
            #"{"media_type":"MANGA","rank":1,"similarity_score":70,"id":\#(id),"title_english":"Manga \#(id)","cover_image_large":"https://s4.anilist.co/m\#(id).jpg","format":"MANGA","episodes":null,"chapters":100,"volumes":10,"is_adult":false,"genres":["Drama"],"created_at":"2026-01-01T00:00:00+00:00","updated_at":"2026-01-01T00:00:00+00:00"}"#
        }
        return .json("[" + rows.joined(separator: ",") + "]")
    }
}

// MARK: - Characters decode fix

@MainActor
@Suite("Details data: characters decode (integer age)", .timeLimit(.minutes(1)))
struct CharacterAgeDecodeTests {
    @Test("A numeric, textual or null age decodes; the embed shape decodes as a whole")
    func ageShapes() throws {
        let decoder = JSONDecoder()
        for (json, expected) in [(#"{"id":1,"age":17}"#, "17"), (#"{"id":1,"age":"17-18"}"#, "17-18"), (#"{"id":1,"age":null}"#, nil),
                                 (#"{"id":1}"#, nil), (#"{"id":1,"age":true}"#, nil)] as [(String, String?)] {
            let character = try decoder.decode(Character.self, from: Data(json.utf8))
            #expect(character.age == expected, "\(json)")
        }
        let join = try decoder.decode(AnimeCharacterJoin.self, from: Data(
            #"{"role":"MAIN","characters":{"id":5,"name_full":"Hero","gender":"Male","age":17}}"#.utf8))
        #expect(join.characters.nameFull == "Hero")
        #expect(join.characters.age == "17")
        #expect(throws: DecodingError.self) { try decoder.decode(Character.self, from: Data(#"{"name_full":"no id"}"#.utf8)) }
    }

    @Test("Regression: the characters rail is populated when a character has a numeric age")
    func railPopulatedWithNumericAge() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "anime_characters" ? DataLaneJSON.characterJoins : .emptyArray
        }
        let rail = await harness.service.catalog.fetchCharactersForAnime(animeId: 990_100)
        #expect(rail.map(\.character.nameFull) == ["Background Guy", "Hero", "Friend"])
        #expect(rail.first { $0.character.id == 1 }?.character.age == "17")
        await harness.tearDown()
    }
}

// MARK: - Cast and voice actors

@MainActor
@Suite("Details data: cast and voice actors", .timeLimit(.minutes(1)))
struct CastAndVoiceActorTests {
    @Test("anime_cast_v1: cast with primary voice actors; the request carries id, language and limit; warm reads are free")
    func castFromRPC() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/anime_cast_v1" ? DataLaneJSON.castRows : .emptyArray
        }
        let catalog = harness.service.catalog
        let cast = await catalog.fetchCast(forAnime: 990_200)
        #expect(cast.map(\.character.nameFull) == ["Eren Yeager", "Extra"])
        #expect(cast.first?.voiceActor?.nameFull == "Yuuki Kaji")
        #expect(cast.first?.voiceActor?.anilistId == 95_672)
        #expect(cast.first?.language == "JAPANESE")
        #expect(cast.last?.voiceActor == nil)
        #expect(cast.last?.language == nil)
        let body = try #require(harness.requests(to: "rpc/anime_cast_v1").first?.jsonObject)
        #expect(body["p_anime_id"] as? Int == 990_200)
        #expect(body["p_language"] as? String == "JAPANESE")
        #expect(body["p_limit"] as? Int == 25)
        _ = await catalog.fetchCast(forAnime: 990_200)
        #expect(harness.requests(to: "rpc/anime_cast_v1").count == 1)
        await harness.tearDown()
    }

    @Test("Not deployed (PGRST202): the cast falls back to anime_characters, role-ordered, no voice actors; the RPC is not retried at once")
    func castFallbackWhenUndeployed() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/anime_cast_v1": return DataLaneJSON.pgrst202
            case "anime_characters": return DataLaneJSON.characterJoins
            default: return .emptyArray
            }
        }
        let catalog = harness.service.catalog
        let cast = await catalog.fetchCast(forAnime: 990_201)
        #expect(cast.map(\.character.nameFull) == ["Hero", "Friend", "Background Guy"], "MAIN, SUPPORTING, other")
        #expect(cast.allSatisfy { $0.voiceActor == nil })
        // Another title: the contract is remembered as undeployed, so only the fallback is read.
        _ = await catalog.fetchCast(forAnime: 990_202)
        #expect(harness.requests(to: "rpc/anime_cast_v1").count == 1)
        #expect(await catalog.fetchVoiceActors(forCharacter: 1).isEmpty)
        await harness.tearDown()
    }

    @Test("A transient failure answers the fallback without caching it")
    func castTransientNotCached() async throws {
        let calls = CallCounter()
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/anime_cast_v1": return calls.next() == 1 ? DataLaneJSON.serverError : DataLaneJSON.castRows
            case "anime_characters": return DataLaneJSON.characterJoins
            default: return .emptyArray
            }
        }
        let catalog = harness.service.catalog
        #expect(await catalog.fetchCast(forAnime: 990_203).allSatisfy { $0.voiceActor == nil })
        #expect(await catalog.fetchCast(forAnime: 990_203).first?.voiceActor?.nameFull == "Yuuki Kaji")
        #expect(harness.requests(to: "rpc/anime_cast_v1").count == 2)
        await harness.tearDown()
    }

    @Test("character_voice_actors_v1 and staff_voice_roles_v1 decode; not deployed answers empty")
    func personReaders() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/character_voice_actors_v1":
                return .json(#"[{"staff_id":7,"anilist_id":95672,"name_full":"Yuuki Kaji","name_native":"梶裕貴","image_large":null,"language":"JAPANESE","anime_ids":[1,2]}]"#)
            case "rpc/staff_voice_roles_v1": return DataLaneJSON.pgrst202
            default: return .emptyArray
            }
        }
        let catalog = harness.service.catalog
        let voices = await catalog.fetchVoiceActors(forCharacter: 40)
        #expect(voices.map(\.staff.nameFull) == ["Yuuki Kaji"])
        #expect(voices.first?.animeIds == [1, 2])
        #expect(voices.first?.language == "JAPANESE")
        #expect(await catalog.fetchVoiceRoles(forStaff: 7).isEmpty)
        #expect(await catalog.fetchVoiceRoles(forStaff: 8).isEmpty)
        #expect(harness.requests(to: "rpc/staff_voice_roles_v1").count == 1, "undeployed: not asked again")
        await harness.tearDown()
    }

    @Test("staff_voice_roles_v1 row maps to a voice role with its anime card fields")
    func voiceRoleRowMapping() throws {
        let row = try JSONDecoder().decode(StaffVoiceRoleRow.self, from: Data("""
            {"character_id":1,"character_anilist_id":40,"character_name_full":"Eren","character_name_native":null,
             "character_image_large":null,"role":"MAIN","language":"JAPANESE","anime_id":990042,"title_english":null,
             "title_romaji":"Shingeki no Kyojin","title_native":"進撃の巨人","cover_image_large":null,"format":"TV",
             "season_year":null,"start_date_year":2013}
            """.utf8))
        let role = row.voiceRole
        #expect(role.anime.key == MediaKey(kind: .anime, id: 990_042))
        #expect(role.anime.displayTitle == "Shingeki no Kyojin")
        #expect(role.anime.year == 2013)
        #expect(role.id == "1-990042")
    }
}

// MARK: - More like this

@MainActor
@Suite("Details data: More like this (per account)", .timeLimit(.minutes(1)))
struct SimilarTitlesTests {
    static let userA = LifecycleFixtures.userA
    static let userB = LifecycleFixtures.userB

    @Test("media_similar_v1: one call, card rows in order with ranks; the seed itself is never listed")
    func similarFromRPC() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/media_similar_v1" ? DataLaneJSON.similarAnimeRows([11, 12, 990_300]) : .emptyArray
        }
        let items = await harness.service.recommendations.fetchSimilar(kind: .anime, id: 990_300, limit: 12)
        #expect(items.map(\.key) == [MediaKey(kind: .anime, id: 11), MediaKey(kind: .anime, id: 12)])
        #expect(items.map(\.rank) == [1, 2])
        #expect(items.first?.display.title == "Similar 11")
        #expect(items.first?.anime?.episodes == 12)
        let body = try #require(harness.requests(to: "rpc/media_similar_v1").first?.jsonObject)
        #expect(body["p_media_type"] as? String == "ANIME")
        #expect(body["p_media_id"] as? Int == 990_300)
        #expect(body["p_limit"] as? Int == 12)
        #expect(harness.requests(to: "anime").isEmpty, "no second hydration round trip")
        await harness.tearDown()
    }

    @Test("Manga rows decode as manga cards")
    func similarManga() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/media_similar_v1" ? DataLaneJSON.similarMangaRows([21]) : .emptyArray
        }
        let items = await harness.service.recommendations.fetchSimilar(kind: .manga, id: 990_301)
        #expect(items.first?.key == MediaKey(kind: .manga, id: 21))
        #expect(items.first?.manga?.chapters == 100)
        await harness.tearDown()
    }

    @Test("The cache is per account: A's answer is never served to B, and a transition clears it")
    func perAccountCache() async throws {
        let harness = try PublicDataHarness { request in
            request.resource == "rpc/media_similar_v1" ? DataLaneJSON.similarAnimeRows([31]) : .emptyArray
        }
        let service = harness.service
        await service.session.applySession(userId: Self.userA, email: "a@example.com")
        _ = await service.recommendations.fetchSimilar(kind: .anime, id: 990_302)
        _ = await service.recommendations.fetchSimilar(kind: .anime, id: 990_302)
        #expect(harness.requests(to: "rpc/media_similar_v1").count == 1, "warm for A")
        await service.session.applySession(userId: Self.userB, email: "b@example.com")
        #expect(service.recommendations.similarCache.isEmpty, "cleared by the session funnel")
        _ = await service.recommendations.fetchSimilar(kind: .anime, id: 990_302)
        #expect(harness.requests(to: "rpc/media_similar_v1").count == 2)
        #expect(service.recommendations.similarCache.keys.allSatisfy { $0.hasPrefix(Self.userB.lowercased()) })
        await harness.tearDown()
    }

    @Test("Not deployed: the same engine through recommend_ids_similar_to_seeds, hydrated by the Catalog")
    func similarFallback() async throws {
        let harness = try PublicDataHarness { request in
            switch request.resource {
            case "rpc/media_similar_v1": return DataLaneJSON.pgrst202
            case "rpc/recommend_ids_similar_to_seeds":
                return .json(#"[{"media_id":41,"overlap_count":3,"score":80},{"media_id":42,"overlap_count":2,"score":70}]"#)
            case "anime":
                return .json("[" + PublicRowJSON.anime(42, title: "Forty Two") + "," + PublicRowJSON.anime(41, title: "Forty One") + "]")
            default: return .emptyArray
            }
        }
        let reader = harness.service.recommendations
        let items = await reader.fetchSimilar(kind: .anime, id: 990_303, limit: 5)
        #expect(items.map(\.key.id) == [41, 42], "the engine's order, not the hydration order")
        let body = try #require(harness.requests(to: "rpc/recommend_ids_similar_to_seeds").first?.jsonObject)
        #expect(body["p_seed_ids"] as? [Int] == [990_303])
        #expect(body["p_allow_gimmicks"] as? Bool == false)
        _ = await reader.fetchSimilar(kind: .anime, id: 990_304, limit: 5)
        #expect(harness.requests(to: "rpc/media_similar_v1").count == 1, "undeployed: not asked again at once")
        await harness.tearDown()
    }
}

// MARK: - Theme songs: optional Apple fields

@MainActor
@Suite("Details data: theme songs with Apple matches", .timeLimit(.minutes(1)))
struct ThemeSongAppleTests {
    static func decode(_ json: String) throws -> [ThemeSong] {
        try JSONDecoder().decode(LenientRows<ThemeSong>.self, from: Data(json.utf8)).rows
    }

    @Test("The old ten-column shape still decodes, with no Apple match")
    func oldShape() throws {
        let songs = try Self.decode(#"[{"kind":"OP","sequence":1,"title":"Gurenge","artist":"LiSA","episodes":"1-19","version":null,"is_spoiler":false,"is_nsfw":false,"source":"animethemes","source_url":null}]"#)
        #expect(songs.count == 1)
        #expect(songs.first?.apple == nil)
        #expect(songs.first?.previewURL == nil)
        #expect(songs.first?.appleMusicURL?.host == "music.apple.com", "falls back to the search link")
        #expect(songs.first?.appleMusicURL?.path == "/search")
    }

    @Test("Trailing Apple columns decode into a verified match")
    func newShape() throws {
        let songs = try Self.decode("""
            [{"kind":"OP","sequence":1,"title":"Gurenge","artist":"LiSA","episodes":null,"version":null,"is_spoiler":false,
              "is_nsfw":false,"source":"animethemes","source_url":null,"apple_track_id":1488408568,
              "apple_artwork_url":"https://is1-ssl.mzstatic.com/image/thumb/Music/a/600x600bb.jpg",
              "apple_preview_url":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/a.m4a",
              "apple_music_url":"https://music.apple.com/jp/album/gurenge/1488408555?i=1488408568",
              "apple_match_confidence":0.97}]
            """)
        let apple = try #require(songs.first?.apple)
        #expect(apple.trackId == 1_488_408_568)
        #expect(apple.artworkURL?.host == "is1-ssl.mzstatic.com")
        #expect(songs.first?.previewURL?.host == "audio-ssl.itunes.apple.com")
        #expect(songs.first?.appleMusicURL == apple.musicURL)
        #expect(abs(apple.confidence - 0.97) < 0.0001)
        #expect(SongPreviewPlayer.canPreview(try #require(songs.first)))
    }

    @Test("Below 0.8, a foreign host, a bad type or a missing music link is no match; the song is kept")
    func refusedMatches() throws {
        func song(_ apple: String) throws -> ThemeSong? {
            try Self.decode(#"[{"kind":"ED","title":"Song","artist":"A",\#(apple)}]"#).first
        }
        let music = #""apple_music_url":"https://music.apple.com/x?i=1""#
        #expect(try song(#""apple_track_id":1,\#(music),"apple_match_confidence":0.79"#)?.apple == nil)
        #expect(try song(#""apple_track_id":"1",\#(music),"apple_match_confidence":0.9"#)?.apple == nil)
        #expect(try song(#""apple_track_id":1,"apple_music_url":"https://music.apple.com.evil.invalid/x","apple_match_confidence":0.9"#)?.apple == nil)
        #expect(try song(#""apple_track_id":1,"apple_match_confidence":0.9"#)?.apple == nil)
        let foreignPreview = try #require(try song(#""apple_track_id":1,\#(music),"apple_match_confidence":0.9,"apple_preview_url":"https://cdn.invalid/a.m4a","apple_artwork_url":"http://is1-ssl.mzstatic.com/a.jpg""#))
        #expect(foreignPreview.apple != nil)
        #expect(foreignPreview.previewURL == nil)
        #expect(foreignPreview.apple?.artworkURL == nil)
        #expect(!SongPreviewPlayer.canPreview(foreignPreview))
        #expect(AppleSongMatch.url("https://evil-.mzstatic.com.invalid/a", hosts: [], suffix: ".mzstatic.com") == nil)
        #expect(AppleSongMatch.url("https://a.b.mzstatic.com/a", hosts: [], suffix: ".mzstatic.com") == nil, "one label only")
    }
}

// MARK: - Song preview player

@MainActor
private final class FakePreviewEngine: SongPreviewEngine {
    var played: [URL] = []
    var stops = 0
    var handlers: [@MainActor (SongPreviewEvent) -> Void] = []

    func play(_ url: URL, onEvent: @escaping @MainActor (SongPreviewEvent) -> Void) {
        played.append(url)
        handlers.append(onEvent)
    }

    func stop() { stops += 1 }
}

@MainActor
private final class FakeAudioSession: SongPreviewAudioSession {
    var activations = 0
    var deactivations = 0
    var failActivation = false

    func activateForPreview() throws {
        if failActivation { throw URLError(.cannotLoadFromNetwork) }
        activations += 1
    }

    func deactivateAfterPreview() { deactivations += 1 }
}

@MainActor
@Suite("Details data: song preview player", .timeLimit(.minutes(1)))
struct SongPreviewPlayerTests {
    static func song(_ title: String, preview: String? = "https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/x.m4a") -> ThemeSong {
        ThemeSong(kind: .opening, sequence: 1, title: title, artist: "LiSA",
                  apple: AppleSongMatch(trackId: 1, artwork: nil, preview: preview,
                                        music: "https://music.apple.com/x?i=1", confidence: 0.9))
    }

    private func makePlayer(center: NotificationCenter = NotificationCenter()) -> (SongPreviewPlayer, FakePreviewEngine, FakeAudioSession) {
        let engine = FakePreviewEngine()
        let session = FakeAudioSession()
        return (SongPreviewPlayer(engine: engine, audioSession: session, notificationCenter: center), engine, session)
    }

    @Test("▶ loads, starts, then the end of the preview returns to idle and releases the session")
    func playToEnd() {
        let (player, engine, session) = makePlayer()
        let a = Self.song("A")
        #expect(player.play(a))
        #expect(player.isLoading(a))
        #expect(session.activations == 1)
        engine.handlers.last?(.started)
        #expect(player.isPlaying(a))
        engine.handlers.last?(.finished)
        #expect(player.phase == .idle)
        #expect(session.deactivations == 1)
    }

    @Test("One at a time: a second song replaces the first; late events of the first are ignored")
    func oneAtATime() {
        let (player, engine, _) = makePlayer()
        let a = Self.song("A"), b = Self.song("B")
        player.play(a)
        engine.handlers[0](.started)
        player.play(b)
        #expect(player.activeSongID == b.id)
        engine.handlers[0](.finished)   // a's late end must not stop b
        engine.handlers[0](.failed)
        #expect(player.isLoading(b))
        engine.handlers[1](.started)
        #expect(player.isPlaying(b))
        #expect(engine.played.count == 2)
    }

    @Test("toggle stops the active song; stop(ifPlaying:) for another song does nothing")
    func toggleAndScopedStop() {
        let (player, _, session) = makePlayer()
        let a = Self.song("A"), b = Self.song("B")
        player.toggle(a)
        player.stop(ifPlaying: b.id)
        #expect(player.activeSongID == a.id)
        player.toggle(a)
        #expect(player.phase == .idle)
        #expect(session.deactivations == 1)
        player.stop()
        #expect(session.deactivations == 1, "stopping nothing does not touch the session")
    }

    @Test("A failed stream shows failed for that song; activation failure too")
    func failures() {
        let (player, engine, session) = makePlayer()
        let a = Self.song("A")
        player.play(a)
        engine.handlers.last?(.failed)
        #expect(player.didFail(a))
        session.failActivation = true
        let b = Self.song("B")
        player.play(b)
        #expect(player.didFail(b))
        #expect(engine.played.count == 1, "nothing is streamed without an audio session")
    }

    @Test("No preview or a non-Apple host: nothing plays")
    func refusesUnverifiedURLs() {
        let (player, engine, session) = makePlayer()
        #expect(!player.play(Self.song("A", preview: nil)))
        #expect(!player.play(ThemeSong(kind: .ending, sequence: nil, title: "No match", artist: nil)))
        #expect(engine.played.isEmpty)
        #expect(session.activations == 0)
        #expect(player.phase == .idle)
    }

    @Test("Background, audio interruption and an account transition stop playback")
    func stopsOnLifecycle() {
        let center = NotificationCenter()
        let (player, _, _) = makePlayer(center: center)
        player.play(Self.song("A"))
        #expect(SongPreviewPlayer.didEnterBackground == UIApplication.didEnterBackgroundNotification)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(player.phase == .idle)
        player.play(Self.song("A"))
        center.post(name: AVAudioSession.interruptionNotification, object: nil)
        #expect(player.phase == .idle)
        player.play(Self.song("A"))
        player.cancelAccountWork()
        #expect(player.phase == .idle)
        player.play(Self.song("A"))
        player.clearPrivateState()
        #expect(player.phase == .idle)
    }

    @Test("The graph holds one player, registered as account-scoped before the interaction telemetry")
    func registered() throws {
        let defaults = try #require(UserDefaults(suiteName: "kuro.tests.song-preview.\(UUID().uuidString)"))
        let graph = AppComposition.testingGraph(testingUserDefaults: defaults, notificationCenter: FakeNotificationCenter())
        let ids = graph.session.accountScopedStates.map { ObjectIdentifier($0) }
        let player = try #require(ids.firstIndex(of: ObjectIdentifier(graph.songPreview)))
        let telemetry = try #require(ids.firstIndex(of: ObjectIdentifier(graph.interactionTelemetry)))
        #expect(player < telemetry)
        #expect(ids.contains(ObjectIdentifier(graph.recommendations)))
    }
}

// MARK: - Fixtures for UI lanes

@MainActor
@Suite("Details data: fixtures for offline renders", .timeLimit(.minutes(1)))
struct DetailsDataFixtureTests {
    @Test("Seeded cast / voice actors / voice roles / similar answers are served with zero requests")
    func seedersServeWithoutRequests() async throws {
        let harness = try PublicDataHarness { _ in DataLaneJSON.pgrst202 }
        let catalog = harness.service.catalog
        catalog.seedFixtureCast(animeId: 990_042)
        catalog.seedFixtureVoiceActors(characterId: 1)
        catalog.seedFixtureVoiceRoles(staffId: 95_672)
        harness.service.recommendations.seedFixtureSimilar(kind: .anime, id: 990_042, items: SimilarTitleFixtures.anime(count: 4))
        #expect(await catalog.fetchCast(forAnime: 990_042).count == 4)
        #expect(await catalog.fetchVoiceActors(forCharacter: 1).first?.staff.nameFull == "Yuuki Kaji")
        #expect(await catalog.fetchVoiceRoles(forStaff: 95_672).count == 2)
        #expect(await harness.service.recommendations.fetchSimilar(kind: .anime, id: 990_042).map(\.rank) == [1, 2, 3, 4])
        #expect(harness.server.requests.isEmpty, "\(harness.server.requests)")
        await harness.tearDown()
    }

    @Test("Card and song fixtures decode: anime/manga cards, songs with and without Apple matches")
    func fixturesAreComplete() {
        #expect(SimilarTitleFixtures.anime(count: 6).count == 6)
        #expect(SimilarTitleFixtures.manga(count: 3).compactMap(\.manga?.chapters).count == 3)
        let songs = ThemeSong.fixturesWithApple
        #expect(songs.filter { SongPreviewPlayer.canPreview($0) }.count == 3)
        #expect(songs.contains { $0.apple == nil })
        #expect(songs.contains { $0.isSpoiler && $0.version == 2 })
    }
}

