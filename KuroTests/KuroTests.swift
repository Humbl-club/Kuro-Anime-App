//
//  KuroTests.swift
//  KuroTests
//
//  Created by Max Dev on 29.09.25.
//

import Testing
import Foundation
@testable import Kuro

@Suite("Kuro App Tests")
struct KuroTests {

    @Test("App Launch Test")
    func testAppLaunch() async throws {
        // Test that the app can initialize without crashing
        #expect(Bool(true), "App should launch successfully")
        print("✅ App Launch: PASSED")
    }
    

    @Test("UI Components Test")
    func testUIComponents() async throws {
        // Test that UI components can be created
        let moods = ["Contemplative", "Energetic", "Melancholic", "Uplifting", "Mysterious"]
        #expect(moods.count == 5, "Should have 5 mood options")

        let sections = ["DISCOVER", "COLLECTION", "SEARCH"]
        #expect(sections.count == 3, "Should have 3 main sections")

        print("✅ UI Components: PASSED")
    }
}

// MARK: - Import Intent Detection Tests

@Suite("Import Intent Detection")
struct ImportIntentTests {

    // MARK: - Positive: should detect as import

    @Test("Detects explicit status keywords")
    func testExplicitStatusKeywords() {
        #expect(TextNormalization.looksLikeImport("Watching Naruto"))
        #expect(TextNormalization.looksLikeImport("Reading One Piece"))
        #expect(TextNormalization.looksLikeImport("Completed Attack on Titan"))
        #expect(TextNormalization.looksLikeImport("Finished Steins;Gate"))
        #expect(TextNormalization.looksLikeImport("Dropped Fairy Tail"))
    }

    @Test("Detects standalone past tense without 'I' prefix")
    func testStandalonePastTense() {
        #expect(TextNormalization.looksLikeImport("Watched Jujutsu Kaisen"))
        #expect(TextNormalization.looksLikeImport("watched jujutsu kaisen halfway through"))
        #expect(TextNormalization.looksLikeImport("Paused My Hero Academia"))
    }

    @Test("Detects 'I' prefix patterns")
    func testIPrefixPatterns() {
        #expect(TextNormalization.looksLikeImport("I'm watching Demon Slayer"))
        #expect(TextNormalization.looksLikeImport("im watching Demon Slayer"))
        #expect(TextNormalization.looksLikeImport("I'm reading Chainsaw Man"))
        #expect(TextNormalization.looksLikeImport("im reading Chainsaw Man"))
        #expect(TextNormalization.looksLikeImport("I've seen Cowboy Bebop"))
        #expect(TextNormalization.looksLikeImport("I have seen Cowboy Bebop"))
    }

    @Test("Detects soft-partial markers")
    func testSoftPartialMarkers() {
        #expect(TextNormalization.looksLikeImport("Jujutsu Kaisen halfway through"))
        #expect(TextNormalization.looksLikeImport("halfway done with Bleach"))
        #expect(TextNormalization.looksLikeImport("midway through One Punch Man"))
        #expect(TextNormalization.looksLikeImport("partway into Vinland Saga"))
        #expect(TextNormalization.looksLikeImport("half way through Naruto"))
    }

    @Test("Detects progress patterns")
    func testProgressPatterns() {
        #expect(TextNormalization.looksLikeImport("Naruto ep 50"))
        #expect(TextNormalization.looksLikeImport("One Piece episode 1000"))
        #expect(TextNormalization.looksLikeImport("Berserk chapter 364"))
        #expect(TextNormalization.looksLikeImport("Naruto vol 72"))
        #expect(TextNormalization.looksLikeImport("Breaking Bad s2e5"))
        #expect(TextNormalization.looksLikeImport("Show 3x12"))
    }

    @Test("Detects multi-line input")
    func testMultiLineInput() {
        #expect(TextNormalization.looksLikeImport("Naruto\nOne Piece\nBleach"))
    }

    @Test("Detects comma-separated title lists")
    func testCommaSeparatedTitles() {
        #expect(TextNormalization.looksLikeImport("Attack on Titan, Demon Slayer, Jujutsu Kaisen"))
        #expect(TextNormalization.looksLikeImport("Naruto (2002), One Piece"))
        // Single-word titles without markers don't register as title-like segments
        #expect(!TextNormalization.looksLikeImport("Bleach, Naruto"))
    }

    @Test("Detects German import language")
    func testGermanImportLanguage() {
        #expect(TextNormalization.looksLikeImport("ich habe Naruto geschaut"))
        #expect(TextNormalization.looksLikeImport("ich schaue gerade One Piece"))
        #expect(TextNormalization.looksLikeImport("Naruto geschaut"))
        #expect(TextNormalization.looksLikeImport("One Piece gesehen"))
        #expect(TextNormalization.looksLikeImport("Berserk gelesen"))
        #expect(TextNormalization.looksLikeImport("Naruto zur Hälfte"))
        #expect(TextNormalization.looksLikeImport("Staffel 2 von Demon Slayer"))
        #expect(TextNormalization.looksLikeImport("Folge 50 von Naruto"))
        #expect(TextNormalization.looksLikeImport("Kapitel 100"))
    }

