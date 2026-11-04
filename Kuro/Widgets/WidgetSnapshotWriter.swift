import Foundation
import KuroCore
import KuroLibrary
import KuroWidgetSupport
import Observation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Widgets (Home Screen) owner
// Writes the CURRENT account's `WidgetSnapshot` into the App Group and drains the widget's +1
// hand-off queue through `LibraryActions` (`WidgetIntentInbox` section below). Nothing here talks to
// the backend directly: releases come from `ReleasesStore`, rows from `LibraryStore`, titles and
// covers from `CatalogStore` (public data) and `ImagePipeline`.
//
// Writing: the inputs are observed (`withObservationTracking` over the schedule, the Library rows and
// the account); any change schedules ONE write after `writeDebounce`. A write that would not change
// the snapshot's content is skipped, and only a real change reloads the widget timelines (WidgetKit's
// reload budget is daily). The app also writes on foreground and before it goes to the background.
//
// Account scope (AccountScopedState): every value is the current account's (an opaque
// `WidgetAccountHash`, never the user id). On a transition (`clearPrivateState`, called by the session
// funnel after `accountSession` already names the next account): signed out → the snapshot, its
// thumbnails and every queued +1 are removed; another account → the same, except that account's own
// queued requests stay; the SAME account restored at launch → the files stay (a widget tap made while
// the app was not running is still applied after the Library loads); a failed offline launch restore
// (no account ended) → the files stay; a failed restore after which the SDK holds no session
// (`removeDataWithoutOwner`) → everything is removed. Deletion removes that account's files as well.
//
// No App Group (an unsigned `CODE_SIGNING_ALLOWED=NO` build has no entitlement): `store` / `queue`
// are nil and the owner does nothing.

/// Reloads the extension's timelines (production: `WidgetCenter`).
@MainActor
protocol WidgetTimelineReloading {
    func reloadTimelines(ofKinds kinds: [String])
}

/// Production reloader.
nonisolated struct LiveWidgetTimelineReloader: WidgetTimelineReloading {
    func reloadTimelines(ofKinds kinds: [String]) {
        #if canImport(WidgetKit)
        for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        #endif
    }
}

/// Small JPEG thumbnails for the snapshot (production: `ImagePipeline`, downsampled).
protocol WidgetThumbnailFetching: Sendable {
    func thumbnailJPEG(from url: URL) async -> Data?
}

nonisolated struct LiveWidgetThumbnailFetcher: WidgetThumbnailFetching {
    /// Pixel size of the longest side (a 34×48 pt cover at 3×).
    static let maxPixelSize = 150

    func thumbnailJPEG(from url: URL) async -> Data? {
        #if canImport(UIKit)
        guard let image = await ImagePipeline.shared.image(url: url, maxPixelSize: Self.maxPixelSize) else { return nil }
        return image.jpegData(compressionQuality: 0.7)
        #else
        return nil
        #endif
    }
}

@MainActor
@Observable
final class WidgetSnapshotWriter: AccountScopedState {
    /// Delay between an input change and the write (coalesces bursts of Library/schedule changes).
    nonisolated static let writeDebounce: Duration = .milliseconds(1500)
    /// Most thumbnails fetched per write.
    nonisolated static let thumbnailsPerWrite = 10
    /// `UserDefaults` key of the per-install salt behind `WidgetAccountHash` (app defaults only).
    nonisolated static let saltKey = "com.kuro.widgets.accountSalt"

    /// The account the writer last served (in memory). Both it and the next account nil means no
    /// account ended (an offline launch whose restore failed): the files stay for their owner.
    @ObservationIgnored private var boundAccount: WidgetAccountHash?
    /// When the last snapshot was written (nil: none for this account yet). Diagnostic only.
    private(set) var lastWrittenAt: Date?
    /// How many queued +1 requests the last drain applied. Diagnostic only.
    private(set) var lastDrainApplied = 0

