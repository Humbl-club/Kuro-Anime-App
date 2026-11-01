import KuroCore
import SwiftUI

struct MediaDetailSheet: View {
    let kind: MediaKind
    let id: Int

    var body: some View {
        ZStack {
            // Keep the sheet background consistent during loading/error states.
            Color.kuroBackground.ignoresSafeArea()

            switch kind {
            case .anime:
                AnimeDetailLoaderView(animeId: id)
            case .manga:
                MangaDetailLoaderView(mangaId: id)
            }
        }
        .accessibilityIdentifier("media_detail_sheet")
        #if os(iOS)
        .presentationDragIndicator(.hidden)
        #endif
    }
}

struct AnimeDetailLoaderView: View {
    let animeId: Int
    @Environment(CatalogStore.self) private var catalog
    @State private var anime: Anime? = nil
    @State private var failure: DetailLoadFailure? = nil
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let anime {
                AnimeDetailView(anime: anime)
            } else if let failure {
                KuroStateView(failure.kind, title: failure.title) {
                    self.failure = nil
                    retryCount += 1
                }
            } else {
                KuroStateView(.loading)
            }
        }
        .task(id: "\(animeId)-\(retryCount)") {
            failure = nil
            let perf = KuroPerf.begin("detail.anime")
            do {
                if let loaded = try await catalog.fetchAnimeById(animeId) {
                    anime = loaded
                    KuroPerf.end(perf, message: "ok")
                } else {
                    failure = .missing
                    KuroPerf.end(perf, message: "missing")
                }
            } catch {
                failure = DetailLoadFailure(error)
                KuroPerf.end(perf, message: "error")
            }
        }
    }
}

struct MangaDetailLoaderView: View {
    let mangaId: Int
    @Environment(CatalogStore.self) private var catalog
    @State private var manga: Manga? = nil
    @State private var failure: DetailLoadFailure? = nil
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let manga {
                MangaDetailView(manga: manga)
            } else if let failure {
                KuroStateView(failure.kind, title: failure.title) {
                    self.failure = nil
                    retryCount += 1
                }
            } else {
                KuroStateView(.loading)
            }
        }
        .task(id: "\(mangaId)-\(retryCount)") {
            failure = nil
            let perf = KuroPerf.begin("detail.manga")
            do {
                if let loaded = try await catalog.fetchMangaById(mangaId) {
                    manga = loaded
                    KuroPerf.end(perf, message: "ok")
                } else {
                    failure = .missing
                    KuroPerf.end(perf, message: "missing")
                }
            } catch {
                failure = DetailLoadFailure(error)
                KuroPerf.end(perf, message: "error")
            }
        }
    }
}

/// Why a detail page could not open, in honest EN/DE copy (rulebook §9): never the raw error text.
enum DetailLoadFailure: Equatable {
    case missing
    case offline
    case failed

    init(_ error: any Error) {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(urlError.code) {
            self = .offline
        } else {
            self = .failed
        }
    }

    var kind: KuroStateView.Kind {
        switch self {
        case .missing, .failed: return .failed(hasCachedContent: false)
        case .offline: return .offline(hasCachedContent: false)
        }
    }

    var title: String? {
        switch self {
        case .missing: return KuroLocale.text("This title isn't available.", "Dieser Titel ist nicht verfügbar.")
        case .offline: return nil
        case .failed: return KuroLocale.text("Couldn't open this title.", "Dieser Titel konnte nicht geöffnet werden.")
        }
    }
}
