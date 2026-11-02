import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - MANGA DETAIL VIEW
// The manga detail for everybody (series flags on or off) is the prototype page, `MangaDetailPage`
// (Kuro/Views/DetailPages/Prototype/MangaDetailSections.swift; its load table is in that file's
// header). The legacy body (genre pills, bottom dock) was removed in the prototype-fidelity pass
// (spec §5.2); its actions live on the hero status mark. The structs below (chapter rows/sheet, action
// dock, hero, similar rail, volumes) are kept for their other callers and earlier evidence renders.

struct MangaDetailView: View {
    let manga: Manga

    var body: some View {
        MangaDetailPage(manga: manga)
    }
}

// MARK: - Swiss-minimal metadata line (replaces grids)
struct MangaMetaLineSection: View {
    let manga: Manga

    private var scoreText: String? {
        guard let score = manga.averageScore, score > 0 else { return nil }
        return String(format: "%.1f", Double(score) / 10.0)
    }

    var body: some View {
        let german = KuroLocale.isGerman
        let parts: [String] = [
            scoreText.map { KuroLocale.text("Score \($0)", "Wertung \($0)") },
            manga.year.isEmpty ? nil : manga.year,
            DetailCopy.format(manga.format, german: german),
            manga.chapterCount.map { DetailCopy.chapters($0, german: german) },
            manga.volumeCount.map { DetailCopy.volumes($0, german: german) },
            DetailCopy.releaseStatus(manga.status, german: german)
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.kuroMicro(weight: .light))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(.kuroBlack60)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MangaSimilarSection: View {
    let title: String
    let items: [Manga]
    let containerWidth: CGFloat

    private var cardWidth: CGFloat {
        let candidate = floor((containerWidth - 56) / 2.8)
        return min(144, max(112, candidate))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            Text(title)
                .font(.kuroMicro(weight: .medium))
                .tracking(1.5)
                .foregroundColor(.kuroBlack80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items.prefix(14), id: \.id) { item in
                        KuroCompactCard(media: item, width: cardWidth)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - "NEXT" suggestion when user completed this manga (heuristic pick)
struct MangaNextPickSection: View {
    let mediaId: Int
    let similar: [Manga]
    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroRoutes) private var routes

    private var userEntry: LibraryEntry? {
        library.entry(for: MediaKey(kind: .manga, id: mediaId))
    }

    private var isCompleted: Bool {
        userEntry?.status == .completed
    }

    private var pick: Manga? {
        guard isCompleted else { return nil }
        if let planned = similar.first(where: { library.entry(for: $0.libraryKey)?.status == .planning }) {
            return planned
        }

        return similar
            .filter { !library.isTracked($0.libraryKey) }
            .max(by: { ($0.averageScore ?? 0) < ($1.averageScore ?? 0) })
    }

    var body: some View {
        if let manga = pick {
            VStack(alignment: .leading, spacing: KuroSpacing.md) {
                Text(KuroLocale.text("NEXT", "ALS NÄCHSTES"))
                    .font(.kuroCaption(weight: .medium))
                    .tracking(1.6)
                    .foregroundColor(.kuroBlack80)

                Button {
                    KuroAccessibility.impactHaptic(.light)
                    // Pushed inside the journey (navigation contract), never a sheet on the detail.
                    routes.openMedia(MediaRoute(kind: .manga, id: manga.id))
                } label: {
                    HStack(spacing: 12) {
                        KuroCachedAsyncImage(url: URL(string: manga.displayImage), maxPixelSize: 200) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .failure, .empty:
                                Rectangle().fill(Color.kuroBlack08)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 48, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(manga.displayTitle)
                                .font(.kuroBody(weight: .regular))
                                .foregroundColor(.kuroBlack)
                                .lineLimit(2)

                            HStack(spacing: 4) {
                                Text(manga.year)
                                if let fmt = manga.format {
                                    Text("·")
                                    Text(fmt.uppercased())
                                }
                            }
                            .font(.kuroCaption())
                            .foregroundColor(.kuroBlack60)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.kuroCustom(12, weight: .medium, maxSize: 19))
                            .foregroundColor(.kuroInkQuiet)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.kuroBlack08, lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Manga Hero Section
struct MangaHeroSection: View {
    let manga: Manga
    let geometry: GeometryProxy
    @Binding var scrollOffset: CGFloat
    
    var body: some View {
        // From the measured container (never the screen): about 320 pt on a 375 pt phone, capped on iPad.
        let baseHeight = min(max(geometry.size.width * 0.85, 224), 480, max(geometry.size.height * 0.6, 224))
        let stretch = max(scrollOffset, 0)
        let parallax = min(scrollOffset, 0) * 0.32

        ZStack(alignment: .bottom) {
            // Cover Image with Parallax
            KuroCachedAsyncImage(url: URL(string: manga.displayImage), maxPixelSize: 1100) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.kuroBlack08, Color.kuroBlack.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: geometry.size.width, height: baseHeight + stretch)
            .clipped()
            .offset(y: parallax - stretch)
            
            LinearGradient(
                colors: [Color.clear, Color.kuroBackground.opacity(0.92), Color.kuroBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 88)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            
            HStack(alignment: .bottom, spacing: 12) {
                KuroCachedAsyncImage(url: URL(string: manga.displayImage), maxPixelSize: 520) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.kuroBlack08)
                }
                .frame(width: 92, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 0.6)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.kuroBlack20, radius: 18, x: 0, y: 12)

                Spacer(minLength: 0)

                KuroStyle.mediaBadge("MANGA", isAnime: false)
            }
            .padding(.horizontal, geometry.size.width <= 330 ? KuroDesignSpacing.md : KuroDesignSpacing.padding)
            .padding(.bottom, 16)
        }
        .frame(height: baseHeight)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Manga Title Section
struct MangaTitleSection: View {
    let manga: Manga
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.sm) {
            // Japanese/Native Title
            if let nativeTitle = manga.titleNative {
                Text(nativeTitle)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Main Title
            Text(manga.displayTitle.uppercased())
                .font(.kuroCustom(24, weight: .ultraLight, design: .serif, relativeTo: .title2, maxSize: 40))
                .tracking(0.5)
                .foregroundColor(.kuroBlack)
                .lineSpacing(4)

            // Year and format appear once, in the metadata line (no second "2015 • Manga" line).
            MangaMetaLineSection(manga: manga)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chapters Section
struct ChaptersSection: View {
    let manga: Manga
    let chapterCount: Int?
    var onError: ((KuroToastState) -> Void)? = nil
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var progressActionScope = AccountActionScope()
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.openURL) private var openURL
    @State private var chapters: [MangaChapter] = []
    @State private var chapterStatus: MangaChapterStatus? = nil
    @State private var isLoading: Bool = false
    @State private var showAllChapters: Bool = false
    @State private var markingChapter: Int? = nil
    @State private var previewGeneration = UUID()
    @State private var legalReadLink: (url: String, site: String, label: String)? = nil

    private var entry: LibraryEntry? {
        library.entry(for: manga.libraryKey)
    }

    private var userProgress: Int {
        entry?.progress ?? 0
    }

    private var nextChapterNumber: Int {
        max(1, userProgress + 1)
    }

    private var shouldShowContinueLine: Bool {
        guard let status = entry?.status else { return userProgress > 0 }
        return userProgress > 0 || status == .current || status == .repeating
    }

    private var knownChapterTotal: Int {
        if let chapterCount { return chapterCount }
        if let statusCount = chapterStatus?.chapterRows { return statusCount }
        return chapters.count
    }
    
    var body: some View {
        let origin = progressActionScope.capture(session: libraryActions.accountSession)
        return VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text(KuroLocale.text("CHAPTERS", "KAPITEL"))
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text(KuroLocale.text("\(knownChapterTotal) total", "\(knownChapterTotal) insgesamt"))
                    .textCase(.uppercase)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }

            if shouldShowContinueLine {
                Text(KuroLocale.text("Continue with chapter \(nextChapterNumber).", "Weiter mit Kapitel \(nextChapterNumber)."))
                    .font(.kuroMicro(weight: .medium))
                    .foregroundColor(.kuroBlack60)
            }
            
            VStack(spacing: KuroSpacing.sm) {
                if isLoading && chapters.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        ChapterSkeletonRow()
                    }
                } else if chapters.isEmpty {
                    HStack {
                        Text(emptyStateMessage())
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroBlack60)
                        Spacer()
                    }
                    .padding(KuroSpacing.md)
                    .background(Color.kuroBlack08)
                    .cornerRadius(KuroRadius.sm)
                } else {
                    ForEach(chapters.prefix(1)) { ch in
                        ChapterItemRow(
                            chapter: ch,
                            isRead: ch.number <= userProgress,
                            isMarking: markingChapter == ch.number,
                            hasExternalLink: legalReadLink != nil,
                            onOpen: { openChapter(ch) },
                            onMarkRead: { markRead(ch, origin: origin) }
                        )
                    }
                }

                if !chapters.isEmpty && legalReadLink == nil {
                    HStack {
                        Text(KuroLocale.text("Link coming soon.", "Link folgt bald."))
                            .font(.kuroMicro(weight: .light))
                            .foregroundColor(.kuroBlack60)
                        Spacer()
                    }
                    .padding(.horizontal, KuroSpacing.md)
                }

                if knownChapterTotal > 5 {
                    Button(action: {
                        KuroAccessibility.impactHaptic(.light)
                        showAllChapters = true
                    }) {
                        DetailSectionUtilityButton(
                            title: KuroLocale.text("VIEW ALL \(knownChapterTotal) CHAPTERS", "ALLE \(knownChapterTotal) KAPITEL"),
                            subtitle: KuroLocale.text("Browse the full release list", "Die ganze Liste durchsehen")
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: nextChapterNumber) {
            guard !Task.isCancelled else { return }
            let generation = UUID()
            previewGeneration = generation
            let fromNumber = nextChapterNumber
            await loadPreview(generation: generation, fromNumber: fromNumber)
            guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
            await refreshChapterStatus(generation: generation, fromNumber: fromNumber)
            guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
            await refreshLegalReadLink(generation: generation, fromNumber: fromNumber)
        }
        .sheet(isPresented: $showAllChapters) {
            ChapterListSheet(manga: manga, chapterCount: chapterCount, chapterStatus: chapterStatus)
        }
        .onAppear { progressActionScope.activate(session: libraryActions.accountSession) }
        .onDisappear {
            progressActionScope.deactivate()
            markingChapter = nil
            previewGeneration = UUID()
            isLoading = false
        }
    }

    private func isCurrentPreview(_ generation: UUID, fromNumber: Int) -> Bool {
        !Task.isCancelled && previewGeneration == generation && nextChapterNumber == fromNumber
    }

    private func loadPreview(generation: UUID, fromNumber: Int) async {
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        isLoading = true
        defer {
            if isCurrentPreview(generation, fromNumber: fromNumber) { isLoading = false }
        }
        let preview = await catalog.fetchChaptersNext(mangaId: manga.id, fromNumber: fromNumber, limit: 10)
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        chapters = preview
    }

    private func refreshChapterStatus(generation: UUID, fromNumber: Int) async {
        let status = await catalog.fetchMangaChapterStatus(mangaId: manga.id)
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        chapterStatus = status
    }

    private func openChapter(_ _: MangaChapter) {
        guard let legalReadLink else { return }
        KuroAccessibility.impactHaptic(.light)
        guard let url = ProviderAvailabilityStore.validatedOutboundURL(legalReadLink.url) else { return }
        openURL(url)
    }

    private func refreshLegalReadLink(generation: UUID, fromNumber: Int) async {
        let best = await availability.getBestLegalReadLink(
            manga: manga,
            locale: Locale.current.identifier
        )
        guard isCurrentPreview(generation, fromNumber: fromNumber) else { return }
        legalReadLink = best.flatMap { ProviderAvailabilityStore.validatedOutboundURL($0.url) != nil ? $0 : nil }
    }

    private func markRead(_ ch: MangaChapter, origin: AccountActionScope.Ticket?) {
        guard progressActionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let target = chapterCount.map { min(ch.number, $0) } ?? ch.number
        markingChapter = ch.number
        progressActionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await LibraryViewActions.markProgress(manga.libraryKey, to: target, actions: libraryActions)
            guard progressActionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            if outcome.error != nil {
                KuroAccessibility.errorHaptic()
                onError?(KuroToastState(kind: .error, title: KuroLocale.text("Update failed", "Nicht gespeichert"), subtitle: KuroLocale.text("Could not mark chapter \(ch.number).", "Kapitel \(ch.number) konnte nicht markiert werden."), actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markRead failed for chapter \(ch.number): \(outcome)")
                #endif
            }
            markingChapter = nil
        }
    }

    private func emptyStateMessage() -> String {
        switch chapterStatus?.mappingStatus.lowercased() {
        case "syncing", "unresolved":
            return KuroLocale.text("Chapters are on their way.", "Die Kapitel sind unterwegs.")
        case "no_source":
            return KuroLocale.text("No chapter list for this title yet.", "Für diesen Titel gibt es noch keine Kapitelliste.")
        default:
            return KuroLocale.text("No chapters yet.", "Noch keine Kapitel.")
        }
    }
}

struct ChapterItemRow: View {
    let chapter: MangaChapter
    let isRead: Bool
    let isMarking: Bool
    let hasExternalLink: Bool
    let onOpen: () -> Void
    let onMarkRead: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(KuroLocale.text("CH \(chapter.number)", "KAP. \(chapter.number)").uppercased())
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.0)
                    .foregroundColor(.kuroBlack80)

                if let title = chapter.title ?? chapter.titleRomaji, !title.isEmpty {
                    Text(title)
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .lineLimit(1)
                } else if let date = chapter.releaseDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted).uppercased())
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.kuroBlack60)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(hasExternalLink ? KuroLocale.text("READ READY", "LESEN") : KuroLocale.text("LINK PENDING", "LINK FOLGT"))
                        .font(.kuroMicro(weight: .medium))
                        .tracking(0.8)
                        .foregroundColor(hasExternalLink ? .kuroBlack80 : .kuroBlack60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(hasExternalLink ? Color.kuroBlack08 : Color.kuroBlack05)
                        )
                }
            }

            Spacer()

            if isMarking {
                KuroBusyMark(width: 24)
                    .frame(minWidth: 44, minHeight: 44)
            } else if isRead {
                Image(systemName: "checkmark.circle.fill")
                    .font(.kuroCustom(14, weight: .semibold, maxSize: 22))
                    .foregroundColor(.kuroBlack)
            } else {
                Button(action: {
                    KuroAccessibility.impactHaptic(.light)
                    onMarkRead()
                }) {
                    Image(systemName: "plus.circle")
                        .font(.kuroCustom(16, weight: .regular, maxSize: 26))
                        .foregroundColor(.kuroBlack80)
                        // 44 pt target (rulebook §8); the row's own tap opens the link.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(KuroLocale.text("Mark read", "Als gelesen markieren"))
            }

            if hasExternalLink {
                Image(systemName: "link.circle")
                    .font(.kuroCustom(14, weight: .regular, maxSize: 22))
                    .foregroundColor(.kuroInkQuiet)
            }
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
        .contentShape(Rectangle())
        .onTapGesture { if hasExternalLink { onOpen() } }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabelText())
        .accessibilityValue(accessibilityValueText())
        .accessibilityHint(hasExternalLink ? KuroLocale.text("Opens legal read provider", "Öffnet den legalen Anbieter") : "")
        .accessibilityAction { if hasExternalLink { onOpen() } }
        .accessibilityAction(named: Text(KuroLocale.text("Mark read", "Als gelesen markieren"))) {
            if !isRead && !isMarking { onMarkRead() }
        }
    }

    private func accessibilityLabelText() -> Text {
        var parts: [String] = []
        parts.append(KuroLocale.text("Chapter \(chapter.number)", "Kapitel \(chapter.number)"))
        if let title = chapter.title ?? chapter.titleRomaji, !title.isEmpty {
            parts.append(title)
        } else if let date = chapter.releaseDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return Text(parts.joined(separator: ", "))
    }

    private func accessibilityValueText() -> Text {
        if isMarking { return Text(KuroLocale.text("Updating", "Wird gespeichert")) }
        return Text(isRead ? KuroLocale.text("Read", "Gelesen") : KuroLocale.text("Not read", "Nicht gelesen"))
    }
}

struct ChapterSkeletonRow: View {
    var body: some View {
        HStack {
            Rectangle()
                .fill(Color.kuroBlack.opacity(0.08))
                .frame(height: 10)
                .frame(maxWidth: 90, alignment: .leading)
            Spacer()
            Rectangle()
                .fill(Color.kuroBlack.opacity(0.06))
                .frame(width: 14, height: 14)
        }
        .padding(KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

struct ChapterListSheet: View {
    let manga: Manga
    let chapterCount: Int?
    let chapterStatus: MangaChapterStatus?
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var progressActionScope = AccountActionScope()
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var chapters: [MangaChapter] = []
    @State private var isLoading: Bool = false
    @State private var hasLoadedOnce: Bool = false
    @State private var hasMore: Bool = true
    @State private var offset: Int = 0
    @State private var pagingGeneration = UUID()
    @State private var pagingTask: Task<Void, Never>? = nil
    // Paging must not supersede the legal link, which belongs to the sheet lifetime.
    @State private var linkGeneration = UUID()
    @State private var markingChapter: Int? = nil
    @State private var toast: KuroToastState? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil
    @State private var legalReadLink: (url: String, site: String, label: String)? = nil

    private let pageSize: Int = 50

    private var userProgress: Int {
        library.entry(for: manga.libraryKey)?.progress ?? 0
    }

    var body: some View {
        let origin = progressActionScope.capture(session: libraryActions.accountSession)
        return NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: KuroSpacing.sm) {
                    if legalReadLink == nil {
                        HStack {
                            Text(KuroLocale.text("Link coming soon.", "Link folgt bald."))
                                .font(.kuroMicro(weight: .light))
                                .foregroundColor(.kuroBlack60)
                            Spacer()
                        }
                        .padding(.horizontal, KuroSpacing.md)
                        .padding(.vertical, KuroSpacing.sm)
                        .background(Color.kuroBlack08)
                        .cornerRadius(KuroRadius.sm)
                    }

                    if hasLoadedOnce && chapters.isEmpty && !isLoading {
                        VStack(spacing: 10) {
                            Text(KuroLocale.text("NO CHAPTERS FOUND", "KEINE KAPITEL GEFUNDEN"))
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.2)
                                .foregroundColor(.kuroBlack60)
                            Text(emptyStateMessage())
                                .font(.kuroMicro(weight: .light))
                                .foregroundColor(.kuroInkQuiet)
                        }
                        .padding(.vertical, 32)
                    }

                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, ch in
                        ChapterItemRow(
                            chapter: ch,
                            isRead: ch.number <= userProgress,
                            isMarking: markingChapter == ch.number,
                            hasExternalLink: legalReadLink != nil,
                            onOpen: { openChapter(ch) },
                            onMarkRead: { markRead(ch, origin: origin) }
                        )
                        .onAppear {
                            if index == chapters.count - 1, hasMore, !isLoading {
                                startLoadMore()
                            }
                        }
                    }

                    if isLoading {
                        KuroLoadingView(scope: .inline)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroSpacing.md)
                .padding(.bottom, KuroSpacing.xl)
            }
            .background(Color.kuroBackground)
            .navigationTitle(KuroLocale.text("Chapters", "Kapitel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DetailSheetCloseButton { dismiss() }
                }
            }
            .task(id: manga.id) {
                guard !Task.isCancelled else { return }
                pagingTask?.cancel()
                pagingTask = nil
                let generation = UUID()
                pagingGeneration = generation
                let legalLinkGeneration = UUID()
                linkGeneration = legalLinkGeneration
                await loadMore(reset: true, generation: generation)
                guard !Task.isCancelled, linkGeneration == legalLinkGeneration else { return }
                await refreshLegalReadLink(generation: legalLinkGeneration)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                KuroToast(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { progressActionScope.activate(session: libraryActions.accountSession) }
        .onDisappear {
            progressActionScope.deactivate()
            markingChapter = nil
            pagingGeneration = UUID()
            linkGeneration = UUID()
            pagingTask?.cancel()
            pagingTask = nil
            toastDismissTask?.cancel()
            isLoading = false
        }
    }

    @MainActor
    private func showToast(_ next: KuroToastState) {
        toastDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { toast = next }
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(2.2 * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.2)) { toast = nil }
            }
        }
    }

    private func startLoadMore() {
        guard hasMore, !isLoading, pagingTask == nil else { return }
        let generation = UUID()
        pagingGeneration = generation
        pagingTask = Task { await loadMore(generation: generation) }
    }

    private func loadMore(reset: Bool = false, generation: UUID) async {
        guard !Task.isCancelled, pagingGeneration == generation else { return }
        if reset {
            isLoading = false
            chapters = []
            offset = 0
            hasMore = true
            hasLoadedOnce = false
        }
        guard hasMore, !isLoading else { return }
        let requestedOffset = offset
        isLoading = true
        defer {
            if !Task.isCancelled, pagingGeneration == generation {
                isLoading = false
                pagingTask = nil
            }
        }

        let page = await catalog.fetchChaptersPage(mangaId: manga.id, offset: requestedOffset, limit: pageSize)
        guard !Task.isCancelled, pagingGeneration == generation, offset == requestedOffset else { return }
        chapters.append(contentsOf: page)
        hasMore = page.count == pageSize
        if hasMore { offset = requestedOffset + pageSize }
        hasLoadedOnce = true
    }

    private func openChapter(_ _: MangaChapter) {
        guard let legalReadLink else { return }
        KuroAccessibility.impactHaptic(.light)
        guard let url = ProviderAvailabilityStore.validatedOutboundURL(legalReadLink.url) else { return }
        openURL(url)
    }

    private func markRead(_ ch: MangaChapter, origin: AccountActionScope.Ticket?) {
        guard progressActionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let target = chapterCount.map { min(ch.number, $0) } ?? ch.number
        markingChapter = ch.number
        progressActionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = await LibraryViewActions.markProgress(manga.libraryKey, to: target, actions: libraryActions)
            guard progressActionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            if outcome.error != nil {
                KuroAccessibility.errorHaptic()
                showToast(KuroToastState(kind: .error, title: KuroLocale.text("Update failed", "Nicht gespeichert"), subtitle: KuroLocale.text("Could not mark chapter \(ch.number).", "Kapitel \(ch.number) konnte nicht markiert werden."), actionTitle: nil, onAction: nil))
                #if DEBUG
                print("markRead failed for chapter \(ch.number): \(outcome)")
                #endif
            }
            markingChapter = nil
        }
    }

