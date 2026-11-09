import Foundation
import KuroCore
import KuroLibrary
import Testing

@Suite("Library export: value types and RFC 4180 encoder")
struct LibraryExportTests {
    @Test func rfc4180FieldQuotesOnlyWhenNeeded() {
        #expect(RFC4180.field("plain") == "plain")
        #expect(RFC4180.field("a,b") == "\"a,b\"")
        #expect(RFC4180.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(RFC4180.field("line1\nline2") == "\"line1\nline2\"")
        #expect(RFC4180.field("cr\r") == "\"cr\r\"")
        #expect(RFC4180.row(["a", "b,c"]) == "a,\"b,c\"\r\n")
    }

    /// `"\r\n"` is ONE `Character` in Swift, so a `Character` search for `"\r"` or `"\n"` misses it, and a
    /// `"` followed by a combining mark is one grapheme that a text search for `"` can skip. Both must be
    /// handled by scalar, or a note would leave a field unquoted / a quote undoubled.
    @Test func rfc4180FieldHandlesGraphemeClustersAndEmptyValues() {
        #expect(RFC4180.field("a\r\nb") == "\"a\r\nb\"")
        #expect(RFC4180.field("\r\n") == "\"\r\n\"")
        #expect(RFC4180.field("q\"\u{0301}x") == "\"q\"\"\u{0301}x\"")
        #expect(RFC4180.field("") == "")
        #expect(RFC4180.field("日本語 ✓") == "日本語 ✓")
        #expect(RFC4180.field("\"") == "\"\"\"\"")
        #expect(RFC4180.row(["", "", ""]) == ",,\r\n")
        #expect(RFC4180.row(["x"]) == "x\r\n")
        #expect(RFC4180.row([]) == "\r\n")
    }

    @Test func summaryGapsFollowTheTwoIndependentCauses() {
        let line = ExportReportLine(key: MediaKey(kind: .anime, id: 7), title: "Untitled anime #7")
        let complete = LibraryExportSummary(
            entryCount: 1, malExported: [.anime: 1], withoutMalId: [], identityUnavailable: [],
            notesAdjusted: [], datesOmitted: []
        )
        #expect(complete.gaps.isEmpty)
        #expect(complete.isComplete)

        let offline = LibraryExportSummary(
            entryCount: 1, malExported: [:], withoutMalId: [], identityUnavailable: [line],
            notesAdjusted: [], datesOmitted: [], organisationUnavailable: true
        )
        #expect(offline.gaps == [.identityUnavailable, .organisationUnavailable])
        #expect(!offline.isComplete)

        let identityOnly = LibraryExportSummary(
            entryCount: 1, malExported: [:], withoutMalId: [], identityUnavailable: [line],
            notesAdjusted: [], datesOmitted: []
        )
        #expect(identityOnly.gaps == [.identityUnavailable])

        // MAL-format limits are reports, not gaps: CSV and JSON still hold those entries completely.
        let limitsOnly = LibraryExportSummary(
            entryCount: 3, malExported: [.anime: 1], withoutMalId: [line], identityUnavailable: [],
            notesAdjusted: [line], datesOmitted: [line]
        )
        #expect(limitsOnly.isComplete)

        let defaults = complete
        #expect(defaults.organisationUnavailable == false)
        #expect(defaults.malParts.isEmpty)
        #expect(defaults.listItemsOutsideLibrary == 0)
    }

    @Test func exportInputDefaultsAndFormatRawValues() {
        let input = LibraryExportInput(entries: [], catalogue: [:])
        #expect(input.tagsByKey.isEmpty)
        #expect(input.customLists.isEmpty)
        #expect(input.organisationUnavailable == false)
        #expect(LibraryExportFormat.allCases.map(\.rawValue) == ["mal_xml", "csv", "json"])
        #expect(LibraryExportGap.allCases.map(\.rawValue) == ["identity_unavailable", "organisation_unavailable"])
        #expect(ExportCatalogueRow(title: nil, anilistId: nil, malId: 5).malId == 5)
    }

    // MARK: - MAL XML

