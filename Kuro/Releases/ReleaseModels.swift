import Foundation
import KuroCore

// MARK: - Release and theme models (spec §3.1–3.3)
// Decoded from `user_release_schedule_v1`, `media_release_schedule_v1` and `media_themes_v1`. None of
// these RPCs is deployed live yet (spec §3.4): `ReleasesStore` falls back silently, so every type here
// can also be built locally (the `user_airing_next` fallback) and decoding is lenient (one bad row
// never blanks a list; see `LenientRows`).

/// What the account's loaded release schedule can claim about one medium (rulebook §9: a failed read
/// or a missing source never reads as "Nothing scheduled"). Published by `ReleasesStore`.
nonisolated enum ReleaseScheduleCoverage: Equatable, Sendable {
    /// Not asked yet for this account.
    case pending
    /// The schedule answered for this medium: an empty list means nothing is announced.
    case complete
    /// Only confirmed episodes of the next seven days are known (the `user_airing_next` fallback).
    case nextSevenDays
    /// No source answers for this medium (manga under the airing fallback): dates are unknown.
    case noSource
    /// The last read failed: dates are unknown until a retry succeeds.
    case failed
}

/// How certain a displayed release date is (spec D10).
nonisolated enum ReleaseBasis: String, Codable, Sendable, CaseIterable {
    /// The source states the date and time.
    case confirmed
    /// The source states a date or window without a time.
    case announced
    /// Computed from cadence; shown only at confidence ≥ `ReleaseScheduleItem.minimumEstimateConfidence`.
    case estimated
}

/// How exact `releaseAt` is (spec §3.3a). For every precision except `instant`, `releaseAt` is the
/// START of the window at 00:00 in the source's zone (UTC when unknown), and the UI never shows a
/// time: day "Thu 15 Oct", month "November", quarter "Q1 2027", year "2027".
nonisolated enum ReleasePrecision: String, Codable, Sendable, CaseIterable {
    /// A date and a time (the only precision a `confirmed` row has).
    case instant
    /// A calendar day without a time.
    case day
    /// A month window.
    case month
    /// A calendar quarter window.
    case quarter
    /// A year window.
    case year
}

/// The unit a release row announces.
nonisolated enum ReleaseUnitKind: String, Codable, Sendable, CaseIterable {
    case episode, chapter, volume, season
}

/// One upcoming (or the last confirmed past) unit of one title.
nonisolated struct ReleaseScheduleItem: Hashable, Sendable, Identifiable {
    /// Estimated rows below this confidence are never shown (spec §3.1, D10).
    static let minimumEstimateConfidence: Double = 0.7

    let medium: MediaKind
    let mediaId: Int
    let title: String
    let coverImage: String?
    let unitKind: ReleaseUnitKind
    /// nil when the source does not number the unit.
    let unitNumber: Double?
    /// The server's English label (e.g. "Ch. 1197"); the UI builds its own EN/DE label from
    /// `unitKind` + `unitNumber` and uses this only when the number is unknown.
    let unitLabel: String?
    /// nil when no date is known ("Dates to come.").
    let releaseAt: Date?
    let basis: ReleaseBasis
    /// 0–1; meaningful for estimated rows.
    let confidence: Double?
    /// `anilist` / `mangaupdates` / `mangadex` / `publisher` / `kuro_estimate`.
    let source: String
    let sourceURL: URL?
    /// `media_release_schedule_v1` only: the last confirmed unit already released.
    let isPast: Bool
    /// The server's `release_precision` (spec §3.3a); nil when the row does not carry it (older
    /// contract, or a locally built fallback row). Read `effectivePrecision`.
    let precision: ReleasePrecision?

    init(
        medium: MediaKind,
        mediaId: Int,
        title: String,
        coverImage: String? = nil,
        unitKind: ReleaseUnitKind,
        unitNumber: Double?,
        unitLabel: String? = nil,
        releaseAt: Date?,
        basis: ReleaseBasis,
        confidence: Double? = nil,
        source: String,
        sourceURL: URL? = nil,
        isPast: Bool = false,
        precision: ReleasePrecision? = nil
    ) {
        self.medium = medium
        self.mediaId = mediaId
        self.title = title
        self.coverImage = coverImage
        self.unitKind = unitKind
        self.unitNumber = unitNumber
        self.unitLabel = unitLabel
        self.releaseAt = releaseAt
        self.basis = basis
        self.confidence = confidence
        self.source = source
        self.sourceURL = sourceURL
        self.isPast = isPast
        self.precision = precision
    }

    /// The precision the UI renders by: the server's `release_precision`, else inferred the way rows
    /// were read before the column existed (spec §3.3a): confirmed → instant; announced → month when
    /// the date is the 1st of a month at 00:00 UTC, otherwise day; estimated → day.
    var effectivePrecision: ReleasePrecision {
        if let precision { return precision }
        switch basis {
        case .confirmed: return .instant
        case .estimated: return .day
        case .announced:
            guard let releaseAt else { return .day }
            return Self.isFirstOfMonthUTC(releaseAt) ? .month : .day
        }
    }

    /// Whether a time of day may be shown for this row: only an instant that is not an estimate.
    var showsTime: Bool { effectivePrecision == .instant && basis != .estimated }

    /// First of a month at 00:00:00 UTC (how month windows were stored before `release_precision`).
    static func isFirstOfMonthUTC(_ date: Date) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? utc.timeZone
        let parts = utc.dateComponents([.day, .hour, .minute, .second], from: date)
        return parts.day == 1 && parts.hour == 0 && parts.minute == 0 && parts.second == 0
    }

    var key: MediaKey { MediaKey(kind: medium, id: mediaId) }

    var id: String {
        let number = unitNumber.map { String($0) } ?? "-"
        let at = releaseAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        return "\(medium.rawValue):\(mediaId):\(unitKind.rawValue):\(number):\(at)"
    }

    /// Whether the row may be shown at all: estimates need confidence ≥ 0.7 (spec D10).
    var isDisplayable: Bool {
        guard basis == .estimated else { return true }
        return (confidence ?? 0) >= Self.minimumEstimateConfidence
    }

    /// The unit number as an integer when it is whole (chapters may be 1197.5).
    var wholeUnitNumber: Int? {
        guard let unitNumber, unitNumber.rounded() == unitNumber,
              abs(unitNumber) < Double(Int.max) else { return nil }
        return Int(unitNumber)
    }
}