    private func emptyStateMessage() -> String {
        switch chapterStatus?.mappingStatus.lowercased() {
        case "no_source":
            return KuroLocale.text("No chapter list for this title yet.", "Für diesen Titel gibt es noch keine Kapitelliste.")
        default:
            return KuroLocale.text("Chapters are on their way.", "Die Kapitel sind unterwegs.")
        }
    }

    private func refreshLegalReadLink(generation: UUID) async {
        let best = await availability.getBestLegalReadLink(
            manga: manga,
            locale: Locale.current.identifier
        )
        guard !Task.isCancelled, linkGeneration == generation else { return }
        legalReadLink = best.flatMap { ProviderAvailabilityStore.validatedOutboundURL($0.url) != nil ? $0 : nil }
    }
}

// MARK: - Volumes Section
struct VolumesSection: View {
    let manga: Manga
    let volumeCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                Text(KuroLocale.text("VOLUMES", "BÄNDE"))
                    .font(.kuroMicro(weight: .medium))
                    .tracking(1.5)
                    .foregroundColor(.kuroBlack80)
                
                Spacer()
                
                Text(KuroLocale.text("\(volumeCount) total", "\(volumeCount) insgesamt"))
                    .textCase(.uppercase)
                    .font(.kuroMicro(weight: .light))
                    .tracking(0.5)
                    .foregroundColor(.kuroBlack60)
            }
            
            // Volume grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: KuroSpacing.md
            ) {
                ForEach(1...min(volumeCount, 6), id: \.self) { volume in
                    VolumeCard(volumeNumber: volume)
                }
            }
            
            // "VIEW ALL VOLUMES" removed — no volume detail destination exists yet.
            // Re-add when volume browsing is implemented.
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Volume Card
struct VolumeCard: View {
    let volumeNumber: Int
    
