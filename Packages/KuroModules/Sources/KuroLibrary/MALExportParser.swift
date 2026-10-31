import Foundation

/// One row of a MyAnimeList XML export. Account API access is a separate connector.
public struct MALExportItem: Equatable, Sendable {
    public var medium: String
    public var externalId: String
    public var status: String
    public var progress: Int?
    public var volumesProgress: Int?
    public var scoreRaw: String?
    public var scoreScale: String
    public var notes: String?
    public var repeatCount: Int?
    public var startedRaw: String?
    public var finishedRaw: String?
    public var sourceTitle: String?
    public var unavailableFields: Set<String>

    /// Missing fields never turn into an instruction to erase a user's Kuro values.
    public func draft() -> LibraryImportDraft {
        var unavailable = unavailableFields.union(["private", "custom_lists", "hidden_from_status_lists"])
        if progress == nil { unavailable.insert("progress") }
        if repeatCount == nil { unavailable.insert("repeat_count") }
        let rating = scoreRaw.flatMap(Int.init).flatMap { (1...10).contains($0) ? $0 : nil }
        return LibraryImportDraft(medium: medium, externalId: externalId, status: status,
            progress: progress ?? 0, volumesProgress: volumesProgress, scoreRaw: scoreRaw,
            scoreScale: scoreScale, notes: notes, repeatCount: repeatCount ?? 0,
            startedRaw: startedRaw, finishedRaw: finishedRaw,
            sourceListOptions: LibraryImportDraft.options(nil, unavailable: unavailable.sorted()),
            normalizedRating: rating, sourceTitle: sourceTitle)
    }

    public init(medium: String, externalId: String, status: String, progress: Int?,
                volumesProgress: Int?, scoreRaw: String?, scoreScale: String = "MAL_10",
                notes: String?, repeatCount: Int?, startedRaw: String?, finishedRaw: String?,
                sourceTitle: String? = nil, unavailableFields: Set<String> = []) {
        self.medium = medium; self.externalId = externalId; self.status = status
        self.progress = progress; self.volumesProgress = volumesProgress
        self.scoreRaw = scoreRaw; self.scoreScale = scoreScale; self.notes = notes
        self.repeatCount = repeatCount; self.startedRaw = startedRaw; self.finishedRaw = finishedRaw
        self.sourceTitle = sourceTitle; self.unavailableFields = unavailableFields
    }
}

public enum MALExportError: Error, Equatable {
    case tooLarge, tooManyItems, malformed, externalEntity
}

/// Bounded device-export parser; scalar rows must be direct children of the actual export root.
public enum MALExportParser {
    public static let maxBytes = 32 * 1024 * 1024
    public static let maxItems = 20_000

