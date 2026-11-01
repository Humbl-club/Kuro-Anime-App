import KuroCore
import KuroLibrary
import SwiftUI

/// The series anime detail now is the one prototype detail page (prototype fidelity, Task 6): both flag
/// worlds show `AnimeDetailPage`, which reads `series_detail_bundle_v1` opportunistically when the series
/// flags are on. Kept as a thin delegate so existing callers and evidence renders keep their API; a
/// preview bundle is shown without network reads.
struct SeriesAnimeDetailView: View {
    let anime: Anime
    private let preview: AnimeDetailContent?

    init(anime: Anime, previewBundle: SeriesDetailBundle? = nil, legacy: (() -> AnyView)? = nil) {
        self.anime = anime
        self.preview = previewBundle.map { AnimeDetailContent(bundle: $0) }
    }

    var body: some View {
        AnimeDetailPage(anime: anime, preview: preview)
    }
}

/// Manga detail (rulebook §14.2): cover, real premise when the catalogue has one, bookmark, editions,
/// reciprocal guide. Legacy sections replace it when the bundle has no series data (spec D15).
struct SeriesMangaDetailView: View {
    let manga: Manga
    @State private var mode: SeriesDetailMode
    @State private var releaseItems: [ReleaseScheduleItem]?
    @State private var releaseSongs: [ThemeSong]?
    private let legacy: (() -> AnyView)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(HomeStore.self) private var home
    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroRoutes) private var routes
    @State private var bundle: SeriesDetailBundle?
    @State private var loadError: String?
    @State private var watchedChoice: String?
    @State private var loadGeneration = UUID()
    @State private var isLoading = false
    @State private var showDiscussion = false
    private let skipNetworkLoad: Bool

    init(manga: Manga, previewBundle: SeriesDetailBundle? = nil, legacy: (() -> AnyView)? = nil) {
        self.manga = manga
        self.legacy = legacy
        self._mode = State(initialValue: SeriesDetailMode.initial(preview: previewBundle, hasLegacy: legacy != nil))
        self._bundle = State(initialValue: previewBundle)
        self.skipNetworkLoad = previewBundle != nil
    }

    var body: some View {
        Group {
            switch mode {
            case .legacy:
                if let legacy { legacy() } else { seriesBody }
            case .resolving:
                SeriesResolvingView(title: manga.displayTitle)
            case .series:
                seriesBody
            }
        }
        .task(id: loadGeneration) {
            guard !skipNetworkLoad, mode != .legacy else { return }
            await load()
        }
        .onChange(of: home.privacyEpoch) { _, _ in
            bundle = nil
            showDiscussion = false
            watchedChoice = nil
            loadGeneration = UUID()
        }
    }

    private var seriesBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                if let bundle { SeriesTrackingAction(bundle: bundle) }
                story
                bookmark
                DetailNextReleaseSection(items: releaseItems ?? [])
                chapters
                guide
                cast
                SeriesPrincipals(items:bundle?.principals ?? [])
                betweenUs
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.bottom, 28)
            .foregroundStyle(Color.kuroInk)
            .kuroReadableWidth()
        }
        .background(Color.kuroCanvasPage)
        .tint(Color.kuroInk)
        .routePresenter()
        .overlay(alignment: .topTrailing) {
            SeriesCloseButton()
        }
        .detailReleases(kind: .manga, id: manga.id, schedule: $releaseItems, songs: $releaseSongs)
    }

    private var intro: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                    cover.frame(width: 128)
                    heading
                }
            } else {
                HStack(alignment: .center, spacing: 23) {
                    cover.containerRelativeFrame(.horizontal) { width, _ in min(128, max(0, width - 40) * 0.35) }
                    heading.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.padding(.top, 12).padding(.bottom, 8)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
            Text(bundle?.header.title ?? manga.displayTitle)
                .font(.kuroFeature())
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let status = SeriesDetailFallback.statusText(bundle?.header.catalogueStatus ?? manga.status, medium: .manga) {
                Text(status)
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 44)
        .padding(.trailing, 8)
    }

    private var cover: some View {
        let raw = bundle?.header.coverImage ?? manga.coverImageLarge ?? manga.coverImageMedium
        let url = SeriesArtwork.verified(raw)
        return Group {
            if let url {
                KuroCachedAsyncImage(url: url, maxPixelSize: 1200) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        Color.kuroMissingArt
                    }
                }
            } else {
                Color.kuroMissingArt
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.kuroHairline))
        .accessibilityLabel(KuroLocale.text("Cover of \(manga.displayTitle)", "Cover von \(manga.displayTitle)"))
    }

    @ViewBuilder
    private var story: some View {
        if let copy = bundle?.copy, copy.premise != nil || copy.synopsis != nil {
            if let hook=copy.hook { Text(hook).font(.kuroTitle()).fixedSize(horizontal: false, vertical: true) }
            if let premise=copy.premise { Text(premise).font(.kuroBody()).fixedSize(horizontal: false, vertical: true) }
            if let synopsis = bundle?.copy.synopsis {
                DisclosureGroup(KuroLocale.text("The story", "Die Geschichte")) {
                    Text(synopsis).font(.kuroBody()).fixedSize(horizontal: false, vertical: true)
                }
                .font(.kuroBody(weight: .medium))
            }
        }
        // No premise on file: the section is omitted (rulebook §9, missing optional metadata).
    }

    @ViewBuilder private var bookmark: some View {
        if let bundle {
            SeriesBookmark(bundle:bundle)
        }
        if isLoading { KuroStateView(.loading, layout: .inline) }
        if let loadError {
            KuroStateView(.failed(hasCachedContent: false), title: loadError, layout: .inline) { loadGeneration = UUID() }
        }
    }

    @ViewBuilder private var chapters: some View {
        if let bundle {
            SeriesUnitsView(bundle:bundle,sectionId:nil)
                .id("manga:\(bundle.mediaId):\(home.privacyEpoch)")
        }
    }

    private var guide: some View {
        let guides=bundle?.adaptations ?? []
        let selected=guides.first { ($0.sectionId ?? "anime:\($0.animeId ?? 0)") == watchedChoice }
        return DisclosureGroup(KuroLocale.text("I've watched the anime", "Ich habe den Anime gesehen")) {
            if guides.isEmpty {
                Text(SeriesCopy.boundaryUnknown(sourceKind: "manga"))
                    .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(KuroLocale.text("Season you finished", "Gesehene Staffel"),selection:$watchedChoice) {
                    Text(KuroLocale.text("Choose a season", "Staffel wählen")).tag(String?.none)
                    ForEach(guides.indices,id:\.self) { index in
                        let guide=guides[index]
                        Text(guide.season ?? KuroLocale.text("Anime adaptation", "Anime-Adaption")).tag(Optional(guide.sectionId ?? "anime:\(guide.animeId ?? 0)"))
                    }
                }.pickerStyle(.menu).frame(minHeight:44)
                if let selected {
                    if selected.mappingState == "exact" || selected.mappingState == "partial" {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top) { guidePoints(selected) }
                            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) { guidePoints(selected) }
                        }
                    }
                    if let id=selected.animeId {
                        KuroInkButton(KuroLocale.text("Open anime", "Anime öffnen"), role: .secondary) {
                            routes.openMedia(MediaRoute(kind:.anime,id:id))
                        }
                    }
                    Text(selected.mappingState == "exact"
                         ? KuroLocale.text("The season ends exactly here.", "Die Staffel endet genau hier.")
                         : (selected.mappingState == "partial"
                            ? KuroLocale.text("Some chapters differ from the anime.", "Einige Kapitel weichen vom Anime ab.")
                            : SeriesCopy.boundaryUnknown(sourceKind: "manga")))
                        .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }.font(.kuroBody(weight: .medium)).padding(.vertical,8)
    }
    @ViewBuilder private func guidePoints(_ selected: SeriesDetailBundle.Coverage) -> some View {
        if let start=selected.startsAt { guidePoint(KuroLocale.text("Starts", "Beginnt"),start) }
        if let end=selected.endsAt { guidePoint(KuroLocale.text("Ends", "Endet"),end) }
        if let next=selected.readNext { guidePoint(KuroLocale.text("Read on from", "Weiterlesen ab"),next) }
    }
    private func guidePoint(_ title:String,_ value:String)->some View {
        VStack(alignment:.leading,spacing:5) {
            Text(title).font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
            Text(value).font(.kuroBody()).foregroundStyle(Color.kuroInk)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
    }

    private var cast: some View { SeriesCast(items:bundle?.cast ?? []) }
    private var betweenUs: some View {
        Group {
            if let bundle {
                DisclosureGroup(isExpanded: $showDiscussion) {
                    if showDiscussion {
                    FriendsActivitySection(mediaId: bundle.mediaId, mediaType: "MANGA", editorial: true)
                        .id("manga:\(bundle.mediaId):\(home.privacyEpoch)")
                    }
                } label: {
                    SeriesDiscussionHeading(title: bundle.header.title, imageURL: bundle.header.coverImage)
                }
                .modifier(SeriesDiscussionMaterial(medium: bundle.medium))
            }
        }
    }

    private func load() async {
        let token = loadGeneration
        isLoading = true
        defer { if token == loadGeneration { isLoading = false } }
        #if canImport(Supabase)
        do {
            let loaded = try await home.detailBundle(medium: "manga", mediaId: manga.id, sectionId: nil)
            guard token == loadGeneration, !Task.isCancelled else { return }
            bundle = loaded
            loadError = nil
            mode = mode.resolved(bundle: loaded, loadFailed: false, hasLegacy: legacy != nil)
        } catch is CancellationError {
            // `detailBundle` also throws this with no account or client: still settle the first answer.
            if token == loadGeneration, !Task.isCancelled {
                mode = mode.resolved(bundle: nil, loadFailed: true, hasLegacy: legacy != nil)
            }
            return
        } catch {
            guard token == loadGeneration, !Task.isCancelled else { return }
            loadError = KuroLocale.text("Couldn't load this book.", "Dieses Buch konnte nicht geladen werden.")
            mode = mode.resolved(bundle: nil, loadFailed: true, hasLegacy: legacy != nil)
        }
        #else
        loadError = KuroLocale.text("Couldn't load this book.", "Dieses Buch konnte nicht geladen werden.")
        mode = mode.resolved(bundle: nil, loadFailed: true, hasLegacy: legacy != nil)
        #endif
    }
}