    var body: some View {
        VStack(spacing: KuroSpacing.xs) {
            Image(systemName: "book.fill")
                .font(.kuroBody())
                .foregroundColor(.kuroInkQuiet)
            
            Text(KuroLocale.text("VOL \(volumeNumber)", "BD. \(volumeNumber)"))
                .font(.kuroMicro(weight: .medium))
                .tracking(0.5)
                .foregroundColor(.kuroBlack80)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, KuroSpacing.md)
        .background(Color.kuroBlack08)
        .cornerRadius(KuroRadius.sm)
    }
}

// MARK: - Manga Action Buttons
struct MangaActionButtons: View {
    let manga: Manga
    let onToast: (KuroToastState) -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(LibraryActions.self) private var libraryActions
    @State private var actionScope = AccountActionScope()
    @Environment(OutboundLinkTelemetry.self) private var outboundLinks
    @Environment(ProviderAvailabilityStore.self) private var availability
    @Environment(\.openURL) private var openURL
    @Environment(\.kuroRoutes) private var routes
    @State private var showQuickVerdict = false
    @State private var showProviders = false
    @State private var readLink: ProviderSheetItem? = nil
    @State private var allLinks: [ProviderSheetItem] = []
    @State private var readAvailabilityNote: String? = nil
    @State private var readAvailabilityStatusCaption: String? = nil

