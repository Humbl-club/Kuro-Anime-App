// W9 journey pages: "Your lists" (index) and one list (titles in the person's own order, Arrange, removal
// with Undo, the stale-move notice). Both are journey pages (✕ / Back, visible grabber); name and organise
// sheets are tool sheets that leave the journey.

import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Index

struct CustomListsJourneyPage: View {
    static let pageID = "lists:index"

    static var page: JourneyPage {
        .custom(AnyJourneyPage(id: pageID, title: OrganiseCopy.text(.yourLists)) { CustomListsJourneyPage() })
    }

    var forcedGerman: Bool?

    @Environment(CustomListsStore.self) private var lists
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.kuroRoutes) private var routes
    @State private var collapse: CGFloat = 0
    @State private var nameTarget: NameTarget?
    @State private var seedHidden = false
    @State private var seedMessage: String?

    private struct NameTarget: Identifiable { let id = UUID() }

    private var german: Bool { forcedGerman ?? KuroLocale.isGerman }
    private func text(_ key: OrganiseCopy.Key) -> String { OrganiseCopy.string(key, german: german) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                Text(text(.yourLists))
                    .font(.kuroFeature())
                    .foregroundStyle(Color.kuroInk)
                    .accessibilityAddTraits(.isHeader)
                if lists.loadState == .loaded || !lists.lists.isEmpty {
                    seedOffer
                    Button { nameTarget = NameTarget() } label: {
                        Text(text(.newList))
                            .font(.kuroMeta(weight: .semibold))
                            .foregroundStyle(Color.kuroInk)
                            .underline(true, color: Color.kuroInk)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lists.new")
                    if lists.lists.isEmpty {
                        KuroStateView(.empty, title: text(.noLists), message: text(.noListsHint), layout: .inline)
                    }
                    ForEach(lists.lists) { list in row(list) }
                } else {
                    stateView
                }
            }
            .padding(KuroDesignSpacing.padding)
            .kuroReadableWidth()
        }
        .kuroCollapseTracking($collapse, start: 0, distance: 44)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: KuroJourneyChrome.barHeight) }
        .background(Color.kuroCanvasPage)
        .tint(Color.kuroInk)
        .task { await lists.load() }
        .sheet(item: $nameTarget) { _ in
            CustomListNameSheet(forcedGerman: forcedGerman) { name in
                if case .failure(let error) = await lists.create(name: name) { return error }
                return nil
            }
            .kuroLeavesJourney()
        }
        .kuroNavigationLayer("lists.name", item: $nameTarget)
        .kuroJourneyChrome(title: text(.yourLists), collapseProgress: collapse)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var stateView: some View {
        switch lists.loadState {
        case .failed:
            KuroStateView(network.isConnected ? .failed(hasCachedContent: false) : .offline(hasCachedContent: false),
                          title: text(network.isConnected ? .loadFailed : .offline), layout: .inline) {
                Task { await lists.load(force: true) }
            }
        case .unavailable:
            KuroStateView(.empty, title: text(.errUnavailable), layout: .inline)
        default:
            KuroStateView(.loading, layout: .inline)
        }
    }

    @ViewBuilder
    private var seedOffer: some View {
        let wanted = lists.importedListNames()
        if !wanted.isEmpty && !seedHidden {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                Text(german ? "Dein Import enthielt \(wanted.count) Liste\(wanted.count == 1 ? "" : "n")."
                            : "Your import had \(wanted.count) list\(wanted.count == 1 ? "" : "s").")
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                HStack(spacing: KuroDesignSpacing.lg) {
                    Button(text(.createTheseLists)) {
                        Task {
                            if case .failure(let error) = await lists.seedFromImport() {
                                seedMessage = OrganiseCopy.error(error, german: german)
                            } else {
                                seedHidden = true
                            }
                        }
                    }
                    .font(.kuroMeta(weight: .semibold))
                    .foregroundStyle(Color.kuroInk)
                    .underline(true, color: Color.kuroInk)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("lists.seed")
                    Button(text(.notNow)) { seedHidden = true }
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .frame(minHeight: 44)
                }
                if let seedMessage {
                    Text(seedMessage).font(.kuroMeta()).foregroundStyle(Color.kuroError)
                }
            }
            .padding(.vertical, KuroDesignSpacing.sm)
        }
    }

    private func row(_ list: CustomList) -> some View {
        Button {
            KuroAccessibility.impactHaptic(.light)
            routes.openPage(CustomListJourneyPage.page(listId: list.id, name: list.name))
        } label: {
            HStack(spacing: KuroDesignSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name).font(.kuroTitleName()).foregroundStyle(Color.kuroInk).multilineTextAlignment(.leading)
                    Text(german ? "\(list.items.count) Titel" : "\(list.items.count) \(list.items.count == 1 ? "title" : "titles")")
                        .font(.kuroMeta()).foregroundStyle(Color.kuroInkQuiet)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.kuroCustom(12, weight: .semibold, relativeTo: .caption1, maxSize: 18))
                    .foregroundStyle(Color.kuroInkQuiet).accessibilityHidden(true)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lists.row.\(list.name)")
    }
}

