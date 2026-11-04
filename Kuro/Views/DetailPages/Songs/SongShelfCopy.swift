import Foundation

// MARK: - Song shelf copy (details-songs spec §15; EN/DE, pure: every function takes `german`)
// EXISTING strings are reused verbatim from the shipped sound panel ("The sound of it." / "So klingt es.",
// "Spoiler. Tap to show.", "Listen", "Show all {n} songs", "Show fewer"). The attribution and "Open in
// Apple Music" are the data lane's `SongPreviewCopy` words, which are identical to the spec.

nonisolated enum SongShelfCopy {
    // EXISTING
    static func heading(german: Bool) -> String { german ? "So klingt es." : "The sound of it." }
    static func spoiler(german: Bool) -> String { german ? "Spoiler. Zum Anzeigen tippen." : "Spoiler. Tap to show." }
    static func listen(german: Bool) -> String { german ? "Anhören" : "Listen" }
    static func listenLabel(_ title: String, german: Bool) -> String { german ? "\(title) anhören" : "Listen to \(title)" }
    static func listenHint(german: Bool) -> String {
        german ? "Sucht in Apple Music oder Spotify." : "Searches Apple Music or Spotify."
    }
    static func showAll(_ count: Int, german: Bool) -> String { german ? "Alle \(count) Songs zeigen" : "Show all \(count) songs" }
    static func showFewer(german: Bool) -> String { german ? "Weniger zeigen" : "Show fewer" }
    /// The same words as `SongPreviewCopy.attribution` (Apple's requested credit).
    static func attribution(german: Bool) -> String {
        german ? "Vorschau mit freundlicher Genehmigung von Apple Music" : "Preview courtesy of Apple Music"
    }
    /// The same words as `SongPreviewCopy.openInAppleMusic`.
    static func openInAppleMusic(german: Bool) -> String { german ? "In Apple Music öffnen" : "Open in Apple Music" }
    static func youreOffline(german: Bool) -> String { german ? "Du bist offline." : "You're offline." }

    // NEW
    static func count(_ count: Int, german: Bool) -> String {
        german ? "\(count) \(count == 1 ? "Song" : "Songs")" : "\(count) \(count == 1 ? "song" : "songs")"
    }
    static func episodePrefix(german: Bool) -> String { german ? "F. " : "Ep. " }
    static func otherSongs(german: Bool) -> String { german ? "Weitere Songs" : "Other songs" }
    static func tvSize(german: Bool) -> String { german ? "TV-Version" : "TV size" }
    static func artistNotListed(german: Bool) -> String { german ? "Künstler nicht angegeben" : "Artist not listed" }
    /// The one footer note when no song on the shelf names its artist.
    static func artistsNotListed(german: Bool) -> String {
        german ? "Künstler sind in der Quelle nicht angegeben." : "Artists not listed by the source."
    }
    static func playLabel(_ title: String, german: Bool) -> String {
        german ? "Vorschau von \(title) abspielen" : "Play preview of \(title)"
    }
    /// The data lane's player stops (it has no pause): the words say what happens.
    static func stopLabel(german: Bool) -> String { german ? "Vorschau anhalten" : "Stop preview" }
    static func previewUnavailable(german: Bool) -> String { german ? "Vorschau nicht verfügbar." : "Preview unavailable." }
    static func songListSource(german: Bool) -> String { german ? "Songliste: AnimeThemes" : "Song list: AnimeThemes" }
    static func appleMusicLink(german: Bool) -> String { "Apple Music ↗" }
    static func spotifyLink(german: Bool) -> String { "Spotify ↗" }
    static func openInAppleMusicLink(german: Bool) -> String { openInAppleMusic(german: german) + " ↗" }
    static func spoilerArt(german: Bool) -> String { "Spoiler" }

    /// The kind word on the row ("Opening 1" / "Vorspann 1"), from `ThemeSong.spokenLabel`.
    static func kind(_ song: ThemeSong, german: Bool) -> String { song.spokenLabel(german: german) }

    /// The branded tile's word ("OP 1", "ED 2", "IN").
    static func tileWord(_ song: ThemeSong) -> String {
        guard let sequence = song.sequence else { return song.kind.rawValue }
        return "\(song.kind.rawValue) \(sequence)"
    }

    /// "Ep. 1–5" / "F. 1–5", "Ep. 13–", "Ep. 26".
    static func span(first: Int, last: Int?, german: Bool) -> String {
        let prefix = episodePrefix(german: german)
        guard let last else { return "\(prefix)\(first)–" }
        return last == first ? "\(prefix)\(first)" : "\(prefix)\(first)–\(last)"
    }

    /// The span for one row ("Ep. 1–19"), from the row's own range text when there is one.
    static func rowSpan(_ row: SongShelfRow, german: Bool) -> String? {
        if row.versions.count == 1, let episodes = row.song.episodes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !episodes.isEmpty {
            return episodePrefix(german: german) + SongEpisodeSpan.display(episodes)
        }
        guard let span = row.span else { return nil }
        return self.span(first: span.first, last: span.isOpen ? nil : span.last, german: german)
    }

    /// The part heading (visible) and its spoken label.
    static func partHeading(_ kind: SongShelfPart.Kind, german: Bool) -> String? {
        switch kind {
        case .all: return nil
        case .other: return otherSongs(german: german)
        case .episodes(let first, let last): return span(first: first, last: last, german: german)
        }
    }

    static func partSpoken(_ kind: SongShelfPart.Kind, german: Bool) -> String? {
        switch kind {
        case .all: return nil
        case .other: return otherSongs(german: german)
        case .episodes(let first, let last):
            guard let last else { return german ? "Folgen ab \(first)" : "Episodes from \(first)" }
            if last == first { return german ? "Folge \(first)" : "Episode \(first)" }
            return german ? "Folgen \(first) bis \(last)" : "Episodes \(first) to \(last)"
        }
    }

    /// One row read as one element: "Opening 1, Gurenge, by LiSA, TV size, version 2".
    static func rowSpoken(_ row: SongShelfRow, german: Bool) -> String {
        var parts = [kind(row.song, german: german), row.displayTitle]
        if let artist = row.song.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            parts.append(german ? "von \(artist)" : "by \(artist)")
        } else {
            parts.append(artistNotListed(german: german))
        }
        if row.isTVSize { parts.append(tvSize(german: german)) }
        for number in row.versionNumbers where number > 1 {
            parts.append(german ? "Version \(number)" : "version \(number)")
        }
        return parts.joined(separator: ", ")
    }

    /// A veiled row: "Spoiler, Opening 1. Double tap to show."
    static func veiledSpoken(_ row: SongShelfRow, german: Bool) -> String {
        german ? "Spoiler, \(kind(row.song, german: true)). Zum Anzeigen doppeltippen."
            : "Spoiler, \(kind(row.song, german: false)). Double tap to show."
    }

    /// "0:12".
    static func clock(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):" + String(format: "%02d", clamped % 60)
    }
}