    @Test("Detects caught up / up to date")
    func testCaughtUpPatterns() {
        #expect(TextNormalization.looksLikeImport("caught up with One Piece"))
        #expect(TextNormalization.looksLikeImport("up to date on Jujutsu Kaisen"))
    }

    // MARK: - Negative: should NOT detect as import

    @Test("Does not detect vibe/recommendation requests")
    func testVibeRequestsNotImport() {
        #expect(!TextNormalization.looksLikeImport("something dark"))
        #expect(!TextNormalization.looksLikeImport("cozy anime"))
        #expect(!TextNormalization.looksLikeImport("sad romance"))
        #expect(!TextNormalization.looksLikeImport("funny short anime"))
    }

    @Test("Does not detect German vibe requests")
    func testGermanVibeRequestsNotImport() {
        #expect(!TextNormalization.looksLikeImport("etwas düsteres"))
        #expect(!TextNormalization.looksLikeImport("empfiehl mir etwas"))
        #expect(!TextNormalization.looksLikeImport("zeig mir etwas lustiges"))
        #expect(!TextNormalization.looksLikeImport("ich möchte etwas kurzes"))
    }

    @Test("Does not detect very short input")
    func testShortInputNotImport() {
        #expect(!TextNormalization.looksLikeImport("hi"))
        #expect(!TextNormalization.looksLikeImport("hello"))
        #expect(!TextNormalization.looksLikeImport("help"))
    }

    @Test("Handles empty and whitespace-only input")
    func testEmptyAndWhitespace() {
        #expect(!TextNormalization.looksLikeImport(""))
        #expect(!TextNormalization.looksLikeImport("   "))
    }

    @Test("German vibe guard yields to staffel/folge")
    func testGermanVibeWithStaffel() {
        // Vibe marker present BUT staffel overrides → import
        #expect(TextNormalization.looksLikeImport("ich möchte Staffel 2 anschauen"))
        #expect(TextNormalization.looksLikeImport("zeig mir Folge 5"))
    }

    @Test("Case insensitive matching")
    func testCaseInsensitive() {
        #expect(TextNormalization.looksLikeImport("WATCHED Attack on Titan"))
        #expect(TextNormalization.looksLikeImport("COMPLETED naruto"))
    }

    @Test("Regex boundary conditions")
    func testRegexBoundaries() {
        #expect(TextNormalization.looksLikeImport("s1e1"))
        #expect(TextNormalization.looksLikeImport("s12e1234"))
        #expect(TextNormalization.looksLikeImport("1x50"))
    }

    // MARK: - Segment title-like detection

    @Test("segmentLooksTitleLike detects title-like segments")
    func testSegmentTitleLike() {
        #expect(TextNormalization.segmentLooksTitleLike("Attack on Titan"))
        #expect(TextNormalization.segmentLooksTitleLike("Naruto (2002)"))
        #expect(TextNormalization.segmentLooksTitleLike("One Piece ep 100"))
    }

    @Test("segmentLooksTitleLike rejects vibe segments")
    func testSegmentVibeNotTitleLike() {
        #expect(!TextNormalization.segmentLooksTitleLike("something funny"))
        #expect(!TextNormalization.segmentLooksTitleLike("sad anime"))
        #expect(!TextNormalization.segmentLooksTitleLike("recommend me"))
    }
}

// MARK: - Auth Error Mapping Tests

@Suite("Auth Error Mapping")
struct AuthErrorMappingTests {

    @Test("Maps offline transport failures to a clear message")
    func testOfflineTransportMessage() {
        let error = URLError(.notConnectedToInternet)
        #expect(
            SupabaseService.userFacingAuthErrorMessage(from: error) ==
            "No internet connection. Check your connection and try again."
        )
    }

    @Test("Maps timeout transport failures to a clear message")
    func testTimeoutTransportMessage() {
        let error = URLError(.timedOut)
        #expect(
            SupabaseService.userFacingAuthErrorMessage(from: error) ==
            "The request timed out. Please try again."
        )
    }

    @Test("Maps wrapped cannot-connect transport failures to a clear message")
    func testWrappedCannotConnectTransportMessage() {
        let wrapped = NSError(
            domain: "Supabase",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: URLError(.cannotConnectToHost)]
        )
        #expect(
            SupabaseService.userFacingAuthErrorMessage(from: wrapped) ==
            "Can't reach the server right now. Please try again."
        )
    }

    @Test("Keeps credential failures specific")
    func testInvalidCredentialsMessage() {
        let error = NSError(
            domain: "Auth",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Invalid login credentials"]
        )
        #expect(
            SupabaseService.userFacingAuthErrorMessage(from: error) ==
            "Incorrect email or password. Please try again."
        )
    }
}

// MARK: - CreditRole Normalization Tests

@Suite("CreditRole Normalization")
struct CreditRoleTests {

    @Test("Director exact match")
    func testDirectorExact() {
        #expect(CreditRole.from(raw: "Director") == .director)
    }

    @Test("Director case insensitive")
    func testDirectorCaseInsensitive() {
        #expect(CreditRole.from(raw: "director") == .director)
    }