/// http(s) artwork only. A bare string is not a picture.
private enum SeriesArtwork {
    static func verified(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}

private struct SeriesCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button(action: dismiss.callAsFunction) {
            Image(systemName: "xmark")
                .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 20))
                .foregroundStyle(Color.kuroInk)
                .frame(width: 44, height: 44)
                .background(Color.kuroWhite92, in: Circle())
                .overlay(Circle().strokeBorder(Color.kuroHairline))
                .contentShape(Circle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityLabel(KuroLocale.text("Close", "Schließen"))
        .padding(.top, 8)
        .padding(.trailing, 12)
    }
}

private struct SeriesSeasonPanel: View {
    let name: String
    let imageURL: URL?
    let isSelected: Bool

    var body: some View {
        Group {
            if let imageURL {
                KuroCachedAsyncImage(url: imageURL, maxPixelSize: 480) { phase in
                    if case .success(let image) = phase {
                        face(image: image, title: .white, scrim: true)
                    } else {
                        face(image: nil, title: Color.kuroInk, scrim: false)
                    }
                }
            } else {
                face(image: nil, title: Color.kuroInk, scrim: false)
            }
        }
    }

    private func face(image: Image?, title: Color, scrim: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(name)
                .font(.kuroCaption())
                .foregroundStyle(title)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .bottomLeading) {
                    if scrim {
                        LinearGradient(
                            stops: [
                                .init(color: Color.kuroBlack25, location: 0),
                                .init(color: Color.kuroBlack70, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
        }
        .frame(minWidth: 132, maxWidth: 132, minHeight: 88, alignment: .bottom)
        .background {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Color.kuroMissingArt
            }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? Color.kuroInk : Color.clear)
                .frame(height: 2)
        }
    }
}

private struct SeriesDiscussionHeading: View {
    let title: String
    let imageURL: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        HStack(spacing: 19) {
            KuroCachedAsyncImage(url: SeriesArtwork.verified(imageURL), maxPixelSize: 240) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
                else { Color.kuroMissingArt }
            }.frame(width: dynamicTypeSize.isAccessibilitySize ? 44 : 105, height: dynamicTypeSize.isAccessibilitySize ? 66 : 145)
                .clipped().clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: KuroDesignSpacing.xs) {
                Text(KuroLocale.text("Your clubs · private", "Deine Clubs · privat")).font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                Text(KuroLocale.text("Between us.", "Unter uns.")).font(.kuroHeadline()).fixedSize(horizontal: false, vertical: true)
                Text(title).font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, KuroDesignSpacing.sm)
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).foregroundStyle(Color.kuroInk)
            .accessibilityLabel(KuroLocale.text("Between us. Private club discussion for \(title)",
                                                "Unter uns. Private Club-Diskussion zu \(title)"))
    }
}


