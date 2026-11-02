//
//  SynopsisCacheTests.swift
//  KuroTests
//
//  Synopsis cache identity and the production condense orchestration (a spy stands in for
//  Foundation Models). The non-FM stub still returns nil. No test talks to a model or a server.
//

import Testing
@testable import Kuro

/// Records each uncached generation. Hooks differ by call so a reused text entry is visible.
@MainActor
private final class SynopsisHookSpy {
    private(set) var calls: [(description: String, title: String, genres: [String])] = []

    func hook(description: String, title: String, genres: [String]) -> String {
        calls.append((description, title, genres))
        return "\(title) [\(genres.joined(separator: ", "))] #\(calls.count)"
    }

    func install(on service: AppleFMService) {
        service.synopsisHookGenerator = { description, title, genres in
            self.hook(description: description, title: title, genres: genres)
        }
    }
}

@MainActor
struct SynopsisCacheTests {

    private let description = "A quiet town hides a gate."
    private let revised = "A quiet town hides a gate. Then everything changes."
    private let title = "The Gate"
    private let genres = ["Mystery"]

    @Test func animeAndMangaWithTheSameIdDoNotShareCachedText() {
        var cache = SynopsisCache()
        let anime = SynopsisCache.mediaKey(kind: "ANIME", id: 7, description: description, title: title, genres: genres)
        let manga = SynopsisCache.mediaKey(kind: "MANGA", id: 7, description: description, title: title, genres: genres)

        cache.store("anime hook", for: anime)

        #expect(cache.lookup(manga) == nil)
        #expect(cache.lookup(anime) == "anime hook")
        #expect(anime != manga)
    }

    @Test func changedDescriptionDoesNotReturnTheOldText() {
        var cache = SynopsisCache()
        let original = SynopsisCache.mediaKey(kind: "ANIME", id: 7, description: description, title: title, genres: genres)
        let updated = SynopsisCache.mediaKey(kind: "ANIME", id: 7, description: revised, title: title, genres: genres)

        cache.store("old hook", for: original)

        #expect(cache.lookup(updated) == nil)
        #expect(cache.lookup(original) == "old hook")
        #expect(synopsisSourceDigest(description) != synopsisSourceDigest(revised))
    }

    @Test func textOnlyEntryDoesNotSatisfyAMediaLookup() {
        var cache = SynopsisCache()
        let text = SynopsisCache.textKey(description: description, title: title, genres: genres)
        let media = SynopsisCache.mediaKey(kind: "ANIME", id: 7, description: description, title: title, genres: genres)

        cache.store("text hook", for: text)

        #expect(cache.lookup(media) == nil)
        #expect(cache.lookup(text) == "text hook")
        #expect(text != media)
    }

    @Test func animeAndMangaWithTheSameDescriptionGenerateSeparateHooks() async {
        let spy = SynopsisHookSpy()
        let service = AppleFMService()
        spy.install(on: service)

        let anime = await service.condenseSynopsis(
            mediaKind: "ANIME", mediaId: 7, description: description, title: "Anime Gate", genres: genres
        )
        let manga = await service.condenseSynopsis(
            mediaKind: "MANGA", mediaId: 7, description: description, title: "Manga Gate", genres: genres
        )
        let animeAgain = await service.condenseSynopsis(
            mediaKind: "anime", mediaId: 7, description: description, title: "Anime Gate", genres: genres
        )

        #expect(spy.calls.count == 2)
        #expect(spy.calls.map(\.description) == [description, description])
        #expect(spy.calls.map(\.title) == ["Anime Gate", "Manga Gate"])
        #expect(anime == "Anime Gate [Mystery] #1")
        #expect(manga == "Manga Gate [Mystery] #2")
        #expect(anime != manga)
        #expect(animeAgain == anime)
    }

    @Test func storedTextOnlyResultDoesNotSatisfyAMediaRequest() async {
        let spy = SynopsisHookSpy()
        let service = AppleFMService()
        spy.install(on: service)

        let text = await service.condenseSynopsis(description: description, title: title, genres: genres)
        let textAgain = await service.condenseSynopsis(description: description, title: title, genres: genres)
        let media = await service.condenseSynopsis(
            mediaKind: "ANIME", mediaId: 7, description: description, title: title, genres: genres
        )

        #expect(text == "The Gate [Mystery] #1")
        #expect(textAgain == text)
        #expect(spy.calls.count == 2, "the text entry does not answer the media request")
        #expect(media == "The Gate [Mystery] #2")
        #expect(media != text)
    }

    @Test func changedTitleOrGenresMissesTheCachedHook() async {
        let spy = SynopsisHookSpy()
        let service = AppleFMService()
        spy.install(on: service)

        let original = await service.condenseSynopsis(
            mediaKind: "ANIME", mediaId: 7, description: description, title: title, genres: genres
        )
        let retitled = await service.condenseSynopsis(
            mediaKind: "ANIME", mediaId: 7, description: description, title: "Another Gate", genres: genres
        )
        let otherGenres = await service.condenseSynopsis(
            mediaKind: "ANIME", mediaId: 7, description: description, title: title, genres: ["Drama"]
        )
        let originalAgain = await service.condenseSynopsis(
            mediaKind: "ANIME", mediaId: 7, description: description, title: title, genres: genres
        )

        #expect(spy.calls.count == 3)
        #expect(original == "The Gate [Mystery] #1")
        #expect(retitled == "Another Gate [Mystery] #2")
        #expect(otherGenres == "The Gate [Drama] #3")
        #expect(originalAgain == original)
        #expect(retitled != original && otherGenres != original)
    }

    @Test func synopsisSourceDigestIsFNV1aOfUTF8() {
        #expect(synopsisSourceDigest("") == 0xcbf29ce484222325)
        #expect(synopsisSourceDigest("a") == 0xaf63dc4c8601ec8c)
        #expect(synopsisSourceDigest("foobar") == 0x85944171f73967e8)
        #expect(synopsisSourceDigest("foobar") == synopsisSourceDigest("foobar"))
    }

    @Test func stubClassificationReturnsNoAssist() async {
        let provider = StubFMProvider()
        #expect(provider.isAvailable == false)

        let result = await provider.classifyMode(
            userText: "something dark and slow",
            availableModes: [("noir", "Noir", ["dark"])]
        )

        #expect(result == nil)
        #expect(provider.isAvailable == false)
    }

    @Test func stubDisambiguationReturnsNoAssist() async {
        let provider = StubFMProvider()
        #expect(provider.isAvailable == false)

        let result = await provider.disambiguate(
            candidates: [
                DisambiguationCandidate(
                    index: 0,
                    title: "Example",
                    year: 1998,
                    format: "TV",
                    score: 80,
                    variantType: "anime"
                )
            ],
            userText: "the 1998 one",
            rawTitle: "Example"
        )

        #expect(result == nil)
        #expect(provider.isAvailable == false)
    }

    @Test func stubSynopsisReturnsNoAssist() async {
        let provider = StubFMProvider()
        #expect(provider.isAvailable == false)

        let result = await provider.condenseSynopsis(
            description: "A long description that would otherwise be condensed on device.",
            title: "Example",
            genres: ["Drama"]
        )

        #expect(result == nil)
        #expect(provider.isAvailable == false)
    }

    @Test func stubCollectionSearchReturnsNoAssist() async {
        let provider = StubFMProvider()
        #expect(provider.isAvailable == false)

        let result = await provider.parseSearchIntent(query: "completed drama from 1998")

        #expect(result == nil)
        #expect(provider.isAvailable == false)
    }
}
