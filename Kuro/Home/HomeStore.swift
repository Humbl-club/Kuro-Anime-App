import Foundation
import KuroCore
import KuroLibrary
import Observation

#if canImport(Supabase)
import Supabase
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Account-scoped Home projection. Progress is committed to the SQLite outbox before the UI
/// reports success. Club bodies are not written to disk.
@MainActor
@Observable
final class HomeStore: AccountScopedState {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var medium = "anime"
    private(set) var anime: HomeBundle?
    private(set) var manga: HomeBundle?
    private(set) var loadState: LoadState = .idle
    private var localStatusMessage: String?
    private(set) var statusMessage: String? {
        get { localStatusMessage ?? library.progressMessage }
        set { localStatusMessage = newValue }
    }
    private(set) var storageUnavailable: String?
    var conflict: HomeProgressConflict? {
        guard let value = library.progressConflict else { return nil }
        let medium = value.key.kind.rawValue.lowercased()
        return HomeProgressConflict(key: "\(medium):\(value.key.id)",
            title: (medium == "manga" ? manga : anime)?.active.first { $0.mediaId == value.key.id }?.title ?? "This title",
            localPosition: value.localPosition, serverPosition: value.serverPosition,
            serverRevision: value.serverRevision, lifecycleId: value.lifecycleId,
            medium: medium, mediaId: value.key.id)
    }
    var privacyEpoch: Int { permissionGeneration }
    var conflictToken: LibraryProgressConflict? { library.progressConflict }
    private(set) var lastAdvancedKey: MediaKey?
    private(set) var lastAdvancedLifecycle: UUID?
    private var loadGeneration = 0
    private var mediumSelectionGeneration = 0
    private var permissionGeneration = 0
    private var loadingMore = false
    private var loadingEvents=false
    private var eventPageToken: UUID?
    private var pendingPageToken: UUID?
    private var activePageToken: UUID?
    private var loadingPending = false
    private var refreshTask: Task<Void,Never>?
    private var refreshDeferrals = 0
    private var refreshDeferred = false
    private var snapshotAccount: AccountContext?
    private(set) var cachedSnapshotDates: [String: Date] = [:]
    private let personalSnapshots: HomePersonalSnapshotCache

    #if canImport(Supabase)
    private let client: SupabaseClient?
    #endif
    private let accountSession: AccountSessionCoordinator
    private let library: LibraryStore

    #if canImport(Supabase)
    init(client: SupabaseClient?, accountSession: AccountSessionCoordinator, library: LibraryStore, outbox: ProgressOutbox? = nil, progressSender: (any HomeProgressSending)? = nil, progressWritesEnabled: @escaping @MainActor @Sendable () -> Bool = { true }, personalSnapshots: HomePersonalSnapshotCache = HomePersonalSnapshotCache()) {
        self.client = client
        let sender = progressSender ?? client.map { SupabaseHomeProgressSender(client: $0) }
        self.accountSession = accountSession
        self.library = library
        self.personalSnapshots = personalSnapshots
        if let storage = outbox ?? Self.makeOutbox() {
            configureProgress(storage: storage, sender: sender, acceptsWrites: progressWritesEnabled)
        } else {
            storageUnavailable = "Progress could not be saved on this device."
        }
    }
    #else
    init(accountSession: AccountSessionCoordinator, library: LibraryStore, outbox: ProgressOutbox? = nil, progressSender: (any HomeProgressSending)? = nil, personalSnapshots: HomePersonalSnapshotCache = HomePersonalSnapshotCache()) {
        self.accountSession = accountSession
        self.library = library
        self.personalSnapshots = personalSnapshots
        if let outbox { configureProgress(storage: outbox, sender: progressSender) }
    }
    #endif

