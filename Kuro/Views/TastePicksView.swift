import KuroCore
import KuroLibrary
import SwiftUI

/// The left-hand Taste page: a short set of titles the person has not really met.
/// Personal picks when the account has enough signal, otherwise a few unseen catalogue titles.
struct TastePicksView: View {
    @Environment(DiscoveryStore.self) private var discovery
    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroRoutes) private var routes

    @State private var showAnime = true
    @State private var animePicks: [Media] = []
    @State private var mangaPicks: [Media] = []
    @State private var animeNote = ""
    @State private var mangaNote = ""
    @State private var isLoading = true
    @State private var failed = false

    private let cap = 4

    var body: some View {
        GeometryReader { geo in
            let width = max(160, geo.size.width - 40)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 16) {
                        mediumButton("ANIME", on: showAnime) { showAnime = true }
                        mediumButton("MANGA", on: !showAnime) { showAnime = false }
                        Spacer()
                    }

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else if failed {
                        Text("Could not load a short list.")
                            .font(.kuroBody())
                            .foregroundColor(.kuroTextSecondary)
                        Button("Retry") {
                            Task { await load() }
                        }
                        .font(.kuroCaption(weight: .medium))
                    } else if picks.isEmpty {
                        Text("Nothing new to put in front of you right now.")
                            .font(.kuroBody())
                            .foregroundColor(.kuroTextSecondary)
                    } else {
                        Text(note)
                            .font(.kuroBody())
                            .foregroundColor(.kuroTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(picks, id: \.stableKey) { item in
                            CompactAnimeCard(media: item, cardWidth: width)
                            Button("Add to list") {
                                routes.presentTrackingEditor(TrackingEditorRequest(media: item))
                            }
                            .font(.kuroBody())
                            .frame(minHeight: 44)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(item.title) to your list")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDisabled(false)
            .background(Color.kuroBackground)
        }
        .task { await load() }
    }

    private var picks: [Media] { showAnime ? animePicks : mangaPicks }
    private var note: String { showAnime ? animeNote : mangaNote }

    private func mediumButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kuroCaption(weight: on ? .semibold : .regular))
                .tracking(1)
                .foregroundColor(on ? .kuroBlack : .kuroTextTertiary)
                .padding(.bottom, 6)
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(on ? Color.kuroBlack : Color.clear)
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func load() async {
        isLoading = true
        failed = false
        async let because = discovery.fetchBecauseYouRail(limit: 8)
        async let bundle = discovery.fetchDiscoverBundle(limit: 12)
        let becauseRows = await because
        let fetched = await bundle
        guard let fetched else {
            if becauseRows == nil {
                failed = true
                isLoading = false
                return
            }
            apply(because: becauseRows ?? [], bundle: nil)
            isLoading = false
            return
        }
        apply(because: becauseRows ?? [], bundle: fetched)
        isLoading = false
    }

    private func apply(because: [BecauseYouCard], bundle: DiscoverBundle?) {
        let animePersonal = because
            .filter { $0.mediaType.uppercased() != "MANGA" }
            .map { $0.toMedia() }
        let mangaPersonal = because
            .filter { $0.mediaType.uppercased() == "MANGA" }
            .map { $0.toMedia() }
        let animeUnseen = (bundle?.anime.newToYou ?? []).map(Media.init(card:))
        let mangaUnseen = (bundle?.manga.newToYou ?? []).map(Media.init(card:))
        let animeStart = (bundle?.anime.essentials ?? []).map(Media.init(card:))
        let mangaStart = (bundle?.manga.essentials ?? []).map(Media.init(card:))

        let animeChoice = choose(personal: animePersonal, unseen: animeUnseen, start: animeStart, mediaType: "anime")
        let mangaChoice = choose(personal: mangaPersonal, unseen: mangaUnseen, start: mangaStart, mediaType: "manga")
        animePicks = animeChoice.items
        mangaPicks = mangaChoice.items
        animeNote = animeChoice.note
        mangaNote = mangaChoice.note
    }

    private func choose(personal: [Media], unseen: [Media], start: [Media], mediaType: String) -> (items: [Media], note: String) {
        let personalOpen = open(personal, mediaType: mediaType)
        if personalOpen.count >= 2 {
            return (Array(personalOpen.prefix(cap)), "Close to what you already like. Not on your list.")
        }
        let unseenOpen = open(unseen, mediaType: mediaType)
        if !unseenOpen.isEmpty {
            return (Array(unseenOpen.prefix(cap)), "A few you have not really looked at.")
        }
        let startOpen = open(start, mediaType: mediaType)
        if !startOpen.isEmpty {
            return (Array(startOpen.prefix(cap)), "A short start, until there is more to go on.")
        }
        return ([], "Nothing new to put in front of you right now.")
    }

    private func open(_ items: [Media], mediaType: String) -> [Media] {
        items.filter { !(MediaKey(mediaType: mediaType, id: $0.id).map { library.isTracked($0) } ?? false) }
    }
}

private extension Media {
    init(card: AnimeCard) {
        self.init(
            id: card.id,
            kind: .anime,
            title: card.title,
            imageURL: card.imageURL,
            year: card.year,
            displayDescription: card.displayDescription,
            episodes: card.episodes,
            chapters: card.chapters,
            rating: card.rating,
            genres: card.genres,
            statusRaw: card.statusRaw,
            formatRaw: card.formatRaw,
            popularityValue: card.popularityValue,
            trendingValue: card.trendingValue,
            createdAtValue: card.createdAtValue
        )
    }

    init(card: MangaCard) {
        self.init(
            id: card.id,
            kind: .manga,
            title: card.title,
            imageURL: card.imageURL,
            year: card.year,
            displayDescription: card.displayDescription,
            episodes: card.episodes,
            chapters: card.chapters,
            rating: card.rating,
            genres: card.genres,
            statusRaw: card.statusRaw,
            formatRaw: card.formatRaw,
            popularityValue: card.popularityValue,
            trendingValue: card.trendingValue,
            createdAtValue: card.createdAtValue
        )
    }
}
