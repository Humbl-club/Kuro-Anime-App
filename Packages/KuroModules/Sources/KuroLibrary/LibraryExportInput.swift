import Foundation
import KuroCore

// MARK: - Export input

/// What the catalogue knows about one title, for an export: its display title and its AniList / MyAnimeList
/// ids. Read from the public `anime` / `manga` tables by the app and handed to the exporter as a value.
public struct ExportCatalogueRow: Equatable, Sendable {
    /// The English title, else the romaji title, else the native title, trimmed; `nil` when the catalogue
    /// row has none of them.
    public var title: String?
    /// The title's AniList id, when the catalogue has one.
    public var anilistId: Int?
    /// The title's MyAnimeList id, when the catalogue has one. `nil` means the title has no MAL id and
    /// cannot be written to a MAL file.
    public var malId: Int?

    /// Creates a catalogue row.
    public init(title: String?, anilistId: Int?, malId: Int?) {
        self.title = title
        self.anilistId = anilistId
        self.malId = malId
    }
}

/// One custom list as the custom-lists owner holds it (supplied by `CustomListsStore.exportLists()`).
public struct ExportCustomList: Equatable, Sendable {
    /// The list's stable id.
    public let id: UUID
    /// The list's name as the person typed it.
    public let name: String
    /// When the list was created.
    public let createdAt: Date
    /// Manual drag order (the custom-lists owner's slot order). Includes titles no longer in the library
    /// (list rows are keyed by title, not lifecycle, and survive library removal). May be empty.
    public let items: [MediaKey]

    /// Creates a custom list value.
    public init(id: UUID, name: String, createdAt: Date, items: [MediaKey]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.items = items
    }
}

/// Everything the exporter needs, gathered by the app before the (pure) build runs off the main actor.
public struct LibraryExportInput: Sendable {
    /// The account's library entries, as `LibraryStore` projects them.
    public var entries: [LibraryEntry]
    /// Missing key = identity unknown (lookup unavailable); present with `malId` nil = no MAL id.
    /// Covers library keys and list-item keys outside the library.
    public var catalogue: [MediaKey: ExportCatalogueRow]
    /// Tags per title, in the order the tags owner shows them.
    public var tagsByKey: [MediaKey: [String]] = [:]
    /// Lists in the order the custom-lists owner shows them; empty lists included. `inLibrary` and per-entry
    /// list names are derived by the exporter from `entries` (one source of truth), never taken from the
    /// custom-lists owner.
    public var customLists: [ExportCustomList] = []
    /// Set by the service when an organisation provider returned nil: JSON writes `tags` / `custom_lists` /
    /// `lists` as null instead of an empty collection.
    public var organisationUnavailable: Bool = false

    /// Creates an export input. Everything after `catalogue` defaults to "nothing".
    public init(
        entries: [LibraryEntry],
        catalogue: [MediaKey: ExportCatalogueRow],
        tagsByKey: [MediaKey: [String]] = [:],
        customLists: [ExportCustomList] = [],
        organisationUnavailable: Bool = false
    ) {
        self.entries = entries
        self.catalogue = catalogue
        self.tagsByKey = tagsByKey
        self.customLists = customLists
        self.organisationUnavailable = organisationUnavailable
    }
}

// MARK: - Export output

/// A file format the export can produce.
public enum LibraryExportFormat: String, CaseIterable, Sendable {
    /// A MyAnimeList XML export, one file per medium (more when a medium must be split into parts).
    case malXML = "mal_xml"
    /// One CSV file with a documented header.
    case csv
    /// One JSON file holding entries, tags and lists.
    case json
}

/// One finished export file, ready to be written to disk and shared.
public struct LibraryExportFile: Equatable, Sendable {
    /// The file name, without a directory.
    public let name: String
    /// The file's bytes.
    public let data: Data
    /// The file's MIME type.
    public let contentType: String

    /// Creates an export file value.
    public init(name: String, data: Data, contentType: String) {
        self.name = name
        self.data = data
        self.contentType = contentType
    }
}

