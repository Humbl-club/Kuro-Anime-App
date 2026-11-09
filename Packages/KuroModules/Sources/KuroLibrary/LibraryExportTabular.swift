import Foundation
import KuroCore

// MARK: - CSV

// The CSV file (written by `LibraryExport.csv(_:)`):
//
// - UTF-8 with a byte order mark (EF BB BF) so spreadsheet apps read umlauts correctly.
// - RFC 4180 records: CRLF line ends, a cell with a comma, quote, CR or LF in double quotes (`RFC4180.field`).
//   This file additionally quotes every cell that holds a semicolon or a TAB (`csvField(_:)`): a spreadsheet
//   in a semicolon locale (German Excel) or a tab-delimited reader splits an unquoted cell at those
//   characters, and the second part would start with a formula trigger that `csvSafeText` never saw.
// - One header row, exactly `LibraryExport.csvHeader` (20 columns), then one row per library entry: anime
//   before manga, then by Kuro id. List items whose title left the library have no row (they are in the JSON
//   file and counted in the summary).
// - An empty cell means "nothing stored" or "not known" (no catalogue row, no source metadata, no unit): the
//   file never writes 0 or a made-up value for a value it does not have.
// - `status` is `ListStatus.rawValue`; `verdict` is `Verdict.rawValue`; `rating` is 1...10; timestamps are
//   ISO 8601 in UTC (`2026-11-09T10:59:30Z`); dates are `PartialDate.raw` when the stored text is a date and
//   the stored text otherwise; `tags` and `custom_lists` join their values with "; ".
// - `progress_label` and `unit_id` are the entry's tracking-unit identity exactly as stored, never inferred.
//
// Formula neutralisation: spreadsheet apps run a cell that starts with `=`, `+`, `-`, `@`, TAB or CR as a
// formula. Every cell goes through `LibraryExport.csvSafeText(_:)` before `csvField(_:)`, which writes such a
// cell with a leading `'`. Consequence, documented: a note that starts with one of those characters
// reads back from the CSV with one extra leading `'`. The JSON file keeps the exact text and is the lossless
// format.

extension LibraryExport {
    /// The CSV header, in column order (20 columns).
    public static let csvHeader: [String] = [
        "kind", "kuro_id", "anilist_id", "mal_id", "title", "status", "progress", "progress_label", "unit_id",
        "volumes_progress", "rating", "verdict", "repeat_count", "started_on", "finished_on", "notes", "tags",
        "custom_lists", "created_at", "updated_at",
    ]

    /// CSV cell text with spreadsheet formula triggers neutralised: a value whose first character is `=`, `+`,
    /// `-`, `@`, TAB (U+0009) or CR (U+000D) gets a leading `'` (OWASP CSV injection guidance).
    ///
    /// Applied to every CSV cell, before `RFC4180.field` quoting. JSON never uses it. The first character is
    /// read as a byte, not a `Character`: `"\r\n"` is one `Character` and must still count as a leading CR.
    public static func csvSafeText(_ value: String) -> String {
        guard let first = value.utf8.first else { return value }
        switch first {
        case 0x3D, 0x2B, 0x2D, 0x40, 0x09, 0x0D: return "'" + value
        default: return value
        }
    }

