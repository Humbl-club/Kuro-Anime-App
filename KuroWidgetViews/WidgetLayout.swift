import Foundation
import KuroCore
import KuroWidgetSupport
import WidgetKit

// MARK: - Widget layout rules (pure; spec §10.2, §10.3)
// Which rows each family shows, which state a widget is in, the eyebrow word and the small widget's
// unit split. The views in this folder only draw what these functions decide, so `DSwidgetTests`
// pins every rule without rendering.

nonisolated enum WidgetContentState: Equatable {
    /// No snapshot: signed out, first install or a build without the App Group.
    case signedOut
    /// A snapshot with nothing to list ("No dates yet." / "Nothing in progress.").
    case empty
    /// Rows to draw.
    case rows
}

/// What the +1 slot of a Now Watching row shows.
nonisolated enum WidgetKeyPhase: Equatable {
    /// The raised ink key, interactive.
    case advance
    /// A +1 the app has not saved yet: the key at 60 % with the caption, still interactive (the intent
    /// accepts the next target).
    case queued
    /// At the known total: the ghost ✓, no button.
    case caughtUp
}

nonisolated enum WidgetLayout {
    // MARK: Row caps

    /// Up next: small 1, medium 3, large 6.
    static func releaseLimit(_ family: WidgetFamily) -> Int {
        switch family {
        case .systemMedium: return 3
        case .systemLarge, .systemExtraLarge: return 6
        default: return 1
        }
    }

    /// Now watching: small 1, medium 2, large 4.
    static func nowWatchingLimit(_ family: WidgetFamily) -> Int {
        switch family {
        case .systemMedium: return 2
        case .systemLarge, .systemExtraLarge: return 4
        default: return 1
        }
    }

    // MARK: Rows and state

    /// The releases still ahead at `date`, capped for `family`.
    static func releases(_ snapshot: WidgetSnapshot?, at date: Date, family: WidgetFamily) -> [WidgetReleaseItem] {
        Array((snapshot?.releases(at: date) ?? []).prefix(releaseLimit(family)))
    }

    /// The Now Watching rows (queued taps already overlaid by the provider), capped for `family`.
    static func nowWatching(_ snapshot: WidgetSnapshot?, family: WidgetFamily) -> [WidgetNowWatchingItem] {
        Array((snapshot?.nowWatching ?? []).prefix(nowWatchingLimit(family)))
    }

    static func releaseState(_ snapshot: WidgetSnapshot?, at date: Date) -> WidgetContentState {
        guard let snapshot else { return .signedOut }
        return snapshot.releases(at: date).isEmpty ? .empty : .rows
    }

    static func nowWatchingState(_ snapshot: WidgetSnapshot?) -> WidgetContentState {
        guard let snapshot else { return .signedOut }
        return snapshot.nowWatching.isEmpty ? .empty : .rows
    }

    /// The language the widget speaks: the app's when a snapshot exists, else the device's.
    static func german(_ snapshot: WidgetSnapshot?, preferred: Bool = WidgetCopy.preferredGerman()) -> Bool {
        snapshot?.german ?? preferred
    }

    /// The locale the system relative countdown speaks (`ReleaseCopy`'s en_GB / de_DE).
    static func locale(german: Bool) -> Locale {
        Locale(identifier: german ? "de_DE" : "en_GB")
    }

    // MARK: Eyebrows

    /// "NEXT EPISODE" / "NEXT CHAPTER" (a volume says "NEXT VOLUME") when every row is of one kind,
    /// "UP NEXT" when the rows mix kinds or there are none (uppercased by the view).
    static func releaseEyebrow(_ rows: [WidgetReleaseItem], german: Bool) -> String {
        let kinds = Set(rows.map(unitKind))
        guard kinds.count == 1, let kind = kinds.first else { return WidgetCopy.upNext(german) }
        switch kind {
        case .episode: return WidgetCopy.nextEpisode(german)
        case .chapter: return WidgetCopy.nextChapter(german)
        case .volume: return WidgetCopy.nextVolume(german)
        }
    }

    /// Home's kicker: "NOW READING" when every row is manga, else "NOW WATCHING".
    static func nowWatchingEyebrow(_ rows: [WidgetNowWatchingItem], german: Bool) -> String {
        if !rows.isEmpty, rows.allSatisfy({ $0.medium == .manga }) { return WidgetCopy.nowReading(german) }
        return WidgetCopy.nowWatching(german)
    }

    enum ReleaseUnitKind: Hashable { case episode, chapter, volume }

    /// Anime rows are episodes; manga rows are chapters unless `ReleaseCopy` worded a volume.
    static func unitKind(_ item: WidgetReleaseItem) -> ReleaseUnitKind {
        switch item.medium {
        case .anime: return .episode
        case .manga:
            return item.unitLabel.hasPrefix("Vol. ") || item.unitLabel.hasPrefix("Bd. ") ? .volume : .chapter
        }
    }

    // MARK: Small widget readout

    /// `"Ep. 8"` → ("Ep.", "8"); `"Kap. 1197"` → ("Kap.", "1197"); a label without a trailing number
    /// ("Next episode") stays whole with no number.
    static func unitParts(_ unitLabel: String) -> (unit: String, number: String?) {
        let trimmed = unitLabel.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.lastIndex(of: " ") else {
            return trimmed.first?.isNumber == true ? ("", trimmed) : (trimmed, nil)
        }
        let tail = String(trimmed[trimmed.index(after: space)...])
        guard tail.first?.isNumber == true else { return (trimmed, nil) }
        return (String(trimmed[..<space]), tail)
    }

    /// A clock or countdown only for a row the app allowed a time (an instant that is not an
    /// estimate). Belt and braces: an estimate never counts down even if a target slipped through.
    static func countdownTarget(_ item: WidgetReleaseItem) -> Date? {
        item.isEstimate ? nil : item.countdownTarget
    }

    // MARK: Now Watching

    static func keyPhase(_ item: WidgetNowWatchingItem) -> WidgetKeyPhase {
        if item.isCaughtUp { return .caughtUp }
        return item.isQueued ? .queued : .advance
    }

    /// The row's one VoiceOver element: "{title}, episode 6 of 23" (+ caught up / queued caption).
    static func rowLabel(_ item: WidgetNowWatchingItem, german: Bool) -> String {
        WidgetCopy.nowWatchingRowLabel(title: item.title, medium: item.medium, progress: item.progress,
                                       total: item.total, caughtUp: item.isCaughtUp, queued: item.isQueued,
                                       german: german)
    }

    /// The unit a +1 tap marks (the shown position already includes queued taps).
    static func nextUnit(_ item: WidgetNowWatchingItem) -> Int { item.progress + 1 }

    /// "Ep." / "Kap." without the trailing space.
    static func unitPrefix(_ item: WidgetNowWatchingItem) -> String {
        item.unitPrefix.trimmingCharacters(in: .whitespaces)
    }

    /// "Next · Ep. 8 · Fri 6 Nov, 21:30" for a Now Watching row whose title has an upcoming release in
    /// the snapshot; nil otherwise.
    /// `prefixed: false` (the medium family) drops "Up next ·": the row already implies it, and the
    /// date is the line's key information, so it must survive the one-line width.
    static func nextReleaseLine(for item: WidgetNowWatchingItem, in snapshot: WidgetSnapshot?, at date: Date,
                                german: Bool, prefixed: Bool = true) -> String? {
        guard let release = snapshot?.releases(at: date)
            .first(where: { $0.medium == item.medium && $0.mediaId == item.mediaId }) else { return nil }
        return prefixed ? "\(WidgetCopy.nextPrefix(german)) · \(release.line)" : release.line
    }
}