/// The disclosure still owns whether protected content mounts. This modifier is material only.
private struct SeriesDiscussionMaterial: ViewModifier {
    let medium: String
    func body(content: Content) -> some View {
        content.padding(KuroDesignSpacing.md)
            .tint(Color.kuroInk)
            .background(Color.kuroCanvasQuiet)
            .clipShape(shape)
            .overlay(shape.stroke(Color.kuroHairline))
    }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: medium == "manga" ? 5 : 22,
            bottomLeadingRadius: medium == "manga" ? 5 : 8,
            bottomTrailingRadius: medium == "manga" ? 5 : 8,
            topTrailingRadius: medium == "manga" ? 19 : 22)
    }
}

/// The selected source entry supplies the editor's identity, never the original season's ID.
private func detailMedia(_ bundle:SeriesDetailBundle)->Media {
    Media(id:bundle.mediaId,kind:bundle.medium == "manga" ? .manga : .anime,title:bundle.header.title,
          imageURL:bundle.header.coverImage,year:"",displayDescription:bundle.header.description ?? "",
          episodes:bundle.header.episodes,chapters:bundle.header.chapters,rating:nil,genres:nil,
          statusRaw:bundle.header.catalogueStatus,formatRaw:bundle.header.format,popularityValue:nil,trendingValue:nil,createdAtValue:nil)
}

