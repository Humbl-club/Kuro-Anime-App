import Foundation

// MARK: - Song shelf organisation (details-songs spec §8.2, D10; pure, KuroTests/DSsongsTests.swift)
// 1. Versions of one song collapse into one row (key: kind, sequence, normalised title) with version tags.
// 2. Parts follow episode ranges only: an opening with a first episode starts a part that runs to the next
//    opening's first episode − 1; endings and insert songs join the part that holds their first episode;
//    songs without a range go into a final "Other songs" part (only when there are other parts). No arc
//    names are ever invented: the heading is the episode span. One part only → no headings.
// 3. Inside a part: openings, then endings, then insert songs, each by sequence.

/// An episode range as AnimeThemes writes it ("1-19", "1–12", "6-16, 18-19", "26", "13-").
nonisolated struct SongEpisodeSpan: Equatable, Sendable {
    let first: Int
    /// The highest episode named; nil when only an open start is known ("13-").
    let last: Int?
    /// The range runs on past `last` ("13-").
    let isOpen: Bool

    /// nil when the text names no episode number.
    static func parse(_ text: String?) -> SongEpisodeSpan? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        var numbers: [Int] = []
        var digits = ""
        for character in text {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                if let value = Int(digits) { numbers.append(value) }
                digits = ""
            }
        }
        if !digits.isEmpty, let value = Int(digits) { numbers.append(value) }
        guard let first = numbers.first else { return nil }
        let dashes: Set<Swift.Character> = ["-", "–", "—", "~"]
        let isOpen = text.last.map { dashes.contains($0) } ?? false
        let highest = numbers.max() ?? first
        // "13-" names only its start: the end is unknown (open), not 13.
        let last: Int? = (isOpen && numbers.count == 1) ? nil : highest
        return SongEpisodeSpan(first: min(first, numbers.min() ?? first), last: last, isOpen: isOpen)
    }

    /// The range text with an en dash, as the source wrote it ("6–16, 18–19").
    static func display(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " - ", with: "–")
            .replacingOccurrences(of: "-", with: "–")
    }
}

/// One song on the shelf: its versions collapsed (spec §8.2.1).
nonisolated struct SongShelfRow: Identifiable, Equatable, Sendable {
    /// The representative version (lowest version number; a song without a version number first).
    let song: ThemeSong
    /// Every version of the song, by version number.
    let versions: [ThemeSong]
    /// The span over every version (the earliest first episode, the highest last).
    let span: SongEpisodeSpan?

    var id: String { song.id }

    /// The version that carries a verified Apple match (the representative first), if any.
    var matched: ThemeSong? {
        if song.apple != nil { return song }
        return versions.first { $0.apple != nil }
    }

    /// Veiled until shown: the representative is flagged a spoiler (a later version alone does not hide
    /// a title the viewer already met in version 1), or any version is NSFW.
    var isSpoiler: Bool { song.isSpoiler }
    var isNSFW: Bool { versions.contains { $0.isNSFW } }

    /// A TV-size marker in the source title ("(TV Size)", "TV ver.", "TVサイズ").
    var isTVSize: Bool { versions.contains { SongShelfGrouping.hasTVSizeMarker($0.title) } }

    /// The title as shown: the source title without a bracketed TV-size marker (the tag says it).
    var displayTitle: String { SongShelfGrouping.strippingTVSizeMarker(song.title) }

    /// "v1 Ep. 1–19", "v2 Ep. 20–22" when the song has more than one version; otherwise none.
    func versionTags(german: Bool) -> [String] {
        guard versions.count > 1 else { return [] }
        return versions.enumerated().map { index, version in
            let number = version.version ?? (index + 1)
            let label = "v\(number)"
            guard let episodes = version.episodes?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !episodes.isEmpty else { return label }
            return "\(label) \(SongShelfCopy.episodePrefix(german: german))\(SongEpisodeSpan.display(episodes))"
        }
    }

    /// Spoken version tags: ", version 2" for the row (VoiceOver).
    var versionNumbers: [Int] {
        guard versions.count > 1 else { return [] }
        return versions.enumerated().map { index, version in version.version ?? (index + 1) }
    }
}