    /// The CSV file's bytes: BOM, header, one row per entry.
    static func csv(_ input: LibraryExportInput) -> Data {
        let organisation = ExportOrganisation(input)
        var text = csvRecord(csvHeader)
        for entry in sortedEntries(input.entries) {
            text += csvRecord(csvCells(for: entry, input: input, organisation: organisation))
        }
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: text.utf8)
        return data
    }

    /// One CSV record: every cell neutralised (`csvSafeText`), then encoded (`csvField`), joined by commas and
    /// ended by CRLF.
    private static func csvRecord(_ cells: [String]) -> String {
        cells.map { csvField(csvSafeText($0)) }.joined(separator: ",") + "\r\n"
    }

    /// One CSV cell: `RFC4180.field`, plus double quotes around a cell that holds a semicolon or a TAB.
    ///
    /// Kept here and not in `RFC4180.field`: that type is the plain RFC 4180 transport encoding (the unresolved
    /// -titles file of W4 shares it and its documented behaviour), while the semicolon and TAB rule is a
    /// spreadsheet-safety rule of this export. When `RFC4180.field` returns its input unchanged the value holds
    /// no quote, comma, CR or LF, so wrapping it in quotes needs no escaping.
    static func csvField(_ value: String) -> String {
        let encoded = RFC4180.field(value)
        guard encoded == value, value.utf8.contains(where: { $0 == 0x3B || $0 == 0x09 }) else { return encoded }
        return "\"" + value + "\""
    }

    private static func csvCells(for entry: LibraryEntry, input: LibraryExportInput, organisation: ExportOrganisation) -> [String] {
        let key = entry.key
        let row = input.catalogue[key]
        let metadata = entry.sourceMetadata
        var cells: [String] = []
        cells.reserveCapacity(csvHeader.count)
        cells.append(key.kind.rawValue)
        cells.append(String(key.id))
        cells.append(row?.anilistId.map(String.init) ?? "")
        cells.append(row?.malId.map(String.init) ?? "")
        cells.append(catalogueTitle(for: key, in: input.catalogue) ?? "")
        cells.append(entry.status.rawValue)
        cells.append(String(entry.progress))
        cells.append(entry.progressLabel ?? "")
        cells.append(entry.unitId?.uuidString.lowercased() ?? "")
        cells.append(metadata?.volumesProgress.map(String.init) ?? "")
        cells.append(entry.rating.map { String($0.value) } ?? "")
        cells.append(entry.verdict?.rawValue ?? "")
        // Known-versus-unknown: with no source metadata the server values were not read; the cell is empty.
        cells.append(entry.datesKnown ? String(entry.repeatCount) : "")
        cells.append(ExportDate.csvText(metadata?.startedRaw))
        cells.append(ExportDate.csvText(metadata?.finishedRaw))
        cells.append(entry.notes ?? "")
        cells.append(organisation.tags(for: key)?.joined(separator: "; ") ?? "")
        cells.append(organisation.listNames(for: key)?.joined(separator: "; ") ?? "")
        cells.append(ExportTimestamp.string(entry.createdAt))
        cells.append(ExportTimestamp.string(entry.updatedAt))
        return cells
    }
}

// MARK: - JSON

// The JSON file (written by `LibraryExport.json(_:summary:exportedAt:)`), `JSONSerialization` with sorted keys,
// pretty printing and unescaped slashes:
//
//   { "format": "kuro-library-export", "version": 1, "exported_at": "<ISO 8601 UTC>",
//     "complete": Bool, "gaps": ["identity_unavailable" | "organisation_unavailable", ...],
//     "entries": [ ... ], "lists": [ ... ] | null }
//
// Text is exact (no neutralisation). Unknown values are `null`, never 0 and never "":
// - `anilist_id`, `mal_id`, `title` are null without a catalogue row; `unit_id` and `progress_label` are null
//   when the entry has none (never inferred);
// - `repeat_count`, `source` and the two dates are null when the server values were not read;
// - `started_on` / `finished_on` are `{"raw": <stored text, verbatim>, "precision": "year" | "month" | "day" |
//   null}` (precision null: the stored text is not a date), or null for no stored date (an empty stored
//   string is no date);
// - `tags` and `custom_lists` (list names) are null when the organisation could not be loaded, else arrays;
// - `lists` is null (not `[]`) when the organisation could not be loaded, else the lists in manual order,
//   empty lists included, each with its items in manual order (`position` is the 1-based ordinal).

