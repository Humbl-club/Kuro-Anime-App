import KuroCore
import SwiftUI

struct MediaDetailSheet: View {
    let kind: MediaKind
    let id: Int
    /// The page has loaded (reported by the loaders; kept for callers that read it). The grabber shows in
    /// every state (navigation contract N8) and every state carries the journey chrome (Back when pushed,
    /// ✕ always), so a loading or failed push is never a page with no way back.
    @State private var loaded = false

    var body: some View {
        ZStack {
            // Keep the sheet background consistent during loading/error states.
            Color.kuroBackground.ignoresSafeArea()

            switch kind {
            case .anime:
                AnimeDetailLoaderView(animeId: id, loaded: $loaded)
            case .manga:
                MangaDetailLoaderView(mangaId: id, loaded: $loaded)
            }
        }
        .accessibilityIdentifier("media_detail_sheet")
        #if os(iOS)
        .presentationDragIndicator(DetailLoaderChrome.dragIndicator)
        #endif
    }
}

struct AnimeDetailLoaderView: View {
    let animeId: Int
    var loaded: Binding<Bool> = .constant(false)
    @Environment(CatalogStore.self) private var catalog
    @State private var anime: Anime? = nil
    @State private var failure: DetailLoadFailure? = nil
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let anime {
                AnimeDetailView(anime: anime)
                    .onAppear { loaded.wrappedValue = true }
            } else if let failure {
                KuroStateView(failure.kind, title: failure.title) {
                    self.failure = nil
                    retryCount += 1
                }
                .kuroJourneyChrome(title: "", collapseProgress: 0)
            } else {
                KuroStateView(.loading)
                    .kuroJourneyChrome(title: "", collapseProgress: 0)
            }
        }
        .task(id: "\(animeId)-\(retryCount)") {
            failure = nil
            let perf = KuroPerf.begin("detail.anime")
            do {
                let loaded = try await catalog.fetchAnimeById(animeId)
                // A retry or dismissal cancelled this load: the newer task (or nobody) owns the state.
                guard !Task.isCancelled else { KuroPerf.end(perf, message: "cancelled"); return }
                if let loaded {
                    anime = loaded
                    KuroPerf.end(perf, message: "ok")
                } else {
                    failure = .missing
                    KuroPerf.end(perf, message: "missing")
                }
            } catch {
                guard !Task.isCancelled, !DetailLoadFailure.isCancellation(error) else {
                    KuroPerf.end(perf, message: "cancelled")
                    return
                }
                failure = DetailLoadFailure(error)
                KuroPerf.end(perf, message: "error")
            }
        }
    }
}

struct MangaDetailLoaderView: View {
    let mangaId: Int
    var loaded: Binding<Bool> = .constant(false)
    @Environment(CatalogStore.self) private var catalog
    @State private var manga: Manga? = nil
    @State private var failure: DetailLoadFailure? = nil
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let manga {
                MangaDetailView(manga: manga)
                    .onAppear { loaded.wrappedValue = true }
            } else if let failure {
                KuroStateView(failure.kind, title: failure.title) {
                    self.failure = nil
                    retryCount += 1
                }
                .kuroJourneyChrome(title: "", collapseProgress: 0)
            } else {
                KuroStateView(.loading)
                    .kuroJourneyChrome(title: "", collapseProgress: 0)
            }
        }
        .task(id: "\(mangaId)-\(retryCount)") {
            failure = nil
            let perf = KuroPerf.begin("detail.manga")
            do {
                let loaded = try await catalog.fetchMangaById(mangaId)
                // A retry or dismissal cancelled this load: the newer task (or nobody) owns the state.
                guard !Task.isCancelled else { KuroPerf.end(perf, message: "cancelled"); return }
                if let loaded {
                    manga = loaded
                    KuroPerf.end(perf, message: "ok")
                } else {
                    failure = .missing
                    KuroPerf.end(perf, message: "missing")
                }
            } catch {
                guard !Task.isCancelled, !DetailLoadFailure.isCancellation(error) else {
                    KuroPerf.end(perf, message: "cancelled")
                    return
                }
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

    /// A cancelled load (task cancellation or a cancelled URL request) is not a failure.
    static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
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