    @ObservationIgnored let accountSession: AccountSessionCoordinator
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let libraryActions: LibraryActions
    @ObservationIgnored private let releases: ReleasesStore
    @ObservationIgnored private let catalog: CatalogStore
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored let store: WidgetSnapshotStore?
    @ObservationIgnored let queue: WidgetAdvanceQueue?
    @ObservationIgnored private let reloader: any WidgetTimelineReloading
    @ObservationIgnored private let thumbnails: any WidgetThumbnailFetching
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Catalogue facts per title (public data; survives transitions but only feeds the current account).
    @ObservationIgnored private var metadataCache: [MediaKey: WidgetTitleMetadata] = [:]
    /// Content of the last snapshot written for the current account.
    @ObservationIgnored private var lastSnapshot: WidgetSnapshot?
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    @ObservationIgnored private var observing = false
    /// The running queue drain (one at a time; `WidgetIntentInbox`).
    @ObservationIgnored var drainTask: Task<Void, Never>?
    /// Identity of `drainTask` (a finished drain only clears its own slot).
    @ObservationIgnored var drainTaskId: UUID?

    init(
        accountSession: AccountSessionCoordinator,
        library: LibraryStore,
        libraryActions: LibraryActions,
        releases: ReleasesStore,
        catalog: CatalogStore,
        userDefaults: UserDefaults,
        store: WidgetSnapshotStore?,
        queue: WidgetAdvanceQueue?,
        reloader: any WidgetTimelineReloading = LiveWidgetTimelineReloader(),
        thumbnails: any WidgetThumbnailFetching = LiveWidgetThumbnailFetcher(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accountSession = accountSession
        self.library = library
        self.libraryActions = libraryActions
        self.releases = releases
        self.catalog = catalog
        self.userDefaults = userDefaults
        self.store = store
        self.queue = queue
        self.reloader = reloader
        self.thumbnails = thumbnails
        self.now = now
    }

    // MARK: Account tag

    /// The opaque tag of `userId` on this install.
    func accountHash(for userId: String) -> WidgetAccountHash {
        WidgetAccountHash.make(userId: userId, salt: WidgetAccountHash.installSalt(in: userDefaults, key: Self.saltKey))
    }

    var currentAccountHash: WidgetAccountHash? {
        accountSession.current.map { accountHash(for: $0.userId) }
    }

    // MARK: AccountScopedState

    func cancelAccountWork() {
        pendingWrite?.cancel()
        pendingWrite = nil
        drainTask?.cancel()
        drainTask = nil
        drainTaskId = nil
    }

    /// Runs after `accountSession` names the next account (or none): see the file header.
    func clearPrivateState() {
        lastSnapshot = nil
        lastWrittenAt = nil
        lastDrainApplied = 0
        let next = currentAccountHash
        let previous = boundAccount
        boundAccount = next
        // No account ended and none started (a failed offline restore): a +1 tapped while Kuro was
        // closed stays queued for the account that owns it.
        if previous == nil && next == nil { return }
        guard store != nil || queue != nil else { return }
        let written = store?.read()?.account
        if next == nil || written != next {
            store?.clear()
            if written != nil { reloader.reloadTimelines(ofKinds: KuroAppGroup.WidgetKind.all) }
        }
        queue?.retainOnly(account: next)
    }

    /// The SDK holds no session after a failed restore: nobody owns the files any more.
    func removeDataWithoutOwner() {
        guard store?.read() != nil || queue?.all().isEmpty == false else { return }
        store?.clear()
        queue?.retainOnly(account: nil)
        reloader.reloadTimelines(ofKinds: KuroAppGroup.WidgetKind.all)
    }

    func removeDeletedAccountData(userId: String) async throws {
        let deleted = accountHash(for: userId)
        if store?.read()?.account == deleted {
            store?.clear()
            reloader.reloadTimelines(ofKinds: KuroAppGroup.WidgetKind.all)
        }
        queue?.remove(account: deleted)
    }

    // MARK: Writing

    /// Starts observing the inputs (once; composition calls it). Every change schedules a write.
    func startObserving() {
        guard !observing else { return }
        observing = true
        observeInputs()
    }

    private func observeInputs() {
        withObservationTracking {
            _ = library.allEntries
            _ = library.loadState
            _ = releases.schedule
            _ = releases.upcomingAirings
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setNeedsWrite()
                self.drainIfLibraryReady()
                self.observeInputs()
            }
        }
    }

