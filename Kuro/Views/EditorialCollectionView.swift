// Collection page: the Folio lists (spec D9, rulebook §14.4), in both worlds.
// One data path whatever the series flags say: the Collection feed (title, cover, totals; scoped to
// the selected medium and status) joined with the Library store (status, progress, rating: the one
// tracking authority) and the release schedule. Flags off it replaces the legacy grid; flags on it
// replaces the bare series text list. Writes: +1 and its guarded Undo through the owner
// (`CollectionStore.advanceFromList` / `undoListAdvance`: the durable progress outbox with the unit cap,
// or one capped progress edit when the outbox is unavailable; never `HomeStore`, so Home's Undo is not
// armed by a Collection +1); status and removal through `LibraryActions` (via `CollectionStore`'s
// batch scopes for batches). Search covers every status of the medium (rulebook §14.4).

import KuroCore
import KuroLibrary
import SwiftUI

struct EditorialCollectionView: View {
    /// Moves the pager to its Browse page. Used where the pager has one (the live order); where it has
    /// none (series Home), "Find a title" opens the Browse route instead (spec D2, `DiscoverBrowseEntry`).
    let onOpenBrowsePage: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(CollectionStore.self) private var collection
    @Environment(ReleasesStore.self) private var releases
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(LibraryActions.self) private var libraryActions
    @Environment(HomeStore.self) private var home
    @Environment(FeatureFlags.self) private var flags
    @Environment(\.kuroRoutes) private var routes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var medium: MediaKind = .anime
    /// The last medium chosen here (a per-device convenience; "" until the first choice).
    @AppStorage("kuro.folio.medium") private var storedMedium: String = ""
    @State private var status: FolioStatus = .watching
    @State private var sort: FolioSort = .recent
    @State private var verdictFilter: FolioVerdictFilter = .all
    @AppStorage("kuro.folio.density.anime") private var animeDensity: FolioDensity = .index
    @AppStorage("kuro.folio.density.manga") private var mangaDensity: FolioDensity = .shelf
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var isSelecting = false
    @State private var selectedKeys: Set<String> = []
    @State private var showRemoveConfirm = false
    @State private var notice: FolioNotice?
    @State private var noticeTask: Task<Void, Never>?
    @State private var pendingAdvance: Set<MediaKey> = []
    @State private var classifyTarget: ClassifyTarget?
    @State private var showImportChooser = false
    @State private var mountedAccount: AccountContext?
    @State private var didInitialLoad = false
    @State private var isLoadingAll = false
    /// The bounded read for search/sort stopped with titles still unread (shown as an honest line).
    @State private var localOrderingTruncated = false

    private struct ClassifyTarget: Identifiable {
        let media: Media
        var id: String { media.stableKey }
    }

    private var german: Bool { KuroLocale.isGerman }
    /// The current account while this page is mounted (writes never start from an unmounted page).
    private var activeAccount: AccountContext? {
        mountedAccount == nil ? nil : collection.accountSession.current
    }
    private var isImportedView: Bool { collection.importedTitleKeys != nil }

    private var density: Binding<FolioDensity> {
        medium == .manga ? $mangaDensity : $animeDensity
    }

    /// An active search reads every status of the medium (search covers the whole list, rulebook §14.4).
    private var isQueryActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The server-side status filter of the feed this page reads.
    private var feedStatus: ListStatus? {
        isImportedView || isQueryActive ? nil : status.listStatus
    }

    // MARK: Rows

    /// Every loaded row of the selected medium joined with its Library entry and next release.
    private var loadedItems: [FolioItem] {
        collection.displayedFeedItems.compactMap { media -> FolioItem? in
            guard media.kind == medium, let entry = library.entry(for: media.libraryKey) else { return nil }
            let progress = library.displayedProgress(for: entry.key, server: entry.progress, lifecycleId: entry.lifecycleId)
            // Only a displayable date (an estimate needs confidence): sort, row and VoiceOver agree.
            let next = entry.status == .completed || entry.status == .dropped
                ? nil : releases.nextRelease(for: entry.key).flatMap { $0.isDisplayable ? $0 : nil }
            return FolioItem(media: media, entry: entry, progress: progress, next: next,
                             banner: collection.feedBanners[entry.key])
        }
    }

