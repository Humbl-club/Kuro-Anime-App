import Foundation
import KuroCore

// MARK: - MAL vocabulary

/// How Kuro's values are written to, and read back from, a MyAnimeList XML export.
///
/// The writer in `LibraryExport.malXML(_:kind:summary:)` is the other half of `MALExportParser`: everything a
/// Kuro export writes must come back through the parser unchanged (the round-trip test pins that). The rules
/// here exist because the parser rejects a whole file for one bad character or one oversized element, so a
/// note that breaks XML would make every other title in the file unimportable.
public enum MALExportMapping {
    /// The parser's per-element limit (`MALExportParser` rejects an element above 16,384 UTF-8 bytes of text).
    public static let notesByteLimit = 16_384

    /// The MAL word written to `my_status` and whether the rewatch / reread flag is set.
    ///
    /// MAL has no "repeating" status: `.repeating` is written as Watching / Reading with the flag set, and the
    /// word "Repeating" is never emitted. Manga uses Reading / Plan to Read, anime Watching / Plan to Watch.
    public static func malStatus(_ status: ListStatus, kind: MediaKind) -> (word: String, repeating: Bool) {
        let isManga = kind == .manga
        switch status {
        case .current: return (isManga ? "Reading" : "Watching", false)
        case .repeating: return (isManga ? "Reading" : "Watching", true)
        case .planning: return (isManga ? "Plan to Read" : "Plan to Watch", false)
        case .completed: return ("Completed", false)
        case .paused: return ("On-Hold", false)
        case .dropped: return ("Dropped", false)
        }
    }

    /// The Kuro status the import path stores for a status string `MALExportParser` returned.
    ///
    /// Mirrors the SQL `_import_v2_status` followed by `SupabaseLibraryBackend.status(fromDB:)`: watching,
    /// reading, current and repeating become `.current` (the database stores `WATCHING` / `READING` for all of
    /// them), `plan_to_*` and planning become `.planning`, on_hold and paused become `.paused`. Returns `nil`
    /// for anything else, which the import rejects.
    public static func storedStatus(fromParsed raw: String) -> ListStatus? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "watching", "reading", "current", "repeating": return .current
        case "completed": return .completed
        case "dropped": return .dropped
        case "planning", "plan_to_watch", "plan_to_read", "plan to watch", "plan to read": return .planning
        case "paused", "on_hold", "on-hold", "on hold": return .paused
        default: return nil
        }
    }

    /// The MAL spelling of a date: `YYYY-MM-DD`, with `00` for an unknown month or day (`2024-00-00`,
    /// `2024-03-00`). `nil` for a `nil` date.
    ///
    /// A stored date that does not parse as a `PartialDate` never gets here: the writer omits that element
    /// and lists the entry in `LibraryExportSummary.datesOmitted`.
    public static func malDate(_ date: PartialDate?) -> String? {
        date?.zeroPadded
    }

    /// XML 1.0 element text for `value`.
    ///
    /// `&`, `<`, `>`, `"` and `'` become entities and a carriage return becomes `&#13;` (an XML parser turns a
    /// literal CR or CRLF into LF, which would alter a note). TAB and LF are kept. Characters XML 1.0 does not
    /// allow are dropped: the C0 controls other than TAB, LF and CR, and U+FFFE and U+FFFF. There is no CDATA
    /// form: the parser scans the raw bytes for `<!DOCTYPE` and `<!ENTITY`, so a CDATA note containing that
    /// text would make it reject the file.
    ///
    /// - Returns: The escaped text and whether any character was dropped (`changed`).
    public static func xmlText(_ value: String) -> (text: String, changed: Bool) {
        let cleaned = removingIllegalCharacters(value)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.text.utf8.count)
        appendEscaped(cleaned.text, to: &bytes)
        return (String(decoding: bytes, as: UTF8.self), cleaned.changed)
    }

    // MARK: Internal helpers (shared with the writer)

    /// `value` without the characters XML 1.0 forbids. Returns `value` itself (no copy) when it has none.
    static func removingIllegalCharacters(_ value: String) -> (text: String, changed: Bool) {
        // 0xEF leads U+F000...U+FFFF, the only range that holds U+FFFE and U+FFFF. A byte scan decides whether
        // the slower scalar pass is needed at all (most notes are plain text).
        let suspicious = value.utf8.contains { byte in
            (byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D) || byte == 0xEF
        }
        guard suspicious else { return (value, false) }
        var kept = String.UnicodeScalarView()
        var changed = false
        for scalar in value.unicodeScalars {
            let code = scalar.value
            let illegal = (code < 0x20 && code != 0x09 && code != 0x0A && code != 0x0D) || code == 0xFFFE || code == 0xFFFF
            if illegal { changed = true } else { kept.append(scalar) }
        }
        return changed ? (String(kept), true) : (value, false)
    }

    /// Appends `clean` to `bytes` with the five XML entities and `&#13;` for CR. `clean` must already be free of
    /// forbidden characters.
    static func appendEscaped(_ clean: String, to bytes: inout [UInt8]) {
        for byte in clean.utf8 {
            switch byte {
            case 0x26: bytes.append(contentsOf: Self.ampersand)
            case 0x3C: bytes.append(contentsOf: Self.lessThan)
            case 0x3E: bytes.append(contentsOf: Self.greaterThan)
            case 0x22: bytes.append(contentsOf: Self.doubleQuote)
            case 0x27: bytes.append(contentsOf: Self.apostrophe)
            case 0x0D: bytes.append(contentsOf: Self.carriageReturn)
            default: bytes.append(byte)
            }
        }
    }

    private static let ampersand = Array("&amp;".utf8)
    private static let lessThan = Array("&lt;".utf8)
    private static let greaterThan = Array("&gt;".utf8)
    private static let doubleQuote = Array("&quot;".utf8)
    private static let apostrophe = Array("&apos;".utf8)
    private static let carriageReturn = Array("&#13;".utf8)
}

