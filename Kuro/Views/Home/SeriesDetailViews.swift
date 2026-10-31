import KuroCore
import KuroLibrary
import SwiftUI

/// Shallow landscape anime detail. The selected season changes the copy underneath.
/// Tracking stays on the list entry and is not inferred from browsing a season.
struct SeriesAnimeDetailView: View {
    let anime: Anime
    @Environment(HomeStore.self) private var home
    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroRoutes) private var routes
    @State private var bundle: SeriesDetailBundle?
    @State private var selectedSection: String?
    @State private var loadError: String?
    @State private var generation = UUID()
    @State private var selectedEntry: Int?
    @State private var sectionChoices: [SeriesDetailBundle.Section] = []
    @State private var isLoading = false
    @State private var showDiscussion = false
    private let skipNetworkLoad: Bool

    init(anime: Anime, previewBundle: SeriesDetailBundle? = nil) {
        self.anime = anime
        self._bundle = State(initialValue: previewBundle)
        self._sectionChoices = State(initialValue: previewBundle?.sections ?? [])
        self._selectedSection = State(initialValue: previewBundle?.sections.first(where: { $0.entries?.contains(where: { $0.mediaId == previewBundle?.mediaId }) == true })?.id)
        self.skipNetworkLoad = previewBundle != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                art
                seasons
                story
                if isLoading { ProgressView("Loading this season") }
                if let loadError {
                    Text(loadError).font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary)
                    Button("Retry season") { generation = UUID() }.frame(minHeight: 44)
                }
                units
                coverage
                music
                cast
                SeriesPrincipals(items: bundle?.principals ?? [])
                betweenUs
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .foregroundStyle(Color.kuroInk)
        }
        .background(Color.kuroCanvasPage)
        .tint(Color.kuroInk)
        .routePresenter()
        .overlay(alignment: .topTrailing) {
            SeriesCloseButton()
        }
        .onChange(of: home.privacyEpoch) { _, _ in
            bundle = nil
            showDiscussion = false
            generation = UUID()
        }
        .task(id: generation) {
            guard !skipNetworkLoad else { return }
            await load(section: selectedSection)
        }
    }

    private var art: some View {
        let url = SeriesArtwork.verified(bundle?.header.bannerImage)
            ?? SeriesArtwork.verified(anime.bannerImage)
            ?? SeriesArtwork.verified(anime.coverImageLarge)
        return GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if let url {
                    KuroCachedAsyncImage(url: url, maxPixelSize: 1400) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.kuroMissingArt
                        }
                    }
                } else {
                    Color.kuroMissingArt
                }
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.45),
                        .init(color: Color.black.opacity(0.62), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(bundle?.header.title ?? anime.displayTitle)
                        .font(.kuroDisplay())
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(bundle?.header.catalogueStatus ?? anime.status ?? "Status unknown")
                        .font(.kuroCaption())
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .padding(16)
                .padding(.trailing, 72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.72))
                if bundle?.header.artworkScope == "cover_fallback" {
                    Text("Series art")
                        .font(.kuroMicro())
                        .foregroundStyle(Color.kuroInk)
                        .padding(6)
                        .background(Color.white.opacity(0.92))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .aspectRatio(1.9, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, -20)
        .accessibilityLabel("Artwork for \(bundle?.header.title ?? anime.displayTitle)")
    }

    @ViewBuilder
    private var story: some View {
        if let copy = bundle?.copy, copy.storyState == "present" || copy.storyState == "source" {
            if let hook = copy.hook {
                Text(hook).font(.kuroTitle()).fixedSize(horizontal: false, vertical: true)
            }
            if let premise = copy.premise {
                Text(premise).font(.kuroBody()).fixedSize(horizontal: false, vertical: true)
            }
            if let synopsis = copy.synopsis {
                DisclosureGroup("About this season") { Text(synopsis).font(.kuroBody()) }
            }
        } else if loadError != nil {
            Text(loadError ?? "").foregroundStyle(Color.kuroInkSecondary)
        } else {
            Text("Story overview isn’t available yet.")
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var seasons: some View {
        let sections = sectionChoices
        return VStack(alignment: .leading, spacing: 8) {
            Text("Seasons")
                .font(.kuroCaption())
                .accessibilityAddTraits(.isHeader)
            if sections.isEmpty {
                Text("This entry is not in an approved season group.")
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sections) { section in
                            let art = SeriesArtwork.verified(section.entries?.first?.bannerImage ?? section.entries?.first?.coverImage)
                            Button {
                                select(section: section)
                            } label: {
                                SeriesSeasonPanel(name: section.name, imageURL: art, isSelected: selectedSection == section.id)
                            }
                            .buttonStyle(HomeContactStyle())
                            .accessibilityLabel(section.name)
                            .accessibilityHint("Inspects this season without changing your progress")
                            .accessibilityAddTraits(selectedSection == section.id ? .isSelected : [])
                        }
                    }
                }
            }
            if let current=sections.first(where:{$0.id == selectedSection}),let entries=current.entries,entries.count>1 {
                ScrollView(.horizontal,showsIndicators:false) {
                    HStack(spacing:8) {
                        ForEach(entries) { entry in
                            Button {
                                selectedEntry=entry.mediaId
                                bundle=nil; generation=UUID()
                            } label: {
                                HStack(spacing:8) {
                                    if let url = SeriesArtwork.verified(entry.coverImage) {
                                        KuroCachedAsyncImage(url:url,maxPixelSize:160) { phase in
                                            if case .success(let image)=phase { image.resizable().scaledToFill() }
                                            else { Color.kuroMissingArt }
                                        }.frame(width:28,height:42).clipped().clipShape(RoundedRectangle(cornerRadius:3))
                                    }
                                    Text(entry.title ?? "Episodes").font(.kuroCaption())
                                        .fixedSize(horizontal: false, vertical: true)
                                }.frame(minHeight:44).padding(.horizontal,8)
                                    .background(Color.kuroCanvasQuiet)
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill((selectedEntry ?? anime.id) == entry.mediaId ? Color.kuroInk : Color.clear)
                                            .frame(height: 2)
                                    }
                            }.buttonStyle(HomeContactStyle()).accessibilityLabel("Open \(entry.title ?? "season entry")")
                        }
                    }
                }
            }
            if (selectedEntry ?? anime.id) != anime.id {
                Button("Return to opened entry") {
                    selectedEntry = anime.id
                    selectedSection = sections.first(where: { $0.entries?.contains(where: { $0.mediaId == anime.id }) == true })?.id
                    bundle = nil
                    loadError = nil
                    generation = UUID()
                }.font(.kuroCaption()).frame(minHeight: 44).buttonStyle(HomeContactStyle())
            }
        }
    }

    private func select(section: SeriesDetailBundle.Section) {
        guard selectedSection != section.id else { return }
        selectedSection = section.id
        selectedEntry = section.entries?.first?.mediaId
        bundle = nil
        showDiscussion = false
        loadError = nil
        generation = UUID()
        KuroAccessibility.impactHaptic(.light)
    }

    @ViewBuilder private var units: some View {
        if let bundle {
            SeriesUnitsView(bundle: bundle,sectionId:selectedSection)
                .id("anime:\(bundle.mediaId):\(selectedSection ?? ""):\(home.privacyEpoch)")
            if currentTrackingUser(bundle, library: library) == nil {
                Button("Add to list") { routes.presentTrackingEditor(TrackingEditorRequest(media: detailMedia(bundle))) }
                    .frame(minHeight:44).buttonStyle(HomeContactStyle())
            } else {
                Button("List settings") { routes.presentTrackingEditor(TrackingEditorRequest(media: detailMedia(bundle))) }
                    .font(.kuroCaption()).frame(minHeight:44).buttonStyle(HomeContactStyle())
            }
        }
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The original story")
                .font(.kuroCaption())
                .accessibilityAddTraits(.isHeader)
            if let coverage = bundle?.coverage, coverage.mappingState == "exact" || coverage.mappingState == "partial" {
                Text(coverage.sourceKind == "novel" ? "Novel" : "Manga")
                if let starts = coverage.startsAt { Text("Starts at \(starts)") }
                if let ends = coverage.endsAt { Text("Ends at \(ends)") }
                if let next = coverage.readNext { Text("Read next \(next)") }
                if let sourceId = coverage.sourceMangaId {
                    Button(coverage.sourceKind == "novel" ? "Explore the novel" : "Explore the manga") {
                        routes.openMedia(MediaRoute(kind: .manga, id: sourceId))
                    }.frame(minHeight: 44).buttonStyle(HomeContactStyle())
                }
            } else {
                Text("Chapter boundaries unverified.")
                    .font(.kuroBody())
                    .foregroundStyle(Color.kuroInkSecondary)
            }
        }
    }

    @ViewBuilder
    private var music: some View {
        if let themes = bundle?.themes, !themes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("The sound of it.")
                    .font(.kuroCaption())
                    .foregroundStyle(Color.kuroInkSecondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(themes.enumerated()), id: \.offset) { _, theme in
                    if theme.matchState == "verified", let raw = theme.externalURL, let url = URL(string: raw), url.scheme == "https", url.host?.lowercased() == "open.spotify.com" {
                        Link(destination: url) {
                            Text("\(theme.role.uppercased()) · \(theme.songTitle ?? "Untitled")")
                                .frame(minHeight: 44)
                        }
                    } else if let title = theme.songTitle {
                        let query = "\(title) \(theme.artist ?? "")".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "https://open.spotify.com/search/\(query)") {
                            Link(destination: url) {
                                Text("Find \(title) on Spotify")
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                }
                Text("Find on Spotify · unmatched tracks are searches, not identified recordings.")
                    .font(.kuroCaption())
                    .foregroundStyle(Color.kuroInkSecondary)
            }
        }
    }

    private var cast: some View { SeriesCast(items: bundle?.cast ?? []) }

    private var betweenUs: some View {
        Group {
            if let bundle {
                DisclosureGroup(isExpanded: $showDiscussion) {
                    if showDiscussion {
                    FriendsActivitySection(mediaId: bundle.mediaId, mediaType: "ANIME", editorial: true)
                        .id("anime:\(bundle.mediaId):\(home.privacyEpoch)")
                    }
                } label: {
                    SeriesDiscussionHeading(title: bundle.header.title, imageURL: bundle.header.coverImage)
                }
                .modifier(SeriesDiscussionMaterial(medium: bundle.medium))
            }
        }
    }

    private func load(section: String?) async {
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        #if canImport(Supabase)
        do {
            let loaded = try await home.detailBundle(medium: "anime", mediaId: selectedEntry ?? anime.id, sectionId: section)
            guard token == generation, !Task.isCancelled else { return }
            bundle = loaded
            sectionChoices = loaded.sections
            if selectedSection == nil { selectedSection = loaded.sections.first(where: { $0.entries?.contains(where: { $0.mediaId == loaded.mediaId }) == true })?.id }
            loadError = nil
        } catch is CancellationError {
            return
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            loadError = "This season could not be loaded."
        }
        #else
        loadError = "Detail is not configured."
        #endif
    }
}

