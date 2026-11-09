import Foundation
import KuroCore

/// The finished export: its files and what they do and do not contain.
public struct LibraryExportBundle: Equatable, Sendable {
    /// The files to write and share, in a fixed order: MAL anime (or its parts), MAL manga (or its parts), the
    /// CSV, the JSON. Only the requested formats are present.
    public let files: [LibraryExportFile]
    /// What the export contains and what it could not contain.
    public let summary: LibraryExportSummary

    /// Creates a bundle.
    public init(files: [LibraryExportFile], summary: LibraryExportSummary) {
        self.files = files
        self.summary = summary
    }
}

/// Builds a person's library export from values gathered by the app. Pure: no I/O, no clock, no locale.
public enum LibraryExport {
    /// Builds the files for `formats` and the summary of what they contain.
    ///
    /// - MAL XML: one file per medium that has at least one entry with a usable MAL id (see
    ///   `malId(for:in:)`), or numbered parts when one document would exceed what the importer accepts (see
    ///   `malXML(_:kind:summary:)`). A medium with none gets no file.
    /// - CSV: one file with both media and every entry (see `csvHeader`).
    /// - JSON: one file with every entry and every list.
    ///
    /// The summary is filled once, here. `identityUnavailable` (a library entry with no catalogue row),
    /// `withoutMalId` (a catalogue row without a usable MAL id) and `listItemsOutsideLibrary` describe the
    /// data and do not depend on the formats asked for; `malExported`, `malParts`, `notesAdjusted` and
    /// `datesOmitted` describe the MAL files and are filled only when `.malXML` is requested. A requested format
    /// that could not be produced is listed in `failedFormats`.
    ///
    /// - Parameters:
    ///   - input: The library, catalogue identities and organisation to export.
    ///   - formats: The formats to produce.
    ///   - exportedAt: The export moment: the file names' date (in `timeZone`) and the JSON `exported_at`.
    ///   - timeZone: The zone the file-name date is read in.
    public static func build(
        _ input: LibraryExportInput,
        formats: Set<LibraryExportFormat>,
        exportedAt: Date,
        timeZone: TimeZone
    ) -> LibraryExportBundle {
        build(input, formats: formats, exportedAt: exportedAt, timeZone: timeZone, jsonSerialiser: serialiseJSON)
    }

    /// `build` with the JSON serialiser injectable, so a test can make serialisation fail. A requested format
    /// that could not be produced is recorded in `summary.failedFormats` and its file is absent.
    static func build(
        _ input: LibraryExportInput,
        formats: Set<LibraryExportFormat>,
        exportedAt: Date,
        timeZone: TimeZone,
        jsonSerialiser: (Any) throws -> Data
    ) -> LibraryExportBundle {
        var summary = LibraryExportSummary(
            entryCount: input.entries.count, malExported: [:], withoutMalId: [], identityUnavailable: [],
            notesAdjusted: [], datesOmitted: [], organisationUnavailable: input.organisationUnavailable
        )
        describeIdentity(of: input, in: &summary)

        var files: [LibraryExportFile] = []
        if formats.contains(.malXML) {
            for kind in [MediaKind.anime, .manga] {
                let parts = malXML(input, kind: kind, summary: &summary)
                for (index, data) in parts.enumerated() {
                    let name = fileName(
                        .malXML, kind: kind, part: parts.count > 1 ? index + 1 : nil,
                        exportedAt: exportedAt, timeZone: timeZone
                    )
                    files.append(LibraryExportFile(name: name, data: data, contentType: "application/xml"))
                }
            }
        }
        if formats.contains(.csv) {
            files.append(LibraryExportFile(
                name: fileName(.csv, kind: nil, exportedAt: exportedAt, timeZone: timeZone),
                data: csv(input), contentType: "text/csv"
            ))
        }
        if formats.contains(.json) {
            if let data = json(input, summary: summary, exportedAt: exportedAt, serialise: jsonSerialiser) {
                files.append(LibraryExportFile(
                    name: fileName(.json, kind: nil, exportedAt: exportedAt, timeZone: timeZone),
                    data: data, contentType: "application/json"
                ))
            } else {
                summary.failedFormats.append(.json)
            }
        }
        return LibraryExportBundle(files: files, summary: summary)
    }

