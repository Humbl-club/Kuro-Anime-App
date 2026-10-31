import Foundation

/// The official MAL v2 list contract. No customer-facing title lookup or detail fan-out is needed.
public enum MALAccountList {
    public static let pageSize = 100
    public static let maximumOffset = 100_000
    public static let maximumBodyBytes = 2 * 1024 * 1024
    public static let notesLimitation = "MAL list endpoint does not provide comments. Existing Kuro notes are preserved; XML imports can include notes."
    public enum Failure: Error, Equatable { case invalidPage, unsafeCursor, sourceLimit, bodyTooLarge }
    public struct Page: Sendable {
        public let drafts: [LibraryImportDraft]
        public let nextOffset: Int?
        public var exhausted: Bool { nextOffset == nil }
    }

    public static func fields(_ medium: LibraryProviderReference.Medium) -> String {
        let progress = medium == .anime ? "num_episodes_watched,is_rewatching,num_times_rewatched,rewatch_value" : "num_chapters_read,num_volumes_read,is_rereading,num_times_reread,reread_value"
        return "list_status{status,score,\(progress),start_date,finish_date,priority,tags,updated_at}"
    }
    public static func url(medium: LibraryProviderReference.Medium, offset: Int) throws -> URL {
        guard offset >= 0, offset < maximumOffset, offset % pageSize == 0 else { throw Failure.sourceLimit }
        var parts = URLComponents(string: "https://api.myanimelist.net/v2/users/@me/\(medium == .anime ? "animelist" : "mangalist")")!
        parts.queryItems = [URLQueryItem(name: "fields", value: fields(medium)),
            URLQueryItem(name: "limit", value: String(pageSize)), URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "nsfw", value: "true")]
        return parts.url!
    }
    /// Paging URLs are data, never authority to send a bearer token to a different host/path.
    public static func nextOffset(_ value: String, medium: LibraryProviderReference.Medium, currentOffset: Int) throws -> Int {
        guard currentOffset >= 0, currentOffset < maximumOffset, currentOffset % pageSize == 0 else { throw Failure.unsafeCursor }
        guard let parts = URLComponents(string: value), parts.scheme == "https", parts.host == "api.myanimelist.net",
              parts.port == nil || parts.port == 443, parts.user == nil, parts.password == nil,
              parts.fragment == nil, parts.path == "/v2/users/@me/\(medium == .anime ? "animelist" : "mangalist")",
              let query = parts.queryItems, Set(query.map(\.name)).count == query.count,
              Set(query.map(\.name)).isSubset(of: ["fields", "limit", "offset", "nsfw"]),
              query.first(where: { $0.name == "fields" })?.value == fields(medium),
              query.first(where: { $0.name == "limit" })?.value == String(pageSize),
              query.first(where: { $0.name == "nsfw" })?.value == "true",
              let raw = query.first(where: { $0.name == "offset" })?.value,
              let offset = Int(raw), String(offset) == raw,
              offset == currentOffset + pageSize else { throw Failure.unsafeCursor }
        guard offset < maximumOffset else { throw Failure.sourceLimit }
        return offset
    }
    public static func decode(_ data: Data, medium: LibraryProviderReference.Medium, offset: Int) throws -> Page {
        guard offset >= 0, offset < maximumOffset, offset % pageSize == 0 else { throw Failure.unsafeCursor }
        guard data.count <= maximumBodyBytes else { throw Failure.bodyTooLarge }
        let decoded: Response
        do { decoded = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw Failure.invalidPage }
        guard decoded.data.count <= pageSize else { throw Failure.invalidPage }
        var identities = Set<Int>()
        var drafts: [LibraryImportDraft] = []
        for item in decoded.data {
            guard item.node.id > 0, item.node.id <= Int32.max,
                  item.node.title.map({ $0.utf8.count <= 16_384 }) ?? true, identities.insert(item.node.id).inserted else { throw Failure.invalidPage }
            drafts.append(try item.list_status.draft(id: item.node.id, medium: medium, title: item.node.title))
        }
        let next = try decoded.paging.next.map { try nextOffset($0, medium: medium, currentOffset: offset) }
        guard next == nil || decoded.data.count == pageSize else { throw Failure.invalidPage }
        return Page(drafts: drafts, nextOffset: next)
    }
    private struct Response: Decodable { let data: [Item]; let paging: Paging }
    private struct Paging: Decodable { let next: String? }
    private struct Item: Decodable { let node: Node; let list_status: Status }
    private struct Node: Decodable { let id: Int; let title: String? }
    private struct Status: Decodable {
        let status: String?
        let score: Int?
        let num_episodes_watched: Int?
        let num_chapters_read: Int?
        let num_volumes_read: Int?
        let is_rewatching: Bool?
        let is_rereading: Bool?
        let start_date: String?
        let finish_date: String?
        let priority: Int?
        let num_times_rewatched: Int?
        let num_times_reread: Int?
        let rewatch_value: Int?
        let reread_value: Int?
        let tags: [String]?
        let updated_at: String?
        func draft(id: Int, medium: LibraryProviderReference.Medium, title: String?) throws -> LibraryImportDraft {
            let active = medium == .anime ? "watching" : "reading"
            let planned = medium == .anime ? "plan_to_watch" : "plan_to_read"
            guard let status, [active, planned, "completed", "on_hold", "dropped"].contains(status) else { throw Failure.invalidPage }
            let progress = medium == .anime ? num_episodes_watched : num_chapters_read
            let repeats = medium == .anime ? num_times_rewatched : num_times_reread
            guard [progress, repeats, num_volumes_read, priority, rewatch_value, reread_value].compactMap({ $0 }).allSatisfy({ $0 >= 0 && $0 <= Int32.max }),
                  score.map({ (0...10).contains($0) }) ?? true,
                  (tags ?? []).allSatisfy({ $0.utf8.count <= 16_384 }), (tags?.count ?? 0) <= 1_000,
                  [start_date, finish_date, updated_at].compactMap({ $0 }).allSatisfy({ $0.utf8.count <= 128 }) else { throw Failure.invalidPage }
            var unavailable = ["notes", "private", "custom_lists", "hidden_from_status_lists"]
            if progress == nil { unavailable.append("progress") }
            if repeats == nil { unavailable.append("repeat_count") }
            if score == nil { unavailable.append("score") }
            if medium == .manga && num_volumes_read == nil { unavailable.append("volumes_progress") }
            if start_date == nil { unavailable.append("started_raw") }
            if finish_date == nil { unavailable.append("finished_raw") }
            var options: [String: Any] = ["notes_unavailable_reason": "MAL list endpoint does not provide comments"]
            if let tags { options["tags"] = tags }
            if let priority { options["priority"] = priority }
            if let updated_at { options["updated_at"] = updated_at }
            if let is_rewatching { options["is_rewatching"] = is_rewatching }
            if let is_rereading { options["is_rereading"] = is_rereading }
            if let rewatch_value { options["rewatch_value"] = rewatch_value }
            if let reread_value { options["reread_value"] = reread_value }
            let rawOptions = String(data: try JSONSerialization.data(withJSONObject: options, options: [.sortedKeys]), encoding: .utf8)
            return LibraryImportDraft(medium: medium.rawValue, externalId: String(id), status: status,
                progress: progress ?? 0, volumesProgress: medium == .manga ? num_volumes_read : nil,
                scoreRaw: score.flatMap { $0 == 0 ? nil : String($0) }, scoreScale: "MAL_10", repeatCount: repeats ?? 0,
                startedRaw: start_date, finishedRaw: finish_date,
                sourceListOptions: LibraryImportDraft.options(rawOptions, unavailable: unavailable),
                normalizedRating: score.flatMap { $0 == 0 ? nil : $0 }, sourceTitle: title)
        }
    }
}

