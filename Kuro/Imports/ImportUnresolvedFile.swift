import CoreTransferable
import Foundation
import KuroLibrary
import UniformTypeIdentifiers

/// W4: the titles an import could not place, as a shareable CSV (nothing is written to disk by the
/// app; the share sheet receives the data). 18+ titles the catalogue does not list are included,
/// with their own reason, so they are never lost or reported as failures.
struct ImportUnresolvedFile: Transferable, Equatable {
    /// Unmatched, conflict, invalid and source-changed items (18+ included); applied rows are not.
    let items: [ImportReviewItem]
    let fileName: String

    nonisolated static let header = ["medium", "external_id", "title", "reason"]

    /// Items that belong in the file.
    nonisolated static func isUnresolved(_ item: ImportReviewItem) -> Bool {
        [.unmatched, .conflict, .invalid, .sourceChanged].contains(item.disposition)
    }

    nonisolated static func reason(_ item: ImportReviewItem) -> String {
        if item.isAdultNotListed { return "adult_not_listed" }
        switch item.disposition {
        case .conflict: return "conflict"
        case .invalid: return "invalid"
        case .sourceChanged: return "source_changed"
        default: return "not_in_catalogue"
        }
    }

    /// `kuro-import-unresolved-YYYY-MM-DD.csv` in the given (default: device) time zone.
    nonisolated static func fileName(on date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 1970, month = parts.month ?? 1, day = parts.day ?? 1
        let pad: (Int) -> String = { $0 < 10 ? "0\($0)" : "\($0)" }
        return "kuro-import-unresolved-\(year)-\(pad(month))-\(pad(day)).csv"
    }

    /// UTF-8 BOM and RFC 4180 rows, sorted by medium then external id. Titles are source text and
    /// are written exactly as read (the importer's own labels carry no formula semantics here, but a
    /// leading formula character is neutralised for spreadsheet safety).
    nonisolated func csv() -> Data {
        var text = RFC4180.row(Self.header)
        let rows = items.filter(Self.isUnresolved).sorted {
            ($0.medium, $0.externalId) < ($1.medium, $1.externalId)
        }
        for item in rows {
            text += RFC4180.row([item.medium, item.externalId, Self.spreadsheetSafe(item.title), Self.reason(item)])
        }
        return Data("\u{FEFF}".utf8) + Data(text.utf8)
    }

    /// A cell that starts with a formula trigger gets a leading apostrophe.
    private nonisolated static func spreadsheetSafe(_ value: String) -> String {
        let triggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
        guard let first = value.unicodeScalars.first, triggers.contains(first) else { return value }
        return "'" + value
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            file.csv()
        }
        .suggestedFileName { $0.fileName }
    }
}