    #if canImport(Supabase)
    func detailBundle(medium: String, mediaId: Int, sectionId: String?) async throws -> SeriesDetailBundle {
        guard let account = accountSession.current, let client else { throw CancellationError() }
        let permissions = permissionGeneration
        let loaded: SeriesDetailBundle = try await accountSession.withCredentialLease(for: account) {
            try await client.rpc("series_detail_bundle_v1", params: RPCSeriesDetailParams(
                p_medium: medium, p_media_id: mediaId, p_section_id: sectionId
            )).execute().value
        }
        guard accountSession.isCurrent(account), permissionGeneration == permissions else { throw CancellationError() }
        return loaded
    }

    func unitPage(medium: String, mediaId: Int, sectionId: String?, edition: String?, after: SeriesUnitPage.Cursor?) async throws -> SeriesUnitPage {
        guard let account=accountSession.current,let client else { throw CancellationError() }
        let permissions=permissionGeneration
        let page: SeriesUnitPage = try await accountSession.withCredentialLease(for: account) {
            try await client.rpc("series_units_page_v1",params: RPCSeriesUnitPage(p_medium: medium,p_media_id: mediaId,
                p_section_id: sectionId,p_edition_key: edition,p_after_order: after?.order,p_after_id: after?.id)).execute().value
        }
        guard accountSession.isCurrent(account),permissions==permissionGeneration else { throw CancellationError() }
        return page
    }
    func loadEditions(medium: String, mediaId: Int, sectionId: String?, after: String?) async throws -> SeriesEditionPage {
        guard let account = accountSession.current, let client else { throw CancellationError() }
        let permissions = permissionGeneration
        let page: SeriesEditionPage = try await accountSession.withCredentialLease(for: account) {
            try await client.rpc("series_editions_page_v1", params: RPCSeriesEditionPage(
                p_medium: medium, p_media_id: mediaId, p_section_id: sectionId, p_after_key: after
            )).execute().value
        }
        guard accountSession.isCurrent(account), permissions == permissionGeneration else { throw CancellationError() }
        return page
    }
    #endif

    var bundle: HomeBundle? { medium == "manga" ? manga : anime }

    func cancelAccountWork() {
        library.cancelProgressWork()
        refreshTask?.cancel()
        refreshTask = nil
        refreshDeferrals = 0
        refreshDeferred = false
        eventPageToken = nil
        pendingPageToken = nil
        activePageToken = nil
        loadingPending = false
        loadingEvents = false
        loadingMore = false
    }

    func removeDeletedAccountData(userId: String) async throws {
        defer { UserDefaults.standard.removeObject(forKey: "kuro.home.medium.\(userId.lowercased())") }
        // Cache purge must run even when the SQLite purge reports a storage failure.
        var failure: (any Error)?
        do { try await library.removeDeletedAccountData(accountId: userId) } catch { failure = error }
        do { try await personalSnapshots.remove(accountId: userId) } catch { if failure == nil { failure = error } }
        if let failure { throw failure }
    }

    func clearPrivateState() {
        loadGeneration += 1
        permissionGeneration += 1
        anime = nil
        manga = nil
        snapshotAccount = nil
        cachedSnapshotDates = [:]
        loadState = .idle
        statusMessage = nil
        lastAdvancedKey = nil
        lastAdvancedLifecycle = nil
        medium = "anime"
        mediumSelectionGeneration = 0
    }

    var hasCachedFoundationMetadata: Bool {
        guard snapshotAccount == accountSession.current, !cachedSnapshotDates.isEmpty else { return false }
        for requested in cachedSnapshotDates.keys {
            let kind: MediaKind = requested == "manga" ? .manga : .anime
            let cards = (requested == "manga" ? manga : anime)?.active ?? []
            for card in cards {
                guard let row = library.entry(for: MediaKey(kind: kind, id: card.mediaId)), row.revision != nil,
                      row.lifecycleId == UUID(uuidString: card.lifecycleId) else { return false }
            }
        }
        return true
    }
    var isUsingCachedSnapshot: Bool { cachedSnapshotDates[medium] != nil }