extension ReleaseScheduleItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case medium
        case mediaId = "media_id"
        case title
        case coverImage = "cover_image"
        case unitKind = "unit_kind"
        case unitNumber = "unit_number"
        case unitLabel = "unit_label"
        case releaseAt = "release_at"
        case basis, confidence, source
        case sourceURL = "source_url"
        case isPast = "is_past"
        case precision = "release_precision"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mediumText = try c.decode(String.self, forKey: .medium).lowercased()
        guard let medium = MediaKind(rawValue: mediumText) else {
            throw DecodingError.dataCorruptedError(forKey: .medium, in: c, debugDescription: "unknown medium \(mediumText)")
        }
        let basisText = try c.decode(String.self, forKey: .basis).lowercased()
        guard let basis = ReleaseBasis(rawValue: basisText) else {
            throw DecodingError.dataCorruptedError(forKey: .basis, in: c, debugDescription: "unknown basis \(basisText)")
        }
        let kindText = (try c.decodeIfPresent(String.self, forKey: .unitKind))?.lowercased()
        self.medium = medium
        self.mediaId = try c.decode(Int.self, forKey: .mediaId)
        self.title = (try c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        self.coverImage = try c.decodeIfPresent(String.self, forKey: .coverImage)
        self.unitKind = kindText.flatMap(ReleaseUnitKind.init(rawValue:)) ?? (medium == .anime ? .episode : .chapter)
        self.unitNumber = Self.lenientDouble(c, .unitNumber)
        self.unitLabel = try c.decodeIfPresent(String.self, forKey: .unitLabel)
        self.releaseAt = try c.decodeIfPresent(Date.self, forKey: .releaseAt)
        self.basis = basis
        self.confidence = Self.lenientDouble(c, .confidence)
        self.source = (try c.decodeIfPresent(String.self, forKey: .source)) ?? ""
        self.sourceURL = (try c.decodeIfPresent(String.self, forKey: .sourceURL)).flatMap(Self.httpsURL)
        self.isPast = (try c.decodeIfPresent(Bool.self, forKey: .isPast)) ?? false
        // Absent, null or an unknown word: nil, so the UI infers it (a new word never drops the row).
        let precisionText = (try? c.decodeIfPresent(String.self, forKey: .precision)).flatMap { $0 }?.lowercased()
        self.precision = precisionText.flatMap(ReleasePrecision.init(rawValue:))
    }

    /// A PostgREST `numeric`/`real` arrives as a JSON number, occasionally as a string.
    private static func lenientDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    /// Only http(s) links are kept (no `javascript:` or app schemes from data).
    static func httpsURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return nil }
        return url
    }
}