/// One part of the shelf: an episode span, or the final "Other songs".
nonisolated struct SongShelfPart: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Episodes `first` … `last` (nil and open: "Ep. 13–").
        case episodes(first: Int, last: Int?)
        /// Songs without an episode range.
        case other
        /// The only part (no heading).
        case all
    }

    let kind: Kind
    let rows: [SongShelfRow]

    var id: String {
        switch kind {
        case .episodes(let first, _): return "ep-\(first)"
        case .other: return "other"
        case .all: return "all"
        }
    }
}

nonisolated enum SongShelfGrouping {
    /// Whether any song names its artist (the shelf drops the per-row "Artist not listed" otherwise).
    static func anyArtist(_ songs: [ThemeSong]) -> Bool {
        songs.contains { !($0.artist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }
    }

    // MARK: Versions

    /// The collapse key's title: lower case, no diacritics or width variants, no TV-size marker, only
    /// letters and digits (any script).
    static func normalisedTitle(_ title: String) -> String {
        let stripped = strippingTVSizeMarker(title)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return String(stripped.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Swift.Character.init))
    }

    static func hasTVSizeMarker(_ title: String) -> Bool {
        title.range(of: #"(?i)tv[ \-]?(size|ver)"#, options: .regularExpression) != nil || title.contains("TVサイズ")
    }

    /// Removes a bracketed TV-size marker ("Gurenge (TV Size)" → "Gurenge"); other text stays.
    static func strippingTVSizeMarker(_ title: String) -> String {
        let pattern = #"\s*[\(\[（【][^\)\]）】]*(?:(?i:tv[ \-]?(?:size|ver))|TVサイズ)[^\)\]）】]*[\)\]）】]"#
        let stripped = title.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? title : stripped
    }

    /// One row per song (spec §8.2.1), in the input order of each song's first version.
    static func collapse(_ songs: [ThemeSong]) -> [SongShelfRow] {
        var order: [String] = []
        var groups: [String: [ThemeSong]] = [:]
        for song in songs {
            let key = "\(song.kind.rawValue)|\(song.sequence.map(String.init) ?? "-")|\(normalisedTitle(song.title))"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(song)
        }
        return order.compactMap { key in
            guard let members = groups[key] else { return nil }
            let versions = members.enumerated()
                .sorted { ($0.element.version ?? 0, $0.offset) < ($1.element.version ?? 0, $1.offset) }
                .map(\.element)
            guard let representative = versions.first else { return nil }
            let spans = versions.compactMap { SongEpisodeSpan.parse($0.episodes) }
            let span: SongEpisodeSpan? = spans.isEmpty ? nil : {
                let first = spans.map(\.first).min() ?? 0
                let open = spans.contains(where: \.isOpen)
                let last = spans.compactMap(\.last).max()
                return SongEpisodeSpan(first: first, last: last, isOpen: open)
            }()
            return SongShelfRow(song: representative, versions: versions, span: span)
        }
    }

    // MARK: Parts

    /// The shelf's parts (spec §8.2.2–4).
    static func parts(_ songs: [ThemeSong]) -> [SongShelfPart] {
        let rows = collapse(songs)
        guard !rows.isEmpty else { return [] }
        let starts = Array(Set(rows.filter { $0.song.kind == .opening }.compactMap { $0.span?.first })).sorted()
        guard let firstStart = starts.first else {
            return [SongShelfPart(kind: .all, rows: ordered(rows))]
        }
        var buckets = Array(repeating: [SongShelfRow](), count: starts.count)
        var other: [SongShelfRow] = []
        for row in rows {
            guard let span = row.span else {
                other.append(row)
                continue
            }
            let index = span.first < firstStart ? 0 : (starts.lastIndex { $0 <= span.first } ?? 0)
            buckets[index].append(row)
        }
        var parts: [SongShelfPart] = []
        for (index, start) in starts.enumerated() {
            let end: Int?
            if index + 1 < starts.count {
                end = starts[index + 1] - 1
            } else {
                let bucket = buckets[index]
                let open = bucket.contains { $0.span?.isOpen == true }
                let highest = rows.compactMap { $0.span?.last }.max()
                if open { end = nil } else if let highest, highest >= start { end = highest } else { end = nil }
            }
            parts.append(SongShelfPart(kind: .episodes(first: start, last: end), rows: ordered(buckets[index])))
        }
        if !other.isEmpty { parts.append(SongShelfPart(kind: .other, rows: ordered(other))) }
        if parts.count == 1, let only = parts.first {
            return [SongShelfPart(kind: .all, rows: only.rows)]
        }
        return parts
    }

    /// Openings, then endings, then insert songs, each by sequence (unnumbered last), then first episode.
    static func ordered(_ rows: [SongShelfRow]) -> [SongShelfRow] {
        func kindRank(_ kind: ThemeSongKind) -> Int {
            switch kind {
            case .opening: return 0
            case .ending: return 1
            case .insert: return 2
            }
        }
        return rows.enumerated().sorted { lhs, rhs in
            let l = (kindRank(lhs.element.song.kind), lhs.element.song.sequence ?? Int.max,
                     lhs.element.span?.first ?? Int.max, lhs.offset)
            let r = (kindRank(rhs.element.song.kind), rhs.element.song.sequence ?? Int.max,
                     rhs.element.span?.first ?? Int.max, rhs.offset)
            return l < r
        }.map(\.element)
    }

    /// Every row in part order.
    static func rowCount(_ parts: [SongShelfPart]) -> Int { parts.reduce(0) { $0 + $1.rows.count } }

    /// The first `limit` rows, counting parts in order (spec §8.5); empty parts are dropped.
    static func folded(_ parts: [SongShelfPart], limit: Int) -> [SongShelfPart] {
        var remaining = limit
        var result: [SongShelfPart] = []
        for part in parts where remaining > 0 {
            let rows = Array(part.rows.prefix(remaining))
            remaining -= rows.count
            if !rows.isEmpty { result.append(SongShelfPart(kind: part.kind, rows: rows)) }
        }
        return result
    }

    // MARK: Veil

    /// Whether a row is veiled (spec §8.3): a spoiler until tapped or until the viewer's progress reached
    /// its first episode; an NSFW song until tapped (never auto-revealed).
    static func isVeiled(_ row: SongShelfRow, revealed: Bool, progress: Int) -> Bool {
        guard row.isSpoiler || row.isNSFW else { return false }
        if revealed { return false }
        if row.isNSFW { return true }
        guard progress > 0, let first = row.span?.first else { return true }
        return first > progress
    }

    // MARK: Action

    /// What the row's trailing control is (spec §8.3).
    enum Action: Equatable {
        /// Veiled: the title is the reveal button; no other control.
        case none
        /// ▶ / ■ for this version's verified preview.
        case preview(ThemeSong)
        /// "Apple Music ↗": the matched track (no preview, or the preview failed).
        case appleMusic(URL)
        /// The existing "Listen" chooser (Apple Music search / Spotify search).
        case listen
    }

    /// `canPlay` is false when no preview player is installed (a host without one shows the Apple Music link).
    static func action(for row: SongShelfRow, veiled: Bool, previewFailed: Bool, canPlay: Bool = true) -> Action {
        guard !veiled else { return .none }
        if let matched = row.matched, let apple = matched.apple {
            if canPlay, !previewFailed, SongPreviewPlayer.canPreview(matched) { return .preview(matched) }
            if let music = ProviderAvailabilityStore.validatedOutboundURL(apple.musicURL.absoluteString),
               AppleSongMatch.musicHosts.contains(music.host()?.lowercased() ?? "") {
                return .appleMusic(music)
            }
        }
        return row.song.appleMusicSearchURL != nil || row.song.spotifySearchURL != nil ? .listen : .none
    }

    // MARK: Artwork

    /// Apple's artwork at `side` × `side` (the trailing "{w}x{h}bb" segment), re-checked to be https on
    /// *.mzstatic.com. nil for no artwork.
    static func artworkURL(_ url: URL?, side: Int) -> URL? {
        guard let url else { return nil }
        let resized = url.absoluteString.replacingOccurrences(
            of: #"/\d+x\d+bb(\.[A-Za-z]+)$"#, with: "/\(side)x\(side)bb$1", options: .regularExpression)
        return AppleSongMatch.url(resized, hosts: [], suffix: ".mzstatic.com")
    }
}
