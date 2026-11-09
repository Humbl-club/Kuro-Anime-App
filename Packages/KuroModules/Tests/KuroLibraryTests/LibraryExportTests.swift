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
        #expect(defaults.failedFormats.isEmpty)
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
        let bundle = LibraryExport.build(input, formats: [.malXML, .csv, .json], exportedAt: Self.now, timeZone: Self.berlin)
        let animeFile = try #require(bundle.files.first { $0.name.contains("anime") })
        let mangaFile = try #require(bundle.files.first { $0.name.contains("manga") })
        let animeParsed = try MALExportParser.parse(animeFile.data)
        let mangaParsed = try MALExportParser.parse(mangaFile.data)

        // JSON half: unknown source values are null, never 0 and never "no dates".
        let jsonEntries = try Self.jsonEntries(bundle.file("kuro-list-2026-11-09.json"))
        #expect(jsonEntries.count == 3)
        for index in [0, 2] {   // anime 1 and manga 2 carry no source metadata (sorted: anime 1, anime 3, manga 2)
            let bareEntry = jsonEntries[index]
            #expect(bareEntry["repeat_count"] is NSNull)
            #expect(bareEntry["source"] is NSNull)
            #expect(bareEntry["started_on"] is NSNull && bareEntry["finished_on"] is NSNull)
            #expect(bareEntry["volumes_progress"] is NSNull)
        }
        let knownEntry = jsonEntries[1]
        #expect(knownEntry["repeat_count"] as? Int == 0)
        #expect(knownEntry["source"] is [String: Any])
        #expect(knownEntry["started_on"] is NSNull && knownEntry["finished_on"] is NSNull)
        // CSV half: the same cells are empty, a known zero is "0".
        let csv = try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv"))
        let repeatColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "repeat_count"))
        let startedColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "started_on"))
        let volumesColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "volumes_progress"))
        #expect(csv.dropFirst().map { $0[repeatColumn] } == ["", "0", ""])
        #expect(csv.dropFirst().map { $0[startedColumn] } == ["", "", ""])
        #expect(csv.dropFirst().map { $0[volumesColumn] } == ["", "", ""])

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

    // MARK: - CSV, JSON, summary, file names

    @Test func entriesWithoutMalIdAreReportedNotDropped() throws {
        let bundle = LibraryExport.build(Self.twoWithoutMalId(), formats: [.malXML, .csv, .json], exportedAt: Self.now, timeZone: Self.berlin)
        let parsed = try bundle.files.filter { $0.name.hasSuffix(".xml") }.flatMap { try MALExportParser.parse($0.data) }
        #expect(parsed.count == 4)
        #expect(bundle.summary.withoutMalId.map(\.title).sorted() == ["Kaiju Diary", "Moon Ledger"])
        #expect(try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv")).count == 1 + 6)   // header + every entry
        #expect(try Self.jsonEntries(bundle.file("kuro-list-2026-11-09.json")).count == 6)
        #expect(bundle.files.map(\.name) == [
            "kuro-anime-2026-11-09.xml", "kuro-manga-2026-11-09.xml", "kuro-list-2026-11-09.csv", "kuro-list-2026-11-09.json",
        ])
        #expect(bundle.summary.isComplete)
    }

    /// The MAL writer skips a MAL id outside `1...Int32.max`; the summary must report the same titles, or a
    /// title would be neither exported to MAL nor reported. CSV and JSON keep the stored id as it is.
    @Test func malIdsOutsideTheWritableRangeAreReportedAsWithoutMalId() throws {
        let ids: [(id: Int, mal: Int?)] = [
            (1, 0), (2, -5), (3, Int(Int32.max) + 1), (4, Int(Int32.max)), (5, 1), (6, nil),
        ]
        var entries: [LibraryEntry] = []
        var catalogue: [MediaKey: ExportCatalogueRow] = [:]
        for item in ids {
            let entry = Self.entry(.anime, item.id, .completed, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
            entries.append(entry)
            catalogue[entry.key] = Self.row("Title \(item.id)", mal: item.mal)
        }
        let bundle = LibraryExport.build(LibraryExportInput(entries: entries, catalogue: catalogue), formats: [.malXML, .csv, .json], exportedAt: Self.now, timeZone: Self.berlin)
        let parsed = try MALExportParser.parse(bundle.file("kuro-anime-2026-11-09.xml").data)
        #expect(parsed.map(\.externalId).sorted() == ["1", String(Int32.max)].sorted())
        #expect(bundle.summary.malExported == [.anime: 2])
        #expect(bundle.summary.withoutMalId.map(\.key.id).sorted() == [1, 2, 3, 6])
        // Every entry is exactly one of: written to MAL, reported without a MAL id.
        #expect(parsed.count + bundle.summary.withoutMalId.count == entries.count)
        #expect(bundle.summary.isComplete)
        // CSV and JSON keep the stored catalogue value. (Every CSV cell is neutralised alike, so the impossible
        // negative id reads back with the leading apostrophe; the JSON value is exact.)
        let malColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "mal_id"))
        let csvMalIds = try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv")).dropFirst().map { $0[malColumn] }
        #expect(csvMalIds == ["0", "'-5", String(Int(Int32.max) + 1), String(Int32.max), "1", ""])
        let jsonIds = try Self.jsonEntries(bundle.file("kuro-list-2026-11-09.json")).map { $0["mal_id"] as? Int }
        #expect(jsonIds == [0, -5, Int(Int32.max) + 1, Int(Int32.max), 1, nil])
    }

    @Test func csvHasDocumentedHeaderAndEscapesText() throws {
        let note = "first, \"quoted\"\r\nsecond line"
        let file = try #require(LibraryExport.build(Self.single(notes: note), formats: [.csv], exportedAt: Self.now, timeZone: Self.berlin).files.first)
        let rows = try Self.csvRows(file)
        #expect(rows[0] == LibraryExport.csvHeader)
        #expect(LibraryExport.csvHeader.first == "kind" && LibraryExport.csvHeader.count == 20)
        #expect(LibraryExport.csvHeader.joined(separator: ",") == "kind,kuro_id,anilist_id,mal_id,title,status,progress,progress_label,unit_id,volumes_progress,rating,verdict,repeat_count,started_on,finished_on,notes,tags,custom_lists,created_at,updated_at")
        let notesColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "notes"))
        #expect(rows[1][notesColumn] == note)
        #expect(rows[1].count == 20)
        // UTF-8 BOM first, CRLF records, the header row is unquoted.
        #expect(Array(file.data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: file.data.dropFirst(3).prefix(40), as: UTF8.self).hasPrefix("kind,kuro_id,anilist_id,mal_id,title,"))
        #expect(file.name == "kuro-list-2026-11-09.csv" && file.contentType == "text/csv")
        #expect(String(decoding: file.data, as: UTF8.self).hasSuffix("\r\n"))
    }

    /// German spreadsheet apps split CSV on `;` and tab-delimited readers split on TAB. A cell holding either is
    /// quoted, so the second part of `abc;=1+1` is never an unquoted segment that starts with a formula trigger.
    /// (`RFC4180.field` itself stays the plain RFC encoder: it leaves such a cell unquoted.)
    @Test func csvQuotesEveryCellThatHoldsASemicolonOrTab() throws {
        let notes = ["abc;=1+1", "x\t@SUM(A1)", "plain", ";=cmd", "a;b;-2;@x", "\t@lead", "=lead;=again"]
        var entries: [LibraryEntry] = []
        var catalogue: [MediaKey: ExportCatalogueRow] = [:]
        for (index, note) in notes.enumerated() {
            let entry = Self.entry(.anime, index + 1, .current, progress: 1, rating: nil, notes: note, repeatCount: 0, started: nil, finished: nil)
            entries.append(entry)
            catalogue[entry.key] = Self.row(index == 0 ? "Fate; Zero" : "Title \(index + 1)", mal: 100 + index)
        }
        let file = try #require(LibraryExport.build(LibraryExportInput(entries: entries, catalogue: catalogue), formats: [.csv], exportedAt: Self.now, timeZone: Self.berlin).files.first)
        let text = String(decoding: file.data.dropFirst(3), as: UTF8.self)

        // The two cells named in the review are written quoted, with the inner trigger neutralised.
        #expect(text.contains("\"abc;'=1+1\"") && text.contains("\"x\t'@SUM(A1)\""))
        #expect(text.contains("\"Fate; Zero\""))
        // A cell with neither character stays unquoted (no gratuitous quoting).
        #expect(text.contains(",plain,") && text.contains(",Title 2,"))

        // The strict RFC 4180 reader returns the neutralised text exactly: only the cell-start rule changes it.
        let rows = try Self.csvRows(file)
        let notesColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "notes"))
        let titleColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "title"))
        #expect(rows.dropFirst().map { $0[notesColumn] } == [
            "abc;'=1+1", "x\t'@SUM(A1)", "plain", ";'=cmd", "a;b;'-2;'@x", "'\t'@lead", "'=lead;'=again",
        ])
        #expect(rows[1][titleColumn] == "Fate; Zero")

        // No `;` or TAB outside quotes, so no segment a quote-aware ;- or tab-splitting reader sees starts with
        // a trigger. (The next test checks readers that ignore the quotes.)
        #expect(Self.triggerSegments(in: text).isEmpty)
        // The check bites: the plain RFC encoder leaves `abc;=1+1` split-able.
        #expect(Self.triggerSegments(in: RFC4180.row(["k", "abc;=1+1"])) == ["=1+1"])
        #expect(Self.triggerSegments(in: RFC4180.row(["k", "x\t@SUM(A1)"])) == ["@SUM(A1)"])
    }

    /// Quoting cannot protect a reader that splits on `;` or TAB without reading quotes (German Excel: the
    /// quote is not at the start of its `;`-field). The neutraliser itself must leave no formula trigger at the
    /// start of any segment such a reader produces, in any cell and for any mix of the delimiters.
    @Test func csvHasNoFormulaTriggerAfterAnyDelimiterForReadersThatIgnoreQuotes() throws {
        let notes = [
            "x;=1+1;y", "a\t@SUM(A1)", "abc;=HYPERLINK(\"http://x\";\"y\")", ";=cmd", "=a;=b;=c", "\t\t=x",
            "line\n=x", "line\r\n+1", "q;\"=x\"", "a;-1;+2;@3", ";\t;=x", "ö;=ö\t=ä",
        ]
        var entries: [LibraryEntry] = []
        var catalogue: [MediaKey: ExportCatalogueRow] = [:]
        var tags: [MediaKey: [String]] = [:]
        for (index, note) in notes.enumerated() {
            let entry = Self.entry(.anime, index + 1, .current, progress: 1, rating: nil, notes: note, repeatCount: 0, started: nil, finished: nil)
            entries.append(entry)
            // Titles, list names and tags are cells too; the joined cells put "; " between their parts.
            catalogue[entry.key] = Self.row(index % 2 == 0 ? "T;=\(index)" : "-\(index);@t", mal: 100 + index)
            tags[entry.key] = ["=t\(index)", "@u;=v", "plain"]
        }
        let lists = [
            ExportCustomList(id: UUID(), name: "=List;=One", createdAt: Self.epoch, items: entries.map(\.key)),
            ExportCustomList(id: UUID(), name: "+Two", createdAt: Self.epoch, items: entries.map(\.key)),
        ]
        let input = LibraryExportInput(entries: entries, catalogue: catalogue, tagsByKey: tags, customLists: lists)
        let file = try #require(LibraryExport.build(input, formats: [.csv], exportedAt: Self.now, timeZone: Self.berlin).files.first)
        let text = String(decoding: file.data.dropFirst(3), as: UTF8.self)

        // Naive readers: lines split at CR / LF, cells at `;` (a semicolon-locale reader) and at TAB, no quote
        // handling.
        #expect(Self.naiveTriggerSegments(in: text).isEmpty)
        #expect(Self.triggerSegments(in: text).isEmpty)
        // The check bites: the plain RFC encoder alone leaves such segments.
        #expect(Self.naiveTriggerSegments(in: RFC4180.row(["k", "x;=1+1;y"])) == ["=1+1"])
        #expect(Self.naiveTriggerSegments(in: RFC4180.row(["k", "a\t@SUM"])) == ["@SUM"])
        #expect(Self.naiveTriggerSegments(in: RFC4180.row(["k", "line\n=x"])) == ["=x\""])
        // A trigger one space after a delimiter does not start a segment (the "; " that joins tags is safe).
        #expect(Self.naiveTriggerSegments(in: RFC4180.row(["k", "a; =x"])).isEmpty)

        // The strict reader still reads every cell back: the neutralised text, with only apostrophes added.
        let rows = try Self.csvRows(file)
        let notesColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "notes"))
        for (index, note) in notes.enumerated() {
            let cell = rows[index + 1][notesColumn]
            #expect(cell == LibraryExport.csvSafeText(note))
            #expect(cell.unicodeScalars.filter { $0 != "'" }.elementsEqual(note.unicodeScalars.filter { $0 != "'" }))
        }
        // Titles, tags and list names are cells too: guarded at the start and after `;`, joined with "; ".
        let titleColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "title"))
        let tagsColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "tags"))
        let listsColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "custom_lists"))
        #expect(rows[1][titleColumn] == "T;'=0" && rows[2][titleColumn] == "'-1;'@t")
        #expect(rows[1][tagsColumn] == "'=t0; @u;'=v; plain")
        #expect(rows[1][listsColumn] == "'=List;'=One; +Two")
        // JSON keeps every one of them exactly.
        let json = try LibraryExport.build(input, formats: [.json], exportedAt: Self.now, timeZone: Self.berlin).file("kuro-list-2026-11-09.json")
        #expect(try Self.jsonEntries(json).map { $0["notes"] as? String } == notes)
        #expect(try Self.jsonEntries(json).first?["tags"] as? [String] == ["=t0", "@u;=v", "plain"])
    }

    /// For any mix of the delimiters, triggers and ordinary characters: the neutraliser only adds apostrophes,
    /// and afterwards no trigger sits at the start of the text or right after `;`, TAB, CR or LF.
    @Test func csvSafeTextPropertyHoldsForGeneratedText() throws {
        let alphabet: [Unicode.Scalar] = [";", "\t", "\r", "\n", "=", "+", "-", "@", "a", "é", " ", ",", "\"", "日"]
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: state >> 33)
        }
        let triggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
        let boundaries: Set<Unicode.Scalar> = [";", "\t", "\r", "\n"]
        var samples: [String] = []
        for _ in 0..<3_000 {
            var scalars = String.UnicodeScalarView()
            for _ in 0..<(next() % 12) { scalars.append(alphabet[next() % alphabet.count]) }
            samples.append(String(scalars))
        }
        for sample in samples {
            let safe = LibraryExport.csvSafeText(sample)
            // Only apostrophes were added (the alphabet has none).
            #expect(safe.unicodeScalars.filter { $0 != "'" }.elementsEqual(sample.unicodeScalars))
            var previous: Unicode.Scalar?
            for scalar in safe.unicodeScalars {
                if triggers.contains(scalar) {
                    // Not at the start (`previous == nil`) and not right after a boundary.
                    let atSegmentStart = previous.map { boundaries.contains($0) } ?? true
                    #expect(!atSegmentStart, "trigger at a segment start in \(safe.debugDescription)")
                }
                previous = scalar
            }
            // Text with nothing to guard comes back untouched (the same String, not a copy with changes).
            if safe.unicodeScalars.count == sample.unicodeScalars.count { #expect(safe == sample) }
        }
        // And through the CSV: a naive reader finds nothing, the strict reader reads the neutralised text back.
        var entries: [LibraryEntry] = []
        for (index, sample) in samples.enumerated() {
            entries.append(Self.entry(.anime, index + 1, .current, progress: 1, rating: nil, notes: sample, repeatCount: 0, started: nil, finished: nil))
        }
        let file = try #require(LibraryExport.build(LibraryExportInput(entries: entries, catalogue: [:]), formats: [.csv], exportedAt: Self.now, timeZone: Self.berlin).files.first)
        #expect(Self.naiveTriggerSegments(in: String(decoding: file.data.dropFirst(3), as: UTF8.self)).isEmpty)
        let rows = try Self.csvRows(file)
        let notesColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "notes"))
        #expect(rows.dropFirst().map { $0[notesColumn] } == samples.map(LibraryExport.csvSafeText))
    }

    @Test func csvCellsFollowTheDocumentedValues() throws {
        let unit = Self.unitId
        let manga = LibraryEntry(
            key: MediaKey(kind: .manga, id: 5), rowId: 5, status: .repeating, progress: 14,
            rating: UserRating(value: 9), notes: "n", verdict: .masterpiece,
            createdAt: Self.epoch, updatedAt: Self.now, progressLabel: "Vol 2", unitId: unit,
            sourceMetadata: LibrarySourceMetadata(
                volumesProgress: 2, repeatCount: 2, startedRaw: "2024-03-00", finishedRaw: "spring 2019"
            )
        )
        let unknown = LibraryEntry(key: MediaKey(kind: .anime, id: 3), rowId: 3, status: .planning, progress: 0, createdAt: Self.epoch, updatedAt: Self.epoch)
        let simple = Self.entry(.anime, 1, .completed, progress: 12, rating: 7, notes: nil, repeatCount: 0, started: "2024", finished: "2024-05-07")
        let input = LibraryExportInput(
            entries: [manga, unknown, simple],
            catalogue: [
                manga.key: ExportCatalogueRow(title: "Moon Ledger", anilistId: 77, malId: nil),
                simple.key: ExportCatalogueRow(title: "Alpha", anilistId: 11, malId: 101),
            ],
            tagsByKey: [manga.key: ["a", "b; c"]],
            customLists: [
                ExportCustomList(id: UUID(), name: "Comfort", createdAt: Self.epoch, items: [manga.key]),
                ExportCustomList(id: UUID(), name: "Later", createdAt: Self.epoch, items: [simple.key, manga.key]),
                ExportCustomList(id: UUID(), name: "Empty", createdAt: Self.epoch, items: []),
            ]
        )
        let bundle = LibraryExport.build(input, formats: [.csv], exportedAt: Self.now, timeZone: Self.berlin)
        let rows = try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv"))
        #expect(rows.count == 4)
        // Rows: anime before manga, then Kuro id.
        #expect(rows.dropFirst().map { $0[0] + ":" + $0[1] } == ["anime:1", "anime:3", "manga:5"])
        let first = Self.cells(rows[1]), second = Self.cells(rows[2]), third = Self.cells(rows[3])

        #expect(first["anilist_id"] == "11" && first["mal_id"] == "101" && first["title"] == "Alpha")
        #expect(first["status"] == "COMPLETED" && first["progress"] == "12" && first["rating"] == "7")
        #expect(first["verdict"] == "" && first["notes"] == "" && first["tags"] == "" && first["custom_lists"] == "Later")
        #expect(first["repeat_count"] == "0" && first["started_on"] == "2024" && first["finished_on"] == "2024-05-07")
        #expect(first["progress_label"] == "" && first["unit_id"] == "" && first["volumes_progress"] == "")
        #expect(first["created_at"] == "2023-11-14T22:13:20Z" && first["updated_at"] == "2023-11-14T22:13:20Z")

        // No catalogue row: ids and title are empty; no source metadata: nothing invented.
        #expect(second["anilist_id"] == "" && second["mal_id"] == "" && second["title"] == "")
        #expect(second["status"] == "PLANNING" && second["progress"] == "0" && second["rating"] == "")
        #expect(second["repeat_count"] == "" && second["started_on"] == "" && second["finished_on"] == "" && second["volumes_progress"] == "")

        #expect(third["kind"] == "manga" && third["anilist_id"] == "77" && third["mal_id"] == "" && third["title"] == "Moon Ledger")
        #expect(third["status"] == "REPEATING" && third["progress"] == "14" && third["verdict"] == "MASTERPIECE" && third["rating"] == "9")
        #expect(third["progress_label"] == "Vol 2" && third["unit_id"] == unit.uuidString.lowercased() && third["volumes_progress"] == "2")
        #expect(third["repeat_count"] == "2")
        // A canonical partial date is written as the parsed value; a stored text that is not a date stays as stored.
        #expect(third["started_on"] == "2024-03" && third["finished_on"] == "spring 2019")
        #expect(third["notes"] == "n" && third["tags"] == "a; b; c" && third["custom_lists"] == "Comfort; Later")
        #expect(third["created_at"] == "2023-11-14T22:13:20Z" && third["updated_at"] == "2026-11-09T10:59:30Z")
    }

    @Test func timestampsAreIso8601UtcWithoutFractionsAcrossTheCalendar() throws {
        let seconds: [TimeInterval] = [0, 951_782_400, 951_868_799, 1_700_000_000, 1_794_221_970, -1, 4_102_444_800, 253_402_300_799, 1_700_000_000.999]
        var entries: [LibraryEntry] = []
        for (index, value) in seconds.enumerated() {
            let entry = LibraryEntry(
                key: MediaKey(kind: .anime, id: index + 1), rowId: index + 1, status: .current, progress: 1,
                createdAt: Date(timeIntervalSince1970: value), updatedAt: Date(timeIntervalSince1970: value)
            )
            entries.append(entry)
        }
        let bundle = LibraryExport.build(LibraryExportInput(entries: entries, catalogue: [:]), formats: [.csv], exportedAt: Self.now, timeZone: Self.berlin)
        let column = try #require(LibraryExport.csvHeader.firstIndex(of: "created_at"))
        let written = try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv")).dropFirst().map { $0[column] }
        let reference = ISO8601DateFormatter()
        reference.formatOptions = [.withInternetDateTime]
        reference.timeZone = TimeZone(secondsFromGMT: 0)
        #expect(written == seconds.map { reference.string(from: Date(timeIntervalSince1970: $0.rounded(.down))) })
        #expect(written[0] == "1970-01-01T00:00:00Z" && written[1] == "2000-02-29T00:00:00Z" && written[2] == "2000-02-29T23:59:59Z")
        #expect(written[3] == "2023-11-14T22:13:20Z" && written[5] == "1969-12-31T23:59:59Z" && written[7] == "9999-12-31T23:59:59Z")
        #expect(written[8] == "2023-11-14T22:13:20Z")   // fractions are dropped, never rounded up
    }

    @Test func jsonCarriesIdsTagsListsAndDates() throws {
        let bundle = LibraryExport.build(Self.idsTagsListsInput(), formats: [.json, .csv], exportedAt: Self.now, timeZone: Self.berlin)
        let json = try bundle.file("kuro-list-2026-11-09.json")
        #expect(json.contentType == "application/json")
        let entries = try Self.jsonEntries(json)
        let entry = try #require(entries.first)
        #expect(entry["kind"] as? String == "anime")
        #expect(entry["kuro_id"] as? Int == 42 && entry["anilist_id"] as? Int == 9253 && entry["mal_id"] as? Int == 9253)
        #expect(entry["title"] as? String == "Frieren")
        #expect(entry["status"] as? String == "COMPLETED" && entry["progress"] as? Int == 28)
        #expect(entry["progress_label"] as? String == "S2 E5")
        #expect(entry["unit_id"] as? String == Self.unitId.uuidString.lowercased())
        #expect(entry["tags"] as? [String] == ["slow burn", "rewatch"])
        #expect(entry["custom_lists"] as? [String] == ["Comfort"])
        #expect((entry["started_on"] as? [String: Any])?["raw"] as? String == "2019-04")
        #expect((entry["started_on"] as? [String: Any])?["precision"] as? String == "month")
        #expect(entry["finished_on"] is NSNull)
        #expect(((entry["source"] as? [String: Any])?["imported_custom_lists"] as? [String]) == ["Imported A"])
        #expect(entry["rating"] as? Int == 9 && entry["verdict"] as? String == "MASTERPIECE")
        #expect(entry["repeat_count"] as? Int == 1 && entry["volumes_progress"] is NSNull)
        #expect(entry["created_at"] as? String == "2023-11-14T22:13:20Z" && entry["updated_at"] as? String == "2023-11-14T22:13:20Z")
        let source = try #require(entry["source"] as? [String: Any])
        #expect(source["score_raw"] as? String == "9" && source["score_scale"] as? String == "POINT_10")
        #expect(source["private"] as? Bool == false && source["hidden_from_status_lists"] as? Bool == true)
        #expect(source["list_options"] as? String == "{\"a\":1}")
        #expect(Set(entry.keys) == [
            "kind", "kuro_id", "anilist_id", "mal_id", "title", "status", "progress", "progress_label", "unit_id",
            "volumes_progress", "rating", "verdict", "notes", "repeat_count", "started_on", "finished_on", "tags",
            "custom_lists", "source", "created_at", "updated_at",
        ])
        // Second entry: no unit, no label, no catalogue row, no tags. Null in JSON (never "" and never
        // inferred), empty cells in CSV.
        let second = entries[1]
        #expect(second["unit_id"] is NSNull && second["progress_label"] is NSNull)
        #expect(second["anilist_id"] is NSNull && second["mal_id"] is NSNull && second["title"] is NSNull)
        #expect((second["tags"] as? [String])?.isEmpty == true && (second["custom_lists"] as? [String])?.isEmpty == true)
        let csvRows = try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv"))
        let unitColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "unit_id"))
        let labelColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "progress_label"))
        #expect(csvRows[2][unitColumn] == "" && csvRows[2][labelColumn] == "")
        #expect(csvRows[1][unitColumn] == Self.unitId.uuidString.lowercased() && csvRows[1][labelColumn] == "S2 E5")
    }

    @Test func jsonTopLevelShapeAndDateRawStayVerbatim() throws {
        let month = Self.entry(.anime, 1, .completed, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: "2019-04-00", finished: "2020")
        let junk = Self.entry(.anime, 2, .completed, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: "spring 2019", finished: "0000-00-00")
        let blank = Self.entry(.anime, 3, .completed, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: "", finished: "2024-02-30")
        let day = Self.entry(.anime, 4, .completed, progress: 1, rating: nil, notes: "", repeatCount: 0, started: "2024-03-05", finished: nil)
        let input = LibraryExportInput(entries: [month, junk, blank, day], catalogue: [:])
        let bundle = LibraryExport.build(input, formats: [.json], exportedAt: Self.now, timeZone: Self.berlin)
        let file = try bundle.file("kuro-list-2026-11-09.json")
        let object = try Self.jsonObject(file)
        #expect(object["format"] as? String == "kuro-library-export" && object["version"] as? Int == 1)
        #expect(object["exported_at"] as? String == "2026-11-09T10:59:30Z")
        #expect(Set(object.keys) == ["format", "version", "exported_at", "complete", "gaps", "entries", "lists"])
        func date(_ index: Int, _ key: String) throws -> (raw: String, precision: String?)? {
            let entries = try Self.jsonEntries(file)
            guard let value = entries[index][key] as? [String: Any] else { return nil }
            return (try #require(value["raw"] as? String), value["precision"] as? String)
        }
        // The JSON keeps the stored text; the precision is what it parses to.
        #expect(try date(0, "started_on")?.raw == "2019-04-00" && date(0, "started_on")?.precision == "month")
        #expect(try date(0, "finished_on")?.raw == "2020" && date(0, "finished_on")?.precision == "year")
        #expect(try date(1, "started_on")?.raw == "spring 2019" && date(1, "started_on")?.precision == nil)
        #expect(try date(1, "finished_on")?.raw == "0000-00-00" && date(1, "finished_on")?.precision == nil)
        #expect(try date(2, "started_on") == nil)                                   // "" is no date
        #expect(try date(2, "finished_on")?.raw == "2024-02-30" && date(2, "finished_on")?.precision == nil)
        #expect(try date(3, "started_on")?.precision == "day")
        // An empty note stays an empty string; a missing note is null.
        let notes = try Self.jsonEntries(file).map { $0["notes"] }
        #expect(notes[0] is NSNull && (notes[3] as? String) == "")
        // Pretty printed, sorted keys, no escaped slashes: stable bytes for the same input.
        let text = String(decoding: file.data, as: UTF8.self)
        #expect(text.contains("\n") && text.contains("\"complete\" : false"))   // no catalogue rows: identities unknown
        #expect(LibraryExport.build(input, formats: [.json], exportedAt: Self.now, timeZone: Self.berlin).files == bundle.files)
    }

    @Test func jsonExportsListsInManualOrderWithItemsOutsideTheLibrary() throws {
        let bundle = LibraryExport.build(Self.listsInput(), formats: [.json, .csv], exportedAt: Self.now, timeZone: Self.berlin)
        let lists = try Self.jsonLists(bundle.file("kuro-list-2026-11-09.json"))
        #expect(lists.map { $0["name"] as? String } == ["Comfort", "Empty one"])            // order kept, empty list kept
        let items = try #require(lists[0]["items"] as? [[String: Any]])
        #expect(items.map { $0["media_id"] as? Int } == [3, 1, 99])                         // manual order
        #expect(items.map { $0["medium"] as? String } == ["manga", "anime", "anime"])
        #expect(items.map { $0["position"] as? Int } == [1, 2, 3])
        #expect(items.map { $0["in_library"] as? Bool } == [true, true, false])
        #expect(items[2]["title"] as? String == "Old Flame")
        #expect(items[0]["title"] as? String == "Moon Ledger" && items[1]["title"] as? String == "Alpha")
        #expect((lists[1]["items"] as? [Any])?.isEmpty == true)
        #expect(lists[0]["created_at"] as? String == "2026-10-01T00:00:00Z" && lists[0]["id"] is String)
        #expect(lists[1]["created_at"] as? String == "2026-10-02T00:00:00Z")
        #expect(lists[0]["id"] as? String == Self.listId.uuidString.lowercased())
        #expect(Set(items[0].keys) == ["medium", "media_id", "position", "in_library", "title"])
        #expect(bundle.summary.listItemsOutsideLibrary == 1)
        #expect(try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv")).count == 1 + 3)  // no CSV row for anime 99
        // The per-entry list names come from the lists (one source of truth).
        let entries = try Self.jsonEntries(bundle.file("kuro-list-2026-11-09.json"))
        #expect(entries.map { $0["custom_lists"] as? [String] } == [["Comfort"], [], ["Comfort"]])
        #expect(bundle.summary.isComplete)

        // A title that is not in the library and has no catalogue row exports title null; it is not a gap.
        var noRow = Self.listsInput()
        noRow.catalogue[MediaKey(kind: .anime, id: 99)] = nil
        let noRowBundle = LibraryExport.build(noRow, formats: [.json], exportedAt: Self.now, timeZone: Self.berlin)
        let noRowItems = try #require(try Self.jsonLists(noRowBundle.file("kuro-list-2026-11-09.json"))[0]["items"] as? [[String: Any]])
        #expect(noRowItems[2]["title"] is NSNull)
        #expect(noRowBundle.summary.isComplete)

        // The provider could not load: lists are null (never []), per-entry organisation is null (never []),
        // CSV cells are empty, and nothing is counted as outside the library.
        var unavailable = Self.listsInput()
        unavailable.organisationUnavailable = true
        let off = LibraryExport.build(unavailable, formats: [.json, .csv], exportedAt: Self.now, timeZone: Self.berlin)
        let object = try Self.jsonObject(off.file("kuro-list-2026-11-09.json"))
        #expect(object["lists"] is NSNull)
        let offEntries = try Self.jsonEntries(off.file("kuro-list-2026-11-09.json"))
        #expect(offEntries.allSatisfy { $0["tags"] is NSNull && $0["custom_lists"] is NSNull })
        let listsColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "custom_lists"))
        let tagsColumn = try #require(LibraryExport.csvHeader.firstIndex(of: "tags"))
        #expect(try Self.csvRows(off.file("kuro-list-2026-11-09.csv")).dropFirst().allSatisfy { $0[listsColumn] == "" && $0[tagsColumn] == "" })
        #expect(off.summary.listItemsOutsideLibrary == 0)
        #expect(off.summary.gaps == [.organisationUnavailable])
    }

    @Test func csvNeutralisesFormulaCellsAndJsonKeepsExactText() throws {
        let bundle = LibraryExport.build(Self.formulaInput(), formats: [.csv, .json], exportedAt: Self.now, timeZone: Self.berlin)
        let rows = try Self.csvRows(bundle.file("kuro-list-2026-11-09.csv"))
        let notes = try #require(LibraryExport.csvHeader.firstIndex(of: "notes"))
        let title = try #require(LibraryExport.csvHeader.firstIndex(of: "title"))
        #expect(rows.dropFirst().prefix(6).map { $0[notes] } == Self.formulaNotes.map { "'" + $0 })
        #expect(rows[7][title] == "'=cmd" && rows[7][notes] == "a=b")
        #expect(try Self.jsonEntries(bundle.file("kuro-list-2026-11-09.json")).prefix(6).map { $0["notes"] as? String } == Self.formulaNotes)
        #expect(try Self.jsonEntries(bundle.file("kuro-list-2026-11-09.json"))[6]["title"] as? String == "=cmd")
        #expect(LibraryExport.csvSafeText("plain") == "plain" && LibraryExport.csvSafeText("") == "")
        // Only the first character decides, and a CRLF start counts as a CR.
        #expect(LibraryExport.csvSafeText("\r\nx") == "'\r\nx")
        #expect(LibraryExport.csvSafeText(" =x") == " =x" && LibraryExport.csvSafeText("x=") == "x=")
        #expect(LibraryExport.csvSafeText("=") == "'=" && LibraryExport.csvSafeText("'=x") == "'=x")
        #expect(LibraryExport.csvSafeText("\nx") == "\nx")
        // A trigger right after `;`, TAB, CR or LF inside the text is guarded too (a ;-delimited reader starts a
        // new cell there). Only an immediately following trigger counts.
        #expect(LibraryExport.csvSafeText("x;=1+1;y") == "x;'=1+1;y")
        #expect(LibraryExport.csvSafeText("a\t@SUM") == "a\t'@SUM")
        #expect(LibraryExport.csvSafeText(";=x") == ";'=x" && LibraryExport.csvSafeText("a;+1;-2;@x") == "a;'+1;'-2;'@x")
        #expect(LibraryExport.csvSafeText("a\n=x") == "a\n'=x" && LibraryExport.csvSafeText("a\r\n=x") == "a\r\n'=x")
        #expect(LibraryExport.csvSafeText("a\r+x") == "a\r'+x")     // a CR mid-text is not at a segment start; the `+` after it is
        #expect(LibraryExport.csvSafeText("a\t\t=x") == "a\t'\t'=x")
        #expect(LibraryExport.csvSafeText(";;==") == ";;'==")
        #expect(LibraryExport.csvSafeText("a; =x") == "a; =x" && LibraryExport.csvSafeText("a;x=1") == "a;x=1")
        #expect(LibraryExport.csvSafeText("a;") == "a;" && LibraryExport.csvSafeText("a;b") == "a;b" && LibraryExport.csvSafeText(";") == ";")
        #expect(LibraryExport.csvSafeText("a;'=x") == "a;'=x")                    // already led by an apostrophe
        #expect(LibraryExport.csvSafeText("é;=é 日本;@語") == "é;'=é 日本;'@語")     // multi-byte text around the insert
        #expect(LibraryExport.csvSafeText("日本=x") == "日本=x")
        // The neutraliser runs before quoting: a trigger inside a quoted cell is still prefixed.
        #expect(RFC4180.field(LibraryExport.csvSafeText("=a,b")) == "\"'=a,b\"")
    }

    @Test func summaryDistinguishesCompleteIdentityAndOrganisationGaps() throws {
        // Complete: every identity known, organisation loaded.
        let complete = LibraryExport.build(Self.twoWithoutMalId(), formats: [.json], exportedAt: Self.now, timeZone: Self.berlin)
        #expect(complete.summary.isComplete && complete.summary.gaps.isEmpty)
        #expect(complete.summary.entryCount == 6 && complete.summary.identityUnavailable.isEmpty)
        let completeObject = try Self.jsonObject(complete.file("kuro-list-2026-11-09.json"))
        #expect(completeObject["complete"] as? Bool == true && (completeObject["gaps"] as? [String])?.isEmpty == true)
        // A real JSON boolean, not the number 1.
        #expect(String(decoding: try complete.file("kuro-list-2026-11-09.json").data, as: UTF8.self).contains("\"complete\" : true"))

        // Two keys without a catalogue row: identity gap, named with the fallback titles.
        var identity = Self.twoWithoutMalId()
        identity.catalogue[MediaKey(kind: .anime, id: 1)] = nil
        identity.catalogue[MediaKey(kind: .manga, id: 4)] = nil
        let identityBundle = LibraryExport.build(identity, formats: [.malXML, .json], exportedAt: Self.now, timeZone: Self.berlin)
        #expect(identityBundle.summary.gaps == [.identityUnavailable])
        #expect(identityBundle.summary.identityUnavailable.map(\.title) == ["Untitled anime #1", "Untitled manga #4"])
        // An unknown identity is not "no MAL id": it is a gap, not a second report.
        #expect(identityBundle.summary.withoutMalId.map(\.title).sorted() == ["Kaiju Diary", "Moon Ledger"])
        #expect(!identityBundle.summary.isComplete)

        // Organisation could not load.
        var organisation = Self.twoWithoutMalId()
        organisation.organisationUnavailable = true
        #expect(LibraryExport.build(organisation, formats: [.json], exportedAt: Self.now, timeZone: Self.berlin).summary.gaps == [.organisationUnavailable])

        // Both: JSON says incomplete and names the gaps, sorted.
        var both = identity
        both.organisationUnavailable = true
        let bothBundle = LibraryExport.build(both, formats: [.json], exportedAt: Self.now, timeZone: Self.berlin)
        #expect(bothBundle.summary.gaps == [.identityUnavailable, .organisationUnavailable])
        let bothObject = try Self.jsonObject(bothBundle.file("kuro-list-2026-11-09.json"))
        #expect(bothObject["complete"] as? Bool == false)
        #expect(bothObject["gaps"] as? [String] == ["identity_unavailable", "organisation_unavailable"])
        #expect(String(decoding: try bothBundle.file("kuro-list-2026-11-09.json").data, as: UTF8.self).contains("\"complete\" : false"))

        // MAL-format limits alone never make the export incomplete.
        let noMal = Self.entry(.anime, 1, .current, progress: 1, rating: nil, notes: "bell\u{07}", repeatCount: 0, started: "spring 2019", finished: nil)
        let limits = LibraryExport.build(
            LibraryExportInput(entries: [noMal, Self.entry(.manga, 2, .current, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)],
                               catalogue: [noMal.key: Self.row("Limits", mal: 5), MediaKey(kind: .manga, id: 2): Self.row("No MAL", mal: nil)]),
            formats: [.malXML, .json], exportedAt: Self.now, timeZone: Self.berlin
        )
        #expect(limits.summary.notesAdjusted.count == 1 && limits.summary.datesOmitted.count == 1 && limits.summary.withoutMalId.count == 1)
        #expect(limits.summary.isComplete && limits.summary.gaps.isEmpty)
        #expect(try Self.jsonObject(limits.file("kuro-list-2026-11-09.json"))["complete"] as? Bool == true)
    }

    @Test func buildProducesOnlyTheRequestedFormatsInAFixedOrder() throws {
        let input = Self.twoWithoutMalId()
        #expect(LibraryExport.build(input, formats: [], exportedAt: Self.now, timeZone: Self.berlin).files.isEmpty)
        #expect(LibraryExport.build(input, formats: [.json], exportedAt: Self.now, timeZone: Self.berlin).files.map(\.name) == ["kuro-list-2026-11-09.json"])
        #expect(LibraryExport.build(input, formats: [.csv], exportedAt: Self.now, timeZone: Self.berlin).files.map(\.name) == ["kuro-list-2026-11-09.csv"])
        // A medium with no MAL id at all gets no MAL file.
        let animeOnlyMissing = Self.entry(.anime, 1, .current, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let manga = Self.entry(.manga, 2, .current, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let mixed = LibraryExportInput(entries: [animeOnlyMissing, manga], catalogue: [animeOnlyMissing.key: Self.row("A", mal: nil), manga.key: Self.row("M", mal: 9)])
        #expect(LibraryExport.build(mixed, formats: [.malXML, .csv], exportedAt: Self.now, timeZone: Self.berlin).files.map(\.name) == ["kuro-manga-2026-11-09.xml", "kuro-list-2026-11-09.csv"])
        // An empty library still produces well-formed CSV and JSON.
        let empty = LibraryExport.build(LibraryExportInput(entries: [], catalogue: [:]), formats: [.csv, .json], exportedAt: Self.now, timeZone: Self.berlin)
        #expect(try Self.csvRows(empty.file("kuro-list-2026-11-09.csv")) == [LibraryExport.csvHeader])
        #expect(try Self.jsonEntries(empty.file("kuro-list-2026-11-09.json")).isEmpty)
        #expect(empty.summary.entryCount == 0 && empty.summary.isComplete)
    }

    @Test func fileNamesUseLocalDateAroundMidnight() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        #expect(LibraryExport.fileName(.csv, kind: nil, exportedAt: Date(timeIntervalSince1970: 1_794_265_170), timeZone: berlin) == "kuro-list-2026-11-09.csv") // 22:59:30Z = 23:59:30 local
        #expect(LibraryExport.fileName(.csv, kind: nil, exportedAt: Date(timeIntervalSince1970: 1_794_265_230), timeZone: berlin) == "kuro-list-2026-11-10.csv") // 23:00:30Z = 00:00:30 local
        #expect(LibraryExport.fileName(.json, kind: nil, exportedAt: Self.now, timeZone: berlin) == "kuro-list-2026-11-09.json")
        #expect(LibraryExport.fileName(.malXML, kind: .anime, exportedAt: Self.now, timeZone: berlin) == "kuro-anime-2026-11-09.xml")
        #expect(LibraryExport.fileName(.malXML, kind: .manga, part: 2, exportedAt: Self.now, timeZone: berlin) == "kuro-manga-2026-11-09-part2.xml")
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

    // MARK: - Tabular fixtures and readers

    static let unitId = UUID(uuidString: "6F1C2A4E-9B3D-4E8F-A1C7-5D2E8B9F0A13") ?? UUID()
    static let listId = UUID(uuidString: "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D") ?? UUID()
    static let formulaNotes = ["=HYPERLINK(\"http://x\")", "+1", "-2", "@SUM(A1)", "\tTab", "\rCR"]

    /// Six entries (anime 1, 2, 7; manga 3, 4, 9); "Kaiju Diary" (anime 7) and "Moon Ledger" (manga 9) have a
    /// catalogue row with no MAL id.
    static func twoWithoutMalId() -> LibraryExportInput {
        let rows: [(MediaKind, Int, String, Int?)] = [
            (.anime, 1, "Alpha", 101), (.anime, 2, "Beta", 102), (.anime, 7, "Kaiju Diary", nil),
            (.manga, 3, "Gamma", 203), (.manga, 4, "Delta", 204), (.manga, 9, "Moon Ledger", nil),
        ]
        var entries: [LibraryEntry] = []
        var catalogue: [MediaKey: ExportCatalogueRow] = [:]
        for (kind, id, title, mal) in rows {
            let entry = Self.entry(kind, id, .current, progress: id, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
            entries.append(entry)
            catalogue[entry.key] = Self.row(title, mal: mal)
        }
        return LibraryExportInput(entries: entries, catalogue: catalogue)
    }

    /// One anime entry with the given notes.
    static func single(notes: String) -> LibraryExportInput {
        let entry = Self.entry(.anime, 5, .current, progress: 2, rating: 8, notes: notes, repeatCount: 0, started: nil, finished: nil)
        return LibraryExportInput(entries: [entry], catalogue: [entry.key: Self.row("Single", mal: 55)])
    }

    /// Anime 42 with every identity, label, unit, tag, list and date shape; anime 43 with none of them.
    static func idsTagsListsInput() -> LibraryExportInput {
        let rich = LibraryEntry(
            key: MediaKey(kind: .anime, id: 42), rowId: 42, status: .completed, progress: 28,
            rating: UserRating(value: 9), notes: "great", verdict: .masterpiece,
            createdAt: Self.epoch, updatedAt: Self.epoch, progressLabel: "S2 E5", unitId: Self.unitId,
            sourceMetadata: LibrarySourceMetadata(
                repeatCount: 1, scoreRaw: "9", scoreScale: "POINT_10", startedRaw: "2019-04", finishedRaw: nil,
                isPrivate: false, customLists: ["Imported A"], hiddenFromStatusLists: true, sourceListOptions: "{\"a\":1}"
            )
        )
        let plain = LibraryEntry(
            key: MediaKey(kind: .anime, id: 43), rowId: 43, status: .planning, progress: 0,
            createdAt: Self.epoch, updatedAt: Self.epoch,
            sourceMetadata: LibrarySourceMetadata(repeatCount: 0)
        )
        return LibraryExportInput(
            entries: [rich, plain],
            catalogue: [rich.key: ExportCatalogueRow(title: "Frieren", anilistId: 9253, malId: 9253)],
            tagsByKey: [rich.key: ["slow burn", "rewatch"]],
            customLists: [ExportCustomList(id: Self.listId, name: "Comfort", createdAt: Date(timeIntervalSince1970: 1_790_812_800), items: [rich.key])]
        )
    }

    /// Anime 1, 2 and manga 3 in the library; anime 99 only in a list. "Comfort" holds [manga 3, anime 1,
    /// anime 99]; "Empty one" holds nothing.
    static func listsInput() -> LibraryExportInput {
        let one = Self.entry(.anime, 1, .current, progress: 1, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let two = Self.entry(.anime, 2, .current, progress: 2, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let three = Self.entry(.manga, 3, .current, progress: 3, rating: nil, notes: nil, repeatCount: 0, started: nil, finished: nil)
        let gone = MediaKey(kind: .anime, id: 99)
        return LibraryExportInput(
            entries: [one, two, three],
            catalogue: [
                one.key: Self.row("Alpha", mal: 1), two.key: Self.row("Beta", mal: 2),
                three.key: Self.row("Moon Ledger", mal: 3), gone: Self.row("Old Flame", mal: 99),
            ],
            customLists: [
                ExportCustomList(id: Self.listId, name: "Comfort", createdAt: Date(timeIntervalSince1970: 1_790_812_800), items: [three.key, one.key, gone]),
                ExportCustomList(id: UUID(), name: "Empty one", createdAt: Date(timeIntervalSince1970: 1_790_899_200), items: []),
            ]
        )
    }

    /// Six anime whose notes start with a formula trigger, then a seventh whose title is "=cmd" and whose notes
    /// only contain one.
    static func formulaInput() -> LibraryExportInput {
        var entries: [LibraryEntry] = []
        var catalogue: [MediaKey: ExportCatalogueRow] = [:]
        for (index, note) in Self.formulaNotes.enumerated() {
            let entry = Self.entry(.anime, index + 1, .current, progress: 1, rating: nil, notes: note, repeatCount: 0, started: nil, finished: nil)
            entries.append(entry)
            catalogue[entry.key] = Self.row("Title \(index + 1)", mal: 100 + index)
        }
        let seventh = Self.entry(.anime, 7, .current, progress: 1, rating: nil, notes: "a=b", repeatCount: 0, started: nil, finished: nil)
        entries.append(seventh)
        catalogue[seventh.key] = Self.row("=cmd", mal: 107)
        return LibraryExportInput(entries: entries, catalogue: catalogue)
    }

    /// What a reader sees that ignores quotes: lines split at CR / LF, cells split at `;` and at TAB. The
    /// segments that start with `=`, `+`, `-` or `@`, cut at the next comma for a short readable result. Empty
    /// means nothing a spreadsheet would read as a formula.
    static func naiveTriggerSegments(in text: String) -> [String] {
        var offenders: [String] = []
        let lines = text.split(omittingEmptySubsequences: false) { $0 == "\r" || $0 == "\n" || $0 == "\r\n" }
        for line in lines {
            for segment in line.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ";" || $0 == "\t" }) {
                if let first = segment.first, "=+-@".contains(first) {
                    offenders.append(String(segment.prefix { $0 != "," }))
                }
            }
        }
        return offenders
    }

    /// The text a reader that splits on `;`, TAB or a record end sees at the start of each segment, when that
    /// is a formula trigger. The scan toggles on every `"` (a delimiter inside quotes does not split); an
    /// empty result means no unquoted delimiter is followed by a trigger. Returns the offending segments.
    static func triggerSegments(in text: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var inQuotes = false
        func endSegment() {
            if let first = current.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) { segments.append(current) }
            current = ""
        }
        for scalar in text.unicodeScalars {
            if scalar == "\"" { inQuotes.toggle() }
            if !inQuotes, scalar == ";" || scalar == "\t" || scalar == "\r" || scalar == "\n" {
                endSegment()
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        endSegment()
        return segments.map { String($0.prefix { $0 != "," && $0 != "\r" }) }
    }

    /// A CSV record as header name to value.
    static func cells(_ row: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: zip(LibraryExport.csvHeader, row))
    }

    private struct CSVReadError: Error { let reason: String }

    /// A strict RFC 4180 reader for the tests: strips the BOM, requires CRLF record ends, honours quoted
    /// CR / LF / commas and doubled quotes, and rejects a quote inside an unquoted field.
    static func csvRows(_ file: LibraryExportFile) throws -> [[String]] {
        var bytes = Array(file.data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var rows: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        var inQuotes = false
        var afterQuote = false
        var index = 0
        func endField() {
            row.append(String(decoding: field, as: UTF8.self))
            field = []
            afterQuote = false
        }
        while index < bytes.count {
            let byte = bytes[index]
            if inQuotes {
                if byte == 0x22 {
                    if index + 1 < bytes.count, bytes[index + 1] == 0x22 {
                        field.append(0x22)
                        index += 1
                    } else {
                        inQuotes = false
                        afterQuote = true
                    }
                } else {
                    field.append(byte)
                }
            } else {
                switch byte {
                case 0x22:
                    guard field.isEmpty, !afterQuote else { throw CSVReadError(reason: "quote inside an unquoted field at \(index)") }
                    inQuotes = true
                case 0x2C:
                    endField()
                case 0x0D:
                    guard index + 1 < bytes.count, bytes[index + 1] == 0x0A else { throw CSVReadError(reason: "bare CR at \(index)") }
                    index += 1
                    endField()
                    rows.append(row)
                    row = []
                case 0x0A:
                    throw CSVReadError(reason: "bare LF outside quotes at \(index)")
                default:
                    guard !afterQuote else { throw CSVReadError(reason: "text after a closing quote at \(index)") }
                    field.append(byte)
                }
            }
            index += 1
        }
        guard !inQuotes else { throw CSVReadError(reason: "unterminated quote") }
        guard field.isEmpty, row.isEmpty, !afterQuote else { throw CSVReadError(reason: "last record has no CRLF") }
        return rows
    }

    static func jsonObject(_ file: LibraryExportFile) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: Any])
    }

    static func jsonEntries(_ file: LibraryExportFile) throws -> [[String: Any]] {
        try #require(try jsonObject(file)["entries"] as? [[String: Any]])
    }

    static func jsonLists(_ file: LibraryExportFile) throws -> [[String: Any]] {
        try #require(try jsonObject(file)["lists"] as? [[String: Any]])
    }
}

private struct MissingExportFile: Error { let name: String }

private extension LibraryExportBundle {
    /// The file called `name`; the test fails when the bundle has none.
    func file(_ name: String) throws -> LibraryExportFile {
        guard let found = files.first(where: { $0.name == name }) else { throw MissingExportFile(name: name) }
        return found
    }
}