// MARK: - Document writer

extension LibraryExport {
    /// `<myanimelist>` documents for `kind`: entries that have a MAL id, sorted by MAL id.
    ///
    /// Usually one document. When the whole escaped document (XML declaration, `<myinfo>`, every row and the
    /// closing tag, in UTF-8 bytes) would exceed `MALExportParser.maxBytes`, or the row count would exceed
    /// `MALExportParser.maxItems`, the rows are packed greedily, in MAL-id order, into several documents. Each
    /// part is complete (it has its own `<myinfo>`), is at most the parser's limits (equal is accepted) and
    /// re-imports on its own; parts are contiguous by MAL id. A single row cannot exceed the limit: a note is
    /// at most 16,384 bytes before escaping (about 100 KB after).
    ///
    /// Sets `summary.malExported[kind]` and `summary.malParts[kind]` (neither when there is nothing to write)
    /// and appends to `summary.notesAdjusted` and `summary.datesOmitted`.
    static func malXML(_ input: LibraryExportInput, kind: MediaKind, summary: inout LibraryExportSummary) -> [Data] {
        var candidates: [(entry: LibraryEntry, malId: Int)] = []
        for entry in input.entries where entry.key.kind == kind {
            guard let malId = input.catalogue[entry.key]?.malId, (1...Int(Int32.max)).contains(malId) else { continue }
            candidates.append((entry, malId))
        }
        guard !candidates.isEmpty else { return [] }
        candidates.sort { ($0.malId, $0.entry.key.id) < ($1.malId, $1.entry.key.id) }

        let header = Data(MALDocument.header(kind: kind))
        let footer = Data(MALDocument.footer)
        var parts: [Data] = []
        var current = header
        var rowsInCurrent = 0
        for candidate in candidates {
            let row = MALDocument.row(candidate.entry, malId: candidate.malId, catalogue: input.catalogue)
            if row.notesAdjusted { summary.notesAdjusted.append(Self.reportLine(candidate.entry.key, in: input.catalogue)) }
            if row.dateOmitted { summary.datesOmitted.append(Self.reportLine(candidate.entry.key, in: input.catalogue)) }
            if rowsInCurrent > 0,
               rowsInCurrent >= MALExportParser.maxItems
                || current.count + row.bytes.count + footer.count > MALExportParser.maxBytes {
                current.append(footer)
                parts.append(current)
                current = header
                rowsInCurrent = 0
            }
            current.append(contentsOf: row.bytes)
            rowsInCurrent += 1
        }
        current.append(footer)
        parts.append(current)

        summary.malExported[kind] = candidates.count
        summary.malParts[kind] = parts.count
        return parts
    }
}

/// Byte-level serialisation of one MAL document and its rows. Everything is built as UTF-8 bytes once: the size
/// that decides a split is the size of the bytes that are written.
private enum MALDocument {
    struct Row {
        var bytes: [UInt8]
        /// The note had characters dropped or was omitted for length.
        var notesAdjusted: Bool
        /// A stored date did not parse and its element was omitted.
        var dateOmitted: Bool
    }

    static func header(kind: MediaKind) -> [UInt8] {
        let exportType = kind == .anime ? 1 : 2
        return Array("""
            <?xml version="1.0" encoding="UTF-8"?>
            <myanimelist>
              <myinfo>
                <user_export_type>\(exportType)</user_export_type>
              </myinfo>

            """.utf8)
    }

    static let footer = Array("</myanimelist>\n".utf8)

    /// MAL's own value for "no date".
    private static let noDate = "0000-00-00"