/// The bundle supplies public context; tracking always follows the Library owner after
/// Add/status/remove writes. Unknown Library state may use the authenticated bundle baseline.
@MainActor
private func currentTrackingUser(_ bundle: SeriesDetailBundle, library: LibraryStore) -> SeriesDetailBundle.UserState? {
    let key = MediaKey(kind: bundle.medium == "manga" ? .manga : .anime, id: bundle.mediaId)
    guard let entry = library.entry(for: key) else {
        return library.loadState == .loaded ? nil : bundle.user
    }
    guard let revision = entry.revision, let lifecycle = entry.lifecycleId else { return nil }
    return SeriesDetailBundle.UserState(serverRevision: revision, lifecycleId: lifecycle.uuidString,
        progress: entry.progress, progressLabel: entry.progressLabel, listType: entry.status.rawValue, notes: entry.notes,
        unitId: entry.unitId?.uuidString)
}

private struct SeriesBookmark: View {
    let bundle:SeriesDetailBundle
    var sectionId: String? = nil
    @Environment(HomeStore.self) private var home
    @Environment(LibraryActions.self) private var libraryActions
    @State private var actionScope = AccountActionScope()
    @Environment(LibraryStore.self) private var library
    @State private var draft=""
    @State private var error:String?
    @State private var showUnitChooser = false
    @State private var showEditor = false
    var body:some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        if let user=currentTrackingUser(bundle, library: library) {
            let progress=home.displayedProgress(medium:bundle.medium,mediaId:bundle.mediaId,server:user.progress,lifecycleId:UUID(uuidString:user.lifecycleId))
            let label=home.displayedProgressLabel(medium:bundle.medium,mediaId:bundle.mediaId,serverLabel:user.progressLabel,lifecycleId:UUID(uuidString:user.lifecycleId),serverRevision:user.serverRevision) ?? String(progress)
            let unitId = home.displayedUnitId(medium: bundle.medium, mediaId: bundle.mediaId,
                serverUnitId: user.unitId, lifecycleId: UUID(uuidString: user.lifecycleId), serverRevision: user.serverRevision)
            let needsUnitChoice = unitId != nil || Int(label) != progress
            let isManga = bundle.medium == "manga"
            let cap = isManga ? bundle.header.chapters : bundle.header.episodes
            let caughtUp = cap.map { progress >= $0 } ?? false
            // A concise inline control (rulebook §14.2): the number beside its unit, a 44 pt step back,
            // the shared +1 key that advances at once, and "Go to…" as an explicit editor with Save.
            VStack(alignment:.leading,spacing:KuroDesignSpacing.sm) {
                Text(isManga ? KuroLocale.text("Your bookmark", "Dein Lesezeichen") : KuroLocale.text("Your progress", "Dein Fortschritt"))
                    .kuroKicker()
                    .accessibilityAddTraits(.isHeader)
                HStack(alignment: .center, spacing:12) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(isManga ? KuroLocale.text("Ch.", "Kap.") : KuroLocale.text("Ep.", "F."))
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkQuiet)
                        Text(label).font(.kuroFeature()).monospacedDigit()
                        if let cap, !isManga { Text("/ \(cap)").font(.kuroMeta()).foregroundStyle(Color.kuroInkQuiet) }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(SeriesCopy.position(isManga: isManga, label: label, total: cap))
                    Spacer(minLength: KuroDesignSpacing.sm)
                    if !needsUnitChoice {
                        Button { actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in await home.setPosition(medium:bundle.medium,mediaId:bundle.mediaId,user:user,position:max(0,progress-1)) } }
                            label: {
                                Image(systemName:"minus")
                                    .font(.kuroCustom(15, weight: .medium, relativeTo: .body, maxSize: 22))
                                    .foregroundStyle(Color.kuroInk)
                                    .frame(width:44,height:44)
                                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.kuroKeyRim))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(HomeContactStyle())
                            .disabled(progress <= 0)
                            .accessibilityLabel(isManga ? KuroLocale.text("Back one chapter", "Ein Kapitel zurück")
                                                        : KuroLocale.text("Back one episode", "Eine Folge zurück"))
                    }
                    KuroAdvanceKey(style: isManga ? .dark : .light,
                                   phase: needsUnitChoice ? .needsChoice : (caughtUp ? .caughtUp : .advance),
                                   accessibilityText: needsUnitChoice
                                       ? (isManga
                                          ? KuroLocale.text("Choose the next chapter of \(bundle.header.title)", "Nächstes Kapitel von \(bundle.header.title) auswählen")
                                          : KuroLocale.text("Choose the next episode of \(bundle.header.title)", "Nächste Folge von \(bundle.header.title) auswählen"))
                                       : (caughtUp ? KuroAdvanceCopy.caughtUpLabel(title: bundle.header.title, german: KuroLocale.isGerman)
                                          : KuroAdvanceCopy.label(medium: isManga ? .manga : .anime, nextUnit: progress + 1,
                                                                  title: bundle.header.title, current: progress, total: cap,
                                                                  german: KuroLocale.isGerman))) {
                        if needsUnitChoice { showUnitChooser = true }
                        else { actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in await home.advance(medium:bundle.medium,mediaId:bundle.mediaId,lifecycleId:user.lifecycleId,
                            baseRevision:user.serverRevision,serverProgress:user.progress,episodeCap:cap,
                            serverLabel:user.progressLabel,serverUnitId:user.unitId) } }
                    }
                }
                Button {
                    showEditor.toggle()
                } label: {
                    Text(isManga ? KuroLocale.text("Go to chapter…", "Zu Kapitel springen…") : KuroLocale.text("Go to episode…", "Zu Folge springen…"))
                        .font(.kuroMeta(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HomeContactStyle())
                .accessibilityAddTraits(showEditor ? .isSelected : [])
                if showEditor {
                    HStack {
                        TextField(isManga ? KuroLocale.text("Chapter", "Kapitel") : KuroLocale.text("Episode", "Folge"), text:$draft)
                            .keyboardType(.numberPad).font(.kuroBody()).frame(minHeight:44)
                            .padding(.horizontal, KuroDesignSpacing.sm)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroInk).frame(height: 1) }
                        Button {
                            guard let position=Int(draft),position>=0, position <= (cap ?? Int.max) else {
                                error = cap.map { KuroLocale.text("Enter a number from 0 to \($0).", "Gib eine Zahl von 0 bis \($0) ein.") }
                                    ?? KuroLocale.text("Enter a number from 0.", "Gib eine Zahl ab 0 ein.")
                                return
                            }
                            error=nil
                            showEditor = false
                            actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in await home.setPosition(medium:bundle.medium,mediaId:bundle.mediaId,user:user,position:position) }
                        } label: {
                            Text(KuroLocale.text("Save", "Speichern"))
                                .font(.kuroMeta(weight: .semibold))
                                .foregroundStyle(Color.kuroInk)
                                .frame(minWidth:44,minHeight:44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(HomeContactStyle())
                    }
                }
                // Inline validation error: the destructive ink (AA on white), never colour alone.
                if let error { Text(error).font(.kuroMeta()).foregroundStyle(Color.kuroDestructiveInk) }
                if let status=home.statusMessage { Text(HomeCopy.display(status)).font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary) }
            }
            .padding(.vertical, KuroDesignSpacing.md)
            .overlay(alignment: .top) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
            .onAppear { actionScope.activate(session: libraryActions.accountSession) }
            .onDisappear { actionScope.deactivate() }
            .sheet(isPresented: $showUnitChooser) {
                NavigationStack {
                    ScrollView {
                        SeriesUnitsView(bundle: bundle, sectionId: sectionId, showsBookmark: false)
                            .padding(KuroDesignSpacing.md)
                    }.toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button(KuroLocale.text("Done", "Fertig")) { showUnitChooser = false } }
                    }
                }
            }
        }
    }
}