/// One title named in an export report.
public struct ExportReportLine: Equatable, Sendable {
    /// The title's identity.
    public let key: MediaKey
    /// The catalogue title, or the fallback `"Untitled anime #<id>"` / `"Untitled manga #<id>"` when the
    /// catalogue has none (the wording the import review uses for an unresolved title).
    public let title: String

    /// Creates a report line.
    public init(key: MediaKey, title: String) {
        self.key = key
        self.title = title
    }
}

/// Why an export is not complete. A MAL-format limit (no MAL id, an adjusted note, an omitted date) is a
/// report, not a gap: CSV and JSON still hold those entries completely.
public enum LibraryExportGap: String, Hashable, Sendable, CaseIterable {
    /// Some library entries have no catalogue row (offline, or the lookup failed), so their ids are missing.
    case identityUnavailable = "identity_unavailable"
    /// Tags / custom lists could not be loaded.
    case organisationUnavailable = "organisation_unavailable"
}

/// What an export contains and what it could not contain, for the summary the person sees after preparing.
public struct LibraryExportSummary: Equatable, Sendable {
    /// Library entries exported.
    public var entryCount: Int
    /// Entries written to MAL XML, per medium.
    public var malExported: [MediaKind: Int]
    /// Entries with a catalogue row but no usable MAL id: none, or one outside `1...Int32.max`, the range the
    /// MAL writer and the importer accept (kept in CSV and JSON, listed here).
    public var withoutMalId: [ExportReportLine]
    /// Library entries with no catalogue row (offline / lookup failed). A list item outside the library
    /// without a row only exports title null and is not a gap.
    public var identityUnavailable: [ExportReportLine]
    /// MAL file only: entries whose notes had controls dropped or were omitted (> 16,384 bytes).
    public var notesAdjusted: [ExportReportLine]
    /// MAL file only: entries whose stored date could not be parsed and was therefore omitted.
    public var datesOmitted: [ExportReportLine]
    /// Tags / custom lists could not be loaded (offline, custom-lists store not loaded). Summary copy:
    /// "Tags and lists couldn't be loaded. Export again when you're online to include them." / "Tags und
    /// Listen konnten nicht geladen werden. Exportiere erneut, wenn du online bist, um sie mitzunehmen."
    public var organisationUnavailable: Bool = false
    /// MAL files per medium (1 = unsplit; > 1 = numbered parts).
    public var malParts: [MediaKind: Int] = [:]
    /// List items whose title is no longer in the library (JSON keeps them with `in_library` false; CSV has
    /// no row for them).
    public var listItemsOutsideLibrary: Int = 0

    /// The reasons the export is incomplete; empty = complete. Both can hold at once (offline: ids and
    /// organisation missing).
    public var gaps: Set<LibraryExportGap> {
        var result: Set<LibraryExportGap> = []
        if !identityUnavailable.isEmpty { result.insert(.identityUnavailable) }
        if organisationUnavailable { result.insert(.organisationUnavailable) }
        return result
    }

    /// `true` when `gaps` is empty.
    public var isComplete: Bool { gaps.isEmpty }

    /// Creates a summary. Public because the app's copy tests build summaries across the module boundary;
    /// fields added later default.
    public init(
        entryCount: Int,
        malExported: [MediaKind: Int],
        withoutMalId: [ExportReportLine],
        identityUnavailable: [ExportReportLine],
        notesAdjusted: [ExportReportLine],
        datesOmitted: [ExportReportLine],
        organisationUnavailable: Bool = false,
        malParts: [MediaKind: Int] = [:],
        listItemsOutsideLibrary: Int = 0
    ) {
        self.entryCount = entryCount
        self.malExported = malExported
        self.withoutMalId = withoutMalId
        self.identityUnavailable = identityUnavailable
        self.notesAdjusted = notesAdjusted
        self.datesOmitted = datesOmitted
        self.organisationUnavailable = organisationUnavailable
        self.malParts = malParts
        self.listItemsOutsideLibrary = listItemsOutsideLibrary
    }
}