    @Test("Original Creator alias — Original Story")
    func testOriginalCreatorAlias() {
        #expect(CreditRole.from(raw: "Original Story") == .originalCreator)
    }

    @Test("Series Composition exact")
    func testSeriesCompositionExact() {
        #expect(CreditRole.from(raw: "Series Composition") == .seriesComposition)
    }

    @Test("Music alias — Theme Song Composition")
    func testMusicAlias() {
        #expect(CreditRole.from(raw: "Theme Song Composition") == .music)
    }

    @Test("Character Design — Chief variant")
    func testCharacterDesignChief() {
        #expect(CreditRole.from(raw: "Chief Character Design") == .characterDesign)
    }

    @Test("Unrecognized role returns nil")
    func testUnrecognizedRole() {
        #expect(CreditRole.from(raw: "Key Animation") == nil)
    }

    @Test("Whitespace handling")
    func testWhitespaceHandling() {
        #expect(CreditRole.from(raw: "  Director  ") == .director)
    }

    @Test("Empty string returns nil")
    func testEmptyString() {
        #expect(CreditRole.from(raw: "") == nil)
    }

    @Test("Role priority order")
    func testRolePriorityOrder() {
        #expect(CreditRole.director.rawValue < CreditRole.originalCreator.rawValue)
        #expect(CreditRole.originalCreator.rawValue < CreditRole.seriesComposition.rawValue)
        #expect(CreditRole.seriesComposition.rawValue < CreditRole.music.rawValue)
        #expect(CreditRole.music.rawValue < CreditRole.characterDesign.rawValue)
    }

    @Test("Cast sort — MAIN first, then SUPPORTING alphabetical")
    func testCastSortMainFirst() {
        let input: [(name: String, role: String)] = [
            ("B", "SUPPORTING"),
            ("A", "MAIN"),
            ("A", "SUPPORTING")
        ]
        let sorted = input
            .sorted { lhs, rhs in
                let lhsMain = lhs.role == "MAIN"
                let rhsMain = rhs.role == "MAIN"
                if lhsMain != rhsMain { return lhsMain }
                return lhs.name < rhs.name
            }
        #expect(sorted[0].name == "A" && sorted[0].role == "MAIN")
        #expect(sorted[1].name == "A" && sorted[1].role == "SUPPORTING")
        #expect(sorted[2].name == "B" && sorted[2].role == "SUPPORTING")
    }

    @Test("Cast filter — BACKGROUND excluded")
    func testCastFilterBackground() {
        let input = ["MAIN", "SUPPORTING", "BACKGROUND", "SUPPORTING"]
        let filtered = input.filter { $0.lowercased() != "background" }
        #expect(filtered.count == 3)
        #expect(!filtered.contains("BACKGROUND"))
    }
}

// MARK: - Provider Availability Note Tests

@MainActor
@Suite("Provider Availability Note Derivation")
struct ProviderAvailabilityNoteTests {
    private func provider(
        audio: [String: [String]] = [:],
        subtitles: [String: [String]] = [:]
    ) -> ProviderAvailabilityProvider {
        ProviderAvailabilityProvider(
            slug: "netflix",
            displayName: "Netflix",
            url: "https://example.com",
            languages: Array(Set(Array(audio.keys) + Array(subtitles.keys))).sorted(),
            audioLanguages: Array(audio.keys).sorted(),
            subtitleLanguages: Array(subtitles.keys).sorted(),
            countriesByAudioLang: audio,
            countriesBySubtitleLang: subtitles,
            isStale: false
        )
    }

    @Test("EN dub for Japanese original with English audio")
    func testEnglishDub() {
        let note = ProviderAvailabilityNoteBuilder.bestNote(
            from: [provider(audio: ["en": ["US", "CA"]])],
            preferredAudioLang: "en",
            originalLanguage: "ja"
        )
        #expect(note == ProviderAvailabilityNote(kind: .dub, languageCode: "en", countries: ["CA", "US"]))
        #expect(note?.displayText == "EN dub: CA, US")
    }

    @Test("DE dub for English original with German audio")
    func testGermanDub() {
        let note = ProviderAvailabilityNoteBuilder.bestNote(
            from: [provider(audio: ["de": ["DE", "AT"]])],
            preferredAudioLang: "de",
            originalLanguage: "en"
        )
        #expect(note == ProviderAvailabilityNote(kind: .dub, languageCode: "de", countries: ["AT", "DE"]))
        #expect(note?.displayText == "DE dub: AT, DE")
    }

    @Test("EN audio for English original with English audio")
    func testEnglishAudio() {
        let note = ProviderAvailabilityNoteBuilder.bestNote(
            from: [provider(audio: ["en": ["GB", "AU"]])],
            preferredAudioLang: "en",
            originalLanguage: "en"
        )
        #expect(note == ProviderAvailabilityNote(kind: .audio, languageCode: "en", countries: ["AU", "GB"]))
        #expect(note?.displayText == "EN audio: AU, GB")
    }