    private var isGermanLocale: Bool {
        KuroLocale.isGerman
    }

    private var isSaved: Bool {
        library.isTracked(manga.libraryKey)
    }

    private var userEntry: LibraryEntry? {
        library.entry(for: manga.libraryKey)
    }

    private var hasReadLink: Bool {
        readLink.flatMap { ProviderAvailabilityStore.validatedOutboundURL($0.url) } != nil
    }

    private var listButtonTitle: String {
        isSaved ? KuroLocale.text("Edit list", "Liste bearbeiten") : KuroLocale.text("Add to list", "Zur Liste")
    }

    private var verdictButtonTitle: String {
        guard let verdict = userEntry?.verdict else { return isGermanLocale ? "Urteil" : "Verdict" }
        return isGermanLocale ? verdict.displayNameDE : verdict.displayName
    }

    /// The line under the dock. Without a legal link (the read button is hidden) it says so first, so the
    /// caption or note never implies links that are not there and VoiceOver hears why there is no button.
    private var readStatusLine: String {
        guard hasReadLink else {
            return KuroLocale.text("No legal provider link is available yet.", "Noch kein legaler Link verfügbar.")
        }
        if let status = readAvailabilityStatusCaption, !status.isEmpty {
            return status
        }
        if let note = readAvailabilityNote, !note.isEmpty {
            return note
        }
        return KuroLocale.text("Open legal provider link.", "Rechtlich verfügbaren Link öffnen.")
    }