// MARK: - One list

struct CustomListJourneyPage: View {
    static func pageID(_ id: UUID) -> String { "lists:\(id.uuidString.lowercased())" }

    static func page(listId: UUID, name: String) -> JourneyPage {
        .custom(AnyJourneyPage(id: pageID(listId), title: name) { CustomListJourneyPage(listId: listId) })
    }

    let listId: UUID
    var forcedGerman: Bool?
    /// Render tests and previews open the page with Arrange on.
    var startsArranging = false
    /// Render tests show the stale-move notice without a server round trip.
    var previewStaleMove: CustomListPendingMove?

    @Environment(CustomListsStore.self) private var lists
    @Environment(\.kuroRoutes) private var routes
    @State private var collapse: CGFloat = 0
    @State private var arranging: Bool
    @State private var notice: FolioNotice?
    @State private var staleMove: CustomListPendingMove?
    @State private var removal: CustomListRemoval?
    @State private var confirmDelete = false
    @State private var nameTarget: NameTarget?
    @State private var organiseTarget: OrganiseTarget?
    @State private var noticeTask: Task<Void, Never>?

    private struct NameTarget: Identifiable { let id = UUID() }
    private struct OrganiseTarget: Identifiable {
        let media: Media
        var id: String { media.stableKey }
    }

    init(listId: UUID, forcedGerman: Bool? = nil, startsArranging: Bool = false, previewStaleMove: CustomListPendingMove? = nil) {
        self.listId = listId
        self.forcedGerman = forcedGerman
        self.startsArranging = startsArranging
        self.previewStaleMove = previewStaleMove
        _arranging = State(initialValue: startsArranging)
        _staleMove = State(initialValue: previewStaleMove)
    }

    private var german: Bool { forcedGerman ?? KuroLocale.isGerman }
    private func text(_ key: OrganiseCopy.Key) -> String { OrganiseCopy.string(key, german: german) }
    private var list: CustomList? { lists.lists.first { $0.id == listId } }

    var body: some View {
        Group {
            if let list {
                content(list)
            } else if lists.loadState == .loaded {
                KuroStateView(.empty, title: text(.errNotFound), layout: .page)
            } else {
                KuroStateView(.loading, layout: .page)
            }
        }
        .background(Color.kuroCanvasPage)
        .tint(Color.kuroInk)
        .safeAreaInset(edge: .bottom, spacing: 0) { noticeBar }
        .confirmationDialog(text(.deleteListConfirm), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(text(.deleteList), role: .destructive) {
                Task {
                    if case .success = await lists.delete(listId) { routes.openPage(CustomListsJourneyPage.page) }
                }
            }
            Button(text(.cancel), role: .cancel) {}
        }
        .sheet(item: $nameTarget) { _ in
            CustomListNameSheet(initialName: list?.name, forcedGerman: forcedGerman) { name in
                if case .failure(let error) = await lists.rename(listId, to: name) { return error }
                return nil
            }
            .kuroLeavesJourney()
        }
        .kuroNavigationLayer("lists.rename", item: $nameTarget)
        .sheet(item: $organiseTarget) { target in
            TitleOrganiseSheet(media: target.media, forcedGerman: forcedGerman).kuroLeavesJourney()
        }
        .kuroNavigationLayer("lists.organise", item: $organiseTarget)
        .task { await lists.load() }
        .onDisappear { noticeTask?.cancel() }
        .kuroJourneyChrome(title: list?.name ?? "", collapseProgress: collapse)
        .presentationDragIndicator(.visible)
    }