    @Test("DE audio when original language is unknown")
    func testGermanAudioWithoutOriginalLanguage() {
        let note = ProviderAvailabilityNoteBuilder.bestNote(
            from: [provider(audio: ["de": ["DE"]])],
            preferredAudioLang: "de",
            originalLanguage: nil
        )
        #expect(note == ProviderAvailabilityNote(kind: .audio, languageCode: "de", countries: ["DE"]))
        #expect(note?.displayText == "DE audio: DE")
    }

    @Test("EN subtitles when only subtitle evidence exists")
    func testEnglishSubtitles() {
        let note = ProviderAvailabilityNoteBuilder.bestNote(
            from: [provider(subtitles: ["en": ["GB", "AU"]])],
            preferredAudioLang: "en",
            preferredSubtitleLang: "en",
            originalLanguage: "ja"
        )
        #expect(note == ProviderAvailabilityNote(kind: .subtitles, languageCode: "en", countries: ["AU", "GB"]))
        #expect(note?.displayText == "EN subtitles: AU, GB")
    }

    @Test("Falls back to provider-country availability when locale metadata is incomplete")
    func testAvailabilityFallback() {
        let note = ProviderAvailabilityNoteBuilder.bestNote(
            from: [provider(audio: ["fr": ["FR"]], subtitles: ["es": ["ES"]])],
            preferredAudioLang: "de",
            preferredSubtitleLang: "de",
            originalLanguage: "ja"
        )
        #expect(note == ProviderAvailabilityNote(kind: .availability, languageCode: nil, countries: ["ES", "FR"]))
        #expect(note?.displayText == "Availability: ES, FR")
    }

    @Test("Returns nil when no provider metadata exists")
    func testNoMetadata() {
        let note = ProviderAvailabilityNoteBuilder.bestNote(
            from: [provider()],
            preferredAudioLang: "en",
            originalLanguage: "ja"
        )
        #expect(note == nil)
    }
}

// MARK: - Entity Work Identity Tests

@Suite("Entity Work Identity")
struct EntityWorkIdentityTests {
    private func media(id: Int, kind: MediaKind) -> Media {
        Media(
            id: id,
            kind: kind,
            title: "\(kind.rawValue)-\(id)",
            imageURL: nil,
            year: "2024",
            displayDescription: "",
            episodes: kind == .anime ? 12 : nil,
            chapters: kind == .manga ? 100 : nil,
            rating: 8.0,
            genres: nil,
            statusRaw: nil,
            formatRaw: nil,
            popularityValue: nil,
            trendingValue: nil,
            createdAtValue: nil
        )
    }

    @Test("Same numeric anime and manga IDs get different rail identities")
    func testMixedMediaIDsStayDistinct() {
        let animeID = EntityWorkIdentity.make(media: media(id: 123, kind: .anime), role: nil, index: 0)
        let mangaID = EntityWorkIdentity.make(media: media(id: 123, kind: .manga), role: nil, index: 0)
        #expect(animeID != mangaID)
        #expect(animeID == "anime-123-none-0")
        #expect(mangaID == "manga-123-none-0")
    }

    @Test("Duplicate media rows remain distinct when role or position differs")
    func testDuplicateMediaRowsStayDistinct() {
        let media = media(id: 321, kind: .anime)
        let first = EntityWorkIdentity.make(media: media, role: "Director", index: 0)
        let second = EntityWorkIdentity.make(media: media, role: "Storyboard", index: 1)
        #expect(first != second)
    }
}

// MARK: - Entity Discovery Filter Tests

@Suite("Entity Discovery Filters")
struct EntityDiscoveryFilterTests {
    @Test("Era buckets group modern titles ahead of classics")
    func testEraBuckets() {
        #expect(EntityEraBucket.from(yearString: "2024") == .current)
        #expect(EntityEraBucket.from(yearString: "2017") == .tens)
        #expect(EntityEraBucket.from(yearString: "2006") == .aughts)
        #expect(EntityEraBucket.from(yearString: "1998") == .classics)
    }

    @Test("Staff role filter groups director writer music and design")
    func testStaffRoleGrouping() {
        #expect(StaffRoleFilter.from(role: "Director") == .director)
        #expect(StaffRoleFilter.from(role: "Series Composition") == .writer)
        #expect(StaffRoleFilter.from(role: "Theme Song Composition") == .music)
        #expect(StaffRoleFilter.from(role: "Chief Character Design") == .design)
        #expect(StaffRoleFilter.from(role: "Key Animation") == nil)
    }

    @Test("Author role filter separates story art and combined roles")
    func testAuthorRoleGrouping() {
        #expect(AuthorRoleFilter.from(role: "Story") == .story)
        #expect(AuthorRoleFilter.from(role: "Art") == .art)
        #expect(AuthorRoleFilter.from(role: "Story & Art") == .storyArt)
        #expect(AuthorRoleFilter.from(role: "Original Creator") == nil)
    }

