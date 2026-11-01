import SwiftUI

// MARK: - Theme song row (spec §3.5, D11, rulebook §14.2)
// "OP1  Title / Artist · Ep. 1–12   Listen". Listen opens an Apple Music or Spotify SEARCH for the
// song on this device (nothing is stored from either service; never autoplay). A spoiler-flagged
// song keeps its title hidden until tapped. Rows carry no separators; the caller adds hairlines.

struct KuroThemeSongRow: View {
    let song: ThemeSong

    init(_ song: ThemeSong) {
        self.song = song
    }

    @Environment(\.openURL) private var openURL
    @State private var revealed = false

    private var hidesTitle: Bool { song.isSpoiler && !revealed }

    private var detailLine: String? {
        var parts: [String] = []
        if let artist = song.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            parts.append(artist)
        }
        if let episodes = song.episodes?.trimmingCharacters(in: .whitespacesAndNewlines), !episodes.isEmpty {
            parts.append(KuroLocale.text("Ep. ", "F. ") + episodes)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: KuroDesignSpacing.md) {
            Text(song.label)
                .font(.kuroMeta(weight: .medium))
                .foregroundStyle(Color.kuroInkQuiet)
                .frame(minWidth: 36, alignment: .leading)
                // Spoken in full so VoiceOver tells an opening from an ending (rulebook §12).
                .accessibilityLabel(song.spokenLabel(german: KuroLocale.isGerman))

            VStack(alignment: .leading, spacing: 2) {
                if hidesTitle {
                    Button {
                        revealed = true
                    } label: {
                        Text(KuroLocale.text("Spoiler. Tap to show.", "Spoiler. Zum Anzeigen tippen."))
                            .font(.kuroBody(weight: .regular))
                            .foregroundStyle(Color.kuroInkSecondary)
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(song.title)
                        .font(.kuroBody(weight: .medium))
                        .foregroundStyle(Color.kuroInk)
                        .lineLimit(2)
                    if let detailLine {
                        Text(detailLine)
                            .font(.kuroMeta())
                            .foregroundStyle(Color.kuroInkSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: hidesTitle ? .contain : .combine)

            if !hidesTitle {
                listenMenu
            }
        }
        .padding(.vertical, KuroDesignSpacing.sm)
    }

    @ViewBuilder
    private var listenMenu: some View {
        let apple = song.appleMusicSearchURL
        let spotify = song.spotifySearchURL
        if apple != nil || spotify != nil {
            Menu {
                if let apple {
                    Button("Apple Music") { openURL(apple) }
                }
                if let spotify {
                    Button("Spotify") { openURL(spotify) }
                }
            } label: {
                Text(KuroLocale.text("Listen", "Anhören"))
                    .font(.kuroMeta(weight: .medium))
                    .foregroundStyle(Color.kuroInk)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(KuroLocale.text("Listen to \(song.title)", "\(song.title) anhören"))
            .accessibilityHint(KuroLocale.text("Searches Apple Music or Spotify.", "Sucht in Apple Music oder Spotify."))
        }
    }
}