    /// Schedules one write after `writeDebounce` (a newer request replaces a waiting one).
    func setNeedsWrite() {
        guard store != nil, accountSession.current != nil else { return }
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDebounce)
            guard !Task.isCancelled else { return }
            await self?.writeNow()
        }
    }

    /// Builds and writes the current account's snapshot now. Returns whether a new snapshot was written
    /// (false: nothing changed, no account, no App Group, or the account changed meanwhile).
    @discardableResult
    func writeNow() async -> Bool {
        guard let store, let context = accountSession.current else { return false }
        let account = accountHash(for: context.userId)
        let copy = ReleaseCopy.current(now: now())
        let tracked = trackedTitles()
        let schedule = releases.scheduleItems(for: nil, now: copy.now)
        await loadMetadata(for: tracked, releases: schedule)
        guard accountSession.isCurrent(context) else { return false }
        let names = await ensureThumbnails(tracked: tracked, releases: schedule, copy: copy, store: store, context: context)
        guard accountSession.isCurrent(context), !Task.isCancelled else { return false }
        let snapshot = WidgetSnapshotBuilder.build(account: account, now: copy.now, copy: copy, releases: schedule,
                                                   tracked: tracked, metadata: metadataCache, thumbnails: names)
        if let previous = lastSnapshot ?? store.read(), previous.hasSameContent(as: snapshot) {
            lastSnapshot = previous
            return false
        }
        guard store.write(snapshot) else { return false }
        lastSnapshot = snapshot
        lastWrittenAt = snapshot.generatedAt
        store.pruneThumbnails(keeping: Set(names.values))
        reloader.reloadTimelines(ofKinds: KuroAppGroup.WidgetKind.all)
        return true
    }

    /// The current account's Library rows as the snapshot needs them (displayed positions).
    func trackedTitles() -> [WidgetTrackedTitle] {
        library.allEntries.map { entry in
            WidgetTrackedTitle(
                key: entry.key, status: entry.status,
                progress: library.displayedProgress(for: entry.key, server: entry.progress, lifecycleId: entry.lifecycleId),
                lifecycleId: entry.lifecycleId, revision: entry.revision, updatedAt: entry.updatedAt)
        }
    }

    /// Reads catalogue facts for the watching/reading titles the cache does not hold (bounded).
    private func loadMetadata(for tracked: [WidgetTrackedTitle], releases: [ReleaseScheduleItem]) async {
        let wanted = tracked.filter { WidgetSnapshotBuilder.nowWatchingStatuses.contains($0.status) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(WidgetSnapshot.maxNowWatching * 2)
            .map(\.key)
            .filter { metadataCache[$0] == nil }
        guard !wanted.isEmpty else { return }
        let animeIds = wanted.filter { $0.kind == .anime }.map(\.id)
        let mangaIds = wanted.filter { $0.kind == .manga }.map(\.id)
        if !animeIds.isEmpty, let rows = await catalog.fetchAnimeByIdsPreservingOrder(animeIds) {
            for row in rows {
                metadataCache[MediaKey(kind: .anime, id: row.id)] = WidgetTitleMetadata(
                    title: row.displayTitle, total: row.episodeCount,
                    artworkURL: (row.coverImageMedium ?? row.coverImageLarge).flatMap(WidgetSnapshotBuilder.httpsURL))
            }
        }
        if !mangaIds.isEmpty, let rows = await catalog.fetchMangaByIdsPreservingOrder(mangaIds) {
            for row in rows {
                metadataCache[MediaKey(kind: .manga, id: row.id)] = WidgetTitleMetadata(
                    title: row.displayTitle, total: row.chapterCount,
                    artworkURL: (row.coverImageMedium ?? row.coverImageLarge).flatMap(WidgetSnapshotBuilder.httpsURL))
            }
        }
    }

    /// Thumbnail file names for the rows the snapshot will show; missing files are fetched (bounded).
    private func ensureThumbnails(tracked: [WidgetTrackedTitle], releases: [ReleaseScheduleItem],
                                  copy: ReleaseCopy, store: WidgetSnapshotStore,
                                  context: AccountContext) async -> [MediaKey: String] {
        var names: [MediaKey: String] = [:]
        var fetched = 0
        for (key, url) in WidgetSnapshotBuilder.artworkNeeded(tracked: tracked, releases: releases,
                                                               metadata: metadataCache, copy: copy) {
            let name = WidgetSnapshotStore.thumbnailName(medium: key.kind.rawValue, mediaId: key.id, artwork: url)
            if store.hasThumbnail(named: name) {
                names[key] = name
                continue
            }
            guard fetched < Self.thumbnailsPerWrite, !Task.isCancelled else { continue }
            fetched += 1
            guard let data = await thumbnails.thumbnailJPEG(from: url) else { continue }
            // The account may have ended during the fetch (sign-out cleared thumbs/): never write an
            // ended account's artwork back into the App Group.
            guard accountSession.isCurrent(context), !Task.isCancelled else { return names }
            if store.writeThumbnail(data, named: name) {
                names[key] = name
            }
        }
        return names
    }

    // MARK: Inbox support (WidgetIntentInbox.swift)

    /// The app's own unit count for `key` (its catalogue facts, read when the cache lacks them); the
    /// queue's echoed total is never trusted alone.
    func ownUnitCap(for key: MediaKey) async -> Int? {
        if let cached = metadataCache[key] { return cached.total.flatMap { $0 > 0 ? $0 : nil } }
        switch key.kind {
        case .anime:
            guard let row = await catalog.fetchAnimeByIdsPreservingOrder([key.id])?.first else { return nil }
            metadataCache[key] = WidgetTitleMetadata(
                title: row.displayTitle, total: row.episodeCount,
                artworkURL: (row.coverImageMedium ?? row.coverImageLarge).flatMap(WidgetSnapshotBuilder.httpsURL))
            return row.episodeCount.flatMap { $0 > 0 ? $0 : nil }
        case .manga:
            guard let row = await catalog.fetchMangaByIdsPreservingOrder([key.id])?.first else { return nil }
            metadataCache[key] = WidgetTitleMetadata(
                title: row.displayTitle, total: row.chapterCount,
                artworkURL: (row.coverImageMedium ?? row.coverImageLarge).flatMap(WidgetSnapshotBuilder.httpsURL))
            return row.chapterCount.flatMap { $0 > 0 ? $0 : nil }
        }
    }

    /// The cap a queued +1 uses: the app's own count, the smaller one when the queue also carries one.
    nonisolated static func queuedAdvanceCap(own: Int?, queued: Int?) -> Int? {
        switch (own, queued.flatMap { $0 > 0 ? $0 : nil }) {
        case let (own?, queued?): min(own, queued)
        case let (own?, nil): own
        case let (nil, queued?): queued
        case (nil, nil): nil
        }
    }

    var libraryLoadState: LibraryStore.LoadState { library.loadState }

    func advanceQueuedProgress(_ key: MediaKey, to target: Int, lifecycleId: UUID?, cap: Int?) async
        -> LibraryActions.QueuedAdvanceOutcome {
        await libraryActions.advanceQueuedProgress(key, to: target, lifecycleId: lifecycleId, cap: cap)
    }

    func recordDrain(_ report: DrainReport) {
        lastDrainApplied = report.applied
    }

    func finishDrainTask(_ id: UUID) {
        guard drainTaskId == id else { return }
        drainTask = nil
        drainTaskId = nil
    }

    // MARK: App lifecycle hooks (KuroApp)

    /// Foreground: drain queued +1 taps, then write.
    func appDidBecomeActive() {
        drainIfLibraryReady()
        setNeedsWrite()
    }

    /// Background: write what is pending now (the widget shows the state the user just left).
    func appWillResignActive() {
        guard pendingWrite != nil else { return }
        pendingWrite?.cancel()
        pendingWrite = Task { [weak self] in await self?.writeNow() }
    }
}