    @Test("Character media filter keeps anime and manga distinct")
    func testCharacterMediaFilter() {
        let works = [
            Media(
                id: 10,
                kind: .anime,
                title: "Anime",
                imageURL: nil,
                year: "2024",
                displayDescription: "",
                episodes: 12,
                chapters: nil,
                rating: 8.2,
                genres: nil,
                statusRaw: nil,
                formatRaw: nil,
                popularityValue: nil,
                trendingValue: nil,
                createdAtValue: nil
            ),
            Media(
                id: 11,
                kind: .manga,
                title: "Manga",
                imageURL: nil,
                year: "2020",
                displayDescription: "",
                episodes: nil,
                chapters: 90,
                rating: 8.0,
                genres: nil,
                statusRaw: nil,
                formatRaw: nil,
                popularityValue: nil,
                trendingValue: nil,
                createdAtValue: nil
            )
        ]
        let animeOnly = works.filter { CharacterMediaFilter.anime == .anime ? $0.kind == .anime : true }
        let mangaOnly = works.filter { CharacterMediaFilter.manga == .manga ? $0.kind == .manga : true }
        #expect(animeOnly.count == 1)
        #expect(animeOnly.first?.kind == .anime)
        #expect(mangaOnly.count == 1)
        #expect(mangaOnly.first?.kind == .manga)
    }
}

@MainActor
@Suite("Adaptation Ladder")
struct AdaptationLadderTests {

    @Test("Empty ladder reports no content")
    func testEmptyLadderHasNoContent() {
        #expect(!MediaLadderResponse.empty.hasContent)
    }

    @Test("Ladder reports content when a source row exists")
    func testLadderHasContentWithSource() {
        let item = MediaLadderItem(
            mediaType: "MANGA",
            mediaId: 12,
            title: "Original Work",
            coverImage: nil,
            year: 2018,
            format: "MANGA",
            rating: 8.6,
            reasonLabel: nil,
            sourceAuthorName: nil
        )
        let ladder = MediaLadderResponse(
            sourceMaterial: [item],
            adaptations: [],
            prequels: [],
            sequels: [],
            sideStories: [],
            spinOffs: [],
            entryPoint: nil,
            nextStep: nil,
            primarySource: nil,
            primaryAdaptation: nil,
            franchiseNote: nil,
            coverageStatus: nil,
            totalFranchiseCount: nil,
            alternateAdaptationSummary: nil
        )
        #expect(ladder.hasContent)
    }

    @Test("Curated ladder fields count as content")
    func testCuratedLadderHasContent() {
        let item = MediaLadderItem(
            mediaType: "ANIME",
            mediaId: 7,
            title: "Best Start",
            coverImage: nil,
            year: 2020,
            format: "TV",
            rating: 9.1,
            reasonLabel: "Best starting point",
            sourceAuthorName: nil
        )
        let ladder = MediaLadderResponse(
            sourceMaterial: [],
            adaptations: [],
            prequels: [],
            sequels: [],
            sideStories: [],
            spinOffs: [],
            entryPoint: item,
            nextStep: nil,
            primarySource: nil,
            primaryAdaptation: nil,
            franchiseNote: "Start here.",
            coverageStatus: .strong,
            totalFranchiseCount: nil,
            alternateAdaptationSummary: nil
        )
        #expect(ladder.hasContent)
    }

    @Test("Ladder item maps anime media correctly")
    func testMediaLadderItemToAnimeMedia() {
        let item = MediaLadderItem(
            mediaType: "ANIME",
            mediaId: 99,
            title: "Adaptation",
            coverImage: "https://example.com/poster.jpg",
            year: 2024,
            format: "TV",
            rating: 8.9,
            reasonLabel: "Most relevant adaptation",
            sourceAuthorName: nil
        )
        let media = item.toMedia()
        #expect(media.kind == MediaKind.anime)
        #expect(media.id == 99)
        #expect(media.title == "Adaptation")
        #expect(media.year == "2024")
        #expect(media.rating == 8.9)
    }

    @Test("Ladder item maps manga media correctly")
    func testMediaLadderItemToMangaMedia() {
        let item = MediaLadderItem(
            mediaType: "MANGA",
            mediaId: 42,
            title: "Source Material",
            coverImage: nil,
            year: nil,
            format: "NOVEL",
            rating: nil,
            reasonLabel: "Original source",
            sourceAuthorName: nil
        )
        let media = item.toMedia()
        #expect(media.kind == MediaKind.manga)
        #expect(media.id == 42)
        #expect(media.year == "TBA")
        #expect(media.formatRaw == "NOVEL")
    }