    /// One `<anime>` / `<manga>` row. Element names and order follow the MAL export schema; the parser reads
    /// only the ones it needs and ignores the rest.
    static func row(_ entry: LibraryEntry, malId: Int, catalogue: [MediaKey: ExportCatalogueRow]) -> Row {
        let kind = entry.key.kind
        let isManga = kind == .manga
        var xml = XMLBytes()
        var notesAdjusted = false
        var dateOmitted = false

        xml.open(isManga ? "manga" : "anime", indent: 1)
        // Element names follow MAL's own export: manga rows use `manga_*`, anime rows `series_*`.
        xml.number(isManga ? "manga_mangadb_id" : "series_animedb_id", malId)
        // The title is informational (the parser reads the id). It is written only when the catalogue has one:
        // the "Untitled ..." fallback belongs in the report lines, not in a file another service imports. An
        // absurdly long title is dropped, not allowed to make the parser reject the file.
        if let title = catalogue[entry.key]?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            let safeTitle = MALExportMapping.removingIllegalCharacters(title).text
            if safeTitle.utf8.count <= MALExportMapping.notesByteLimit {
                xml.escaped(isManga ? "manga_title" : "series_title", safeTitle)
            }
        }
        if isManga, let volumes = entry.sourceMetadata?.volumesProgress {
            xml.number("my_read_volumes", count(volumes))
        }
        xml.number(isManga ? "my_read_chapters" : "my_watched_episodes", count(entry.progress))

        // Dates, repeat count: written only when the server values were read. With no source metadata they
        // are unknown, the elements are omitted and the parser marks them unavailable (import never clears).
        if entry.datesKnown, let metadata = entry.sourceMetadata {
            for (name, raw) in [("my_start_date", metadata.startedRaw), ("my_finish_date", metadata.finishedRaw)] {
                switch dateElement(raw) {
                case .value(let text): xml.literal(name, text)
                case .none: xml.literal(name, noDate)
                case .unparseable: dateOmitted = true
                }
            }
        }
        xml.number("my_score", entry.rating?.value ?? 0)
        let status = MALExportMapping.malStatus(entry.status, kind: kind)
        xml.literal("my_status", status.word)

        let note = MALExportMapping.removingIllegalCharacters(entry.notes ?? "")
        if note.changed { notesAdjusted = true }
        if note.text.utf8.count > MALExportMapping.notesByteLimit {
            notesAdjusted = true
        } else {
            xml.escaped("my_comments", note.text)
        }

        if entry.datesKnown {
            xml.number(isManga ? "my_times_read" : "my_times_watched", count(entry.repeatCount))
        }
        // MAL's own spelling of the manga flag is "my_rereadingg".
        xml.number(isManga ? "my_rereadingg" : "my_rewatching", status.repeating ? 1 : 0)
        xml.number("update_on_import", 1)
        xml.close(isManga ? "manga" : "anime", indent: 1)
        return Row(bytes: xml.bytes, notesAdjusted: notesAdjusted, dateOmitted: dateOmitted)
    }

    /// What to write for one stored date.
    private enum DateElement {
        /// Known metadata with no date: MAL's no-date value.
        case none
        /// The zero-padded date.
        case value(String)
        /// The stored text is not a date: omit the element and report the entry.
        case unparseable
    }

    private static func dateElement(_ raw: String?) -> DateElement {
        guard let raw else { return .none }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == noDate { return .none }
        guard let date = PartialDate(raw: trimmed), let text = MALExportMapping.malDate(date) else { return .unparseable }
        return .value(text)
    }

    /// A count the parser accepts: digits only, at most `Int32.max`.
    private static func count(_ value: Int) -> Int { min(max(value, 0), Int(Int32.max)) }
}

/// A tiny append-only XML element writer over UTF-8 bytes.
private struct XMLBytes {
    var bytes: [UInt8] = []

    mutating func open(_ name: String, indent: Int) {
        pad(indent)
        bytes.append(contentsOf: "<\(name)>\n".utf8)
    }

    mutating func close(_ name: String, indent: Int) {
        pad(indent)
        bytes.append(contentsOf: "</\(name)>\n".utf8)
    }

    /// A number element (child of a row).
    mutating func number(_ name: String, _ value: Int) {
        literal(name, String(value))
    }

    /// An element whose text is already XML-safe (a number, a status word, a date).
    mutating func literal(_ name: String, _ text: String) {
        pad(2)
        bytes.append(contentsOf: "<\(name)>".utf8)
        bytes.append(contentsOf: text.utf8)
        bytes.append(contentsOf: "</\(name)>\n".utf8)
    }

    /// An element whose text is `clean` (no forbidden characters) escaped as XML text.
    mutating func escaped(_ name: String, _ clean: String) {
        pad(2)
        bytes.append(contentsOf: "<\(name)>".utf8)
        MALExportMapping.appendEscaped(clean, to: &bytes)
        bytes.append(contentsOf: "</\(name)>\n".utf8)
    }

    private mutating func pad(_ indent: Int) {
        bytes.append(contentsOf: repeatElement(0x20, count: indent * 2))
    }
}