/// Manga detail: cover, real premise when the catalogue has one, bookmark, editions, reciprocal guide.
struct SeriesMangaDetailView: View {
    let manga: Manga
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

    init(manga: Manga, previewBundle: SeriesDetailBundle? = nil) {
        self.manga = manga
        self._bundle = State(initialValue: previewBundle)
        self.skipNetworkLoad = previewBundle != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                intro
                story
                bookmark
                chapters
                guide
                cast
                SeriesPrincipals(items:bundle?.principals ?? [])
                betweenUs
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
            .foregroundStyle(Color.kuroInk)
        }
        .background(Color.kuroCanvasPage)
        .tint(Color.kuroInk)
        .routePresenter()
        .overlay(alignment: .topTrailing) {
            SeriesCloseButton()
        }
        .task(id: loadGeneration) {
            guard !skipNetworkLoad else { return }
            await load()
        }
        .onChange(of: home.privacyEpoch) { _, _ in
            bundle = nil
            showDiscussion = false
            watchedChoice = nil
            loadGeneration = UUID()
        }
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
                .font(.kuroDisplay())
                .foregroundStyle(Color.kuroInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(bundle?.header.catalogueStatus ?? manga.status ?? "Status unknown")
                .font(.kuroCaption())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel("Cover of \(manga.displayTitle)")
    }