    public static func parse(_ data: Data) throws -> [MALExportItem] {
        try Task.checkCancellation()
        if data.count > maxBytes { throw MALExportError.tooLarge }
        // Padding removal also detects declarations in XMLParser's UTF-16/32 input encodings.
        let folded = String(decoding: data.filter { $0 != 0 }, as: UTF8.self).uppercased()
        if folded.contains("<!DOCTYPE") || folded.contains("<!ENTITY") { throw MALExportError.externalEntity }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let parsed = parser.parse()
        if delegate.cancelled { throw CancellationError() }
        try Task.checkCancellation()
        guard parsed, delegate.failure == nil else { throw delegate.failure ?? MALExportError.malformed }
        return delegate.items
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [MALExportItem] = []
        var failure: MALExportError?
        var cancelled = false
        private var stack: [String] = []
        private var sawRoot = false
        private var medium: String?
        private var fields: [String: String] = [:]
        private var text = ""

        private func admit(_ parser: XMLParser) -> Bool {
            guard !Task.isCancelled else { cancelled = true; parser.abortParsing(); return false }
            return failure == nil
        }
        private func reject(_ parser: XMLParser, _ error: MALExportError = .malformed) {
            failure = error; parser.abortParsing()
        }
        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
                    publicID: String?, systemID: String?) { reject(parser, .externalEntity) }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            guard admit(parser) else { return }
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { reject(parser); return }
            switch stack.count {
            case 0:
                guard name == "myanimelist", !sawRoot else { reject(parser); return }
                sawRoot = true
            case 1:
                guard ["anime", "manga", "myinfo"].contains(name) else { reject(parser); return }
                if name != "myinfo" { medium = name; fields = [:] }
            case 2:
                guard name != "anime", name != "manga", name != "myanimelist" else { reject(parser); return }
                if medium != nil, fields[name] != nil { reject(parser); return }
            default: reject(parser); return
            }
            stack.append(name); text = ""
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard admit(parser) else { return }
            guard text.utf8.count + string.utf8.count <= 16_384 else { reject(parser, .tooLarge); return }
            text += string
        }
        func parser(_ parser: XMLParser, foundCDATA data: Data) {
            guard let value = String(data: data, encoding: .utf8) else { reject(parser); return }
            self.parser(parser, foundCharacters: value)
        }
        func parserDidEndDocument(_ parser: XMLParser) {
            if !sawRoot || !stack.isEmpty { failure = .malformed }
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard admit(parser), stack.last == name else { return }
            if stack.count == 3, medium != nil {
                fields[name] = name == "my_comments" ? text : text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || stack.count == 3 else { reject(parser); return }
                if stack.count == 2, medium != nil {
                    do { items.append(try makeItem()) }
                    catch { reject(parser); return }
                    if items.count > MALExportParser.maxItems { reject(parser, .tooManyItems); return }
                    medium = nil; fields = [:]
                }
            }
            stack.removeLast(); text = ""
        }

        private func makeItem() throws -> MALExportItem {
            guard let medium else { throw MALExportError.malformed }
            let idKey = medium == "anime" ? "series_animedb_id" : "series_mangadb_id"
            guard let id = try number(idKey), id > 0, let rawStatus = fields["my_status"],
                  let status = status(rawStatus, medium: medium) else { throw MALExportError.malformed }
            let progressKey = medium == "anime" ? "my_watched_episodes" : "my_read_chapters"
            let repeatKey = medium == "anime" ? "my_times_watched" : "my_times_read"
            let score = try number("my_score")
            guard score.map({ $0 <= 10 }) ?? true else { throw MALExportError.malformed }
            var unavailable: Set<String> = []
            for (key, field) in [(progressKey, "progress"), (repeatKey, "repeat_count"),
                ("my_score", "score"), ("my_comments", "notes"), ("my_start_date", "started_raw"),
                ("my_finish_date", "finished_raw")] where fields[key] == nil { unavailable.insert(field) }
            if medium == "manga", fields["my_read_volumes"] == nil { unavailable.insert("volumes_progress") }
            return MALExportItem(medium: medium, externalId: String(id), status: status,
                progress: try number(progressKey), volumesProgress: try number("my_read_volumes"),
                scoreRaw: score.flatMap { $0 == 0 ? nil : String($0) }, notes: emptyToNil(fields["my_comments"]),
                repeatCount: try number(repeatKey), startedRaw: try date(fields["my_start_date"]),
                finishedRaw: try date(fields["my_finish_date"]), sourceTitle: emptyToNil(fields["series_title"]),
                unavailableFields: unavailable)
        }
        private func number(_ key: String) throws -> Int? {
            guard let raw = fields[key] else { return nil }
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
                  let value = Int(raw), value <= Int32.max else { throw MALExportError.malformed }
            return value
        }
        private func status(_ raw: String, medium: String) -> String? {
            let value = raw.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
            let active = medium == "anime" ? "watching" : "reading"
            let planned = medium == "anime" ? "plan_to_watch" : "plan_to_read"
            if [active, planned, "completed", "on_hold", "dropped", "repeating"].contains(value) { return value }
            return ["1": active, "2": "completed", "3": "on_hold", "4": "dropped", "6": planned][value]
        }
        private func emptyToNil(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
        private func date(_ raw: String?) throws -> String? {
            guard let raw else { return nil }
            guard raw.count == 10, raw.utf8.enumerated().allSatisfy({ index, byte in
                [4, 7].contains(index) ? byte == 45 : (48...57).contains(byte)
            }) else { throw MALExportError.malformed }
            if raw == "0000-00-00" { return nil }
            let parts = raw.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, (1...9999).contains(parts[0]), (0...12).contains(parts[1]),
                  (0...31).contains(parts[2]), parts[1] != 0 || parts[2] == 0 else { throw MALExportError.malformed }
            if parts[1] > 0, parts[2] > 0 {
                let leap = parts[0] % 4 == 0 && (parts[0] % 100 != 0 || parts[0] % 400 == 0)
                let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
                guard parts[2] <= days[parts[1] - 1] else { throw MALExportError.malformed }
            }
            return raw
        }
    }
}
