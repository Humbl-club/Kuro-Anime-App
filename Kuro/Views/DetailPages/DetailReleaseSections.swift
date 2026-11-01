import KuroCore
import SwiftUI

// MARK: - Detail release and song sections (spec §3.2, §3.3, D10, D11; rulebook §14.2)
// Shared by the legacy detail pages (flags off, live) and the series detail pages (flags on), so both
// worlds show the same next-release block and songs. The pages own the loaded values as @State and
// load them with `.detailReleases(...)`; the sections are pure and render nothing when empty (manga
// schedules stay empty until the owner approves sources, and songs until themes are collected), so a
// missing contract never leaves an empty box or error copy behind (spec §3.4).

extension View {
    /// Loads the title's release schedule (and, for anime, its songs) from `ReleasesStore` once per
    /// title. `schedule`/`songs` stay nil until the store answers; the store falls back silently.
    func detailReleases(kind: MediaKind, id: Int, schedule: Binding<[ReleaseScheduleItem]?>,
                        songs: Binding<[ThemeSong]?>) -> some View {
        modifier(DetailReleaseLoader(kind: kind, id: id, schedule: schedule, songs: songs))
    }
}

private struct DetailReleaseLoader: ViewModifier {
    let kind: MediaKind
    let id: Int
    @Binding var schedule: [ReleaseScheduleItem]?
    @Binding var songs: [ThemeSong]?
    @Environment(ReleasesStore.self) private var releases

    func body(content: Content) -> some View {
        content.task(id: "\(kind.rawValue):\(id)") {
            // Another title or season entry: never show the previous one's dates or songs meanwhile.
            schedule = nil
            songs = nil
            let loaded = await releases.mediaSchedule(kind: kind, id: id)
            guard !Task.isCancelled else { return }
            schedule = loaded
            guard kind == .anime else { return }
            let loadedSongs = await releases.themes(animeId: id)
            guard !Task.isCancelled else { return }
            songs = loadedSongs
        }
    }
}

/// "Coming up." on a detail page: the next known units with their certainty ("Ep. 8 · Thu 15 Oct,
/// 18:30", "Vol. 115 · November", "Ch. 1197 · expected around Sun 9 Nov") and their source, then the
/// last released unit when the source has one. Hidden when nothing is known (never "TBA").
struct DetailNextReleaseSection: View {
    let items: [ReleaseScheduleItem]

    init(items: [ReleaseScheduleItem]) {
        self.items = items
    }

    private var upcoming: [ReleaseScheduleItem] {
        Array(items.filter { $0.isDisplayable && !$0.isPast }.prefix(3))
    }

    private var lastReleased: ReleaseScheduleItem? {
        items.first { $0.isPast && $0.isDisplayable && $0.releaseAt != nil }
    }