public struct MALAccountImportCursor: Codable, Equatable, Sendable {
    public private(set) var anime: Int? = 0
    public private(set) var manga: Int? = 0
    public init() {}
    public var nextMedium: LibraryProviderReference.Medium? { anime != nil ? .anime : manga != nil ? .manga : nil }
    public func offset(for medium: LibraryProviderReference.Medium) -> Int? { medium == .anime ? anime : manga }
    public mutating func advance(_ medium: LibraryProviderReference.Medium, to offset: Int?) {
        if medium == .anime { anime = offset } else { manga = offset }
    }
    public static func decode(_ value: String?) throws -> Self {
        guard let value else { return Self() }
        guard let data = value.data(using: .utf8), data.count <= 512 else { throw MALAccountList.Failure.unsafeCursor }
        let cursor: Self
        do { cursor = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw MALAccountList.Failure.unsafeCursor }
        guard [cursor.anime, cursor.manga].compactMap({ $0 }).allSatisfy({ $0 >= 0 && $0 < MALAccountList.maximumOffset && $0 % MALAccountList.pageSize == 0 }) else { throw MALAccountList.Failure.unsafeCursor }
        return cursor
    }
    public func encode() throws -> String { String(data: try JSONEncoder().encode(self), encoding: .utf8)! }
}