private struct SeriesUnitsView: View {
    let bundle:SeriesDetailBundle
    let sectionId:String?
    var showsBookmark = true
    @Environment(HomeStore.self) private var home
    @Environment(LibraryActions.self) private var libraryActions
    @State private var actionScope = AccountActionScope()
    @Environment(LibraryStore.self) private var library
    @State private var units:[SeriesDetailBundle.Unit]=[]
    @State private var cursor:SeriesUnitPage.Cursor?
    @State private var edition:String?
    @State private var editionKeys: [String] = []
    @State private var editionsCursor: String?
    @State private var editionsGeneration = 0
    @State private var loadingEditions = false
    @State private var editionsError: String?
    @State private var pageGeneration=0
    @State private var loading=false
    @State private var error:String?
    @State private var expanded = false
    @State private var needsInitialPage = false
    private var isManga: Bool { bundle.medium == "manga" }
    var body:some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        VStack(alignment:.leading,spacing:12) {
            if bundle.medium == "anime" && showsBookmark { SeriesBookmark(bundle:bundle, sectionId:sectionId) }
            KuroSectionHeader(isManga ? KuroLocale.text("Chapters", "Kapitel") : KuroLocale.text("Episodes", "Folgen"), size: .title)
            if editionKeys.count>1 {
                Picker(KuroLocale.text("Edition", "Ausgabe"), selection: Binding(get: { edition ?? "" }, set: selectEdition)) {
                    ForEach(editionKeys,id:\.self) { Text($0.isEmpty ? KuroLocale.text("Original", "Original") : $0).tag($0) }
                }.frame(minHeight:44)
            } else if let edition {
                Text(edition.isEmpty ? KuroLocale.text("Original edition", "Originalausgabe") : edition)
                    .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
            }
            if loadingEditions { KuroStateView(.loading, layout: .inline) }
            if let editionsError {
                KuroStateView(.failed(hasCachedContent: !editionKeys.isEmpty), title: editionsError, layout: .inline) { Task { await moreEditions() } }
            } else if editionsCursor != nil {
                Button(KuroLocale.text("More editions", "Weitere Ausgaben")) { Task { await moreEditions() } }
                    .font(.kuroMeta(weight: .medium)).frame(minHeight: 44).buttonStyle(HomeContactStyle())
            }
            if units.isEmpty && !loading {
                Text(isManga ? KuroLocale.text("Chapters aren't listed yet.", "Kapitel sind noch nicht aufgeführt.")
                             : KuroLocale.text("Episodes aren't listed yet.", "Folgen sind noch nicht aufgeführt."))
                    .font(.kuroMeta()).foregroundStyle(Color.kuroInkSecondary)
            }
            ForEach(expanded ? units : Array(units.prefix(3))) { unit in
                let display = SeriesUnitPresentation.display(unit, isManga: isManga, german: KuroLocale.isGerman)
                HStack(alignment:.top,spacing:10) {
                    Text(display.numeral)
                        .font(.kuroCustom(22, weight: .light, relativeTo: .title2, maxSize: 34))
                        .foregroundStyle(Color.kuroInkSecondary)
                        .frame(minWidth:32,minHeight:44)
                        .accessibilityHidden(true)
                    Group {
                        if let synopsis = unit.synopsis {
                            DisclosureGroup(display.title) {
                                Text(synopsis).font(.kuroBody()).fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text(display.title).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    .font(.kuroBody())
                    .frame(minHeight:44)
                    if let user=currentTrackingUser(bundle, library: library) {
                        Button { actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in
                            guard let unitId = UUID(uuidString: unit.id), unit.orderKey.isFinite,
                                  unit.orderKey >= 0, unit.orderKey < Double(Int.max) else { return }
                            let current = home.displayedProgress(medium: bundle.medium, mediaId: bundle.mediaId,
                                server: user.progress, lifecycleId: UUID(uuidString: user.lifecycleId))
                            await home.setPosition(medium:bundle.medium,mediaId:bundle.mediaId,user:user,
                                position:SeriesUnitPresentation.integerPosition(unit.exactOrderKey) ?? current,unitId:unitId.uuidString,
                                label:unit.label)
                        } } label: { Image(systemName:"checkmark").frame(width:44,height:44) }
                            .disabled(!unit.available || UUID(uuidString: unit.id) == nil || !unit.orderKey.isFinite || unit.orderKey < 0 || unit.orderKey >= Double(Int.max))
                            .buttonStyle(HomeContactStyle())
                            .accessibilityLabel(isManga ? KuroLocale.text("Mark \(display.title) read", "\(display.title) als gelesen markieren")
                                                        : KuroLocale.text("Mark \(display.title) watched", "\(display.title) als gesehen markieren"))
                    }
                }.padding(.vertical,6).overlay(alignment:.bottom) { Rectangle().fill(Color.kuroHairline).frame(height: 0.5) }
            }
            if loading { KuroStateView(.loading, layout: .inline) }
            if let error {
                KuroStateView(.failed(hasCachedContent: !units.isEmpty), title: error, layout: .inline) { Task { await more(reset: needsInitialPage) } }
            }
            else if !expanded && (units.count > 3 || cursor != nil || needsInitialPage) {
                Button(isManga ? KuroLocale.text("More chapters", "Weitere Kapitel") : KuroLocale.text("More episodes", "Weitere Folgen")) {
                    expanded = true
                    if needsInitialPage { Task { await more(reset: true) } }
                }.font(.kuroMeta(weight: .medium)).frame(minHeight: 44).buttonStyle(HomeContactStyle())
            } else if cursor != nil {
                Button(isManga ? KuroLocale.text("More chapters", "Weitere Kapitel") : KuroLocale.text("More episodes", "Weitere Folgen")) { Task { await more() } }
                    .font(.kuroMeta(weight: .medium)).frame(minHeight:44).buttonStyle(HomeContactStyle())
            }
        }
        .onAppear { actionScope.activate(session: libraryActions.accountSession) }
        .onDisappear { actionScope.deactivate() }
        .task(id:"\(bundle.mediaId):\(sectionId ?? "")") {
            pageGeneration += 1; loading=false; error=nil; expanded=false
            editionsGeneration += 1; loadingEditions=false; editionsError=nil
            edition=SeriesUnitPresentation.selectedEdition(bundle)
            editionKeys=SeriesUnitPresentation.editionKeys(bundle)
            editionsCursor=bundle.editionsNext
            units=bundle.units.filter { $0.editionKey == edition }
            cursor=bundle.unitsNext
            // Older servers omit the cursor. The first deliberate expansion asks for the
            // authoritative first page once; row counts cannot prove exhaustion.
            needsInitialPage=bundle.edition == nil && bundle.unitsState != "not_in_catalogue"
        }
        .onChange(of:home.privacyEpoch) { _,_ in
            pageGeneration += 1; loading=false; units=[]; cursor=nil
            editionsGeneration += 1; loadingEditions=false; editionKeys=[]; editionsCursor=nil; editionsError=nil
        }
    }
    private func selectEdition(_ selected: String) {
        guard edition != selected else { return }
        edition=selected
        pageGeneration += 1; loading=false; error=nil; expanded=false
        units=[]; cursor=nil; needsInitialPage=true
        Task { await more(reset: true) }
    }
    private func more(reset:Bool=false) async {
        guard !loading else { return }; loading=true
        let request=pageGeneration, requestedEdition=edition, permissions=home.privacyEpoch
        defer { if request == pageGeneration { loading=false } }
        #if canImport(Supabase)
        do {
            let page=try await home.unitPage(medium:bundle.medium,mediaId:bundle.mediaId,sectionId:sectionId,edition:requestedEdition,after:reset ? nil : cursor)
            guard request == pageGeneration,requestedEdition == edition,permissions == home.privacyEpoch,!Task.isCancelled else { return }
            if reset { units=page.items } else { units += page.items.filter { row in !units.contains(where:{$0.id==row.id}) } }
            cursor=page.next; error=nil; needsInitialPage=false
        } catch is CancellationError {} catch { if request == pageGeneration,requestedEdition == edition,permissions == home.privacyEpoch { self.error=KuroLocale.text("Couldn't load more.", "Weitere konnten nicht geladen werden.") } }
        #endif
    }

    private func moreEditions() async {
        guard !loadingEditions, let after=editionsCursor else { return }
        loadingEditions=true
        let request=editionsGeneration, permissions=home.privacyEpoch
        defer { if request == editionsGeneration { loadingEditions=false } }
        #if canImport(Supabase)
        do {
            let page=try await home.loadEditions(medium:bundle.medium,mediaId:bundle.mediaId,sectionId:sectionId,after:after)
            guard request == editionsGeneration,permissions == home.privacyEpoch,editionsCursor == after,!Task.isCancelled else { return }
            editionKeys += page.items.filter { !editionKeys.contains($0) }
            editionsCursor=page.next; editionsError=nil
        } catch is CancellationError {} catch {
            if request == editionsGeneration,permissions == home.privacyEpoch { editionsError=KuroLocale.text("Couldn't load the editions.", "Die Ausgaben konnten nicht geladen werden.") }
        }
        #endif
    }
}

/// Presentation reads one real edition. Numeric ordering remains exact on the wire;
/// only a lossless integer can become the legacy integer progress projection.
enum SeriesUnitPresentation {
    static func selectedEdition(_ bundle: SeriesDetailBundle) -> String? {
        bundle.edition ?? bundle.units.first?.editionKey ?? bundle.editions?.first
    }