extension LibraryExport {
    /// The JSON file's bytes, or `nil` if serialisation fails. `build` records a `nil` in
    /// `LibraryExportSummary.failedFormats`, so a requested file is never silently missing.
    ///
    /// The object graph is built from JSON types only (strings, integers, booleans, `NSNull`, arrays and
    /// dictionaries) and checked with `JSONSerialization.isValidJSONObject` first, so neither step can fail
    /// for real data; `serialise` is a parameter so a test can make the second step fail.
    static func json(
        _ input: LibraryExportInput,
        summary: LibraryExportSummary,
        exportedAt: Date,
        serialise: (Any) throws -> Data
    ) -> Data? {
        let organisation = ExportOrganisation(input)
        let libraryKeys = Set(input.entries.map(\.key))

        var entries: [[String: Any]] = []
        entries.reserveCapacity(input.entries.count)
        for entry in sortedEntries(input.entries) {
            entries.append(jsonEntry(entry, input: input, organisation: organisation))
        }

        var root: [String: Any] = [:]
        root["format"] = "kuro-library-export"
        root["version"] = 1
        root["exported_at"] = ExportTimestamp.string(exportedAt)
        root["complete"] = summary.isComplete
        root["gaps"] = summary.gaps.map(\.rawValue).sorted()
        root["entries"] = entries
        if organisation.isAvailable {
            root["lists"] = input.customLists.map { jsonList($0, libraryKeys: libraryKeys, catalogue: input.catalogue) }
        } else {
            root["lists"] = NSNull()
        }

        // Unreachable by construction (see above); a DEBUG build stops here so the bug is found, a release
        // build reports the failed format instead of crashing an export.
        guard JSONSerialization.isValidJSONObject(root) else {
            assertionFailure("The library export built a value JSON cannot hold.")
            return nil
        }
        return try? serialise(root)
    }

    /// The production JSON serialiser: pretty printed, sorted keys, slashes unescaped.
    static func serialiseJSON(_ root: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func jsonEntry(_ entry: LibraryEntry, input: LibraryExportInput, organisation: ExportOrganisation) -> [String: Any] {
        let key = entry.key
        let row = input.catalogue[key]
        let metadata = entry.sourceMetadata
        var object: [String: Any] = [:]
        object["kind"] = key.kind.rawValue
        object["kuro_id"] = key.id
        object["anilist_id"] = jsonValue(row?.anilistId)
        object["mal_id"] = jsonValue(row?.malId)
        object["title"] = jsonValue(catalogueTitle(for: key, in: input.catalogue))
        object["status"] = entry.status.rawValue
        object["progress"] = entry.progress
        object["progress_label"] = jsonValue(entry.progressLabel)
        object["unit_id"] = jsonValue(entry.unitId?.uuidString.lowercased())
        object["volumes_progress"] = jsonValue(metadata?.volumesProgress)
        object["rating"] = jsonValue(entry.rating?.value)
        object["verdict"] = jsonValue(entry.verdict?.rawValue)
        object["notes"] = jsonValue(entry.notes)
        object["repeat_count"] = jsonValue(entry.datesKnown ? entry.repeatCount : nil)
        object["started_on"] = ExportDate.json(metadata?.startedRaw)
        object["finished_on"] = ExportDate.json(metadata?.finishedRaw)
        object["tags"] = jsonValue(organisation.tags(for: key))
        object["custom_lists"] = jsonValue(organisation.listNames(for: key))
        if entry.datesKnown, let metadata {
            var source: [String: Any] = [:]
            source["score_raw"] = jsonValue(metadata.scoreRaw)
            source["score_scale"] = jsonValue(metadata.scoreScale)
            source["private"] = jsonValue(metadata.isPrivate)
            source["imported_custom_lists"] = jsonValue(metadata.customLists)
            source["hidden_from_status_lists"] = jsonValue(metadata.hiddenFromStatusLists)
            source["list_options"] = jsonValue(metadata.sourceListOptions)
            object["source"] = source
        } else {
            object["source"] = NSNull()
        }
        object["created_at"] = ExportTimestamp.string(entry.createdAt)
        object["updated_at"] = ExportTimestamp.string(entry.updatedAt)
        return object
    }

    private static func jsonList(_ list: ExportCustomList, libraryKeys: Set<MediaKey>, catalogue: [MediaKey: ExportCatalogueRow]) -> [String: Any] {
        var items: [[String: Any]] = []
        items.reserveCapacity(list.items.count)
        for (index, key) in list.items.enumerated() {
            var item: [String: Any] = [:]
            item["medium"] = key.kind.rawValue
            item["media_id"] = key.id
            item["position"] = index + 1
            item["in_library"] = libraryKeys.contains(key)
            item["title"] = jsonValue(catalogueTitle(for: key, in: catalogue))
            items.append(item)
        }
        var object: [String: Any] = [:]
        object["id"] = list.id.uuidString.lowercased()
        object["name"] = list.name
        object["created_at"] = ExportTimestamp.string(list.createdAt)
        object["items"] = items
        return object
    }

    /// `value`, or JSON `null` for `nil`.
    private static func jsonValue<T>(_ value: T?) -> Any {
        guard let value else { return NSNull() }
        return value
    }
}

// MARK: - Shared pieces

/// Tags and list membership as CSV and JSON write them. When the organisation could not be loaded
/// (`organisationUnavailable`) every lookup is `nil`: JSON writes null, CSV an empty cell, never an empty
/// collection that would read as "this title has no tags".
private struct ExportOrganisation {
    /// `false` when tags and lists could not be loaded.
    let isAvailable: Bool
    private let tagsByKey: [MediaKey: [String]]
    private let listNamesByKey: [MediaKey: [String]]