    // MARK: Content

    private func content(_ list: CustomList) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    Text(list.name)
                        .font(.kuroFeature())
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: KuroDesignSpacing.lg) {
                        wordButton(arranging ? .done : .arrange, id: "list.arrange") { arranging.toggle() }
                        wordButton(.rename, id: "list.rename") { nameTarget = NameTarget() }
                        wordButton(.deleteList, id: "list.delete") { confirmDelete = true }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.kuroCanvasPage)
            }
            if list.items.isEmpty {
                KuroStateView(.empty, title: text(.empty), layout: .inline)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.kuroCanvasPage)
            }
            ForEach(list.items, id: \.self) { key in
                row(key)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.kuroCanvasPage)
            }
            .onMove { offsets, destination in
                guard arranging else { return }
                Task { handle(await lists.move(in: listId, fromOffsets: offsets, toOffset: destination)) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(arranging ? .active : .inactive))
        .kuroCollapseTracking($collapse, start: 0, distance: 44)
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: KuroJourneyChrome.barHeight) }
        .task(id: list.items) { await lists.hydrate(list.items) }
    }

    private func wordButton(_ key: OrganiseCopy.Key, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text(key))
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .underline(true, color: Color.kuroInk)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func row(_ key: MediaKey) -> some View {
        let media = lists.media[key]
        let tracked = lists.isTracked(key)
        return Button {
            guard !arranging else { return }
            KuroAccessibility.impactHaptic(.light)
            routes.openMedia(MediaRoute(key))
        } label: {
            HStack(spacing: KuroDesignSpacing.md) {
                FolioArtwork(url: media?.imageURL, width: 44, height: 62)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media?.title ?? "\(key.kind == .manga ? "Manga" : "Anime") #\(key.id)")
                        .font(.kuroTitleName())
                        .foregroundStyle(Color.kuroInk)
                        .multilineTextAlignment(.leading)
                    if !tracked {
                        Text(text(.notInLibrary)).font(.kuroMeta()).foregroundStyle(Color.kuroInkQuiet)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if tracked, let media {
                Button { organiseTarget = OrganiseTarget(media: media) } label: {
                    Label(text(.tagsAndLists), systemImage: "tag.circle")
                }
            }
            Button(role: .destructive) { remove(key) } label: {
                Label(text(.removeFromList), systemImage: "minus.circle")
            }
        }
        .accessibilityIdentifier("list.item.\(key.kind.rawValue).\(key.id)")
    }

    // MARK: Notices and actions

    @ViewBuilder
    private var noticeBar: some View {
        if let staleMove {
            FolioNoticeBar(notice: FolioNotice(tone: .problem, message: text(.staleMove),
                                               actionTitle: staleMove.isRetry ? nil : text(.tryAgain))) {
                let pending = staleMove
                self.staleMove = nil
                Task { handle(await lists.retry(pending)) }
            }
            .padding(.bottom, KuroDesignSpacing.sm)
        } else if let notice {
            FolioNoticeBar(notice: notice) { undoRemoval() }
                .padding(.bottom, KuroDesignSpacing.sm)
        }
    }

    private func handle(_ outcome: CustomListMoveOutcome) {
        switch outcome {
        case .moved: break
        case .stale(let pending): staleMove = pending
        case .failed(let error):
            if error == .staleList {
                staleMove = nil
                show(FolioNotice(tone: .problem, message: text(.staleMove), actionTitle: nil))
            } else {
                show(FolioNotice(tone: .problem, message: OrganiseCopy.error(error, german: german), actionTitle: nil))
            }
        }
    }

    private func remove(_ key: MediaKey) {
        Task {
            let receipt = await lists.remove(key, from: listId)
            removal = receipt
            show(FolioNotice(tone: .confirmation, message: text(.removed), actionTitle: receipt == nil ? nil : text(.undo)))
        }
    }

    private func undoRemoval() {
        guard let receipt = removal else { return }
        removal = nil
        notice = nil
        Task { _ = await lists.undo(receipt) }
    }

    private func show(_ next: FolioNotice) {
        notice = next
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(next.actionTitle == nil ? 3 : 6))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}