    @Test func statusTableCoversEveryListStatusAndMedium() {
        for kind in [MediaKind.anime, .manga] {
            for status in ListStatus.allCases {
                let (word, repeating) = MALExportMapping.malStatus(status, kind: kind)
                #expect(repeating == (status == .repeating))
                #expect(!word.lowercased().contains("repeat"))
            }
        }
        #expect(MALExportMapping.malStatus(.paused, kind: .anime).word == "On-Hold")
        #expect(MALExportMapping.malStatus(.planning, kind: .manga).word == "Plan to Read")
        #expect(MALExportMapping.malStatus(.planning, kind: .anime).word == "Plan to Watch")
        #expect(MALExportMapping.malStatus(.current, kind: .anime).word == "Watching")
        #expect(MALExportMapping.malStatus(.repeating, kind: .manga).word == "Reading")
        #expect(MALExportMapping.malStatus(.completed, kind: .manga).word == "Completed")
        #expect(MALExportMapping.malStatus(.dropped, kind: .anime).word == "Dropped")
        #expect(MALExportMapping.storedStatus(fromParsed: "on_hold") == .paused)
        #expect(MALExportMapping.storedStatus(fromParsed: "repeating") == .current)
        #expect(MALExportMapping.storedStatus(fromParsed: "plan_to_read") == .planning)
        #expect(MALExportMapping.storedStatus(fromParsed: "plan_to_watch") == .planning)
        #expect(MALExportMapping.storedStatus(fromParsed: "watching") == .current)
        #expect(MALExportMapping.storedStatus(fromParsed: "reading") == .current)
        #expect(MALExportMapping.storedStatus(fromParsed: "completed") == .completed)
        #expect(MALExportMapping.storedStatus(fromParsed: "dropped") == .dropped)
        #expect(MALExportMapping.storedStatus(fromParsed: "bogus") == nil)
        // Every word the writer emits comes back through the parser's own status normalisation.
        for kind in [MediaKind.anime, .manga] {
            for status in ListStatus.allCases {
                let (word, _) = MALExportMapping.malStatus(status, kind: kind)
                let normalised = word.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
                #expect(MALExportMapping.storedStatus(fromParsed: normalised) == Self.storedEquivalent(status))
            }
        }
    }

