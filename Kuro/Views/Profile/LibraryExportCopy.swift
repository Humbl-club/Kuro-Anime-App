import Foundation
import KuroCore
import KuroLibrary

// MARK: - Library export copy (W2, EN/DE)
// Every string of Profile > "Export your list" and of its tool sheet. Pure: `german` is explicit so
// tests pin both languages. Numbers use the reader's locale ("1,234" / "1.234"). A line is only
// returned for something the person should know: a complete export returns no summary lines.

nonisolated enum LibraryExportCopy {
    // MARK: Profile row

    static func rowTitle(german: Bool) -> String { german ? "Liste exportieren" : "Export your list" }

    static func rowSubtitle(german: Bool) -> String {
        german ? "CSV, MyAnimeList oder JSON. Kostenlos." : "CSV, MyAnimeList or JSON. Free."
    }

    // MARK: Sheet

    static func heading(german: Bool) -> String { german ? "Liste exportieren." : "Export your list." }

    static func intro(german: Bool) -> String {
        german
            ? "Deine Liste als Datei zum Behalten. Sie wird auf deinem Gerät erstellt und geht nur dorthin, wohin du sie teilst."
            : "Your list as a file you keep. It's made on your device and goes only where you share it."
    }

    static func formatLabel(german: Bool) -> String { "Format" }

    static func formatTitle(_ format: LibraryExportFormat, german: Bool) -> String {
        switch format {
        case .csv: return german ? "Tabelle (CSV)" : "Spreadsheet (CSV)"
        case .malXML: return "MyAnimeList (XML)"
        case .json: return german ? "Alles (JSON)" : "Everything (JSON)"
        }
    }

    static func formatSubtitle(_ format: LibraryExportFormat, german: Bool) -> String {
        switch format {
        case .csv:
            return german ? "Eine Datei für Excel, Numbers oder Google Tabellen." : "One file for Excel, Numbers or Google Sheets."
        case .malXML:
            return german ? "Zum Import in MyAnimeList. Nur Titel mit MyAnimeList-ID." : "To import into MyAnimeList. Titles with a MyAnimeList id only."
        case .json:
            return german ? "Alles: IDs, Notizen, Tags und Listen. Für Sicherungen." : "Everything: ids, notes, tags and lists. For backups."
        }
    }

    static func prepareTitle(german: Bool) -> String { german ? "Datei vorbereiten" : "Prepare file" }

    static func prepareAgainTitle(german: Bool) -> String { german ? "Erneut vorbereiten" : "Prepare again" }

    static func shareTitle(german: Bool) -> String { german ? "Teilen" : "Share" }

    static func closeLabel(german: Bool) -> String { german ? "Schließen" : "Close" }

    /// "Your file is ready." / "Your 2 files are ready."
    static func readyNote(fileCount: Int, german: Bool) -> String {
        if fileCount == 1 { return german ? "Deine Datei ist bereit." : "Your file is ready." }
        let n = number(fileCount, german: german)
        return german ? "Deine \(n) Dateien sind bereit." : "Your \(n) files are ready."
    }

    /// Shown when the request built no file (for example a MyAnimeList file while no title has a MyAnimeList id).
    static func emptyResultNote(german: Bool) -> String {
        german ? "In diesem Format gibt es nichts zu exportieren." : "Nothing to export in this format."
    }

    /// The footnote under a CSV result (not a summary line: a complete CSV export has no lines).
    static func csvSafetyNote(german: Bool) -> String {
        german
            ? "CSV wird für Tabellenprogramme entschärft; JSON enthält Notizen unverändert."
            : "CSV is made safe for spreadsheets; JSON keeps notes exactly."
    }

    static func offlineNote(german: Bool) -> String {
        german
            ? "Du bist offline. Deine Liste wird exportiert; manche Katalog-IDs können fehlen."
            : "You're offline. Your list exports; some catalogue ids may be missing."
    }

    // MARK: Failure

    static func failure(_ failure: LibraryExportFailure, german: Bool) -> String {
        switch failure {
        case .disabled:
            return german ? "Export ist noch nicht verfügbar." : "Export isn't available yet."
        case .notLoaded:
            return german ? "Deine Liste wird noch geladen. Versuch es gleich noch einmal." : "Your list is still loading. Try again in a moment."
        case .signedOut:
            return german ? "Melde dich an, um deine Liste zu exportieren." : "Sign in to export your list."
        case .writeFailed:
            return german ? "Die Datei konnte nicht gespeichert werden. Versuch es noch einmal." : "The file couldn't be saved. Try again."
        case .buildFailed:
            return german
                ? "Die Datei konnte nicht erstellt werden. Versuch es noch einmal oder wähle ein anderes Format."
                : "The file couldn't be created. Try again, or choose another format."
        }
    }

    // MARK: Summary

    /// What the export lacks or changed, one sentence per fact, most important first: ids that could not be
    /// looked up, tags and lists (CSV and JSON file), tracking details, titles without a MyAnimeList id
    /// (MAL file), a medium split into several files (MAL file), list entries that left the library (CSV and
    /// MAL file). Empty for a complete export with nothing to report.
    static func summaryLines(_ summary: LibraryExportSummary, format: LibraryExportFormat, german: Bool) -> [String] {
        var lines: [String] = []

        let unavailable = summary.identityUnavailable.count
        if unavailable > 0 {
            let n = number(unavailable, german: german)
            if german {
                lines.append(unavailable == 1
                    ? "\(n) Titel konnte offline nicht nachgeschlagen werden; seine ID fehlt."
                    : "\(n) Titel konnten offline nicht nachgeschlagen werden; ihre IDs fehlen.")
            } else {
                lines.append(unavailable == 1
                    ? "\(n) title could not be looked up offline; its id is missing."
                    : "\(n) titles could not be looked up offline; their ids are missing.")
            }
        }

        // Tags and lists are in the CSV and JSON files only; a MAL file never carries them, so "export again
        // to include them" would promise something that format cannot hold.
        if summary.organisationUnavailable, format != .malXML {
            lines.append(german
                ? "Tags und Listen konnten nicht geladen werden. Exportiere erneut, wenn du online bist, um sie mitzunehmen."
                : "Tags and lists couldn't be loaded. Export again when you're online to include them.")
        }

        if summary.trackingDetailUnavailable {
            lines.append(german
                ? "Einige Tracking-Details (Fortschritt pro Band und Import-Quellfelder) wurden nicht geladen. Exportiere später erneut, um sie mitzunehmen."
                : "Some tracking details (units, volume progress and import source fields) weren't loaded. Export again later to include them.")
        }

        if format == .malXML {
            let missing = summary.withoutMalId.count
            if missing > 0 {
                let n = number(missing, german: german)
                if german {
                    lines.append(missing == 1
                        ? "\(n) Titel hat keine MyAnimeList-ID und fehlt in der MAL-Datei. Er ist in CSV und JSON."
                        : "\(n) Titel haben keine MyAnimeList-ID und fehlen in der MAL-Datei. Sie sind in CSV und JSON.")
                } else {
                    lines.append(missing == 1
                        ? "\(n) title has no MyAnimeList id and is not in the MAL file. It is in CSV and JSON."
                        : "\(n) titles have no MyAnimeList id and are not in the MAL file. They are in CSV and JSON.")
                }
            }
            for kind in [MediaKind.anime, .manga] {
                let parts = summary.malParts[kind] ?? 0
                guard parts > 1 else { continue }
                let n = number(parts, german: german)
                switch (kind, german) {
                case (.anime, false): lines.append("Your anime list is in \(n) files so importers accept it. Import all \(n).")
                case (.manga, false): lines.append("Your manga list is in \(n) files so importers accept it. Import all \(n).")
                case (.anime, true): lines.append("Deine Anime-Liste ist auf \(n) Dateien verteilt, damit Importe sie annehmen. Importiere alle \(n).")
                case (.manga, true): lines.append("Deine Manga-Liste ist auf \(n) Dateien verteilt, damit Importe sie annehmen. Importiere alle \(n).")
                }
            }
        }

        let outside = summary.listItemsOutsideLibrary
        if outside > 0, format != .json {
            let n = number(outside, german: german)
            if german {
                lines.append(outside == 1
                    ? "\(n) Listeneintrag ist nicht mehr in deiner Bibliothek; er steht in der JSON-Datei."
                    : "\(n) Listeneinträge sind nicht mehr in deiner Bibliothek; sie stehen in der JSON-Datei.")
            } else {
                lines.append(outside == 1
                    ? "\(n) list entry is no longer in your library; it is in the JSON file."
                    : "\(n) list entries are no longer in your library; they are in the JSON file.")
            }
        }
        return lines
    }

    // MARK: Helpers

    /// A count in the reader's locale ("1,234" / "1.234").
    private static func number(_ value: Int, german: Bool) -> String {
        value.formatted(.number.locale(Locale(identifier: german ? "de_DE" : "en_US")).grouping(.automatic))
    }
}