// MARK: - Theme songs (spec §3.3)

/// Opening, ending or insert song of an anime.
nonisolated enum ThemeSongKind: String, Sendable, CaseIterable {
    case opening = "OP"
    case ending = "ED"
    case insert = "IN"
}

nonisolated struct ThemeSong: Hashable, Sendable, Identifiable {
    let kind: ThemeSongKind
    /// OP1, OP2… nil when the source does not number it.
    let sequence: Int?
    let title: String
    let artist: String?
    /// Episode range as the source writes it, e.g. "1–12".
    let episodes: String?
    let version: Int?
    let isSpoiler: Bool
    let isNSFW: Bool
    let source: String
    let sourceURL: URL?
    /// The confident iTunes match for this song (artwork, 30-second preview, Apple Music link), or nil.
    /// Decoded only from the trailing `media_themes_v1` columns of 20261103100200; the older shape
    /// (and any row the client cannot verify) has none.
    let apple: AppleSongMatch?

    init(kind: ThemeSongKind, sequence: Int?, title: String, artist: String?, episodes: String? = nil,
         version: Int? = nil, isSpoiler: Bool = false, isNSFW: Bool = false,
         source: String = "animethemes", sourceURL: URL? = nil, apple: AppleSongMatch? = nil) {
        self.kind = kind
        self.sequence = sequence
        self.title = title
        self.artist = artist
        self.episodes = episodes
        self.version = version
        self.isSpoiler = isSpoiler
        self.isNSFW = isNSFW
        self.source = source
        self.sourceURL = sourceURL
        self.apple = apple
    }

    var id: String { "\(kind.rawValue):\(sequence ?? 0):\(version ?? 0):\(title)" }

    /// The short label, e.g. "OP1", "ED", "IN2".
    var label: String {
        guard let sequence else { return kind.rawValue }
        return "\(kind.rawValue)\(sequence)"
    }

    /// `label` spelled out for VoiceOver: "Opening 1" / "Vorspann 1", "Ending" / "Abspann",
    /// "Insert song" / "Einlagesong".
    func spokenLabel(german: Bool) -> String {
        let word: String
        switch kind {
        case .opening: word = german ? "Vorspann" : "Opening"
        case .ending: word = german ? "Abspann" : "Ending"
        case .insert: word = german ? "Einlagesong" : "Insert song"
        }
        return sequence.map { "\(word) \($0)" } ?? word
    }

    /// The search text for the listen links ("Title Artist").
    var searchQuery: String {
        [title, artist].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Apple Music search for this song (nothing is stored from the service, spec D11).
    var appleMusicSearchURL: URL? { ThemeListenLinks.appleMusicSearch(searchQuery) }

    /// Spotify search for this song (nothing is stored from the service, spec D11).
    var spotifySearchURL: URL? { ThemeListenLinks.spotifySearch(searchQuery) }

    /// "Open in Apple Music": the matched track when one is stored, otherwise the search.
    var appleMusicURL: URL? { apple?.musicURL ?? appleMusicSearchURL }

    /// Apple's 30-second preview stream (▶ in the page), when the match carries one.
    var previewURL: URL? { apple?.previewURL }
}

/// A verified iTunes Search match of one theme song (owner item 7). Every URL is on Apple's own
/// hosts (checked by the server and again here); a confidence under 0.8 is never a match.
nonisolated struct AppleSongMatch: Hashable, Sendable {
    let trackId: Int
    /// 600×600 artwork on *.mzstatic.com, or nil.
    let artworkURL: URL?
    /// 30-second AAC preview (audio-ssl.itunes.apple.com / *.mzstatic.com), or nil.
    let previewURL: URL?
    /// The track on music.apple.com.
    let musicURL: URL
    let confidence: Double

    static let minimumConfidence = 0.8

    init?(trackId: Int?, artwork: String?, preview: String?, music: String?, confidence: Double?) {
        guard let trackId, trackId > 0, let confidence, confidence >= Self.minimumConfidence,
              let musicURL = Self.url(music, hosts: Self.musicHosts) else { return nil }
        self.trackId = trackId
        self.artworkURL = Self.url(artwork, hosts: [], suffix: ".mzstatic.com")
        self.previewURL = Self.url(preview, hosts: ["audio-ssl.itunes.apple.com"], suffix: ".mzstatic.com")
        self.musicURL = musicURL
        self.confidence = min(1, confidence)
    }

    static let musicHosts: Set<String> = ["music.apple.com", "itunes.apple.com"]

    /// An https URL on one of `hosts` (or any subdomain ending in `suffix`), no credentials, port 443.
    static func url(_ text: String?, hosts: Set<String>, suffix: String? = nil) -> URL? {
        guard let text, text.count <= 2048, let url = URL(string: text),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased() else { return nil }
        if hosts.contains(host) { return url }
        if let suffix, host.hasSuffix(suffix), host.count > suffix.count,
           host.dropLast(suffix.count).allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            return url
        }
        return nil
    }
}