    @Test func malXmlRoundTripPreservesEveryMappedEntry() throws {
        let input = Self.everyStatusInput()
        let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        #expect(bundle.files.map(\.name) == ["kuro-anime-2026-11-09.xml", "kuro-manga-2026-11-09.xml"])
        let parsed = try bundle.files.flatMap { try MALExportParser.parse($0.data) }
        #expect(parsed.count == 12)
        for entry in input.entries {
            let malId = try #require(input.catalogue[entry.key]?.malId)
            let row = try #require(parsed.first { $0.medium == entry.key.kind.rawValue && $0.externalId == String(malId) })
            #expect(MALExportMapping.storedStatus(fromParsed: row.status) == Self.storedEquivalent(entry.status))
            #expect(row.progress == entry.progress)
            #expect(row.scoreRaw.flatMap(Int.init) == entry.rating?.value)
            #expect((row.notes ?? "") == (entry.notes ?? ""))
            #expect(row.repeatCount == entry.repeatCount)
            #expect(row.startedRaw.flatMap(PartialDate.init(raw:)) == entry.startedOn)
            #expect(row.finishedRaw.flatMap(PartialDate.init(raw:)) == entry.finishedOn)
            #expect(row.sourceTitle == input.catalogue[entry.key]?.title)
            if entry.key.kind == .manga { #expect(row.volumesProgress == entry.sourceMetadata?.volumesProgress) }
        }
        #expect(bundle.summary.notesAdjusted.isEmpty && bundle.summary.datesOmitted.isEmpty)
        #expect(bundle.summary.malExported == [.anime: 6, .manga: 6])
        #expect(bundle.summary.malParts == [.anime: 1, .manga: 1])
    }

    @Test func malDatesZeroPadEveryPrecisionAndOmitUnparseable() throws {
        #expect(MALExportMapping.malDate(PartialDate(raw: "2024")) == "2024-00-00")
        #expect(MALExportMapping.malDate(PartialDate(raw: "2024-03")) == "2024-03-00")
        #expect(MALExportMapping.malDate(PartialDate(raw: "2024-03-05")) == "2024-03-05")
        #expect(MALExportMapping.malDate(PartialDate(raw: "2024-03-00")) == "2024-03-00")
        #expect(MALExportMapping.malDate(nil) == nil)

        // started_raw "spring 2019" does not parse: no <my_start_date>, listed in datesOmitted. A stored
        // "0000-00-00" or "" is "no date", not a malformed one: written as MAL's own no-date value.
        let unparseable = Self.entry(.anime, 1, .completed, progress: 12, rating: nil, notes: nil, repeatCount: 0, started: "spring 2019", finished: "2019-05-01")
        let noDate = Self.entry(.anime, 2, .completed, progress: 12, rating: nil, notes: nil, repeatCount: 0, started: "0000-00-00", finished: "")
        let input = LibraryExportInput(
            entries: [unparseable, noDate],
            catalogue: [unparseable.key: Self.row("Spring Tale", mal: 11), noDate.key: Self.row("No Date", mal: 12)]
        )
        let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        let file = try #require(bundle.files.first)
        let parsed = try MALExportParser.parse(file.data)
        let first = try #require(parsed.first { $0.externalId == "11" })
        #expect(first.startedRaw == nil)
        #expect(first.unavailableFields.contains("started_raw"))
        #expect(first.finishedRaw == "2019-05-01")
        #expect(!first.unavailableFields.contains("finished_raw"))
        let second = try #require(parsed.first { $0.externalId == "12" })
        #expect(second.startedRaw == nil && second.finishedRaw == nil)
        #expect(!second.unavailableFields.contains("started_raw") && !second.unavailableFields.contains("finished_raw"))
        #expect(bundle.summary.datesOmitted == [ExportReportLine(key: unparseable.key, title: "Spring Tale")])
    }

    @Test func malXmlNotesSurviveEscapingAndAreReportedWhenAdjusted() throws {
        let cases: [(id: Int, note: String)] = [
            (1, "<!DOCTYPE x> ]]> & <"),
            (2, "bell\u{07}tab\tend"),
            (3, String(repeating: "é", count: 8_192)),
            (4, String(repeating: "é", count: 8_193)),
            (5, "nul\u{0}\u{1F}x\u{FFFE}\u{FFFF}y"),
            (6, "<!ENTITY a SYSTEM \"file:///etc/passwd\"> <![CDATA[x]]>"),
            (7, "lone\rcr and\r\ncrlf"),
        ]
        #expect(String(repeating: "é", count: 8_192).utf8.count == MALExportMapping.notesByteLimit)
        var entries: [LibraryEntry] = []
        var catalogue: [MediaKey: ExportCatalogueRow] = [:]
        for item in cases {
            let entry = Self.entry(.anime, item.id, .current, progress: 1, rating: nil, notes: item.note, repeatCount: 0, started: nil, finished: nil)
            entries.append(entry)
            catalogue[entry.key] = Self.row("Note \(item.id)", mal: 100 + item.id)
        }
        let bundle = LibraryExport.build(LibraryExportInput(entries: entries, catalogue: catalogue), formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        let parsed = try MALExportParser.parse(try #require(bundle.files.first).data)
        #expect(parsed.count == cases.count)
        func note(_ id: Int) throws -> String? { try #require(parsed.first { $0.externalId == String(100 + id) }).notes }
        #expect(try note(1) == cases[0].note)
        #expect(try note(2) == "belltab\tend")
        #expect(try note(3) == cases[2].note)
        #expect(try note(4) == nil)
        #expect(try #require(parsed.first { $0.externalId == "104" }).unavailableFields.contains("notes"))
        #expect(try note(5) == "nulxy")
        #expect(try note(6) == cases[5].note)
        #expect(try note(7) == cases[6].note)
        let adjusted = bundle.summary.notesAdjusted.map(\.key.id)
        #expect(adjusted == [2, 4, 5])
        #expect(bundle.summary.notesAdjusted.map(\.title) == ["Note 2", "Note 4", "Note 5"])
        // Entity escaping only: a CDATA section would carry "<!DOCTYPE" past the parser's byte scan.
        let xml = String(decoding: bundle.files[0].data, as: UTF8.self)
        #expect(!xml.contains("<![CDATA["))
    }

    @Test func xmlTextEscapesEntitiesAndDropsIllegalCharacters() {
        let escaped = MALExportMapping.xmlText("a&b<c>\"d\"'e'\r\n\tz")
        #expect(escaped.text == "a&amp;b&lt;c&gt;&quot;d&quot;&apos;e&apos;&#13;\n\tz")
        #expect(!escaped.changed)
        #expect(MALExportMapping.xmlText("").text == "" && !MALExportMapping.xmlText("").changed)
        #expect(MALExportMapping.xmlText("日本語 ✓ 🌸").text == "日本語 ✓ 🌸")
        let dropped = MALExportMapping.xmlText("x\u{0}\u{8}\u{B}\u{C}\u{1F}y\u{FFFE}\u{FFFF}z")
        #expect(dropped.text == "xyz")
        #expect(dropped.changed)
        // U+FFFD and other characters sharing the 0xEF lead byte are legal and kept.
        let kept = MALExportMapping.xmlText("a\u{FFFD}b\u{FF21}c")
        #expect(kept.text == "a\u{FFFD}b\u{FF21}c")
        #expect(!kept.changed)
    }

    @Test func missingSourceMetadataExportsNullNotZero() throws {
        let animeBare = LibraryEntry(key: MediaKey(kind: .anime, id: 1), rowId: 1, status: .current, progress: 3, createdAt: Self.epoch, updatedAt: Self.epoch)
        let mangaBare = LibraryEntry(key: MediaKey(kind: .manga, id: 2), rowId: 2, status: .completed, progress: 9, createdAt: Self.epoch, updatedAt: Self.epoch)
        let known = Self.entry(.anime, 3, .completed, progress: 12, rating: 8, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let input = LibraryExportInput(
            entries: [animeBare, mangaBare, known],
            catalogue: [animeBare.key: Self.row("Bare Anime", mal: 21), mangaBare.key: Self.row("Bare Manga", mal: 22), known.key: Self.row("Known", mal: 23)]
        )
        let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        let animeFile = try #require(bundle.files.first { $0.name.contains("anime") })
        let mangaFile = try #require(bundle.files.first { $0.name.contains("manga") })
        let animeParsed = try MALExportParser.parse(animeFile.data)
        let mangaParsed = try MALExportParser.parse(mangaFile.data)

        let bare = try #require(animeParsed.first { $0.externalId == "21" })
        #expect(bare.repeatCount == nil && bare.startedRaw == nil && bare.finishedRaw == nil)
        #expect(bare.unavailableFields.isSuperset(of: ["repeat_count", "started_raw", "finished_raw"]))
        #expect(bare.progress == 3)

        let bareManga = try #require(mangaParsed.first { $0.externalId == "22" })
        #expect(bareManga.repeatCount == nil)
        #expect(bareManga.unavailableFields.isSuperset(of: ["repeat_count", "started_raw", "finished_raw", "volumes_progress"]))

        // The writer drops the elements, it does not write zero or "0000-00-00" for unknown values.
        let animeXML = String(decoding: animeFile.data, as: UTF8.self)
        let bareBlock = try #require(animeXML.components(separatedBy: "<anime>").first { $0.contains("<series_animedb_id>21<") })
        #expect(!bareBlock.contains("my_times_watched") && !bareBlock.contains("my_start_date") && !bareBlock.contains("my_finish_date"))

        // Known-empty is different from unknown: a zero count and "no date" are written.
        let knownRow = try #require(animeParsed.first { $0.externalId == "23" })
        #expect(knownRow.repeatCount == 0)
        #expect(!knownRow.unavailableFields.contains("repeat_count"))
        #expect(!knownRow.unavailableFields.contains("started_raw") && !knownRow.unavailableFields.contains("finished_raw"))
        #expect(bundle.summary.datesOmitted.isEmpty)
    }

    @Test func repeatingExportsAsWatchingOrReadingWithTheRewatchFlag() throws {
        let anime = Self.entry(.anime, 1, .repeating, progress: 5, rating: nil, notes: nil, repeatCount: 2, started: nil, finished: nil)
        let manga = Self.entry(.manga, 1, .repeating, progress: 5, rating: nil, notes: nil, repeatCount: 1, started: nil, finished: nil)
        let plain = Self.entry(.anime, 2, .current, progress: 5, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let input = LibraryExportInput(
            entries: [anime, manga, plain],
            catalogue: [anime.key: Self.row("A", mal: 31), manga.key: Self.row("M", mal: 32), plain.key: Self.row("P", mal: 33)]
        )
        let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        let animeXML = String(decoding: try #require(bundle.files.first { $0.name.contains("anime") }).data, as: UTF8.self)
        let mangaXML = String(decoding: try #require(bundle.files.first { $0.name.contains("manga") }).data, as: UTF8.self)
        #expect(!animeXML.localizedCaseInsensitiveContains("Repeating") && !mangaXML.localizedCaseInsensitiveContains("Repeating"))
        #expect(animeXML.contains("<my_status>Watching</my_status>"))
        #expect(animeXML.contains("<my_rewatching>1</my_rewatching>") && animeXML.contains("<my_rewatching>0</my_rewatching>"))
        #expect(animeXML.contains("<my_times_watched>2</my_times_watched>"))
        #expect(mangaXML.contains("<my_status>Reading</my_status>"))
        #expect(mangaXML.contains("<my_rereadingg>1</my_rereadingg>"))
        #expect(mangaXML.contains("<my_times_read>1</my_times_read>"))
    }

    @Test func malXmlWritesOnlyEntriesWithAMalIdSortedByMalId() throws {
        let high = Self.entry(.anime, 1, .completed, progress: 12, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let none = Self.entry(.anime, 2, .completed, progress: 12, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let unknown = Self.entry(.anime, 3, .completed, progress: 12, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let low = Self.entry(.anime, 4, .completed, progress: 12, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let input = LibraryExportInput(
            entries: [high, none, unknown, low],
            catalogue: [high.key: Self.row("High", mal: 30), none.key: Self.row("None", mal: nil), low.key: Self.row("Low", mal: 10)]
        )
        let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        #expect(bundle.files.map(\.name) == ["kuro-anime-2026-11-09.xml"])
        #expect(bundle.files.first?.contentType == "application/xml")
        let parsed = try MALExportParser.parse(try #require(bundle.files.first).data)
        #expect(parsed.map(\.externalId) == ["10", "30"])
        #expect(bundle.summary.malExported == [.anime: 2])
        #expect(bundle.summary.malParts == [.anime: 1])
        #expect(bundle.summary.entryCount == 4)
        // No MAL-format file for a medium with nothing to write.
        #expect(LibraryExport.build(LibraryExportInput(entries: [], catalogue: [:]), formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin).files.isEmpty)
    }

    /// Worst case for the whole-file limit: 2,000 entries whose notes sit exactly on the per-element limit and
    /// are made only of characters that escape to 5, 4, 4 and 6 bytes. About 156 MB of XML must be split into
    /// parts that each re-import on their own (a part above 32 MiB is rejected by the importer as a whole).
    @Test(.timeLimit(.minutes(3))) func malXmlSplitsLargeLibrariesIntoReimportableParts() throws {
        let note = String(repeating: "&<>\"", count: 4_096)
        #expect(note.utf8.count == MALExportMapping.notesByteLimit)
        let input = Self.largeLibrary(count: 2_000, kind: .anime, note: note)
        let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        let parts = bundle.files
        #expect(parts.count >= 2)
        #expect(parts.map(\.name) == (1...max(parts.count, 1)).map { "kuro-anime-2026-11-09-part\($0).xml" })
        #expect(bundle.summary.malParts[.anime] == parts.count)
        var parsed: [MALExportItem] = []
        var previousMax = 0
        for part in parts {
            #expect(part.data.count <= MALExportParser.maxBytes)
            let items = try MALExportParser.parse(part.data)
            #expect(items.count <= MALExportParser.maxItems)
            let ids = items.compactMap { Int($0.externalId) }
            #expect((ids.min() ?? 0) > previousMax)
            previousMax = ids.max() ?? previousMax
            parsed += items
        }
        #expect(parsed.count == 2_000)
        #expect(Set(parsed.compactMap { Int($0.externalId) }) == Set(1...2_000))
        #expect(parsed.allSatisfy { $0.notes == note })
        #expect(bundle.summary.notesAdjusted.isEmpty)
        #expect(bundle.summary.malExported[.anime] == 2_000)
    }

    @Test(.timeLimit(.minutes(3))) func malXmlSplitsAtTheParserItemLimit() throws {
        let over = Self.largeLibrary(count: MALExportParser.maxItems + 1, kind: .manga, note: "short")
        let split = LibraryExport.build(over, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        #expect(split.files.map(\.name) == ["kuro-manga-2026-11-09-part1.xml", "kuro-manga-2026-11-09-part2.xml"])
        let counts = try split.files.map { try MALExportParser.parse($0.data).count }
        #expect(counts == [MALExportParser.maxItems, 1])
        #expect(split.summary.malParts[.manga] == 2)

        let exact = Self.largeLibrary(count: MALExportParser.maxItems, kind: .manga, note: "short")
        let single = LibraryExport.build(exact, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        #expect(single.files.map(\.name) == ["kuro-manga-2026-11-09.xml"])
        #expect(try MALExportParser.parse(single.files[0].data).count == MALExportParser.maxItems)
        #expect(single.summary.malParts[.manga] == 1)
    }

    /// MAL's own manga export names its id and title `manga_mangadb_id` / `manga_title`; the anime ones stay
    /// `series_*`. No duplicate `series_*` element is written for manga.
    @Test func mangaRowsUseMalsOwnElementNames() throws {
        let manga = Self.entry(.manga, 1, .current, progress: 5, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil, volumes: 2)
        let anime = Self.entry(.anime, 1, .current, progress: 5, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let input = LibraryExportInput(
            entries: [manga, anime],
            catalogue: [manga.key: Self.row("Moon Ledger", mal: 41), anime.key: Self.row("Kaiju Diary", mal: 42)]
        )
        let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        let mangaXML = String(decoding: try #require(bundle.files.first { $0.name.contains("manga") }).data, as: UTF8.self)
        let animeXML = String(decoding: try #require(bundle.files.first { $0.name.contains("anime") }).data, as: UTF8.self)
        #expect(mangaXML.contains("<manga_mangadb_id>41</manga_mangadb_id>"))
        #expect(mangaXML.contains("<manga_title>Moon Ledger</manga_title>"))
        #expect(!mangaXML.contains("series_"))
        #expect(animeXML.contains("<series_animedb_id>42</series_animedb_id>"))
        #expect(animeXML.contains("<series_title>Kaiju Diary</series_title>"))
        #expect(!animeXML.contains("manga_"))
        let parsed = try MALExportParser.parse(try #require(bundle.files.first { $0.name.contains("manga") }).data)
        #expect(parsed.map(\.externalId) == ["41"] && parsed.first?.sourceTitle == "Moon Ledger")
    }

    /// The "Untitled ..." fallback names a title in the report; it is never written into the file another
    /// service imports.
    @Test func missingCatalogueTitleOmitsTheTitleElementButKeepsTheReportFallback() throws {
        let anime = Self.entry(.anime, 7, .current, progress: 1, rating: nil, notes: "bell\u{07}", repeatCount: 0, started: nil, finished: nil)
        let manga = Self.entry(.manga, 9, .current, progress: 1, rating: nil, notes: "bell\u{07}", repeatCount: 0, started: nil, finished: nil)
        let blank = Self.entry(.manga, 10, .current, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let input = LibraryExportInput(
            entries: [anime, manga, blank],
            catalogue: [anime.key: Self.row(nil, mal: 51), manga.key: Self.row(nil, mal: 52), blank.key: Self.row("   ", mal: 53)]
        )
        let bundle = LibraryExport.build(input, formats: [.malXML], exportedAt: Self.now, timeZone: Self.berlin)
        for file in bundle.files {
            let xml = String(decoding: file.data, as: UTF8.self)
            #expect(!xml.contains("_title>") && !xml.contains("Untitled"))
            #expect(try MALExportParser.parse(file.data).allSatisfy { $0.sourceTitle == nil })
        }
        #expect(bundle.summary.notesAdjusted.map(\.title) == ["Untitled anime #7", "Untitled manga #9"])
    }

    // MARK: - Fixtures

    /// 2026-11-09 10:59:30 UTC, which is 11:59:30 in Europe/Berlin.
    static let now = Date(timeIntervalSince1970: 1_794_221_970)
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    static let berlin = TimeZone(identifier: "Europe/Berlin") ?? TimeZone(secondsFromGMT: 3_600) ?? .gmt

    static func row(_ title: String?, mal: Int?) -> ExportCatalogueRow {
        ExportCatalogueRow(title: title, anilistId: nil, malId: mal)
    }

    /// An entry whose `sourceMetadata` carries the given repeat count, dates and volumes.
    static func entry(
        _ kind: MediaKind, _ id: Int, _ status: ListStatus, progress: Int, rating: Int?, notes: String?,
        repeatCount: Int?, started: String?, finished: String?, volumes: Int? = nil
    ) -> LibraryEntry {
        LibraryEntry(
            key: MediaKey(kind: kind, id: id), rowId: id, status: status, progress: progress,
            rating: rating.flatMap { UserRating(value: $0) }, notes: notes, createdAt: epoch, updatedAt: epoch,
            sourceMetadata: LibrarySourceMetadata(
                volumesProgress: volumes, repeatCount: repeatCount, startedRaw: started, finishedRaw: finished
            )
        )
    }

    /// The status the import path stores for an exported status: the database has no `REPEATING`.
    static func storedEquivalent(_ status: ListStatus) -> ListStatus {
        status == .repeating ? .current : status
    }

    /// Anime and manga, every status, with every note / rating / date shape and a MAL id for each entry
    /// (anime 1001..., manga 2001...).
    static func everyStatusInput() -> LibraryExportInput {
        let notes: [String?] = [nil, "", "a & b <c> \"d\" 'e'", "line1\r\nline2", "  padded  ", "Grüße 🌸"]
        let ratings: [Int?] = [nil, 1, 10]
        let dates: [String?] = [nil, "2024", "2024-03", "2024-03-05", "2024-03-00"]
        let progress = [0, 1, 12, 64, 99, 140]
        var entries: [LibraryEntry] = []
        var catalogue: [MediaKey: ExportCatalogueRow] = [:]
        for (kindIndex, kind) in [MediaKind.anime, .manga].enumerated() {
            for (index, status) in ListStatus.allCases.enumerated() {
                let id = index + 1
                let seed = kindIndex * 6 + index
                let entry = Self.entry(
                    kind, id, status, progress: progress[(index + kindIndex * 3) % progress.count],
                    rating: ratings[seed % ratings.count], notes: notes[seed % notes.count],
                    repeatCount: seed % 2 == 0 ? 0 : 3, started: dates[seed % dates.count],
                    finished: dates[(seed + 2) % dates.count], volumes: kind == .manga ? seed : nil
                )
                entries.append(entry)
                catalogue[entry.key] = ExportCatalogueRow(
                    title: id == 3 ? "Tom & Jerry <\"3\">" : "Title \(id)", anilistId: 500 + id,
                    malId: (kind == .anime ? 1_000 : 2_000) + id
                )
            }
        }
        return LibraryExportInput(entries: entries, catalogue: catalogue)
    }

    /// `count` entries of one medium with MAL ids `1...count` (Kuro ids reversed, so sorting is by MAL id) and
    /// the same note on every entry.
    static func largeLibrary(count: Int, kind: MediaKind, note: String) -> LibraryExportInput {
        var entries: [LibraryEntry] = []
        var catalogue: [MediaKey: ExportCatalogueRow] = [:]
        entries.reserveCapacity(count)
        for index in 1...count {
            let kuroId = count + 1 - index
            let entry = Self.entry(kind, kuroId, .completed, progress: 12, rating: 7, notes: note, repeatCount: 1, started: "2024-03-05", finished: nil, volumes: kind == .manga ? 2 : nil)
            entries.append(entry)
            catalogue[entry.key] = ExportCatalogueRow(title: "Title \(index)", anilistId: nil, malId: index)
        }
        return LibraryExportInput(entries: entries, catalogue: catalogue)
    }
}
