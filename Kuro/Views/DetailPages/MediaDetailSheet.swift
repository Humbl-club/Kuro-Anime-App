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
    @Environment(SupabaseService.self) private var supabaseService
    @State private var anime: Anime? = nil
    @State private var errorMessage: String? = nil
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let anime {
                AnimeDetailView(anime: anime)
            } else if let errorMessage {
                VStack(spacing: 10) {
                    Text("COULDN'T LOAD")
                        .font(.kuroCaption())
                        .tracking(1.6)
                        .foregroundColor(.black.opacity(0.55))
                    Text(errorMessage)
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button {
                        self.errorMessage = nil
                        retryCount += 1
                    } label: {
                        Text("RETRY")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.black))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 60)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .task(id: "\(animeId)-\(retryCount)") {
            errorMessage = nil
            let perf = KuroPerf.begin("detail.anime")
            do {
                if let loaded = try await supabaseService.fetchAnimeById(animeId) {
                    anime = loaded
                    KuroPerf.end(perf, message: "ok")
                } else {
                    errorMessage = "Not found"
                    KuroPerf.end(perf, message: "missing")
                }
            } catch {
                errorMessage = error.localizedDescription
                KuroPerf.end(perf, message: "error")
            }
        }
    }
}

struct MangaDetailLoaderView: View {
    let mangaId: Int
    @Environment(SupabaseService.self) private var supabaseService
    @State private var manga: Manga? = nil
    @State private var errorMessage: String? = nil
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let manga {
                MangaDetailView(manga: manga)
            } else if let errorMessage {
                VStack(spacing: 10) {
                    Text("COULDN'T LOAD")
                        .font(.kuroCaption())
                        .tracking(1.6)
                        .foregroundColor(.black.opacity(0.55))
                    Text(errorMessage)
                        .font(.kuroMicro(weight: .light))
                        .foregroundColor(.black.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    Button {
                        self.errorMessage = nil
                        retryCount += 1
                    } label: {
                        Text("RETRY")
                            .font(.kuroCaption(weight: .medium))
                            .tracking(1.6)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color.black))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 60)
            } else {
                ProgressView()
                    .padding(.top, 80)
            }
        }
        .task(id: "\(mangaId)-\(retryCount)") {
            errorMessage = nil
            let perf = KuroPerf.begin("detail.manga")
            do {
                if let loaded = try await supabaseService.fetchMangaById(mangaId) {
                    manga = loaded
                    KuroPerf.end(perf, message: "ok")
                } else {
                    errorMessage = "Not found"
                    KuroPerf.end(perf, message: "missing")
                }
            } catch {
                errorMessage = error.localizedDescription
                KuroPerf.end(perf, message: "error")
            }
        }
    }
}
