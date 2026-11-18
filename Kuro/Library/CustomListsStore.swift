import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Custom lists (W9)
// The account's custom lists: mixed-medium, manual order, private. Behind `library_organise_v1` (read at call
// time, before any request). Every private request runs inside the account's credential lease and publishes
// only while the captured context is current. Order and membership carry a per-list revision; a move against
// a stale revision is refused (`STALE_LIST`), the list reloads, and the move is tried again only when the
// person chooses "Try again", once. List items outlive the title's presence in the library.

struct CustomList: Identifiable, Equatable {
    let id: UUID
    var name: String
    var items: [MediaKey]
}

struct CustomListMeta: Equatable, Sendable {
    let createdAt: Date
    var revision: Int64
}

struct CustomListRemoval: Equatable {
    let listId: UUID
    let slot: CustomListSlot
    let revisionAfter: Int64
    let account: AccountContext
}

/// What a stale move meant, by neighbour ids (it survives a reload).
struct CustomListPendingMove: Equatable, Sendable {
    let listId: UUID
    let itemId: UUID
    let afterItemId: UUID?
    let beforeItemId: UUID?
    let account: AccountContext
    let isRetry: Bool
}

enum CustomListMoveOutcome: Equatable {
    case moved
    case stale(CustomListPendingMove)
    case failed(OrganiseError)
}

struct CustomListSeedReport: Equatable {
    var created: [String]
    var reused: [String]
    var skipped: [String]
    var added: Int
}

// MARK: Wire

private struct CustomListWire: Decodable {
    struct Item: Decodable {
        let itemId: UUID
        let medium: String
        let mediaId: Int
        let position: Double
        enum CodingKeys: String, CodingKey { case itemId = "item_id", medium, mediaId = "media_id", position }
    }
    let id: UUID
    let name: String
    let createdAt: String?
    let revision: Int64
    let items: [Item]
    enum CodingKeys: String, CodingKey { case id, name, createdAt = "created_at", revision, items }
}

private struct CustomListCreated: Decodable {
    let id: UUID
    let name: String
    let createdAt: String?
    let revision: Int64
    enum CodingKeys: String, CodingKey { case id, name, createdAt = "created_at", revision }
}

private struct MoveResult: Decodable {
    let itemId: UUID
    let position: Double
    let revision: Int64
    enum CodingKeys: String, CodingKey { case itemId = "item_id", position, revision }
}

private struct RebalanceResult: Decodable {
    struct Item: Decodable {
        let itemId: UUID
        let position: Double
        enum CodingKeys: String, CodingKey { case itemId = "item_id", position }
    }
    let revision: Int64
    let items: [Item]
}

private struct SeedResult: Decodable {
    struct Skipped: Decodable { let name: String }
    let created: [String]
    let reused: [String]
    let skipped: [Skipped]
    let added: Int
}

private struct RPCCreateListParams: Encodable { let p_name: String }
private struct RPCRenameListParams: Encodable { let p_list_id: UUID; let p_name: String }
private struct RPCDeleteListParams: Encodable { let p_list_id: UUID }
private struct RPCRebalanceParams: Encodable {
    let p_list_id: UUID
    let p_item_ids: [UUID]
    let p_expected_list_revision: Int64
}
private struct RPCMoveParams: Encodable {
    let p_list_id: UUID
    let p_item_id: UUID
    let p_after_position: Double?
    let p_before_position: Double?
    let p_expected_list_revision: Int64

    enum CodingKeys: String, CodingKey {
        case p_list_id, p_item_id, p_after_position, p_before_position, p_expected_list_revision
    }

    /// Explicit nulls at head and tail: the function has no defaults, so an omitted key would not resolve.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_list_id, forKey: .p_list_id)
        try c.encode(p_item_id, forKey: .p_item_id)
        try c.encode(p_after_position, forKey: .p_after_position)
        try c.encode(p_before_position, forKey: .p_before_position)
        try c.encode(p_expected_list_revision, forKey: .p_expected_list_revision)
    }
}
private struct RPCSeedParams: Encodable {
    struct Item: Encodable { let medium: String; let media_id: Int }
    struct Entry: Encodable { let name: String; let items: [Item] }
    let p_lists: [Entry]
}