    var body: some View {
        if !upcoming.isEmpty || lastReleased != nil {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                KuroSectionHeader(KuroLocale.text("Coming up.", "Demnächst."), size: .title)
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, item in
                    KuroReleaseLine(item, showsSource: index == 0, undatedFallback: true,
                                    font: index == 0 ? .kuroBody(weight: .regular) : .kuroMeta(),
                                    color: index == 0 ? .kuroInk : .kuroInkSecondary)
                }
                if let lastReleased {
                    KuroReleaseLine(lastReleased, color: .kuroInkQuiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The anime's own next airing (catalogue row) as a confirmed AniList release, shown before the
    /// schedule answers so the page does not jump. nil when there is no future airing time: an
    /// episode number alone is never turned into a date.
    static func seed(for anime: Anime, now: Date = Date()) -> [ReleaseScheduleItem] {
        guard let at = anime.nextAiringAt, at > now, let episode = anime.nextEpisodeNumber, episode > 0 else { return [] }
        return [ReleaseScheduleItem(medium: .anime, mediaId: anime.id, title: anime.displayTitle,
                                    unitKind: .episode, unitNumber: Double(episode), releaseAt: at,
                                    basis: .confirmed, source: "anilist", precision: .instant)]
    }
}

/// "Songs." on an anime page: openings, endings and insert songs with a Listen menu (on-device Apple
/// Music / Spotify searches, nothing stored, never autoplay). Hidden when there are none.
struct DetailSongsSection: View {
    let songs: [ThemeSong]
    @State private var showsAll = false

    init(songs: [ThemeSong]) {
        self.songs = songs
    }

    private static let collapsedCount = 4

    private var credit: String? {
        guard !songs.isEmpty, songs.allSatisfy({ $0.source.lowercased() == "animethemes" }) else { return nil }
        return KuroLocale.text("via AnimeThemes", "über AnimeThemes")
    }

    var body: some View {
        if !songs.isEmpty {
            let shown = showsAll ? songs : Array(songs.prefix(Self.collapsedCount))
            VStack(alignment: .leading, spacing: 0) {
                KuroSectionHeader(KuroLocale.text("Songs.", "Musik."), size: .title)
                    .padding(.bottom, KuroDesignSpacing.xs)
                ForEach(shown) { song in
                    KuroThemeSongRow(song)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                        }
                }
                if songs.count > Self.collapsedCount {
                    Button {
                        showsAll.toggle()
                    } label: {
                        Text(showsAll
                             ? KuroLocale.text("Show fewer", "Weniger zeigen")
                             : KuroLocale.text("Show all \(songs.count) songs", "Alle \(songs.count) Songs zeigen"))
                            .font(.kuroMeta(weight: .medium))
                            .foregroundStyle(Color.kuroInk)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(KuroPressStyle())
                }
                if let credit {
                    Text(credit)
                        .font(.kuroMeta())
                        .foregroundStyle(Color.kuroInkQuiet)
                        .padding(.top, KuroDesignSpacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Series detail fallback (spec D15)

/// When the flag-on series detail shows the legacy sections instead (spec D15): its bundle carries no
/// series data (no series and no seasons), or the bundle could not be read at all (the series RPC is
/// a prepared migration, not deployed live). Decided once, on the first answer.
enum SeriesDetailFallback {
    static func usesLegacy(bundle: SeriesDetailBundle?, loadFailed: Bool) -> Bool {
        if loadFailed { return true }
        guard let bundle else { return false }
        return !hasSeriesData(bundle)
    }

    static func hasSeriesData(_ bundle: SeriesDetailBundle) -> Bool {
        bundle.seriesId != nil || !bundle.sections.isEmpty
    }

    /// The series bundle's own songs as `ThemeSong`s (used only when `media_themes_v1` has none).
    static func songs(from themes: [SeriesDetailBundle.Theme]) -> [ThemeSong] {
        themes.compactMap { theme in
            let role = theme.role.uppercased()
            let kind: ThemeSongKind
            if role.hasPrefix("OP") { kind = .opening }
            else if role.hasPrefix("ED") { kind = .ending }
            else if role.hasPrefix("IN") { kind = .insert }
            else { return nil }
            guard let title = theme.songTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
            let sequence = Int(role.drop(while: { $0.isLetter }))
            return ThemeSong(kind: kind, sequence: sequence, title: title, artist: theme.artist, source: "kuro")
        }
    }

    /// "Finished" / "Airing" / "Publishing" … for a catalogue status; nil when unknown (omitted).
    static func statusText(_ raw: String?, medium: MediaKind) -> String? {
        switch raw?.uppercased() {
        case "FINISHED": return KuroLocale.text("Finished", "Abgeschlossen")
        case "RELEASING":
            return medium == .manga ? KuroLocale.text("Publishing", "Erscheint") : KuroLocale.text("Airing", "Läuft")
        case "NOT_YET_RELEASED": return KuroLocale.text("Not yet released", "Noch nicht erschienen")
        case "HIATUS": return KuroLocale.text("On hiatus", "Pausiert")
        case "CANCELLED": return KuroLocale.text("Cancelled", "Eingestellt")
        default: return nil
        }
    }
}