    /// The rows the list shows: status (Library authority), verdict, search, then sort. A search spans
    /// every status of the medium. Computed once per render (`body`).
    private var visibleItems: [FolioItem] {
        var rows = loadedItems
        if !isImportedView && !isQueryActive {
            rows = rows.filter { status.listStatuses.contains($0.entry.status) }
            if status == .completed {
                rows = rows.filter { verdictFilter.includes($0.entry.verdict) }
            }
        }
        rows = rows.filter { FolioPolicy.matches($0, query: searchText) }
        return FolioPolicy.sorted(rows, by: sort)
    }

    private var counts: [FolioStatus: Int] {
        FolioPolicy.counts(library.allEntries, medium: medium)
    }

    private var unsortedCompleted: Int {
        library.allEntries.filter { $0.key.kind == medium && $0.status == .completed && $0.verdict == nil }.count
    }

    private var actions: FolioRowActions {
        FolioRowActions(
            open: { item in
                KuroAccessibility.impactHaptic(.light)
                routes.openMedia(MediaRoute(item.key))
            },
            advance: { item in advance(item) },
            edit: { item in routes.presentTrackingEditor(TrackingEditorRequest(media: item.media)) },
            classify: { item in classifyTarget = ClassifyTarget(media: item.media) },
            remove: { item in removeOne(item) },
            toggleSelection: { item in
                KuroAccessibility.impactHaptic(.light)
                if selectedKeys.contains(item.id) { selectedKeys.remove(item.id) } else { selectedKeys.insert(item.id) }
            },
            keyPhase: { item in keyPhase(item) }
        )
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let gutter = FolioPolicy.gutter(forWidth: width)
            let rows = visibleItems
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header(gutter: gutter, canSelect: !rows.isEmpty)
                    content(rows: rows, width: width, gutter: gutter)
                        .padding(.top, KuroDesignSpacing.md)
                    Color.clear.frame(height: KuroDesignSpacing.xl)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await reload(refreshLibrary: true) }
            .background(Color.kuroCanvasPage)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: KuroDesignSpacing.sm) {
                    if let notice {
                        FolioNoticeBar(notice: notice) { performNoticeAction() }
                            .transition(.opacity)
                    }
                    if isSelecting && !selectedKeys.isEmpty {
                        FolioBatchBar(count: selectedKeys.count, medium: medium,
                                      onChangeStatus: { target in Task { await batchChangeStatus(target) } },
                                      onRemove: { showRemoveConfirm = true })
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, isSelecting && !selectedKeys.isEmpty ? 0 : KuroDesignSpacing.sm)
                .kuroAnimation(KuroMotion.settle, value: notice?.id)
            }
        }
        .confirmationDialog(
            german ? "\(selectedKeys.count) Titel aus deinen Listen entfernen?"
                   : "Remove \(selectedKeys.count) \(selectedKeys.count == 1 ? "title" : "titles") from your lists?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button(german ? "Entfernen" : "Remove", role: .destructive) { Task { await confirmBatchRemove() } }
            Button(german ? "Abbrechen" : "Cancel", role: .cancel) {}
        } message: {
            Text(german ? "Status, Fortschritt und Notizen dieser Titel werden gelöscht."
                        : "Their status, progress and notes are deleted.")
        }
        .sheet(item: $classifyTarget) { target in
            QuickVerdictActionSheet(media: target.media) { toast in
                show(FolioNotice(tone: toast.kind == .error ? .problem : .confirmation, message: toast.title, actionTitle: nil))
            }
        }
        .sheet(isPresented: $showImportChooser) {
            ImportSourceChooser { destination in
                showImportChooser = false
                switch destination {
                case .importedTitles(let keys): collection.showImportedTitles(keys)
                case .fullCollection: collection.clearImportedTitles()
                }
            }
        }
        .onAppear { mountedAccount = collection.accountSession.current }
        .onDisappear {
            mountedAccount = nil
            noticeTask?.cancel()
        }
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            if let request = collection.consumeListRequest() {
                apply(request)
            } else if let stored = MediaKind(rawValue: storedMedium) {
                medium = stored
            } else {
                medium = home.medium == "manga" ? .manga : .anime
            }
            await reload()
            await releases.loadSchedule()
        }
        .onChange(of: collection.requestedListFilter) { _, request in
            guard request != nil, let request = collection.consumeListRequest() else { return }
            apply(request)
            Task { await reload() }
        }
        .onChange(of: storedMedium) { _, raw in
            // Onboarding's medium choice while this page is already mounted (its first load has run).
            guard didInitialLoad, let chosen = MediaKind(rawValue: raw), chosen != medium else { return }
            medium = chosen
        }
        .onChange(of: medium) { _, value in
            storedMedium = value.rawValue
            resetTransientState()
            Task { await reload() }
        }
        .onChange(of: status) { _, _ in
            selectedKeys.removeAll()
            verdictFilter = .all
            // Choosing a status ends a search (which spans every status); the query change reloads.
            if isQueryActive {
                searchText = ""
                isSearching = false
                return
            }
            Task { await reload() }
        }
        .onChange(of: collection.importedTitleKeys) { _, _ in
            resetTransientState()
            Task { await reload() }
        }
        .onChange(of: collection.currentCollectionStatusFilter) { _, filter in
            // Another surface re-read the feed for a different filter (sync, realtime, import):
            // read the list this page is showing again.
            // Latest wins in the store, so this read replaces the other one; ours already match.
            guard !isImportedView, filter != feedStatus else { return }
            Task { await reload() }
        }
        .onChange(of: isQueryActive) { _, _ in
            // Starting a search reads the whole medium; clearing it reads the selected status again.
            guard !isImportedView else { return }
            Task { await reload() }
        }
        .onChange(of: collection.isCollectionLoading) { _, loading in
            // Any feed refresh (batch end, a Library change) reads the first page again: a sorted or
            // searched list reads the rest again so it is never silently incomplete.
            guard !loading, sort != .recent || isQueryActive else { return }
            Task { await loadAllForLocalOrdering() }
        }
        .onChange(of: sort) { _, value in
            if value != .recent { Task { await loadAllForLocalOrdering() } }
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(gutter: CGFloat, canSelect: Bool) -> some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            if isImportedView {
                HStack(alignment: .firstTextBaseline, spacing: KuroDesignSpacing.md) {
                    Text(german ? "Importierte Titel" : "Imported titles")
                        .font(.kuroTitle())
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button {
                        collection.clearImportedTitles()
                    } label: {
                        Text(german ? "Alle Listen" : "All lists")
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInk)
                            .underline(true, color: Color.kuroInk)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, gutter)
            }

            KuroMediumSwitch(selection: $medium, size: .compact)
                .padding(.horizontal, gutter)
                .padding(.top, KuroDesignSpacing.sm)

            if !isImportedView {
                FolioStatusStrip(selection: $status, counts: counts, medium: medium, gutter: gutter)
            }

            FolioControlsRow(
                density: density,
                sort: $sort,
                isSearching: isSearching,
                isSelecting: isSelecting,
                canSelect: canSelect,
                onToggleSearch: toggleSearch,
                onToggleSelect: toggleSelect,
                gutter: gutter
            )

            if isSearching {
                FolioSearchField(text: $searchText, medium: medium, focused: $searchFocused, gutter: gutter)
                    .transition(.opacity)
            }

            if status == .completed && !isImportedView {
                FolioVerdictWords(selection: $verdictFilter, unsortedCount: unsortedCompleted, gutter: gutter)
            }

            Rectangle()
                .fill(Color.kuroHairline)
                .frame(height: 0.5)
                .padding(.horizontal, gutter)
                .padding(.top, KuroDesignSpacing.xs)
        }
    }

    // MARK: Content and states

    @ViewBuilder
    private func content(rows: [FolioItem], width: CGFloat, gutter: CGFloat) -> some View {
        let hasError = collection.collectionErrorMessage?.isEmpty == false
        let offline = !networkMonitor.isConnected
        if collection.isCollectionLoading && rows.isEmpty {
            FolioSkeleton(density: density.wrappedValue, medium: medium, width: width)
        } else if rows.isEmpty {
            emptyState(hasError: hasError, offline: offline, gutter: gutter)
        } else {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                if hasError || offline {
                    KuroStateView(offline ? .offline(hasCachedContent: true) : .failed(hasCachedContent: true),
                                  layout: .inline, retry: offline ? nil : { Task { await reload(refreshLibrary: true) } })
                        .padding(.horizontal, gutter)
                }
                Group {
                    if density.wrappedValue == .shelf {
                        FolioShelf(items: rows, medium: medium, width: width, isSelecting: isSelecting,
                                   selectedKeys: selectedKeys, actions: actions)
                    } else {
                        FolioIndex(items: rows, width: width, isSelecting: isSelecting,
                                   selectedKeys: selectedKeys, actions: actions)
                    }
                }
                // The density switch is a crossfade, never rows travelling between layouts (§8).
                .id(density.wrappedValue)
                .transition(.opacity)
                if sort == .recent && !isQueryActive {
                    KuroLoadMoreSentinel(
                        itemCount: collection.displayedFeedItems.count,
                        hasMore: collection.hasMoreDisplayedFeed,
                        isLoading: collection.isLoadingMoreCollectionFeed
                    ) {
                        _ = await collection.fetchNextCollectionFeedPage(limit: 90)
                    }
                } else if isLoadingAll {
                    KuroBusyMark(width: 44)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(german ? "Weitere Titel werden geladen" : "Loading more titles")
                } else if localOrderingTruncated {
                    truncationLine(gutter: gutter)
                }
            }
        }
    }

    /// The bounded read stopped early: say so instead of implying the order or the matches are complete.
    private func truncationLine(gutter: CGFloat) -> some View {
        Text(FolioCopy.showingFirst(collection.displayedFeedItems.count, german: german))
            .font(.kuroMeta())
            .foregroundStyle(Color.kuroInkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, gutter)
    }

    @ViewBuilder
    private func emptyState(hasError: Bool, offline: Bool, gutter: CGFloat) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = CollectionEmptyState.resolve(
            libraryKnown: library.loadState == .loaded || !library.allEntries.isEmpty,
            libraryFailed: library.loadState == .failed,
            libraryIsEmpty: library.allEntries.isEmpty,
            isImportedView: isImportedView,
            hasQuery: !query.isEmpty,
            statusCount: counts[status] ?? 0,
            mediumTotal: counts.values.reduce(0, +),
            hasError: hasError,
            offline: offline,
            feedIsEmpty: collection.displayedFeedItems.isEmpty
        )
        switch state {
        case .awaitingLibrary:
            // The Library has not answered yet: keep stable geometry instead of an "empty" claim.
            KuroStateView(.loading, title: german ? "Deine Listen werden geladen." : "Loading your lists.", layout: .inline)
                .padding(.horizontal, gutter)
        case .statusEmpty:
            // The Library (the tracking authority) knows this status is empty: that is an honest empty
            // line, never a failure, even offline (rulebook §9).
            KuroStateView(.empty, title: status.emptyLine(medium: medium, german: german), layout: .inline)
                .padding(.horizontal, gutter)
        case .unavailable(let isOffline):
            KuroStateView(isOffline ? .offline(hasCachedContent: false) : .failed(hasCachedContent: false),
                          retry: { Task { await reload(refreshLibrary: true) } })
                .frame(minHeight: 280)
        case .noMatches:
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                KuroStateView(.empty, title: FolioCopy.noMatches(query, german: german), layout: .inline)
                if isLoadingAll {
                    KuroBusyMark(width: 44)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(german ? "Weitere Titel werden geladen" : "Loading more titles")
                } else if localOrderingTruncated {
                    Text(FolioCopy.showingFirst(collection.displayedFeedItems.count, german: german))
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, gutter)
        case .invitation:
            libraryInvitation
        case .otherMediumEmpty:
            otherMediumShortcut
        case .importedEmpty:
            KuroStateView(.empty, title: german ? "Keine importierten Titel in diesem Medium." : "No imported titles in this medium.",
                          layout: .inline)
                .padding(.horizontal, gutter)
        }
    }

    /// The whole Library is empty: the new-account invitation (the prototype's ＋ block, spec §5.3),
    /// with Import and Find (rulebook §7, §9). Never a blank page.
    private var libraryInvitation: some View {
        FirstRunInvitation(
            headline: HomeNewAccountCopy.headline(german: german),
            line: HomeNewAccountCopy.line(german: german)
        ) {
            KuroOutlineButton(HomeNewAccountCopy.importList(german: german)) { showImportChooser = true }
            KuroOutlineButton(german ? "Titel finden" : "Find a title") { findTitle() }
        }
    }

    /// Nothing in this medium, but the other medium may have titles: an honest shortcut, never an
    /// auto-switch.
    @ViewBuilder
    private var otherMediumShortcut: some View {
        let other: MediaKind = medium == .anime ? .manga : .anime
        let otherCount = library.allEntries.filter { $0.key.kind == other }.count
        FirstRunInvitation(
            headline: medium == .anime
                ? (german ? "Noch keine Anime in deinen Listen." : "No anime in your lists yet.")
                : (german ? "Noch keine Manga in deinen Listen." : "No manga in your lists yet."),
            line: nil
        ) {
            if otherCount > 0 {
                KuroOutlineButton(other == .manga
                                  ? (german ? "Deine Manga zeigen (\(otherCount))" : "Show your manga (\(otherCount))")
                                  : (german ? "Deine Anime zeigen (\(otherCount))" : "Show your anime (\(otherCount))")) {
                    medium = other
                }
            }
            KuroOutlineButton(german ? "Titel finden" : "Find a title") { findTitle() }
        }
    }

    /// One Browse, never two: the Browse route only where the pager has no Browse page (spec D2).
    private func findTitle() {
        if DiscoverBrowseEntry.isOffered(flags: flags) {
            routes.openBrowse()
        } else {
            onOpenBrowsePage()
        }
    }

    // MARK: Loading

    private func apply(_ request: CollectionListRequest) {
        if let requested = request.medium { medium = requested }
        status = FolioStatus(listStatus: request.status)
        resetTransientState()
    }

    private func resetTransientState() {
        isSelecting = false
        selectedKeys.removeAll()
        searchText = ""
        isSearching = false
        verdictFilter = .all
    }

    /// Reads the selected medium and status from the feed (the Library store keeps the tracking values).
    private func reload(refreshLibrary: Bool = false) async {
        guard let context = collection.accountSession.current else { return }
        if refreshLibrary {
            try? await library.refresh()
            guard collection.accountSession.isCurrent(context) else { return }
        }
        collection.feedMedium = isImportedView ? nil : medium
        localOrderingTruncated = false
        await collection.fetchCollectionFeed(status: feedStatus)
        guard collection.accountSession.isCurrent(context) else { return }
        if sort != .recent || isQueryActive { await loadAllForLocalOrdering() }
        if refreshLibrary { await releases.loadSchedule(force: true) }
    }

    /// Title/score/date sorts and search need the whole list: read the remaining pages (bounded at
    /// `FolioPolicy.localOrderingPageLimit`; past it the page says "Showing the first N titles").
    private func loadAllForLocalOrdering() async {
        guard !isLoadingAll, let context = collection.accountSession.current else { return }
        isLoadingAll = true
        // Reset whatever the account did meanwhile: a flag left set would block the next account.
        defer { isLoadingAll = false }
        var pages = 0
        while collection.hasMoreDisplayedFeed, pages < FolioPolicy.localOrderingPageLimit, !Task.isCancelled {
            let loaded = await collection.fetchNextCollectionFeedPage(limit: 120)
            guard loaded, collection.accountSession.isCurrent(context) else { return }
            pages += 1
        }
        guard collection.accountSession.isCurrent(context) else { return }
        localOrderingTruncated = collection.hasMoreDisplayedFeed && pages >= FolioPolicy.localOrderingPageLimit
    }

    // MARK: Controls

    private func toggleSearch() {
        withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) {
            isSearching.toggle()
            if !isSearching { searchText = "" }
        }
        searchFocused = isSearching
    }

    private func toggleSelect() {
        withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) {
            isSelecting.toggle()
            if !isSelecting { selectedKeys.removeAll() }
        }
    }

    // MARK: Progress

    private func keyPhase(_ item: FolioItem) -> FolioKeyPhase? {
        let entry = item.entry
        let unit = library.displayedUnitId(for: entry.key, serverUnitId: entry.unitId, lifecycleId: entry.lifecycleId)
        let label = library.displayedProgressLabel(for: entry.key, serverLabel: entry.progressLabel, lifecycleId: entry.lifecycleId)
        let needsChoice = unit != nil || (label.map { Int($0) != item.progress } ?? false)
        return FolioPolicy.keyPhase(status: entry.status, progress: item.progress, total: item.total,
                                    needsChoice: needsChoice, isPending: pendingAdvance.contains(entry.key))
    }

    private func displayedProgress(_ key: MediaKey) -> Int? {
        guard let entry = library.entry(for: key) else { return nil }
        return library.displayedProgress(for: key, server: entry.progress, lifecycleId: entry.lifecycleId)
    }

    /// +1 with the cap through the owner (`CollectionStore.advanceFromList`: the durable outbox with its
    /// caught-up guard, or one capped edit). A title at its total never advances. One notice per tap.
    private func advance(_ item: FolioItem) {
        guard let context = activeAccount else { return }
        let key = item.key
        switch keyPhase(item) {
        case .needsChoice:
            show(FolioNotice(tone: .confirmation, message: FolioCopy.needsChoice(german: german), actionTitle: nil))
            routes.openMedia(MediaRoute(key))
            return
        case .advance:
            break
        case .caughtUp, .pending, .none:
            return
        }
        guard FolioPolicy.mayAdvance(progress: item.progress, total: item.total) else { return }
        let entry = item.entry
        let before = item.progress
        pendingAdvance.insert(key)
        Task {
            // Released whatever happens meanwhile: a key left pending would show "pending" forever.
            defer { pendingAdvance.remove(key) }
            let result = await collection.advanceFromList(key, cap: item.total)
            guard collection.accountSession.isCurrent(context) else { return }
            switch result {
            case .admitted(let path):
                let after = displayedProgress(key) ?? before
                // Admitted without moving: the outbox found the title already at its total.
                guard after > before else { return }
                KuroAccessibility.successHaptic()
                collection.recordListAdvance(CollectionAdvanceReceipt(
                    key: key, title: item.media.title, lifecycleId: entry.lifecycleId,
                    prior: before, advancedTo: after, account: context, path: path))
                show(FolioNotice(tone: .confirmation, message: FolioCopy.advanced(medium: key.kind, to: after, german: german),
                                 actionTitle: FolioCopy.undoTitle(german: german)), seconds: UIAccessibility.isVoiceOverRunning ? 12 : 5)
            case .refused:
                return
            case .failed:
                KuroAccessibility.errorHaptic()
                show(FolioNotice(tone: .problem, message: FolioCopy.advanceFailed(german: german), actionTitle: nil))
            }
        }
    }

    private func performNoticeAction() {
        guard notice?.actionTitle != nil else { return }
        hideNotice()
        undoLastAdvance()
    }

    /// Guarded Undo through the owner: the receipt's own path (the durable outbox's cancel/compensate,
    /// or the prior position for a plain edit), only while the title still shows the advanced position.
    private func undoLastAdvance() {
        guard let context = activeAccount else { return }
        Task {
            let result = await collection.undoListAdvance()
            guard collection.accountSession.isCurrent(context) else { return }
            switch result {
            case .undone:
                return
            case .alreadySending:
                show(FolioNotice(tone: .problem, message: FolioCopy.undoInFlight(german: german), actionTitle: nil))
            case .failed:
                show(FolioNotice(tone: .problem, message: FolioCopy.undoFailed(german: german), actionTitle: nil))
            }
        }
    }

    // MARK: Removal and batch

    private func removeOne(_ item: FolioItem) {
        guard let context = activeAccount else { return }
        Task {
            let removed = await LibraryViewActions.remove(item.key, actions: libraryActions)
            guard collection.accountSession.isCurrent(context) else { return }
            show(FolioNotice(tone: removed ? .confirmation : .problem,
                             message: FolioCopy.removed(removed ? 1 : 0, of: 1, german: german), actionTitle: nil))
        }
    }

    private func selectedItemKeys() -> [MediaKey] {
        loadedItems.filter { selectedKeys.contains($0.id) }.map(\.key)
    }

    private func batchChangeStatus(_ target: FolioStatus) async {
        guard let context = activeAccount else { return }
        let keys = selectedItemKeys()
        guard !keys.isEmpty else { return }
        let outcomes = await collection.applyBatchStatusChange(target.listStatus, to: keys, visibleFilter: feedStatus) { edit, key, create in
            await libraryActions.apply(edit, to: key, createIfMissing: create)
        }
        guard collection.accountSession.isCurrent(context), mountedAccount != nil else { return }
        let updated = outcomes.filter { $0.change != nil }.count
        if updated == keys.count { KuroAccessibility.successHaptic() } else if updated == 0 { KuroAccessibility.errorHaptic() }
        show(FolioNotice(tone: updated == keys.count ? .confirmation : .problem,
                         message: FolioCopy.updated(updated, of: keys.count, german: german), actionTitle: nil))
        withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) {
            selectedKeys.removeAll()
            isSelecting = false
        }
    }

    private func confirmBatchRemove() async {
        guard let context = activeAccount else { return }
        let keys = selectedItemKeys()
        guard !keys.isEmpty else { return }
        let removed = await collection.applyBatchRemoval(to: keys) { key in
            await LibraryViewActions.remove(key, actions: libraryActions)
        }
        guard collection.accountSession.isCurrent(context), mountedAccount != nil else { return }
        if removed == keys.count { KuroAccessibility.successHaptic() } else if removed == 0 { KuroAccessibility.errorHaptic() }
        show(FolioNotice(tone: removed == keys.count ? .confirmation : .problem,
                         message: FolioCopy.removed(removed, of: keys.count, german: german), actionTitle: nil))
        withAnimation(KuroMotion.resolve(KuroMotion.contextChange)) {
            selectedKeys.removeAll()
            isSelecting = false
        }
    }

    // MARK: Notice

    private func show(_ next: FolioNotice, seconds: Double = 3) {
        noticeTask?.cancel()
        notice = next
        UIAccessibility.post(notification: .announcement, argument: next.message)
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }

    private func hideNotice() {
        noticeTask?.cancel()
        notice = nil
    }
}