private struct CatalogRow: Decodable {
    let id: Int
    let title_english: String?
    let title_romaji: String?
    let title_native: String?
    let cover_image_large: String?
    let episodes: Int?
    let chapters: Int?

    func media(kind: MediaKind) -> Media {
        Media(id: id, kind: kind,
              title: title_english ?? title_romaji ?? title_native ?? "Untitled \(kind.rawValue) #\(id)",
              imageURL: cover_image_large, year: "", displayDescription: "",
              episodes: kind == .anime ? episodes : nil, chapters: kind == .manga ? chapters : nil,
              rating: nil, genres: nil, statusRaw: nil, formatRaw: nil, popularityValue: nil,
              trendingValue: nil, createdAtValue: nil)
    }
}

@MainActor
@Observable
final class CustomListsStore: AccountScopedState {
    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let accountSession: AccountSessionCoordinator
    @ObservationIgnored private let flags: FeatureFlags
    @ObservationIgnored weak var library: LibraryStore?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var names: [UUID: String] = [:]
    @ObservationIgnored private var busyLists: Set<UUID> = []

    private(set) var lists: [CustomList] = []
    private(set) var meta: [UUID: CustomListMeta] = [:]
    private(set) var slots: [UUID: [CustomListSlot]] = [:]
    private(set) var media: [MediaKey: Media] = [:]
    private(set) var loadState: OrganiseLoadState = .notLoaded

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, flags: FeatureFlags) {
        self.client = client
        self.accountSession = accountSession
        self.flags = flags
    }

    /// Read at call time (flags hydrate after launch and carry per-account overrides).
    var isEnabled: Bool { flags.libraryOrganiseV1Enabled }

    func isTracked(_ key: MediaKey) -> Bool { library?.isTracked(key) ?? false }

    // MARK: Loading

    /// Flag off: `.unavailable`, no request. `force == false` sends nothing once loaded.
    func load(force: Bool = false) async {
        guard isEnabled else { loadState = .unavailable; return }
        if !force, loadState == .loaded || loadState == .loading { return }
        guard let client, let account = accountSession.current else { return }
        generation += 1
        let mine = generation
        loadState = .loading
        do {
            let rows: [CustomListWire] = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("custom_lists_v1").execute().value
            }
            guard mine == generation, accountSession.isCurrent(account) else { return }
            var names: [UUID: String] = [:]
            var meta: [UUID: CustomListMeta] = [:]
            var slots: [UUID: [CustomListSlot]] = [:]
            for row in rows {
                names[row.id] = row.name
                meta[row.id] = CustomListMeta(createdAt: Self.date(row.createdAt), revision: row.revision)
                slots[row.id] = CustomListOrder.ordered(row.items.compactMap { item in
                    MediaKind(rawValue: item.medium).map {
                        CustomListSlot(itemId: item.itemId, key: MediaKey(kind: $0, id: item.mediaId), position: item.position)
                    }
                })
            }
            self.names = names
            self.meta = meta
            self.slots = slots
            rebuildLists()
            loadState = .loaded
        } catch {
            guard mine == generation, accountSession.isCurrent(account) else { return }
            switch OrganiseError.from(error) {
            case .unavailable?: loadState = .unavailable; clearLists()
            case nil: loadState = .notLoaded
            default: loadState = .failed
            }
        }
    }

    // MARK: Create, rename, delete

    func create(name: String) async -> Result<CustomList, OrganiseError> {
        guard isEnabled else { return .failure(.unavailable) }
        guard let clean = Self.cleanName(name) else { return .failure(.nameInvalid) }
        guard let client, let account = accountSession.current else { return .failure(.failed) }
        do {
            let created: CustomListCreated = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("create_custom_list_v1", params: RPCCreateListParams(p_name: clean)).execute().value
            }
            guard accountSession.isCurrent(account) else { return .failure(.failed) }
            names[created.id] = created.name
            meta[created.id] = CustomListMeta(createdAt: Self.date(created.createdAt), revision: created.revision)
            slots[created.id] = []
            rebuildLists()
            return .success(CustomList(id: created.id, name: created.name, items: []))
        } catch {
            return .failure(OrganiseError.from(error) ?? .failed)
        }
    }

    func rename(_ id: UUID, to name: String) async -> Result<Void, OrganiseError> {
        guard isEnabled else { return .failure(.unavailable) }
        guard let clean = Self.cleanName(name) else { return .failure(.nameInvalid) }
        guard let client, let account = accountSession.current else { return .failure(.failed) }
        do {
            let renamed: CustomListCreated = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("rename_custom_list_v1", params: RPCRenameListParams(p_list_id: id, p_name: clean))
                    .execute().value
            }
            guard accountSession.isCurrent(account) else { return .failure(.failed) }
            if names[id] != nil { names[id] = renamed.name; rebuildLists() }
            return .success(())
        } catch {
            return .failure(OrganiseError.from(error) ?? .failed)
        }
    }

    func delete(_ id: UUID) async -> Result<Void, OrganiseError> {
        guard isEnabled else { return .failure(.unavailable) }
        guard let client, let account = accountSession.current else { return .failure(.failed) }
        do {
            try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("delete_custom_list_v1", params: RPCDeleteListParams(p_list_id: id)).execute()
            }
            guard accountSession.isCurrent(account) else { return .failure(.failed) }
            names[id] = nil; meta[id] = nil; slots[id] = nil
            rebuildLists()
            return .success(())
        } catch {
            return .failure(OrganiseError.from(error) ?? .failed)
        }
    }

    // MARK: Order

    func move(in listId: UUID, fromOffsets: IndexSet, toOffset: Int) async -> CustomListMoveOutcome {
        guard isEnabled else { return .failed(.unavailable) }
        guard let account = accountSession.current else { return .failed(.failed) }
        guard let indices = CustomListOrder.indices(fromOffsets: fromOffsets, toOffset: toOffset) else { return .moved }
        return await perform(listId: listId, from: indices.from, to: indices.to, account: account, isRetry: false)
    }

    /// Called only from the person's "Try again": the move re-derived from its neighbours in the reloaded list.
    func retry(_ pending: CustomListPendingMove) async -> CustomListMoveOutcome {
        guard isEnabled else { return .failed(.unavailable) }
        guard accountSession.isCurrent(pending.account) else { return .failed(.failed) }
        let ordered = CustomListOrder.ordered(slots[pending.listId] ?? [])
        guard let from = ordered.firstIndex(where: { $0.itemId == pending.itemId }) else { return .failed(.notFound) }
        let others = ordered.filter { $0.itemId != pending.itemId }
        let to: Int
        if let after = pending.afterItemId, let index = others.firstIndex(where: { $0.itemId == after }) {
            to = index + 1
        } else if let before = pending.beforeItemId, let index = others.firstIndex(where: { $0.itemId == before }) {
            to = index
        } else {
            to = pending.afterItemId == nil ? 0 : others.count
        }
        return await perform(listId: pending.listId, from: from, to: to, account: pending.account, isRetry: true)
    }

    private func perform(listId: UUID, from: Int, to: Int, account: AccountContext, isRetry: Bool) async -> CustomListMoveOutcome {
        guard let client else { return .failed(.failed) }
        guard !busyLists.contains(listId), let before = slots[listId], let revision = meta[listId]?.revision else {
            return .failed(.failed)
        }
        let plan = CustomListOrder.move(before, from: from, to: to)
        if plan == .none { return .moved }

        // Neighbour ids at the target (what a stale move meant), from the moved arrangement.
        var arranged = CustomListOrder.ordered(before)
        let moved = arranged.remove(at: from)
        arranged.insert(moved, at: to)
        let pending = CustomListPendingMove(
            listId: listId, itemId: moved.itemId,
            afterItemId: to > 0 ? arranged[to - 1].itemId : nil,
            beforeItemId: to + 1 < arranged.count ? arranged[to + 1].itemId : nil,
            account: account, isRetry: isRetry)

        busyLists.insert(listId)
        defer { busyLists.remove(listId) }
        // Optimistic projection.
        switch plan {
        case .single(let itemId, let position, _, _):
            slots[listId] = before.map { $0.itemId == itemId ? CustomListSlot(itemId: $0.itemId, key: $0.key, position: position) : $0 }
        case .rebalance(let renumbered):
            slots[listId] = renumbered
        case .none: break
        }
        rebuildLists()

        do {
            switch plan {
            case .single(let itemId, _, let after, let beforePosition):
                let result: MoveResult = try await accountSession.withCredentialLease(for: account) {
                    try await client.rpc("move_custom_list_item_v1", params: RPCMoveParams(
                        p_list_id: listId, p_item_id: itemId, p_after_position: after, p_before_position: beforePosition,
                        p_expected_list_revision: revision)).execute().value
                }
                guard accountSession.isCurrent(account) else { return .failed(.failed) }
                slots[listId] = (slots[listId] ?? []).map {
                    $0.itemId == result.itemId ? CustomListSlot(itemId: $0.itemId, key: $0.key, position: result.position) : $0
                }
                meta[listId]?.revision = result.revision
            case .rebalance(let renumbered):
                let result: RebalanceResult = try await accountSession.withCredentialLease(for: account) {
                    try await client.rpc("rebalance_custom_list_v1", params: RPCRebalanceParams(
                        p_list_id: listId, p_item_ids: renumbered.map(\.itemId), p_expected_list_revision: revision))
                        .execute().value
                }
                guard accountSession.isCurrent(account) else { return .failed(.failed) }
                let positions = Dictionary(result.items.map { ($0.itemId, $0.position) }, uniquingKeysWith: { first, _ in first })
                slots[listId] = renumbered.map { CustomListSlot(itemId: $0.itemId, key: $0.key, position: positions[$0.itemId] ?? $0.position) }
                meta[listId]?.revision = result.revision
            case .none: break
            }
            rebuildLists()
            return .moved
        } catch {
            guard accountSession.isCurrent(account) else { return .failed(.failed) }
            let mapped = OrganiseError.from(error) ?? .failed
            slots[listId] = before
            rebuildLists()
            switch mapped {
            case .staleList:
                await load(force: true)
                return isRetry ? .failed(.staleList) : .stale(pending)
            case .notFound:
                await load(force: true)
                return .failed(.notFound)
            default:
                return .failed(mapped)
            }
        }
    }

    // MARK: Remove and Undo

    /// Removes one title from one list (a one-list delta). Nil (no Undo) when the removal failed, or the
    /// title is no longer tracked (a re-add would be refused).
    func remove(_ key: MediaKey, from listId: UUID) async -> CustomListRemoval? {
        guard isEnabled, let client, let account = accountSession.current,
              let slot = slots[listId]?.first(where: { $0.key == key }) else { return nil }
        let params = RPCOrganisationDeltaParams(p_medium: key.kind.rawValue, p_media_id: key.id, p_add_tags: [],
                                                p_remove_tags: [], p_add_list_ids: [], p_remove_list_ids: [listId])
        do {
            let result: OrganisationDeltaResult = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("apply_title_organisation_delta_v1", params: params).execute().value
            }
            guard accountSession.isCurrent(account) else { return nil }
            slots[listId] = (slots[listId] ?? []).filter { $0.key != key }
            let changed = result.lists.first { $0.listId == listId }
            if let changed, meta[listId]?.revision == changed.revisionBefore { meta[listId]?.revision = changed.revision }
            rebuildLists()
            guard isTracked(key) else { return nil }
            return CustomListRemoval(listId: listId, slot: slot, revisionAfter: changed?.revision ?? meta[listId]?.revision ?? 0,
                                     account: account)
        } catch {
            return nil
        }
    }

    /// Re-adds the removed title; it goes back to its old place only when nothing else changed the list since.
    func undo(_ removal: CustomListRemoval) async -> Bool {
        guard isEnabled, let client, accountSession.isCurrent(removal.account) else { return false }
        let account = removal.account
        let key = removal.slot.key
        let params = RPCOrganisationDeltaParams(p_medium: key.kind.rawValue, p_media_id: key.id, p_add_tags: [],
                                                p_remove_tags: [], p_add_list_ids: [removal.listId], p_remove_list_ids: [])
        do {
            let result: OrganisationDeltaResult = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("apply_title_organisation_delta_v1", params: params).execute().value
            }
            guard accountSession.isCurrent(account) else { return false }
            apply(TitleOrganisation(tags: result.tags, items: result.items, changedLists: result.lists), for: key)
            guard let change = result.lists.first(where: { $0.listId == removal.listId }),
                  change.revisionBefore == removal.revisionAfter,
                  let readded = result.items.first(where: { $0.listId == removal.listId }) else { return true }
            let others = (slots[removal.listId] ?? []).filter { $0.itemId != readded.itemId }
            let after = others.filter { $0.position < removal.slot.position }.map(\.position).max()
            let before = others.filter { $0.position > removal.slot.position }.map(\.position).min()
            guard let before else { return true }   // it was last: already in place
            do {
                let moved: MoveResult = try await accountSession.withCredentialLease(for: account) {
                    try await client.rpc("move_custom_list_item_v1", params: RPCMoveParams(
                        p_list_id: removal.listId, p_item_id: readded.itemId, p_after_position: after,
                        p_before_position: before, p_expected_list_revision: change.revision)).execute().value
                }
                guard accountSession.isCurrent(account) else { return true }
                slots[removal.listId] = (slots[removal.listId] ?? []).map {
                    $0.itemId == moved.itemId ? CustomListSlot(itemId: $0.itemId, key: $0.key, position: moved.position) : $0
                }
                meta[removal.listId]?.revision = moved.revision
                rebuildLists()
            } catch {
                if OrganiseError.from(error) == .staleList, accountSession.isCurrent(account) { await load(force: true) }
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: Export and import

    /// W2's ordered list objects; nil unless loaded (so an export reports "could not load", not "no lists").
    func exportLists() -> [ExportCustomList]? {
        guard loadState == .loaded else { return nil }
        return lists.map { list in
            ExportCustomList(id: list.id, name: list.name, createdAt: meta[list.id]?.createdAt ?? .distantPast,
                             items: CustomListOrder.ordered(slots[list.id] ?? []).map(\.key))
        }
    }

    /// Custom-list names the import carried and no Kuro list has yet, grouped case-insensitively (first
    /// spelling wins), keys in library order.
    func importedListNames() -> [(name: String, keys: [MediaKey])] {
        guard let library else { return [] }
        let existing = Set(names.values.map(LibraryTagRules.key))
        let entries = library.allEntries.sorted {
            $0.key.kind == $1.key.kind ? $0.key.id < $1.key.id : $0.key.kind.rawValue < $1.key.kind.rawValue
        }
        var order: [String] = []
        var spelling: [String: String] = [:]
        var keys: [String: [MediaKey]] = [:]
        for entry in entries {
            for raw in entry.sourceMetadata?.customLists ?? [] {
                guard let clean = LibraryTagRules.normalised(raw) else { continue }
                let id = clean.lowercased()
                if spelling[id] == nil { spelling[id] = clean; order.append(id) }
                if keys[id]?.contains(entry.key) != true { keys[id, default: []].append(entry.key) }
            }
        }
        return order.filter { !existing.contains($0) }.compactMap { id in spelling[id].map { ($0, keys[id] ?? []) } }
    }

    /// ONE seed request for every imported name, then a reload.
    func seedFromImport() async -> Result<CustomListSeedReport, OrganiseError> {
        guard isEnabled else { return .failure(.unavailable) }
        let wanted = importedListNames()
        if wanted.isEmpty { return .success(CustomListSeedReport(created: [], reused: [], skipped: [], added: 0)) }
        guard let client, let account = accountSession.current else { return .failure(.failed) }
        let params = RPCSeedParams(p_lists: wanted.prefix(60).map { entry in
            RPCSeedParams.Entry(name: entry.name, items: entry.keys.prefix(2000).map {
                RPCSeedParams.Item(medium: $0.kind.rawValue, media_id: $0.id)
            })
        })
        do {
            let result: SeedResult = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("seed_custom_lists_v1", params: params).execute().value
            }
            guard accountSession.isCurrent(account) else { return .failure(.failed) }
            await load(force: true)
            return .success(CustomListSeedReport(created: result.created, reused: result.reused,
                                                 skipped: result.skipped.map(\.name), added: result.added))
        } catch {
            return .failure(OrganiseError.from(error) ?? .failed)
        }
    }

    // MARK: Hydration (public catalogue read, no lease)

    func hydrate(_ keys: [MediaKey]) async {
        guard let client, let account = accountSession.current else { return }
        let missing = keys.filter { media[$0] == nil }
        for kind in [MediaKind.anime, .manga] {
            let ids = Array(missing.filter { $0.kind == kind }.map(\.id).prefix(30))
            if ids.isEmpty { continue }
            do {
                let rows: [CatalogRow] = try await client.from(kind == .anime ? "anime" : "manga")
                    .select(kind == .anime
                        ? "id,title_english,title_romaji,title_native,cover_image_large,episodes"
                        : "id,title_english,title_romaji,title_native,cover_image_large,chapters")
                    .in("id", values: ids).limit(30).execute().value
                guard accountSession.isCurrent(account), !Task.isCancelled else { return }
                for row in rows { media[MediaKey(kind: kind, id: row.id)] = row.media(kind: kind) }
            } catch {
                return
            }
        }
    }

    // MARK: Called by the tag owner

    /// A delta save's server state for one title: updates its membership, and adopts a changed list's revision
    /// only when this device saw the revision the change started from (otherwise the next move is refused and
    /// the list reloads, instead of moving against an order this device has not seen).
    func apply(_ organisation: TitleOrganisation, for key: MediaKey) {
        let inLists = Dictionary(organisation.items.map { ($0.listId, $0) }, uniquingKeysWith: { first, _ in first })
        for listId in names.keys {
            var current = slots[listId] ?? []
            let existing = current.firstIndex { $0.key == key }
            if let row = inLists[listId] {
                let slot = CustomListSlot(itemId: row.itemId, key: key, position: row.position)
                if let existing { current[existing] = slot } else { current.append(slot) }
            } else if let existing {
                current.remove(at: existing)
            }
            slots[listId] = CustomListOrder.ordered(current)
        }
        for change in organisation.changedLists where meta[change.listId]?.revision == change.revisionBefore {
            meta[change.listId]?.revision = change.revision
        }
        rebuildLists()
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        generation += 1
        if loadState == .loading { loadState = .notLoaded }
    }

    func clearPrivateState() {
        cancelAccountWork()
        clearLists()
        media = [:]
        loadState = .notLoaded
    }

    // MARK: Helpers

    private func clearLists() {
        names = [:]; meta = [:]; slots = [:]; busyLists = []
        lists = []
    }

    private func rebuildLists() {
        lists = names.sorted { LibraryTagRules.key($0.value) < LibraryTagRules.key($1.value) }.map { id, name in
            CustomList(id: id, name: name, items: CustomListOrder.ordered(slots[id] ?? []).map(\.key))
        }
    }

    private static func cleanName(_ raw: String) -> String? {
        guard let clean = LibraryTagRules.normalised(raw), LibraryTagRules.length(clean) <= 60 else { return nil }
        return clean
    }

    private static func date(_ raw: String?) -> Date {
        guard let raw else { return .distantPast }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw) ?? .distantPast
    }
}
#endif