    init(_ input: LibraryExportInput) {
        let available = !input.organisationUnavailable
        var names: [MediaKey: [String]] = [:]
        if available {
            for list in input.customLists {
                // A title is named once per list, however often the list holds it.
                var seen = Set<MediaKey>()
                for key in list.items where seen.insert(key).inserted {
                    names[key, default: []].append(list.name)
                }
            }
        }
        isAvailable = available
        tagsByKey = available ? input.tagsByKey : [:]
        listNamesByKey = names
    }

    /// The title's tags in the tags owner's order; `nil` when the organisation is unavailable.
    func tags(for key: MediaKey) -> [String]? {
        isAvailable ? (tagsByKey[key] ?? []) : nil
    }

    /// The names of the lists that hold the title, in list order; `nil` when the organisation is unavailable.
    func listNames(for key: MediaKey) -> [String]? {
        isAvailable ? (listNamesByKey[key] ?? []) : nil
    }
}

/// A stored `started_raw` / `finished_raw` text as the CSV and JSON files write it.
private enum ExportDate {
    /// CSV: the canonical `PartialDate.raw` when the stored text is a date, else the stored text; empty for no
    /// date.
    static func csvText(_ raw: String?) -> String {
        guard let raw, !isBlank(raw) else { return "" }
        return PartialDate(raw: raw)?.raw ?? raw
    }

    /// JSON: `{"raw": <stored text>, "precision": ...}` or null for no stored date.
    static func json(_ raw: String?) -> Any {
        guard let raw, !isBlank(raw) else { return NSNull() }
        var object: [String: Any] = ["raw": raw]
        switch PartialDate(raw: raw)?.precision {
        case .year?: object["precision"] = "year"
        case .month?: object["precision"] = "month"
        case .day?: object["precision"] = "day"
        case nil: object["precision"] = NSNull()
        }
        return object
    }

    private static func isBlank(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// ISO 8601 in UTC (`2026-11-09T10:59:30Z`, whole seconds) by integer calendar arithmetic: no `DateFormatter`,
/// no locale, no time zone, no shared formatter state.
private enum ExportTimestamp {
    /// 0001-01-01T00:00:00Z and 9999-12-31T23:59:59Z; a `Date` outside them is clamped.
    private static let earliest: Double = -62_135_596_800
    private static let latest: Double = 253_402_300_799

    static func string(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        let seconds = interval.isFinite ? Int(min(max(interval.rounded(.down), earliest), latest)) : 0
        var days = seconds / 86_400
        var rest = seconds % 86_400
        if rest < 0 {
            days -= 1
            rest += 86_400
        }
        let (year, month, day) = civil(fromDaysSinceEpoch: days)
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(rest / 3_600, 2)):\(pad(rest % 3_600 / 60, 2)):\(pad(rest % 60, 2))Z"
    }

    /// Proleptic Gregorian year, month and day for a day count from 1970-01-01 (Howard Hinnant's
    /// `civil_from_days`).
    private static func civil(fromDaysSinceEpoch days: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
