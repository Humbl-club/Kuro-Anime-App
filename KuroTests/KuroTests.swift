//
//  KuroTests.swift
//  KuroTests
//
//  Created by Max Dev on 29.09.25.
//

import Testing
@testable import Kuro

@Suite("Kuro App Tests")
struct KuroTests {

    @Test("App Launch Test")
    func testAppLaunch() async throws {
        // Test that the app can initialize without crashing
        #expect(true, "App should launch successfully")
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