    private func cacheMatchesKnownLibrary(_ cached: HomeBundle) -> Bool {
        let kind: MediaKind = cached.medium == "manga" ? .manga : .anime
        return cached.active.allSatisfy { card in
            switch library.entry(for: LibraryKnowledgeQuery(MediaKey(kind: kind, id: card.mediaId))) {
            case .unknown: return true // A partial snapshot cannot establish absence.
            case .untracked: return false
            case .tracked(let row):
                return row.lifecycleId == UUID(uuidString: card.lifecycleId)
                    && (row.status == .current || row.status == .planning)
            }
        }
    }

    /// A complete Library refresh can invalidate a snapshot restored before it finished.
    private func discardObsoleteCachedBundles() {
        for requested in Array(cachedSnapshotDates.keys) {
            guard let cached = requested == "manga" ? manga : anime,
                  !cacheMatchesKnownLibrary(cached) else { continue }
            if requested == "manga" { manga = nil } else { anime = nil }
            cachedSnapshotDates[requested] = nil
        }
    }

    enum SnapshotSelectionPolicy { case restorePreference, preserveSelection }

    /// Only authenticated/restored account identity selects a file. Club bodies remain unavailable
    /// until fetched through current authorization; cached tracking stays partial Library knowledge.
    @discardableResult
    func restorePersonalSnapshot(for account: AccountContext, selection: SnapshotSelectionPolicy = .restorePreference) async -> Bool {
        guard accountSession.isCurrent(account) else { return false }
        let request = loadGeneration, selectedAt = mediumSelectionGeneration
        let mayRestoreSelection = selection == .restorePreference && selectedAt == 0
        if mayRestoreSelection { restoreMedium() }
        for requested in ["anime", "manga"] {
            guard let snapshot = await personalSnapshots.read(accountId: account.userId, medium: requested) else { continue }
            guard accountSession.isCurrent(account), request == loadGeneration else { return false }
            let prior = requested == "manga" ? manga : anime
            guard prior == nil || snapshot.revision > (prior?.homeRevision ?? -1) else { continue }
            let restored = snapshot.bundle
            guard cacheMatchesKnownLibrary(restored) else { continue }
            if requested == "manga" { manga = restored } else { anime = restored }
            let kind: MediaKind = requested == "manga" ? .manga : .anime
            library.restoreCachedProgressBaselines(snapshot.tracking.map { $0.entry(medium: kind) }, account: account)
            snapshotAccount = account
            cachedSnapshotDates[requested] = snapshot.savedAt
        }
        guard accountSession.isCurrent(account), request == loadGeneration else { return false }
        discardObsoleteCachedBundles()
        await restorePendingProjection()
        guard accountSession.isCurrent(account), request == loadGeneration else { return false }
        if mayRestoreSelection, selectedAt == mediumSelectionGeneration {
            if bundle == nil, anime != nil { medium = "anime" }
            if bundle == nil, manga != nil { medium = "manga" }
        }
        if bundle != nil, hasCachedFoundationMetadata {
            loadState = .loaded
            statusMessage = "Showing saved Home. Club content needs a connection."
        }
        return hasCachedFoundationMetadata
    }

    /// Persists only an accepted server bundle and confirmed rows, never fixture seeding or pending
    /// optimistic values. Cache failure does not weaken the Library disk commitment.
    func persistPersonalSnapshot(_ accepted: HomeBundle, for account: AccountContext) async {
        guard accountSession.isCurrent(account) else { return }
        let kind: MediaKind = accepted.medium == "manga" ? .manga : .anime
        var baselines: [MediaKey: LibraryEntry] = [:]
        for card in accepted.active.prefix(12) {
            let key = MediaKey(kind: kind, id: card.mediaId)
            baselines[key] = library.progressBaseline(for: key)
        }
        guard let snapshot = HomePersonalSnapshot(accountId: account.userId, bundle: accepted, baselines: baselines) else { return }
        do { try await personalSnapshots.write(snapshot) } catch {
            #if DEBUG
            print("[Home] personal snapshot unavailable: \(error)")
            #endif
        }
    }