    static func editionKeys(_ bundle: SeriesDetailBundle) -> [String] {
        var keys=Array(Set(bundle.editions ?? bundle.units.map(\.editionKey))).sorted()
        if let selected=selectedEdition(bundle), !keys.contains(selected) { keys.append(selected) }
        return keys
    }

    /// The unit row's numeral and title without repeating the unit word ("Episode 1 · Episode
    /// Episode 1" is never shown): the numeral is the whole order number when there is one, the title
    /// is the unit's own title, else its label when that already names the unit, else "Episode 1".
    static func display(_ unit: SeriesDetailBundle.Unit, isManga: Bool, german: Bool) -> (numeral: String, title: String) {
        let label = unit.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let numeral = integerPosition(unit.exactOrderKey).map(String.init) ?? label
        if let title = unit.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return (numeral, title)
        }
        if label.contains(where: { $0.isLetter }) { return (numeral, label) }
        let word = isManga ? (german ? "Kapitel" : "Chapter") : (german ? "Folge" : "Episode")
        return (numeral, "\(word) \(label)")
    }

    static func integerPosition(_ exact: String) -> Int? {
        let pieces=exact.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let whole=pieces.first, !whole.isEmpty,
              whole.utf8.allSatisfy({ (48...57).contains($0) }),
              pieces.count == 1 || (!pieces[1].isEmpty && pieces[1].allSatisfy({ $0 == "0" })),
              let value=Int(whole), value <= Int(Int32.max) else { return nil }
        return value
    }
}

