import SwiftUI

struct GenreHubView: View {
    enum MediaKind: String, CaseIterable, Identifiable {
        case anime = "ANIME"
        case manga = "MANGA"

        var id: String { rawValue }
    }

    @Environment(SupabaseService.self) private var supabaseService

    let genre: String
    @State private var mediaKind: MediaKind = .anime

    @State private var selectedTag: TagFacet? = nil
    @State private var tagFacets: [TagFacet] = []
    @State private var mediaToTagIds: [Int: Set<Int>] = [:]

    @State private var essentialsAnime: [Anime] = []
    @State private var newToYouAnime: [Anime] = []
    @State private var classicsAnime: [Anime] = []
    @State private var trendingAnime: [Anime] = []
    @State private var topRatedAnime: [Anime] = []

    @State private var essentialsManga: [Manga] = []
    @State private var newToYouManga: [Manga] = []
    @State private var classicsManga: [Manga] = []
    @State private var trendingManga: [Manga] = []
    @State private var topRatedManga: [Manga] = []

    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    tagSection

                    if mediaKind == .anime {
                        if !essentialsAnime.isEmpty {
                            CompactHorizontalSection(title: "ESSENTIAL \(genre.uppercased())", subtitle: "Premium picks", items: filteredAnime(essentialsAnime))
                        }
                        if !newToYouAnime.isEmpty {
                            CompactHorizontalSection(title: "NEW TO YOU", subtitle: "Great + unseen", items: filteredAnime(newToYouAnime))
                        }
                        if !topRatedAnime.isEmpty {
                            CompactHorizontalSection(title: "TOP RATED", subtitle: "Highest scores", items: filteredAnime(topRatedAnime))
                        }
                        if !trendingAnime.isEmpty {
                            CompactHorizontalSection(title: "TRENDING", subtitle: "Right now", items: filteredAnime(trendingAnime))
                        }
                        if !classicsAnime.isEmpty {
                            CompactHorizontalSection(title: "CLASSICS", subtitle: "Before 2015", items: filteredAnime(classicsAnime))
                        }
                    } else {
                        if !essentialsManga.isEmpty {
                            CompactHorizontalMangaSection(title: "ESSENTIAL \(genre.uppercased())", subtitle: "Premium picks", items: filteredManga(essentialsManga))
                        }
                        if !newToYouManga.isEmpty {
                            CompactHorizontalMangaSection(title: "NEW TO YOU", subtitle: "Great + unseen", items: filteredManga(newToYouManga))
                        }
                        if !topRatedManga.isEmpty {
                            CompactHorizontalMangaSection(title: "TOP RATED", subtitle: "Highest scores", items: filteredManga(topRatedManga))
                        }
                        if !trendingManga.isEmpty {
                            CompactHorizontalMangaSection(title: "TRENDING", subtitle: "Right now", items: filteredManga(trendingManga))
                        }
                        if !classicsManga.isEmpty {
                            CompactHorizontalMangaSection(title: "CLASSICS", subtitle: "Before 2015", items: filteredManga(classicsManga))
                        }
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .background(Color.kuroBackground)
        .task { await refresh() }
        .onChange(of: mediaKind) { _ in
            Task { await refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(genre.uppercased())
                    .font(.system(size: 18, weight: .light, design: .serif))
                    .tracking(1.0)

                Spacer()

                Picker("", selection: $mediaKind) {
                    ForEach(MediaKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .accessibilityLabel("Media type")
            }

            Text("BROWSE \(genre.uppercased()) • REAL GENRES + MICRO‑TAGS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(.black.opacity(0.5))

            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.85)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.kuroBackground)
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUB‑GENRES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .foregroundColor(.black.opacity(0.5))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        title: "All",
                        isSelected: selectedTag == nil
                    ) { selectedTag = nil }

                    ForEach(tagFacets) { tag in
                        FilterChip(
                            title: tag.name,
                            isSelected: selectedTag?.id == tag.id
                        ) { selectedTag = tag }
                    }
                }
                .padding(.horizontal, 20)
            }
            .kuroSwipeExclusionZone()
        }
        .padding(.top, 6)
    }

    private func filteredAnime(_ items: [Anime]) -> [Anime] {
        guard let tag = selectedTag else { return items }
        return items.filter { mediaToTagIds[$0.id]?.contains(tag.id) == true }
    }

    private func filteredManga(_ items: [Manga]) -> [Manga] {
        guard let tag = selectedTag else { return items }
        return items.filter { mediaToTagIds[$0.id]?.contains(tag.id) == true }
    }

    private func refresh() async {
        await MainActor.run {
            isLoading = true
            selectedTag = nil
            tagFacets = []
            mediaToTagIds = [:]
        }

        if mediaKind == .anime {
            async let essentials = supabaseService.fetchEssentialsAnime(limit: 30, minScore: 85, genre: genre)
            async let newToYou = supabaseService.fetchNewToYouAnime(limit: 30, candidateLimit: 300, minScore: 80, genre: genre)
            async let classics = supabaseService.fetchClassicsAnime(limit: 30, yearBefore: 2015, minScore: 80, genre: genre)
            async let trending = supabaseService.fetchTrendingAnime(limit: 30, onlyAiring: false, genre: genre)
            async let top = supabaseService.fetchTopRatedAnime(limit: 30, minScore: 80, genre: genre)
            async let tags = supabaseService.fetchTopTagsForAnimeGenre(genre: genre, sampleLimit: 200, limit: 18)

            let (a, n, c, t, r, tagData) = await (essentials, newToYou, classics, trending, top, tags)
            await MainActor.run {
                essentialsAnime = a
                newToYouAnime = n
                classicsAnime = c
                trendingAnime = t
                topRatedAnime = r
                tagFacets = tagData.facets
                mediaToTagIds = tagData.mediaToTagIds
                isLoading = false
            }
        } else {
            async let essentials = supabaseService.fetchEssentialsManga(limit: 30, minScore: 85, genre: genre)
            async let newToYou = supabaseService.fetchNewToYouManga(limit: 30, candidateLimit: 350, minScore: 80, genre: genre)
            async let classics = supabaseService.fetchClassicsManga(limit: 30, yearBefore: 2015, minScore: 80, genre: genre)
            async let trending = supabaseService.fetchTrendingManga(limit: 30, genre: genre)
            async let top = supabaseService.fetchTopRatedManga(limit: 30, minScore: 80, genre: genre)
            async let tags = supabaseService.fetchTopTagsForMangaGenre(genre: genre, sampleLimit: 200, limit: 18)

            let (m, n, c, t, r, tagData) = await (essentials, newToYou, classics, trending, top, tags)
            await MainActor.run {
                essentialsManga = m
                newToYouManga = n
                classicsManga = c
                trendingManga = t
                topRatedManga = r
                tagFacets = tagData.facets
                mediaToTagIds = tagData.mediaToTagIds
                isLoading = false
            }
        }
    }
}
