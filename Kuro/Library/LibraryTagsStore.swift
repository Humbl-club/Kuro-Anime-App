import Foundation
import KuroCore
import Observation

#if canImport(Supabase)
import Supabase

// MARK: - Library tags (W9)
// The account's tag index and the one atomic organisation write (tags and list membership of one title,
// as a delta). Behind `library_organise_v1`: the switch is read at call time, before any request, so a
// switch that is off sends nothing and the UI reads `.unavailable`. Every private request runs inside
// the account's credential lease; nothing is published unless the captured context is still current.
// A tag is only ever added for a title the person tracks (the database enforces it); the strip and the
// filter count tracked titles only.

@MainActor
@Observable
final class LibraryTagsStore: AccountScopedState {
    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let accountSession: AccountSessionCoordinator
    @ObservationIgnored private let flags: FeatureFlags
    /// Applies the list half of an organise result.
    @ObservationIgnored weak var customLists: CustomListsStore?
    @ObservationIgnored private var generation = 0

    private(set) var tagsByKey: [MediaKey: [String]] = [:]
    private(set) var loadState: OrganiseLoadState = .notLoaded

    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, flags: FeatureFlags) {
        self.client = client
        self.accountSession = accountSession
        self.flags = flags
    }

    /// Read at call time (flags hydrate after launch and carry per-account overrides).
    var isEnabled: Bool { flags.libraryOrganiseV1Enabled }

    // MARK: Reading

    func tags(for key: MediaKey) -> [String] { tagsByKey[key] ?? [] }

    /// Distinct tags (by case-insensitive key) of tracked titles, sorted by key.
    func allTags(kind: MediaKind?, tracked: Set<MediaKey>) -> [String] {
        var spelling: [String: String] = [:]
        let ordered = tagsByKey.keys.filter { tracked.contains($0) && (kind == nil || $0.kind == kind) }
            .sorted { $0.kind.rawValue == $1.kind.rawValue ? $0.id < $1.id : $0.kind.rawValue < $1.kind.rawValue }
        for key in ordered {
            for tag in tagsByKey[key] ?? [] where spelling[LibraryTagRules.key(tag)] == nil {
                spelling[LibraryTagRules.key(tag)] = tag
            }
        }
        return spelling.keys.sorted().compactMap { spelling[$0] }
    }

    /// Tracked titles carrying `tag` (case-insensitive), over the whole index, not the loaded pages.
    func keys(taggedWith tag: String, among tracked: Set<MediaKey>) -> Set<MediaKey> {
        let wanted = LibraryTagRules.key(tag)
        return Set(tagsByKey.compactMap { key, tags in
            tracked.contains(key) && tags.contains { LibraryTagRules.key($0) == wanted } ? key : nil
        })
    }

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
            let rows: [TagIndexRow] = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("library_tag_index_v1").execute().value
            }
            guard mine == generation, accountSession.isCurrent(account) else { return }
            var index: [MediaKey: [String]] = [:]
            for row in rows { if let key = row.key { index[key] = row.tags } }
            tagsByKey = index
            loadState = .loaded
        } catch {
            guard mine == generation, accountSession.isCurrent(account) else { return }
            switch OrganiseError.from(error) {
            case .unavailable?: loadState = .unavailable; tagsByKey = [:]
            case nil: loadState = .notLoaded
            default: loadState = .failed
            }
        }
    }

    // MARK: Writing

    /// One atomic delta write. Publishes the server's tags (not the client's input) and hands the list half
    /// to `customLists`, only while the captured context is current.
    func saveOrganisation(_ delta: TitleOrganisationDelta) async -> Result<TitleOrganisation, OrganiseError> {
        guard isEnabled else { return .failure(.unavailable) }
        if delta.isEmpty {
            return .success(TitleOrganisation(tags: tags(for: delta.key), items: [], changedLists: []))
        }
        for tag in delta.addTags {
            guard let normalised = LibraryTagRules.normalised(tag), LibraryTagRules.length(normalised) <= LibraryTagRules.maxLength
            else { return .failure(.tagTooLong) }
        }
        guard let client, let account = accountSession.current else { return .failure(.failed) }
        let params = RPCOrganisationDeltaParams(
            p_medium: delta.key.kind.rawValue, p_media_id: delta.key.id,
            p_add_tags: delta.addTags, p_remove_tags: delta.removeTags,
            p_add_list_ids: delta.addListIds, p_remove_list_ids: delta.removeListIds)
        do {
            let result: OrganisationDeltaResult = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("apply_title_organisation_delta_v1", params: params).execute().value
            }
            guard accountSession.isCurrent(account) else { return .failure(.failed) }
            if result.tags.isEmpty { tagsByKey[delta.key] = nil } else { tagsByKey[delta.key] = result.tags }
            let organisation = TitleOrganisation(tags: result.tags, items: result.items, changedLists: result.lists)
            customLists?.apply(organisation, for: delta.key)
            return .success(organisation)
        } catch {
            return .failure(OrganiseError.from(error) ?? .failed)
        }
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        generation += 1
        if loadState == .loading { loadState = .notLoaded }
    }

    func clearPrivateState() {
        cancelAccountWork()
        tagsByKey = [:]
        loadState = .notLoaded
    }
}
#endif