private struct SeriesCast: View {
    let items:[SeriesDetailBundle.Cast]
    var body:some View {
        CastSection(characters:items.map { person in
            (character:Character(id:person.id,anilistId:nil,nameFull:person.name,nameNative:nil,imageLarge:person.imageURL,
              description:person.description,gender:nil,age:nil),role:person.role ?? "SUPPORTING")
        })
    }
}

private struct SeriesPrincipals: View {
    let items:[SeriesDetailBundle.Principal]
    var body:some View {
        ProductionSection(studios:items.filter{$0.kind=="studio"}.map {
            Studio(id:$0.id,anilistId:nil,name:$0.name,isAnimationStudio:true,siteUrl:nil,favourites:nil)
        },staffItems:items.filter{$0.kind=="staff"}.map {
            (staff:Staff(id:$0.id,anilistId:nil,nameFull:$0.name,nameNative:nil,imageLarge:$0.imageURL,
                         description:$0.description,primaryOccupations:nil),role:$0.role ?? "")
        })
        MangaProductionSection(authorItems:items.filter{$0.kind=="author"}.map {
            (author:Author(id:$0.id,anilistId:nil,nameFull:$0.name,nameNative:nil,imageLarge:$0.imageURL,description:$0.description),role:$0.role ?? "")
        })
    }
}