    @ViewBuilder
    private var story: some View {
        if let copy = bundle?.copy, copy.premise != nil || copy.synopsis != nil {
            if let hook=copy.hook { Text(hook).font(.kuroTitle()) }
            if let premise=copy.premise { Text(premise).font(.kuroBody()) }
            if let synopsis = bundle?.copy.synopsis {
                DisclosureGroup("The story") { Text(synopsis).font(.kuroBody()) }
            }
        } else {
            Text("No spoiler-light premise is on file for this book.")
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInkSecondary)
        }
    }

    @ViewBuilder private var bookmark: some View {
        if let bundle {
            SeriesBookmark(bundle:bundle)
            Button(currentTrackingUser(bundle, library: library) == nil ? "Add to list" : "List settings") {
                routes.presentTrackingEditor(TrackingEditorRequest(media: detailMedia(bundle)))
            }.frame(minHeight:44).buttonStyle(HomeContactStyle())
        }
        if isLoading { ProgressView("Loading this book") }
        if let loadError {
            Text(loadError).font(.kuroCaption())
            Button("Retry book") { loadGeneration = UUID() }.frame(minHeight: 44)
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
        return DisclosureGroup("I've watched the anime") {
            if guides.isEmpty {
                Text("Chapter boundaries are unverified.").font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary)
            } else {
                Picker("Finished season",selection:$watchedChoice) {
                    Text("Choose a season").tag(String?.none)
                    ForEach(guides.indices,id:\.self) { index in
                        let guide=guides[index]
                        Text(guide.season ?? "Anime adaptation").tag(Optional(guide.sectionId ?? "anime:\(guide.animeId ?? 0)"))
                    }
                }.pickerStyle(.menu).frame(minHeight:44)
                if let selected {
                    if selected.mappingState == "exact" || selected.mappingState == "partial" {
                    HStack {
                        if let start=selected.startsAt { guidePoint("Starts",start) }
                        if let end=selected.endsAt { guidePoint("Ends",end) }
                        if let next=selected.readNext { guidePoint("Read next",next) }
                    }
                    }
                    if let id=selected.animeId {
                        Button("Open anime") { routes.openMedia(MediaRoute(kind:.anime,id:id)) }.frame(minHeight:44)
                    }
                    Text(selected.mappingState == "exact" ? "Verified season boundary." : (selected.mappingState == "partial" ? "Partial adaptation; some chapters differ." : "Chapter boundary unverified."))
                        .font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary)
                }
            }
        }.font(.kuroBody()).padding(.vertical,8)
    }
    private func guidePoint(_ title:String,_ value:String)->some View {
        VStack(alignment:.leading,spacing:5) { Text(title).font(.kuroCaption()); Text(value).font(.kuroBody()) }
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
        } catch is CancellationError {
            return
        } catch {
            guard token == loadGeneration, !Task.isCancelled else { return }
            loadError = "This book could not be loaded."
        }
        #else
        loadError = "Detail is not configured."
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
            Text("Close")
                .font(.kuroBody(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .padding(.horizontal, 14)
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.white.opacity(0.92), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.kuroHairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
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
                                .init(color: Color.black.opacity(0.28), location: 0),
                                .init(color: Color.black.opacity(0.72), location: 1)
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
                Text("Your clubs · private").font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary)
                Text("Between us.").font(.kuroHeadline()).fixedSize(horizontal: false, vertical: true)
                Text(title).font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, KuroDesignSpacing.sm)
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).foregroundStyle(Color.kuroInk)
            .accessibilityLabel("Between us. Private club discussion for \(title)")
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