// MARK: - Empty block (pure)

/// Which empty block the Collection shows when the list has no rows. Every input resolves to a block,
/// so an empty list is never a blank page. Order matters: an unanswered Library never claims "empty",
/// a known-empty status is honest even offline, a failure never shows as the invitation.
nonisolated enum CollectionEmptyState: Equatable {
    case awaitingLibrary
    case statusEmpty
    case unavailable(offline: Bool)
    case noMatches
    case invitation
    case otherMediumEmpty
    case importedEmpty

    /// `statusCount`: the selected status's count in this medium; `mediumTotal`: every status of it.
    static func resolve(libraryKnown: Bool, libraryFailed: Bool, libraryIsEmpty: Bool, isImportedView: Bool,
                        hasQuery: Bool, statusCount: Int, mediumTotal: Int, hasError: Bool, offline: Bool,
                        feedIsEmpty: Bool) -> CollectionEmptyState {
        if !libraryKnown && !libraryFailed { return .awaitingLibrary }
        if !isImportedView && !hasQuery && libraryKnown && statusCount == 0 && mediumTotal > 0 { return .statusEmpty }
        if hasError || (libraryFailed && libraryIsEmpty) || (offline && feedIsEmpty && !libraryIsEmpty) {
            return .unavailable(offline: offline)
        }
        if hasQuery { return .noMatches }
        if libraryIsEmpty && !isImportedView { return .invitation }
        if !isImportedView && mediumTotal == 0 { return .otherMediumEmpty }
        if isImportedView { return .importedEmpty }
        return .statusEmpty
    }
}