// MARK: - Series detail chrome and copy (overnight 2026-11-01)

/// Which body a series detail shows: deciding (first load), the series sections, or the legacy
/// sections (spec D15). Decided once, on the first answer; a later season switch never flips it.
enum SeriesDetailMode: Equatable {
    case resolving
    case series
    case legacy

    static func initial(preview: SeriesDetailBundle?, hasLegacy: Bool) -> SeriesDetailMode {
        (preview != nil || !hasLegacy) ? .series : .resolving
    }

    func resolved(bundle: SeriesDetailBundle?, loadFailed: Bool, hasLegacy: Bool) -> SeriesDetailMode {
        guard self == .resolving else { return self }
        guard hasLegacy else { return .series }
        return SeriesDetailFallback.usesLegacy(bundle: bundle, loadFailed: loadFailed) ? .legacy : .series
    }
}

/// The first moment of a series detail, before it is known which body to show.
private struct SeriesResolvingView: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
            Text(title)
                .font(.kuroFeature())
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
            KuroStateView(.loading, layout: .inline)
        }
        .padding(.horizontal, KuroDesignSpacing.padding)
        .padding(.top, 72)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .kuroReadableWidth()
        .background(Color.kuroCanvasPage)
        .overlay(alignment: .topTrailing) { SeriesCloseButton() }
    }
}

/// The lead tracking action, near the title (not buried under the units): "Add to list" when the
/// title is not tracked, "List settings" when it is. Both open the shared tracking editor route.
private struct SeriesTrackingAction: View {
    let bundle: SeriesDetailBundle
    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroRoutes) private var routes

    var body: some View {
        if currentTrackingUser(bundle, library: library) == nil {
            KuroInkButton(KuroLocale.text("Add to list", "Zur Liste hinzufügen")) {
                routes.presentTrackingEditor(TrackingEditorRequest(media: detailMedia(bundle)))
            }
        } else {
            KuroInkButton(KuroLocale.text("List settings", "Listeneinstellungen"), role: .secondary) {
                routes.presentTrackingEditor(TrackingEditorRequest(media: detailMedia(bundle)))
            }
        }
    }
}

/// Series detail copy shared by both pages (rulebook §9: no internal words).
enum SeriesCopy {
    /// Where an anime ends in its source is not mapped yet. Names the source's kind only when known.
    static func boundaryUnknown(sourceKind: String?) -> String {
        switch sourceKind?.lowercased() {
        case "manga":
            return KuroLocale.text("Where the anime ends in the manga isn't known yet.",
                                   "Wo der Anime im Manga endet, ist noch nicht bekannt.")
        case "novel":
            return KuroLocale.text("Where the anime ends in the novel isn't known yet.",
                                   "Wo der Anime im Roman endet, ist noch nicht bekannt.")
        default:
            return KuroLocale.text("Where the anime ends in its source isn't known yet.",
                                   "Wo der Anime in seiner Vorlage endet, ist noch nicht bekannt.")
        }
    }

    /// "Episode 7 of 25" / "Kapitel 24".
    static func position(isManga: Bool, label: String, total: Int?) -> String {
        let word = isManga ? KuroLocale.text("Chapter", "Kapitel") : KuroLocale.text("Episode", "Folge")
        guard let total, total > 0, !isManga else { return "\(word) \(label)" }
        return KuroLocale.text("\(word) \(label) of \(total)", "\(word) \(label) von \(total)")
    }
}