    var body: some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                dockRow(origin: origin, listForm: .full, verdictForm: .full)
                dockRow(origin: origin, listForm: .full, verdictForm: .icon)
                dockRow(origin: origin, listForm: .text, verdictForm: .icon)
                dockRow(origin: origin, listForm: .icon, verdictForm: .icon)
            }

            Text(readStatusLine)
                .font(.kuroCaption(weight: .regular))
                .foregroundColor(.kuroInkQuiet)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate() }
        .task(id: manga.id) {
            await refreshLinks()
        }
        .sheet(isPresented: $showQuickVerdict) {
            QuickVerdictPickerSheet(media: manga, onToast: onToast)
        }
        .sheet(isPresented: $showProviders) {
            ProviderSelectionSheet(
                title: KuroLocale.text("Read on", "Lesen bei"),
                links: allLinks,
                statusCaption: readAvailabilityStatusCaption
            ) { link in
                if let url = ProviderAvailabilityStore.validatedOutboundURL(link.url) {
                    KuroAccessibility.impactHaptic(.light)
                    outboundLinks.recordOutboundLink(mediaType: "MANGA", mediaId: manga.id, linkKind: "provider_sheet", provider: link.title)
                    openURL(url)
                } else {
                    onToast(.init(kind: .error, title: KuroLocale.text("Couldn’t open link", "Link konnte nicht geöffnet werden"), subtitle: KuroLocale.text("Try a different provider.", "Versuch einen anderen Anbieter."), actionTitle: nil, onAction: nil))
                }
            }
        }
    }

    /// One arrangement of the dock's buttons. `body` offers the widest first and steps down (verdict
    /// to its icon, then the list button to its word, then to its glyph) so nothing truncates.
    @ViewBuilder
    private func dockRow(origin: AccountActionScope.Ticket?, listForm: DetailDockLabelForm, verdictForm: DetailDockLabelForm) -> some View {
        HStack(spacing: 8) {
            Button { toggleSaved(origin: origin) } label: {
                DetailDockCapsule(role: .secondary, iconOnly: true) {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                }
            }
            .buttonStyle(KuroPressStyle())
            .accessibilityLabel(isSaved ? KuroLocale.text("Saved", "Gemerkt") : KuroLocale.text("Save", "Merken"))

            Button {
                KuroAccessibility.impactHaptic(.medium)
                routes.presentTrackingEditor(TrackingEditorRequest(media: manga))
            } label: {
                DetailDockCapsule(role: .primary, iconOnly: listForm == .icon) {
                    // The glyph says which action this is (add vs edit) when the word does not fit.
                    DetailDockLabel(form: listForm, systemImage: isSaved ? "pencil" : "plus", title: listButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(KuroPressStyle())
            .accessibilityLabel(listButtonTitle)

            Button {
                KuroAccessibility.impactHaptic(.light)
                showQuickVerdict = true
            } label: {
                DetailDockCapsule(role: .secondary, iconOnly: verdictForm == .icon) {
                    DetailDockLabel(form: verdictForm, systemImage: "tag", title: verdictButtonTitle)
                }
            }
            .buttonStyle(KuroPressStyle())
            .accessibilityLabel(userEntry?.verdict == nil ? KuroLocale.text("Set verdict", "Urteil festlegen") : KuroLocale.text("Edit verdict, \(verdictButtonTitle)", "Urteil bearbeiten, \(verdictButtonTitle)"))

            // Shown only with a legal link to open; without one the line below says so (no greyed button).
            if hasReadLink {
                Button(action: handleReadAction) {
                    DetailDockCapsule(role: .secondary, iconOnly: true) {
                        Image(systemName: "book.fill")
                    }
                }
                .buttonStyle(KuroPressStyle())
                .accessibilityLabel(
                    allLinks.count > 1
                        ? KuroLocale.text("Choose reading provider", "Anbieter zum Lesen wählen")
                        : KuroLocale.text("Open reading provider", "Anbieter zum Lesen öffnen")
                )
            }
        }
    }

    private func toggleSaved(origin: AccountActionScope.Ticket?) {
        guard actionScope.isCurrent(origin, session: libraryActions.accountSession) else { return }
        let currentlySaved = isSaved
        let key = manga.libraryKey
        actionScope.launch(origin: origin, session: libraryActions.accountSession) { ticket in
            let outcome = currentlySaved
                ? await libraryActions.remove(key)
                : await libraryActions.save(key, status: .planning)

            guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
            await MainActor.run {
                guard actionScope.isCurrent(ticket, session: libraryActions.accountSession) else { return }
                if outcome.change != nil {
                    KuroAccessibility.successHaptic()
                    onToast(
                        .init(
                            kind: .success,
                            title: currentlySaved ? KuroLocale.text("Removed", "Entfernt") : KuroLocale.text("Saved", "Gemerkt"),
                            subtitle: currentlySaved ? KuroLocale.text("Removed from your list", "Aus deiner Liste entfernt") : KuroLocale.text("Added to Planning", "Zu „Geplant“ hinzugefügt"),
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                } else {
                    KuroAccessibility.errorHaptic()
                    onToast(
                        .init(
                            kind: .error,
                            title: KuroLocale.text("Couldn't save", "Nicht gespeichert"),
                            subtitle: outcome.error.map { friendlyListMutationMessage($0, isGerman: KuroLocale.isGerman) },
                            actionTitle: nil,
                            onAction: nil
                        )
                    )
                }
            }
        }
    }

    private func handleReadAction() {
        guard let link = readLink, let linkURL = ProviderAvailabilityStore.validatedOutboundURL(link.url) else {
            KuroAccessibility.impactHaptic(.light)
            onToast(
                .init(
                    kind: .info,
                    title: KuroLocale.text("Link coming soon", "Link folgt bald"),
                    subtitle: KuroLocale.text("No legal provider link is available yet.", "Noch kein legaler Anbieter-Link verfügbar."),
                    actionTitle: nil,
                    onAction: nil
                )
            )
            return
        }

        KuroAccessibility.impactHaptic(.medium)
        if allLinks.count > 1 {
            showProviders = true
        } else {
            outboundLinks.recordOutboundLink(mediaType: "MANGA", mediaId: manga.id, linkKind: "read", provider: link.title)
            openURL(linkURL)
        }
    }

    /// Resolves the read links through the ProviderAvailability owner (keyed on the manga id; the
    /// primary is the first item) and publishes them unless this run was superseded.
    private func refreshLinks() async {
        guard let snapshot = await availability.resolveReadLinks(mangaId: manga.id),
              !Task.isCancelled else { return }
        allLinks = snapshot.all
        readLink = snapshot.primary
        readAvailabilityNote = snapshot.note
        readAvailabilityStatusCaption = snapshot.statusCaption
    }
}