extension ThemeSong: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, sequence, title, artist, episodes, version
        case isSpoiler = "is_spoiler"
        case isNSFW = "is_nsfw"
        case source
        case sourceURL = "source_url"
        case appleTrackId = "apple_track_id"
        case appleArtworkURL = "apple_artwork_url"
        case applePreviewURL = "apple_preview_url"
        case appleMusicURL = "apple_music_url"
        case appleMatchConfidence = "apple_match_confidence"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kindText = try c.decode(String.self, forKey: .kind).uppercased()
        guard let kind = ThemeSongKind(rawValue: kindText) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown theme kind \(kindText)")
        }
        let title = (try c.decodeIfPresent(String.self, forKey: .title))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: c, debugDescription: "theme without a title")
        }
        self.kind = kind
        self.sequence = try? c.decodeIfPresent(Int.self, forKey: .sequence)
        self.title = title
        self.artist = try c.decodeIfPresent(String.self, forKey: .artist)
        self.episodes = try c.decodeIfPresent(String.self, forKey: .episodes)
        self.version = try? c.decodeIfPresent(Int.self, forKey: .version)
        self.isSpoiler = (try c.decodeIfPresent(Bool.self, forKey: .isSpoiler)) ?? false
        self.isNSFW = (try c.decodeIfPresent(Bool.self, forKey: .isNSFW)) ?? false
        self.source = (try c.decodeIfPresent(String.self, forKey: .source)) ?? "animethemes"
        self.sourceURL = (try c.decodeIfPresent(String.self, forKey: .sourceURL)).flatMap(ReleaseScheduleItem.httpsURL)
        // Trailing Apple columns (20261103100200): optional, and an unreadable value is no match
        // (never a decode failure that would drop the song).
        self.apple = AppleSongMatch(
            trackId: try? c.decodeIfPresent(Int.self, forKey: .appleTrackId),
            artwork: try? c.decodeIfPresent(String.self, forKey: .appleArtworkURL),
            preview: try? c.decodeIfPresent(String.self, forKey: .applePreviewURL),
            music: try? c.decodeIfPresent(String.self, forKey: .appleMusicURL),
            confidence: try? c.decodeIfPresent(Double.self, forKey: .appleMatchConfidence))
    }
}

/// On-device search links for a song (spec D11: search URLs only).
nonisolated enum ThemeListenLinks {
    static func appleMusicSearch(_ query: String) -> URL? {
        guard let term = encoded(query) else { return nil }
        return URL(string: "https://music.apple.com/search?term=\(term)")
    }

    static func spotifySearch(_ query: String) -> URL? {
        guard let term = encoded(query) else { return nil }
        return URL(string: "https://open.spotify.com/search/\(term)")
    }

    /// Percent-encoded for both a query value and a path segment; nil for an empty query.
    private static func encoded(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
    }
}

// MARK: - Lenient row decoding

/// Decodes a JSON array element by element; rows that fail to decode are skipped, so one bad row
/// never blanks a section. Fails only when the payload is not an array at all.
nonisolated struct LenientRows<Row: Decodable>: Decodable {
    let rows: [Row]
    /// How many elements could not be decoded.
    let skipped: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var rows: [Row] = []
        var skipped = 0
        while !container.isAtEnd {
            if let row = try? container.decode(Row.self) {
                rows.append(row)
            } else {
                skipped += 1
                // Advance past the undecodable element.
                _ = try? container.decode(DiscardedElement.self)
            }
        }
        self.rows = rows
        self.skipped = skipped
    }

    private struct DiscardedElement: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

extension LenientRows: Sendable where Row: Sendable {}