private struct SeriesBookmarkMaterial: ViewModifier {
    let medium: String
    @ViewBuilder func body(content: Content) -> some View {
        if medium == "manga" {
            content
                .background(Color.kuroCanvasQuiet)
                .overlay(Rectangle().strokeBorder(Color.kuroHairline))
        } else {
            content
                .background(Color.kuroCanvasQuiet)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.kuroHairline))
        }
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
    var body:some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        if let user=currentTrackingUser(bundle, library: library) {
            let progress=home.displayedProgress(medium:bundle.medium,mediaId:bundle.mediaId,server:user.progress,lifecycleId:UUID(uuidString:user.lifecycleId))
            let label=home.displayedProgressLabel(medium:bundle.medium,mediaId:bundle.mediaId,serverLabel:user.progressLabel,lifecycleId:UUID(uuidString:user.lifecycleId),serverRevision:user.serverRevision) ?? String(progress)
            let unitId = home.displayedUnitId(medium: bundle.medium, mediaId: bundle.mediaId,
                serverUnitId: user.unitId, lifecycleId: UUID(uuidString: user.lifecycleId), serverRevision: user.serverRevision)
            let needsUnitChoice = unitId != nil || Int(label) != progress
            VStack(alignment:.leading,spacing:8) {
                Text(bundle.medium == "manga" ? "Your bookmark" : "Your progress").font(.kuroCaption())
                HStack(spacing:12) {
                    Text(label).font(.kuroFeature()).monospacedDigit()
                    Spacer()
                    if !needsUnitChoice {
                        Button { actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in await home.setPosition(medium:bundle.medium,mediaId:bundle.mediaId,user:user,position:max(0,progress-1)) } }
                            label: { Image(systemName:"minus").frame(width:44,height:44) }
                            .accessibilityLabel("Previous \(bundle.medium == "manga" ? "chapter" : "episode")")
                    }
                    Button {
                        if needsUnitChoice { showUnitChooser = true }
                        else { actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in await home.advance(medium:bundle.medium,mediaId:bundle.mediaId,lifecycleId:user.lifecycleId,
                            baseRevision:user.serverRevision,serverProgress:user.progress,episodeCap:bundle.medium == "manga" ? bundle.header.chapters : bundle.header.episodes,
                            serverLabel:user.progressLabel,serverUnitId:user.unitId) } }
                    } label: { Image(systemName: needsUnitChoice ? "list.number" : "plus").frame(width:44,height:44) }
                        .accessibilityLabel(needsUnitChoice ? "Choose the next available unit" : "Next \(bundle.medium == "manga" ? "chapter" : "episode")")
                }.buttonStyle(HomeContactStyle())
                HStack {
                    TextField("Go to \(bundle.medium == "manga" ? "chapter" : "episode")",text:$draft)
                        .keyboardType(.numberPad).font(.kuroBody()).frame(minHeight:44)
                    Button("Save") {
                        guard let position=Int(draft),position>=0,
                              position <= ((bundle.medium == "manga" ? bundle.header.chapters : bundle.header.episodes) ?? Int.max) else {
                            error="Enter a valid position."; return
                        }
                        error=nil
                        actionScope.launch(origin: origin, session: libraryActions.accountSession) { _ in await home.setPosition(medium:bundle.medium,mediaId:bundle.mediaId,user:user,position:position) }
                    }.frame(minWidth:44,minHeight:44).buttonStyle(HomeContactStyle())
                }
                if let error { Text(error).font(.kuroCaption()) }
                if let status=home.statusMessage { Text(status).font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary) }
            }.padding(16)
            .modifier(SeriesBookmarkMaterial(medium: bundle.medium))
            .onAppear { actionScope.activate(session: libraryActions.accountSession) }
            .onDisappear { actionScope.deactivate() }
            .sheet(isPresented: $showUnitChooser) {
                NavigationStack {
                    ScrollView {
                        SeriesUnitsView(bundle: bundle, sectionId: sectionId, showsBookmark: false)
                            .padding(KuroDesignSpacing.md)
                    }.toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showUnitChooser = false } }
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
    var body:some View {
        let origin = actionScope.capture(session: libraryActions.accountSession)
        VStack(alignment:.leading,spacing:12) {
            if bundle.medium == "anime" && showsBookmark { SeriesBookmark(bundle:bundle, sectionId:sectionId) }
            Text(bundle.medium == "manga" ? "Chapters" : "Episodes").font(.kuroTitle()).accessibilityAddTraits(.isHeader)
            if editionKeys.count>1 {
                Picker("Edition", selection: Binding(get: { edition ?? "" }, set: selectEdition)) {
                    ForEach(editionKeys,id:\.self) { Text($0.isEmpty ? "Original" : $0).tag($0) }
                }.frame(minHeight:44)
            } else if let edition {
                Text(edition.isEmpty ? "Original edition" : edition).font(.kuroCaption())
            }
            if loadingEditions { ProgressView("Loading editions") }
            if let editionsError {
                Text(editionsError).font(.kuroCaption())
                Button("Retry editions") { Task { await moreEditions() } }.frame(minHeight: 44)
            } else if editionsCursor != nil {
                Button("More editions") { Task { await moreEditions() } }
                    .frame(minHeight: 44).buttonStyle(HomeContactStyle())
            }
            if units.isEmpty && !loading { Text("No verified \(bundle.medium == "manga" ? "chapter" : "episode") rows yet.").font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary) }
            ForEach(expanded ? units : Array(units.prefix(3))) { unit in
                HStack(alignment:.top,spacing:10) {
                    Text(unit.label).font(.system(size:22,weight:.light)).foregroundStyle(Color.kuroInkSecondary).frame(minWidth:32,minHeight:44)
                    DisclosureGroup(unit.title ?? (bundle.medium == "manga" ? "Chapter \(unit.label)" : "Episode \(unit.label)")) {
                        if let synopsis=unit.synopsis { Text(synopsis).font(.kuroBody()) }
                        else { Text("No summary on file.").font(.kuroCaption()).foregroundStyle(Color.kuroInkSecondary) }
                    }.font(.kuroBody()).frame(minHeight:44)
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
                            .accessibilityLabel("Mark \(bundle.medium == "manga" ? "chapter" : "episode") \(unit.label)")
                    }
                }.padding(.vertical,6).overlay(alignment:.bottom) { Divider() }
            }
            if loading { ProgressView() }
            if let error { Text(error).font(.kuroCaption()); Button("Retry") { Task { await more(reset: needsInitialPage) } }.frame(minHeight:44) }
            else if !expanded && (units.count > 3 || cursor != nil || needsInitialPage) {
                Button("More \(bundle.medium == "manga" ? "chapters" : "episodes")") {
                    expanded = true
                    if needsInitialPage { Task { await more(reset: true) } }
                }.frame(minHeight: 44).buttonStyle(HomeContactStyle())
            } else if cursor != nil {
                Button("More \(bundle.medium == "manga" ? "chapters" : "episodes")") { Task { await more() } }.frame(minHeight:44)
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
        } catch is CancellationError {} catch { if request == pageGeneration,requestedEdition == edition,permissions == home.privacyEpoch { self.error="More could not be loaded." } }
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
            if request == editionsGeneration,permissions == home.privacyEpoch { editionsError="Editions could not be loaded." }
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