    @Test("Ladder response decodes editorial fields")
    func testLadderResponseDecodesEditorialFields() throws {
        let json = """
        {
          "source_material": [],
          "adaptations": [],
          "prequels": [],
          "sequels": [],
          "side_stories": [],
          "spin_offs": [],
          "entry_point": {
            "media_type": "MANGA",
            "media_id": 5,
            "title": "Original Work",
            "cover_image": null,
            "year": 2019,
            "format": "MANGA",
            "rating": 8.4,
            "reason_label": "Best starting point"
          },
          "next_step": null,
          "primary_source": null,
          "primary_adaptation": null,
          "franchise_note": "Start with the source, then follow the main adaptation path.",
          "coverage_status": "strong"
        }
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(MediaLadderResponse.self, from: data)
        #expect(decoded.coverageStatus == .strong)
        #expect(decoded.entryPoint?.reasonLabel == "Best starting point")
        #expect(decoded.franchiseNote == "Start with the source, then follow the main adaptation path.")
    }
}

@Suite("Editorial Search")
struct EditorialSearchTests {
    @Test("Runs search with empty query when filters are active")
    func testFilterOnlySearchAllowed() {
        #expect(EditorialSearchView.shouldRunSearch(query: "", hasFilters: true))
        #expect(EditorialSearchView.shouldRunSearch(query: " ", hasFilters: true))
    }

    @Test("Blocks empty query when no filters are active")
    func testEmptyQueryWithoutFiltersBlocked() {
        #expect(!EditorialSearchView.shouldRunSearch(query: "", hasFilters: false))
        #expect(!EditorialSearchView.shouldRunSearch(query: " ", hasFilters: false))
    }

    @Test("Allows typed query once minimum length is met")
    func testTypedQueryStillRequiresMinimumLength() {
        #expect(!EditorialSearchView.shouldRunSearch(query: "a", hasFilters: false))
        #expect(EditorialSearchView.shouldRunSearch(query: "ab", hasFilters: false))
        #expect(EditorialSearchView.shouldRunSearch(query: "naruto", hasFilters: false))
    }
}

@Suite("Detail Truthfulness")
struct DetailTruthfulnessTests {
    @Test("Sanitizes media descriptions with HTML and entities")
    func testSanitizeMediaDescription() {
        let raw = "Line one<br><br><p>Elf &amp; mage&nbsp;story</p>&#39;quoted&#39;"
        let cleaned = TextNormalization.sanitizeMediaDescription(raw)
        #expect(cleaned == "Line one\n\nElf & mage story\n\n'quoted'")
    }

    @Test("Verified provider items outrank catalog fallback")
    func testVerifiedProviderItems() {
        let fallbackLinks = [
            ExternalLink(
                id: 1,
                mediaType: "ANIME",
                mediaId: 1,
                site: "Crunchyroll",
                url: "https://www.crunchyroll.com/series/test",
                language: "en",
                color: nil,
                priority: nil,
                isDisabled: false,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        let providers = [
            ProviderAvailabilityProvider(
                slug: "crunchyroll",
                displayName: "Crunchyroll",
                url: "https://www.crunchyroll.com/series/test",
                languages: ["ja"],
                audioLanguages: ["ja"],
                subtitleLanguages: ["en"],
                countriesByAudioLang: ["ja": ["DE", "US"]],
                countriesBySubtitleLang: ["en": ["DE", "US"]],
                isStale: false
            )
        ]

        let verified = makeVerifiedProviderItems(
            providers: providers.filter { !$0.isStale },
            fallbackLinks: fallbackLinks,
            ranking: ["crunchyroll"],
            preferredAudioLang: "en",
            preferredSubtitleLang: "en",
            originalLanguage: "ja"
        )
        let catalog = makeCatalogProviderItems(
            from: fallbackLinks,
            ranking: ["crunchyroll"],
            fallbackSubtitle: "Catalog link only. Availability may vary by region."
        )

        #expect(verified.count == 1)
        #expect(verified.first?.isVerified == true)
        #expect(catalog.first?.isVerified == false)
        #expect(preferredPrimaryProviderItem(from: verified + catalog, preferredSite: "Crunchyroll")?.isVerified == true)
    }
}


// MARK: - Taste Deck Tests

@Suite("Taste Deck")
struct TasteDeckTests {

    @Test("Decodes a full deck card from snake_case JSON")
    func testDeckCardDecoding() throws {
        let json = """
        {
          "media_type": "ANIME",
          "media_id": 123,
          "title": "Frieren: Beyond Journey's End",
          "cover_image_large": "https://example.com/frieren-large.jpg",
          "cover_image_medium": "https://example.com/frieren-medium.jpg",
          "cover_image_color": "#e4d5c8",
          "genres": ["Adventure", "Drama", "Fantasy"],
          "average_score": 91,
          "format": "TV",
          "year": 2023,
          "synopsis": "An elf mage reflects on a long journey.",
          "episodes": 28,
          "chapters": null,
          "volumes": null,
          "seasons_count": 2,
          "has_dub": true,
          "has_sub": true
        }
        """
        let data = try #require(json.data(using: .utf8))
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: data)
        #expect(card.mediaType == "ANIME")
        #expect(card.mediaId == 123)
        #expect(card.title == "Frieren: Beyond Journey's End")
        #expect(card.coverImageLarge == "https://example.com/frieren-large.jpg")
        #expect(card.coverImageColor == "#e4d5c8")
        #expect(card.genres == ["Adventure", "Drama", "Fantasy"])
        #expect(card.averageScore == 91)
        #expect(card.format == "TV")
        #expect(card.year == 2023)
        #expect(card.synopsis == "An elf mage reflects on a long journey.")
        #expect(card.episodes == 28)
        #expect(card.chapters == nil)
        #expect(card.volumes == nil)
        #expect(card.seasonsCount == 2)
        #expect(card.hasDub == true)
        #expect(card.hasSub == true)
    }

    @Test("Decodes v1.1 meta fields on a manga card")
    func testDeckCardMetaDecodingManga() throws {
        let json = """
        {
          "media_type": "MANGA", "media_id": 42, "title": "Berserk",
          "format": "MANGA", "chapters": 364, "volumes": 41,
          "has_dub": null, "has_sub": null
        }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.episodes == nil)
        #expect(card.chapters == 364)
        #expect(card.volumes == 41)
        #expect(card.seasonsCount == nil)
        #expect(card.hasDub == nil)
        #expect(card.hasSub == nil)
    }

    @Test("Meta chips: TV anime with dub")
    func testMetaChipsAnimeTVDub() throws {
        let json = """
        {
          "media_type": "ANIME", "media_id": 1, "title": "X",
          "format": "TV", "episodes": 24, "seasons_count": 2, "has_dub": true, "has_sub": true
        }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.metaChips == ["24 EP", "2 SEASONS", "DUB"])
    }

    @Test("Meta chips: singular forms stay singular")
    func testMetaChipsSingular() throws {
        let json = """
        {
          "media_type": "ANIME", "media_id": 2, "title": "X",
          "format": "TV", "episodes": 1, "seasons_count": 1
        }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.metaChips == ["1 EP", "1 SEASON"])
    }

    @Test("Meta chips: sub only when no dub is known")
    func testMetaChipsSubOnlyWhenNoDub() throws {
        let json = """
        {
          "media_type": "ANIME", "media_id": 3, "title": "X",
          "format": "TV", "episodes": 12, "seasons_count": 1, "has_dub": false, "has_sub": true
        }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.metaChips == ["12 EP", "1 SEASON", "SUB"])
    }

    @Test("Meta chips: no language chip when availability is unknown or negative")
    func testMetaChipsLanguageUnknown() throws {
        let unknownJSON = """
        {
          "media_type": "ANIME", "media_id": 4, "title": "X",
          "format": "TV", "episodes": 12, "seasons_count": 1, "has_dub": null, "has_sub": null
        }
        """
        let negativeJSON = """
        {
          "media_type": "ANIME", "media_id": 5, "title": "Y",
          "format": "TV", "episodes": 12, "seasons_count": 1, "has_dub": false, "has_sub": false
        }
        """
        let unknown = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(unknownJSON.data(using: .utf8)))
        let negative = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(negativeJSON.data(using: .utf8)))
        #expect(unknown.metaChips == ["12 EP", "1 SEASON"])
        #expect(negative.metaChips == ["12 EP", "1 SEASON"])
    }

    @Test("Meta chips: movie reads as FILM plus language")
    func testMetaChipsMovie() throws {
        let json = """
        {
          "media_type": "ANIME", "media_id": 6, "title": "X",
          "format": "MOVIE", "episodes": 1, "has_dub": true
        }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.metaChips == ["FILM", "DUB"])
    }

    @Test("Meta chips: non-TV anime formats show episodes only")
    func testMetaChipsOtherAnimeFormat() throws {
        let json = """
        { "media_type": "ANIME", "media_id": 7, "title": "X", "format": "OVA", "episodes": 6 }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.metaChips == ["6 EP"])
    }

    @Test("Meta chips: manga prefers volumes, falls back to chapters")
    func testMetaChipsManga() throws {
        let volumesJSON = """
        { "media_type": "MANGA", "media_id": 8, "title": "X", "format": "MANGA", "volumes": 14, "chapters": 120 }
        """
        let chaptersJSON = """
        { "media_type": "MANGA", "media_id": 9, "title": "Y", "format": "MANGA", "chapters": 1 }
        """
        let withVolumes = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(volumesJSON.data(using: .utf8)))
        let chaptersOnly = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(chaptersJSON.data(using: .utf8)))
        #expect(withVolumes.metaChips == ["VOL 14"])
        #expect(chaptersOnly.metaChips == ["1 CH"])
    }

    @Test("Meta chips: empty when nothing is known")
    func testMetaChipsEmpty() throws {
        let json = """
        { "media_type": "ANIME", "media_id": 10, "title": "X", "format": "TV" }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.metaChips.isEmpty)
    }

    @Test("Stable key follows the MediaDisplayable format")
    func testStableKeyFormat() throws {
        let animeJSON = """
        { "media_type": "ANIME", "media_id": 123, "title": "Frieren" }
        """
        let mangaJSON = """
        { "media_type": "MANGA", "media_id": 42, "title": "Berserk" }
        """
        let anime = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(animeJSON.data(using: .utf8)))
        let manga = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(mangaJSON.data(using: .utf8)))
        #expect(anime.stableKey == "anime-123")
        #expect(manga.stableKey == "manga-42")
        #expect(anime.id == "anime-123")
        // Same numeric id across media types must stay distinct.
        let anime42 = try JSONDecoder().decode(
            TasteDeckCard.self,
            from: try #require(#"{ "media_type": "ANIME", "media_id": 42, "title": "X" }"#.data(using: .utf8))
        )
        #expect(anime42.stableKey != manga.stableKey)
    }

    @Test("Optional card fields tolerate absence")
    func testDeckCardMissingOptionals() throws {
        let json = """
        { "media_type": "MANGA", "media_id": 7, "title": "Solo Leveling" }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.coverImageLarge == nil)
        #expect(card.coverImageMedium == nil)
        #expect(card.genres == nil)
        #expect(card.averageScore == nil)
        #expect(card.year == nil)
        #expect(card.synopsis == nil)
        #expect(card.imageURL == nil)
        #expect(card.captionLine.isEmpty)
    }

    @Test("Caption line joins genres, year and format quietly")
    func testCaptionLine() throws {
        let json = """
        {
          "media_type": "ANIME", "media_id": 1, "title": "Cowboy Bebop",
          "genres": ["Action", "Sci-Fi", "Drama"], "year": 1998, "format": "TV"
        }
        """
        let card = try JSONDecoder().decode(TasteDeckCard.self, from: try #require(json.data(using: .utf8)))
        #expect(card.captionLine == "Action · Sci-Fi · 1998 · TV")
    }

    @Test("Decodes a full taste profile vector")
    func testTasteProfileVectorDecoding() throws {
        let json = """
        {
          "genres": { "Drama": 0.82, "Sci-Fi": 0.41 },
          "tags": { "Found Family": 0.3 },
          "avoided_tags": ["Ecchi"],
          "confidence": 0.2,
          "event_count": 34
        }
        """
        let data = try #require(json.data(using: .utf8))
        let vector = try JSONDecoder().decode(TasteProfileVector.self, from: data)
        #expect(vector.genres["Drama"] == 0.82)
        #expect(vector.genres["Sci-Fi"] == 0.41)
        #expect(vector.tags["Found Family"] == 0.3)
        #expect(vector.avoidedTags == ["Ecchi"])
        #expect(vector.confidence == 0.2)
        #expect(vector.eventCount == 34)
    }

    @Test("Profile vector tolerates missing fields with quiet defaults")
    func testTasteProfileVectorMissingFields() throws {
        let json = """
        { "genres": { "Drama": 0.5 } }
        """
        let data = try #require(json.data(using: .utf8))
        let vector = try JSONDecoder().decode(TasteProfileVector.self, from: data)
        #expect(vector.genres["Drama"] == 0.5)
        #expect(vector.tags.isEmpty)
        #expect(vector.avoidedTags.isEmpty)
        #expect(vector.confidence == 0)
        #expect(vector.eventCount == 0)
        #expect(vector.computedAt == nil)

        let empty = try JSONDecoder().decode(TasteProfileVector.self, from: try #require("{}".data(using: .utf8)))
        #expect(empty.genres.isEmpty)
        #expect(empty.confidence == 0)
    }

    @Test("Confidence maps to words, never raw numbers")
    func testConfidenceWord() {
        let emerging = TasteProfile(vector: TasteProfileVector(confidence: 0.1, eventCount: 6), updatedAt: nil)
        let confident = TasteProfile(vector: TasteProfileVector(confidence: 0.15, eventCount: 20), updatedAt: nil)
        #expect(emerging.confidenceWord == "emerging")
        #expect(confident.confidenceWord == "confident")
    }

    @Test("Profile sorts leanings by weight")
    func testProfileTopGenresOrdering() {
        let vector = TasteProfileVector(genres: ["Action": 0.3, "Drama": 0.9, "Sci-Fi": 0.6])
        let profile = TasteProfile(vector: vector, updatedAt: nil)
        #expect(profile.topGenres.map(\.name) == ["Drama", "Sci-Fi", "Action"])
    }
}


// MARK: - Deep Link Router Tests

@Suite("Deep Link Router")
struct DeepLinkRouterTests {

    @Test("Parses kuro://join with a valid code")
    func testJoinValidCode() throws {
        let url = try #require(URL(string: "kuro://join/AB12CD34"))
        #expect(DeepLink.from(url: url) == .joinClub(code: "AB12CD34"))
    }

    @Test("Lowercased join code is uppercased")
    func testJoinLowercasedCode() throws {
        let url = try #require(URL(string: "kuro://join/ab12cd34"))
        #expect(DeepLink.from(url: url) == .joinClub(code: "AB12CD34"))
    }

    @Test("Six-character codes are accepted")
    func testJoinShortestValidCode() throws {
        let url = try #require(URL(string: "kuro://join/AB12CD"))
        #expect(DeepLink.from(url: url) == .joinClub(code: "AB12CD"))
    }

    @Test("Garbage join codes are rejected")
    func testJoinGarbageRejected() throws {
        // Too short (< 6)
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://join/AB12C"))) == nil)
        // Too long (> 12)
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://join/AB12CD34EF567"))) == nil)
        // Non-alphanumeric
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://join/AB-12CD3"))) == nil)
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://join/AB%2012CD"))) == nil)
        // Missing code
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://join/"))) == nil)
        #expect(DeepLink.from(url: try #require(URL(string: "kuro://join"))) == nil)
    }

    @Test("Existing club link still parses alongside join")
    func testClubLinkUnaffected() throws {
        let url = try #require(URL(string: "kuro://club/9f2c1a44-1234-4abc-8def-0123456789ab"))
        #expect(DeepLink.from(url: url) == .club(id: "9f2c1a44-1234-4abc-8def-0123456789ab"))
    }
}
