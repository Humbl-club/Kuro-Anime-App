import Foundation
import KuroCore

/// The finished export: its files and what they do and do not contain.
public struct LibraryExportBundle: Equatable, Sendable {
    /// The files to write and share, in the order they were built (MAL anime, then MAL manga).
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
    /// Builds the files for `formats`.
    ///
    /// MAL XML: one file per medium that has at least one entry with a MAL id, or numbered parts when one
    /// document would exceed what the importer accepts (see `malXML(_:kind:summary:)`).
    ///
    /// - Parameters:
    ///   - input: The library, catalogue identities and organisation to export.
    ///   - formats: The formats to produce.
    ///   - exportedAt: The export moment, used for the file names.
    ///   - timeZone: The zone the file-name date is read in.
    public static func build(
        _ input: LibraryExportInput,
        formats: Set<LibraryExportFormat>,
        exportedAt: Date,
        timeZone: TimeZone
    ) -> LibraryExportBundle {
        var summary = LibraryExportSummary(
            entryCount: input.entries.count, malExported: [:], withoutMalId: [], identityUnavailable: [],
            notesAdjusted: [], datesOmitted: [], organisationUnavailable: input.organisationUnavailable
        )
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

    /// The title an export shows for `key`: the catalogue title, else `"Untitled anime #<id>"` /
    /// `"Untitled manga #<id>"` (the wording the import review uses for an unresolved title).
    static func title(for key: MediaKey, in catalogue: [MediaKey: ExportCatalogueRow]) -> String {
        if let title = catalogue[key]?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        switch key.kind {
        case .anime: return "Untitled anime #\(key.id)"
        case .manga: return "Untitled manga #\(key.id)"
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