    /// The file name for one export file: `kuro-list-YYYY-MM-DD.csv` / `.json`, `kuro-anime-YYYY-MM-DD.xml`,
    /// `kuro-manga-YYYY-MM-DD.xml`; a split MAL file adds `-part<N>` (`kuro-anime-YYYY-MM-DD-part1.xml`).
    /// The date is `exportedAt` in `timeZone`, read in the Gregorian calendar.
    public static func fileName(
        _ format: LibraryExportFormat,
        kind: MediaKind?,
        part: Int? = nil,
        exportedAt: Date,
        timeZone: TimeZone
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let day = calendar.dateComponents([.year, .month, .day], from: exportedAt)
        let date = "\(padded(day.year ?? 1970, width: 4))-\(padded(day.month ?? 1, width: 2))-\(padded(day.day ?? 1, width: 2))"
        switch format {
        case .csv: return "kuro-list-\(date).csv"
        case .json: return "kuro-list-\(date).json"
        case .malXML:
            let suffix = part.map { "-part\($0)" } ?? ""
            return "kuro-\(kind?.rawValue ?? "list")-\(date)\(suffix).xml"
        }
    }

    /// The MAL id the MAL writer can use for `key`, or `nil`.
    ///
    /// `nil` when the catalogue has no row, the row has no MAL id, or the id is outside `1...Int32.max` (the
    /// range the importer accepts). The MAL writer and the summary's `withoutMalId` both decide through this
    /// function, so a title is always either written to a MAL file or reported, never neither.
    static func malId(for key: MediaKey, in catalogue: [MediaKey: ExportCatalogueRow]) -> Int? {
        guard let malId = catalogue[key]?.malId, (1...Int(Int32.max)).contains(malId) else { return nil }
        return malId
    }

    /// The catalogue title for `key`, trimmed, or `nil` when the catalogue has no row or no title.
    static func catalogueTitle(for key: MediaKey, in catalogue: [MediaKey: ExportCatalogueRow]) -> String? {
        guard let title = catalogue[key]?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }
        return title
    }

    /// The title an export shows for `key`: the catalogue title, else `"Untitled anime #<id>"` /
    /// `"Untitled manga #<id>"` (the wording the import review uses for an unresolved title).
    static func title(for key: MediaKey, in catalogue: [MediaKey: ExportCatalogueRow]) -> String {
        if let title = catalogueTitle(for: key, in: catalogue) { return title }
        switch key.kind {
        case .anime: return "Untitled anime #\(key.id)"
        case .manga: return "Untitled manga #\(key.id)"
        }
    }

    /// The entries in the order CSV and JSON list them: anime before manga, then by Kuro id.
    static func sortedEntries(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.key.kind != rhs.key.kind { return lhs.key.kind == .anime }
            return lhs.key.id < rhs.key.id
        }
    }

    /// Fills the summary fields that describe the input rather than a format: entries whose identity could
    /// not be looked up, entries the catalogue knows but that have no usable MAL id, and list items whose
    /// title is no longer in the library. Reports are in CSV order.
    private static func describeIdentity(of input: LibraryExportInput, in summary: inout LibraryExportSummary) {
        for entry in sortedEntries(input.entries) {
            if input.catalogue[entry.key] == nil {
                summary.identityUnavailable.append(reportLine(entry.key, in: input.catalogue))
            } else if malId(for: entry.key, in: input.catalogue) == nil {
                summary.withoutMalId.append(reportLine(entry.key, in: input.catalogue))
            }
        }
        // Lists are exported only when the organisation loaded; counted per list item.
        if !input.organisationUnavailable {
            let libraryKeys = Set(input.entries.map(\.key))
            summary.listItemsOutsideLibrary = input.customLists.reduce(0) { total, list in
                total + list.items.filter { !libraryKeys.contains($0) }.count
            }
        }
    }

    /// A summary line for `key`, titled by `title(for:in:)`.
    static func reportLine(_ key: MediaKey, in catalogue: [MediaKey: ExportCatalogueRow]) -> ExportReportLine {
        ExportReportLine(key: key, title: title(for: key, in: catalogue))
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