    /// Fixed-bundle seed for composition screenshots. Does not hit the network.
    func seedForVisualQA(anime: HomeBundle?, manga: HomeBundle?, medium: String = "anime") {
        self.anime = anime
        self.manga = manga
        if medium == "anime" || medium == "manga" {
            self.medium = medium
        }
        loadState = .loaded
        statusMessage = nil
    }

    func selectMedium(_ next: String) {
        guard next == "anime" || next == "manga", next != medium else { return }
        mediumSelectionGeneration += 1
        medium = next
        if let userId = accountSession.current?.userId.lowercased() {
            UserDefaults.standard.set(next, forKey: "kuro.home.medium.\(userId)")
        }
        if bundle == nil { Task { await load() } }
    }

    func restoreMedium() {
        guard let userId = accountSession.current?.userId.lowercased() else { return }
        let stored = UserDefaults.standard.string(forKey: "kuro.home.medium.\(userId)")
        if stored == "manga" || stored == "anime" { medium = stored ?? "anime" }
    }

    func load() async {
        guard let account = accountSession.current else {
            loadState = .failed("Sign in to see your Home.")
            return
        }
        if bundle == nil { _ = await restorePersonalSnapshot(for: account, selection: .preserveSelection) }
        await restorePendingProjection()
        guard accountSession.isCurrent(account) else { return }
        discardObsoleteCachedBundles()
        let requested = medium
        let generation = account.generation
        loadGeneration += 1
        let request = loadGeneration
        let permissions = permissionGeneration
        loadState = .loading
        #if canImport(Supabase)
        guard let client else {
            loadState = .failed("Home is not configured.")
            return
        }
        do {
            let bundle: HomeBundle = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("home_bundle_v1", params: RPCHomeBundleParams(
                    p_medium: requested,
                    p_window_days: 7,
                    p_active_limit: 12,
                    p_event_limit: 20,
                    p_cursor: nil
                ))
                .execute()
                .value
            }
            guard accountSession.current?.generation == generation, medium == requested,
                  request == loadGeneration, permissions == permissionGeneration else { return }
            let prior=requested == "manga" ? manga : anime
            if bundle.homeRevision >= (prior?.homeRevision ?? 0) {
                if requested == "manga" { manga = bundle } else { anime = bundle }
            }
            loadState = .loaded
            cachedSnapshotDates[requested] = nil
            statusMessage = nil
            await persistPersonalSnapshot(bundle, for: account)
        } catch {
            guard accountSession.current?.generation == generation, medium == requested,
                  request == loadGeneration, permissions == permissionGeneration else { return }
            if isUsingCachedSnapshot, self.bundle != nil {
                loadState = .loaded
                statusMessage = "Showing saved Home. Club content needs a connection."
            } else { loadState = .failed("Home could not be loaded.") }
            #if DEBUG
            print("[Home] bundle failed: \(error.localizedDescription)")
            #endif
        }
        #else
        if isUsingCachedSnapshot {
            loadState = .loaded
            statusMessage = "Showing saved Home. Club content needs a connection."
        } else { loadState = .failed("Home is not configured.") }
        #endif
    }

    /// Import is ready only after BOTH medium projections meet their committed revision floor.
    /// This prewarms empty/unmounted Home without changing the user's persistent medium.
    func prepareImportHome(revisions:[String:Int64],for account:AccountContext) async throws {
        guard accountSession.isCurrent(account) else { throw CancellationError() }
        guard !revisions.isEmpty else { return }
        guard revisions.allSatisfy({ ["anime","manga"].contains($0.key) && $0.value >= 0 }) else {
            throw LibraryError.invalidValue(field: "Home revision")
        }
        let permissions=permissionGeneration
        #if canImport(Supabase)
        guard let client else { throw MissingSupabaseConfiguration() }
        for requested in ["anime","manga"] where revisions[requested] != nil {
            var adopted=false
            for attempt in 0..<3 {
                try Task.checkCancellation()
                guard accountSession.isCurrent(account),permissions==permissionGeneration else { throw CancellationError() }
                let loaded:HomeBundle = try await accountSession.withCredentialLease(for:account) {
                    try await client.rpc("home_bundle_v1",params:RPCHomeBundleParams(p_medium:requested,p_window_days:7,
                        p_active_limit:12,p_event_limit:20,p_cursor:nil)).execute().value
                }
                guard accountSession.isCurrent(account),permissions==permissionGeneration else { throw CancellationError() }
                if loaded.homeRevision >= (revisions[requested] ?? 0) {
                    let prior=requested == "manga" ? manga : anime
                    if loaded.homeRevision >= (prior?.homeRevision ?? 0) {
                        if requested == "manga" { manga=loaded } else { anime=loaded }
                    }
                    cachedSnapshotDates[requested] = nil
                    await persistPersonalSnapshot(loaded, for: account)
                    adopted=true; break
                }
                if attempt<2 { try await Task.sleep(nanoseconds:UInt64(attempt+1)*250_000_000) }
            }
            guard adopted else { throw NSError(domain:"KuroImport",code:5,userInfo:[NSLocalizedDescriptionKey:"Your list is saved. Home is still catching up; retry to finish."]) }
        }
        loadState = .loaded
        await restorePendingProjection()
        #else
        throw CancellationError()
        #endif
    }

    func loadMoreEvents() async {
        #if canImport(Supabase)
        guard !loadingEvents,let account=accountSession.current,let cursor=bundle?.eventsCursor else { return }
        let requested=medium,permissions=permissionGeneration,generation=loadGeneration
        let token=UUID(); eventPageToken=token
        loadingEvents=true
        defer { if eventPageToken==token { loadingEvents=false; eventPageToken=nil } }
        do {
            guard let client else { throw MissingSupabaseConfiguration() }
            let page:HomeEventPage=try await accountSession.withCredentialLease(for:account) {
                try await client.rpc("home_events_page_v1",params:RPCHomeEventPage(p_medium:requested,p_window_days:7,p_cursor:cursor)).execute().value
            }
            guard accountSession.isCurrent(account),medium==requested,permissions==permissionGeneration,
                  generation==loadGeneration,eventPageToken==token,var current=bundle,current.eventsCursor==cursor else { return }
            current.upcoming += page.items.filter { item in !current.upcoming.contains(where:{$0.id==item.id}) }
            current.upcomingTotal=page.total; current.eventsCursor=page.nextCursor
            if requested=="manga" { manga=current } else { anime=current }
        } catch {
            if accountSession.isCurrent(account),medium==requested,permissions==permissionGeneration,generation==loadGeneration,eventPageToken==token {
                statusMessage="More dates could not be loaded. Try again."
            }
        }
        #endif
    }

    func loadMorePending() async {
        #if canImport(Supabase)
        guard !loadingPending, let account = accountSession.current, let cursor = bundle?.pendingCursor else { return }
        let requested = medium, permissions = permissionGeneration, generation = loadGeneration
        let token = UUID(); pendingPageToken = token
        loadingPending = true
        defer { if pendingPageToken == token { loadingPending = false; pendingPageToken = nil } }
        do {
            guard let client else { throw MissingSupabaseConfiguration() }
            let page: HomeEventPage = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("home_pending_page_v1", params: RPCHomePendingPage(p_medium: requested, p_cursor: cursor)).execute().value
            }
            guard accountSession.isCurrent(account), medium == requested, permissions == permissionGeneration,
                  generation == loadGeneration, pendingPageToken == token, var current = bundle, current.pendingCursor == cursor else { return }
            current.pending += page.items.filter { item in !current.pending.contains(where: { $0.id == item.id }) }
            current.pendingTotal = page.total; current.pendingCursor = page.nextCursor
            if requested == "manga" { manga = current } else { anime = current }
        } catch {
            if accountSession.isCurrent(account), medium == requested, permissions == permissionGeneration,
               generation == loadGeneration, pendingPageToken == token {
                statusMessage = "More announcements could not be loaded. Try again."
            }
        }
        #endif
    }

    func loadMore() async {
        guard !loadingMore else { return }
        guard let cursor = bundle?.nextCursor, !cursor.isEmpty else { return }
        guard let account = accountSession.current else { return }
        let requested = medium
        let generation = account.generation
        #if canImport(Supabase)
        guard let client else { return }
        loadingMore = true
        let token = UUID(); activePageToken = token
        let request = loadGeneration
        let permissions = permissionGeneration
        defer { if activePageToken == token { loadingMore = false; activePageToken = nil } }
        do {
            let page: HomeBundle = try await accountSession.withCredentialLease(for: account) {
                try await client.rpc("home_bundle_v1", params: RPCHomeBundleParams(
                    p_medium: requested,
                    p_window_days: 7,
                    p_active_limit: 12,
                    p_event_limit: 20,
                    p_cursor: cursor
                ))
                .execute()
                .value
            }
            guard accountSession.current?.generation == generation, medium == requested,
                  request == loadGeneration, permissions == permissionGeneration, activePageToken == token,
                  var current = bundle, current.nextCursor == cursor else { return }
            current = current.appendingActive(page.active, cursor: page.nextCursor)
            if requested == "manga" { manga = current } else { anime = current }
        } catch {
            guard accountSession.isCurrent(account), request == loadGeneration,
                  permissions == permissionGeneration, medium == requested else { return }
            statusMessage = "More titles could not be loaded."
        }
        #endif
    }

    /// Every surface reads the Library owner's durable projection.
    func pendingPosition(medium: String, mediaId: Int) -> Int? {
        library.pendingProgress(for: progressKey(medium: medium, mediaId: mediaId))?.position
    }

    func displayedProgress(medium: String, mediaId: Int, server: Int, lifecycleId: UUID? = nil) -> Int {
        library.displayedProgress(for: progressKey(medium: medium, mediaId: mediaId), server: server, lifecycleId: lifecycleId)
    }

    func displayedProgressLabel(medium: String, mediaId: Int, serverLabel: String?, lifecycleId: UUID? = nil, serverRevision: Int64? = nil) -> String? {
        library.displayedProgressLabel(for: progressKey(medium: medium, mediaId: mediaId), serverLabel: serverLabel, lifecycleId: lifecycleId, serverRevision: serverRevision)
    }

    func displayedUnitId(medium: String, mediaId: Int, serverUnitId: String?, lifecycleId: UUID? = nil, serverRevision: Int64? = nil) -> String? {
        library.displayedUnitId(for: progressKey(medium: medium, mediaId: mediaId),
            serverUnitId: serverUnitId.flatMap(UUID.init(uuidString:)), lifecycleId: lifecycleId, serverRevision: serverRevision)?.uuidString
    }

    func displayedProgress(for card: HomeCard) -> Int {
        displayedProgress(medium: medium, mediaId: card.mediaId, server: card.progress, lifecycleId: UUID(uuidString: card.lifecycleId))
    }

    func advance(_ card: HomeCard) async {
        await advance(medium: medium, mediaId: card.mediaId, lifecycleId: card.lifecycleId,
            baseRevision: card.serverRevision, serverProgress: card.progress,
            episodeCap: medium == "manga" ? card.chapters : card.episodes, serverLabel: card.progressLabel, serverUnitId: card.unitId)
    }

    func advance(medium: String, mediaId: Int, lifecycleId: String, baseRevision: Int64,
                 serverProgress: Int, episodeCap: Int? = nil, serverLabel: String? = nil, serverUnitId: String? = nil) async {
        guard let account = accountSession.current, let lifecycle = UUID(uuidString: lifecycleId) else { return }
        let current = displayedProgress(medium: medium, mediaId: mediaId, server: serverProgress, lifecycleId: lifecycle)
        if displayedUnitId(medium: medium, mediaId: mediaId, serverUnitId: serverUnitId, lifecycleId: lifecycle, serverRevision: baseRevision) != nil {
            statusMessage = "Choose the next episode or chapter in its details."
            return
        }
        if let label = displayedProgressLabel(medium: medium, mediaId: mediaId, serverLabel: serverLabel, lifecycleId: lifecycle, serverRevision: baseRevision), Int(label) != current {
            statusMessage = "Choose the next episode or chapter in its details."
            return
        }
        if let episodeCap, current >= episodeCap { statusMessage = "Caught up"; return }
        guard library.progressAvailable else { statusMessage = storageUnavailable ?? "Progress could not be saved on this device."; return }
        do {
            _ = try await library.storeProgress(ProgressIntent(accountId: account.userId.lowercased(), medium: medium,
                mediaId: mediaId, lifecycleId: lifecycle, baseRevision: baseRevision,
                position: current, priorPosition: current), advancing: true, cap: episodeCap)
            guard accountSession.isCurrent(account) else { return }
            lastAdvancedKey = progressKey(medium: medium, mediaId: mediaId)
            lastAdvancedLifecycle = lifecycle
            statusMessage = nil
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } catch { if accountSession.isCurrent(account) { statusMessage = "Progress could not be saved on this device." } }
    }

    func setPosition(medium: String, mediaId: Int, user: SeriesDetailBundle.UserState, position: Int,
                     unitId: String? = nil, label: String? = nil) async {
        guard let account = accountSession.current, let lifecycle = UUID(uuidString: user.lifecycleId), position >= 0 else { return }
        do {
            _ = try await library.storeProgress(ProgressIntent(accountId: account.userId.lowercased(), medium: medium,
                mediaId: mediaId, lifecycleId: lifecycle, unitId: unitId.flatMap(UUID.init(uuidString:)),
                baseRevision: user.serverRevision, position: position, positionLabel: label,
                priorPosition: displayedProgress(medium: medium, mediaId: mediaId, server: user.progress, lifecycleId: lifecycle)))
            if accountSession.isCurrent(account) { statusMessage = nil }
        } catch { if accountSession.isCurrent(account) { statusMessage = "Progress could not be saved on this device." } }
    }

    func undo(_ card: HomeCard) async {
        guard let account = accountSession.current, let lifecycle = UUID(uuidString: card.lifecycleId) else { return }
        guard lastAdvancedKey == progressKey(medium: medium,mediaId: card.mediaId),lastAdvancedLifecycle == lifecycle else { return }
        do {
            try await library.undoProgress(for: progressKey(medium: medium, mediaId: card.mediaId), lifecycleId: lifecycle)
            if accountSession.isCurrent(account) { statusMessage = nil }
        } catch {
            if accountSession.isCurrent(account) {
                statusMessage = (error as? LibraryError).map(LibraryActions.libraryErrorDescription) ?? "Progress could not be saved on this device."
            }
        }
    }

    func keepServerProgress(expected: LibraryProgressConflict? = nil) async { await resolveProgressConflict(reapply: false, expected: expected) }
    func reapplyLocalProgress(expected: LibraryProgressConflict? = nil) async { await resolveProgressConflict(reapply: true, expected: expected) }
    private func resolveProgressConflict(reapply: Bool, expected: LibraryProgressConflict?) async {
        guard let account = accountSession.current else { return }
        do {
            try await library.resolveProgressConflict(reapply: reapply, expected: expected)
            if accountSession.isCurrent(account) { statusMessage = nil }
        } catch { if accountSession.isCurrent(account) { statusMessage = "Progress could not be saved on this device." } }
    }

    private func progressKey(medium: String, mediaId: Int) -> MediaKey {
        MediaKey(kind: medium == "manga" ? .manga : .anime, id: mediaId)
    }

    /// Membership changes invalidate cached bodies immediately, including requests in flight.
    func invalidateClubContent() {
        permissionGeneration += 1
        anime = anime?.withoutClubContent()
        manga = manga?.withoutClubContent()
    }

    func libraryDidChange(_ change: LibraryChange) {
        guard accountSession.isCurrent(change.account) else { return }
        guard !change.isProgressOnly else { return }
        // Progress receipts patch locally. Add/remove/status changes need a fresh bounded bundle.
        if !change.isProgressOnly { requestLibraryRefresh() }
    }

    func beginLibraryBatch() { refreshDeferrals += 1 }
    func endLibraryBatch() {
        refreshDeferrals = max(0,refreshDeferrals-1)
        if refreshDeferrals == 0,refreshDeferred { refreshDeferred=false; requestLibraryRefresh() }
    }
    private func requestLibraryRefresh() {
        if refreshDeferrals > 0 { refreshDeferred=true; return }
        refreshTask?.cancel()
        let account=accountSession.current
        refreshTask=Task { [weak self] in
            do { try await Task.sleep(for:.milliseconds(150)) } catch { return }
            guard let self,!Task.isCancelled,self.accountSession.isCurrent(account) else { return }
            await self.load()
        }
    }

    func restorePendingProjection() async {
        guard let account = accountSession.current else { return }
        do { try await library.restoreProgress() }
        catch { if accountSession.isCurrent(account) { statusMessage = "Saved progress could not be read." } }
    }

    func drain() async { await library.drainProgress() }

    private func configureProgress(storage: ProgressOutbox, sender: (any HomeProgressSending)?, acceptsWrites: @escaping @MainActor @Sendable () -> Bool = { true }) {
        let session = accountSession
        library.configureProgress(outbox: storage, acceptsWrites: acceptsWrites) { intents, account in
            guard let sender else { throw MissingSupabaseConfiguration() }
            let mutations = intents.map { item in
                RPCProgressMutationsParams.Mutation(mutation_id: item.mutationId.uuidString, medium: item.medium,
                    media_id: item.mediaId, lifecycle_id: item.lifecycleId!.uuidString, base_revision: item.baseRevision!,
                    position: item.writesPosition ? item.position : nil, position_label: item.writesPosition ? item.positionLabel : nil,
                    unit_id: item.writesPosition ? item.unitId?.uuidString : nil,
                    status: item.status.map { value in
                        switch value.lowercased() {
                        case "current", "watching", "reading", "repeating": return item.medium == "manga" ? "READING" : "WATCHING"
                        default: return value.uppercased()
                        }
                    })
            }
            let result = try await session.withCredentialLease(for: account) { try await sender.apply(mutations) }
            return result.items.compactMap { item in
                guard let id = UUID(uuidString: item.mutationId) else { return nil }
                return LibraryProgressReceipt(mutationId: id, outcome: item.outcome, position: item.position, revision: item.serverRevision)
            }
        }
    }

    private static func makeOutbox() -> ProgressOutbox? {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = base.appendingPathComponent("Kuro", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:directory.path)
            #endif
            let url = directory.appendingPathComponent("progress-outbox.sqlite")
            return try ProgressOutbox(path: url.path)
        } catch {
            return nil
        }
    }
}

#if canImport(Supabase)
@MainActor
private struct SupabaseHomeProgressSender: HomeProgressSending {
    let client: SupabaseClient
    func apply(_ mutations: [RPCProgressMutationsParams.Mutation]) async throws -> ProgressMutationResult {
        try await client.rpc("apply_progress_mutations_v1",params: RPCProgressMutationsParams(p_mutations: mutations)).execute().value
    }
}
#endif
