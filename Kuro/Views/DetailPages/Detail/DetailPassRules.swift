import Foundation
import KuroCore
import KuroLibrary

// MARK: - Detail pass: pure rules and copy (details-songs spec §5.3, §6, §7, §15)
// Everything the new detail parts decide without a view: the hero's facts line, the next-release row's
// words, the bell's eligibility, the timeline's rows and the wrong-season still guard, the cast rail's
// members and More like this's filter. No string here is invented data: a part without a value is
// left out (§5.4). Pinned in KuroTests/DSdetailTests.swift.

// MARK: Facts line (§6.2 item 2, §7.2)

nonisolated enum DetailFacts {
    /// One part of the facts line; the score's value is drawn brighter on the hero.
    struct Part: Equatable, Sendable {
        let text: String
        let isScore: Bool
    }

    /// Year · format · episodes · main studio · score (anime hero). Missing parts are dropped.
    static func anime(year: Int?, format: String?, episodes: Int?, studio: String?, averageScore: Int?,
                      german: Bool, locale: Locale) -> [Part] {
        var parts: [Part] = []
        if let year, year > 0 { parts.append(Part(text: "\(year)", isScore: false)) }
        if let word = animeFormatWord(format, german: german) { parts.append(Part(text: word, isScore: false)) }
        if let episodes, episodes > 0 { parts.append(Part(text: count(episodes, .episode, german: german), isScore: false)) }
        if let studio = studio?.trimmingCharacters(in: .whitespacesAndNewlines), !studio.isEmpty {
            parts.append(Part(text: studio, isScore: false))
        }
        if let score = scoreText(averageScore, german: german, locale: locale) { parts.append(Part(text: score, isScore: true)) }
        return parts
    }

    /// Year · format · status · volumes · chapters (finished only) · score (manga hero).
    static func manga(year: Int?, format: String?, status: String?, volumes: Int?, chapters: Int?,
                      averageScore: Int?, german: Bool, locale: Locale) -> [Part] {
        var parts: [Part] = []
        if let year, year > 0 { parts.append(Part(text: "\(year)", isScore: false)) }
        if let word = mangaFormatWord(format, german: german) { parts.append(Part(text: word, isScore: false)) }
        if let word = mangaStatusWord(status, german: german) { parts.append(Part(text: word, isScore: false)) }
        if let volumes, volumes > 0 { parts.append(Part(text: count(volumes, .volume, german: german), isScore: false)) }
        if status?.uppercased() == "FINISHED", let chapters, chapters > 0 {
            parts.append(Part(text: count(chapters, .chapter, german: german), isScore: false))
        }
        if let score = scoreText(averageScore, german: german, locale: locale) { parts.append(Part(text: score, isScore: true)) }
        return parts
    }

    /// The line as one string (" · "), and VoiceOver's reading (", ").
    static func line(_ parts: [Part]) -> String { parts.map(\.text).joined(separator: " · ") }
    static func spoken(_ parts: [Part]) -> String { parts.map(\.text).joined(separator: ", ") }

    /// "Score 8.6" / "Wertung 8,6" (D4: `averageScore / 10`, one decimal, the locale's separator);
    /// nil when there is no score.
    static func scoreText(_ averageScore: Int?, german: Bool, locale: Locale) -> String? {
        guard let averageScore, averageScore > 0 else { return nil }
        let value = (Double(averageScore) / 10).formatted(.number.precision(.fractionLength(1)).locale(locale))
        return (german ? "Wertung " : "Score ") + value
    }

    /// TV · Film · OVA · ONA · Special · TV short · Music (nil for an unknown format: left out).
    static func animeFormatWord(_ format: String?, german: Bool) -> String? {
        switch format?.uppercased() {
        case "TV": return "TV"
        case "TV_SHORT": return german ? "TV-Kurzserie" : "TV short"
        case "MOVIE": return "Film"
        case "OVA": return "OVA"
        case "ONA": return "ONA"
        case "SPECIAL": return "Special"
        case "MUSIC": return german ? "Musik" : "Music"
        default: return nil
        }
    }

    /// Manga · Light novel · Novel · One-shot (the catalogue row carries no country, so no Manhwa).
    static func mangaFormatWord(_ format: String?, german: Bool) -> String? {
        switch format?.uppercased() {
        case "MANGA": return "Manga"
        case "LIGHT_NOVEL": return german ? "Light Novel" : "Light novel"
        case "NOVEL": return german ? "Roman" : "Novel"
        case "ONE_SHOT": return german ? "One-Shot" : "One-shot"
        case "MANHWA": return "Manhwa"
        case "MANHUA": return "Manhua"
        default: return nil
        }
    }

    /// Ongoing · Finished · On hiatus (nil for anything else).
    static func mangaStatusWord(_ status: String?, german: Bool) -> String? {
        switch status?.uppercased() {
        case "RELEASING": return german ? "Laufend" : "Ongoing"
        case "FINISHED": return german ? "Abgeschlossen" : "Finished"
        case "HIATUS": return german ? "Pausiert" : "On hiatus"
        default: return nil
        }
    }

    enum Unit { case episode, chapter, volume }

    /// "12 episodes" / "1 episode" / "12 Folgen" / "1 Folge"; chapters and volumes alike.
    static func count(_ n: Int, _ unit: Unit, german: Bool) -> String {
        switch unit {
        case .episode: return german ? (n == 1 ? "1 Folge" : "\(n) Folgen") : (n == 1 ? "1 episode" : "\(n) episodes")
        case .chapter: return german ? "\(n) Kapitel" : (n == 1 ? "1 chapter" : "\(n) chapters")
        case .volume: return german ? (n == 1 ? "1 Band" : "\(n) Bände") : (n == 1 ? "1 volume" : "\(n) volumes")
        }
    }

    /// The anime's year: the season year, else the start-date year.
    static func animeYear(seasonYear: Int?, startDateYear: Int?) -> Int? {
        if let seasonYear, seasonYear > 0 { return seasonYear }
        if let startDateYear, startDateYear > 0 { return startDateYear }
        return nil
    }
}

// MARK: Next release (§6.2 item 3, §5.3, §7.3)

nonisolated enum DetailNextRelease {
    /// The hero shows the next row only for a title that is not finished and has a row ahead.
    static func showsRow(status: String?, upcoming: ReleaseScheduleItem?) -> Bool {
        upcoming != nil && status?.uppercased() != "FINISHED"
    }

    /// "NEXT EPISODE" / "NÄCHSTE FOLGE" (chapter, volume and season alike).
    static func kicker(_ kind: ReleaseUnitKind, german: Bool) -> String {
        switch kind {
        case .episode: return german ? "NÄCHSTE FOLGE" : "NEXT EPISODE"
        case .chapter: return german ? "NÄCHSTES KAPITEL" : "NEXT CHAPTER"
        case .volume: return german ? "NÄCHSTER BAND" : "NEXT VOLUME"
        case .season: return german ? "NÄCHSTE STAFFEL" : "NEXT SEASON"
        }
    }

    /// "today" / "tomorrow" / "in 3 days" (`ReleaseCopy.daysFromToday`); nil when unknown or past.
    static func dayCount(_ days: Int?, german: Bool) -> String? {
        guard let days, days >= 0 else { return nil }
        switch days {
        case 0: return german ? "heute" : "today"
        case 1: return german ? "morgen" : "tomorrow"
        default: return german ? "in \(days) Tagen" : "in \(days) days"
        }
    }

    /// The certainty mark's word (§5.3): Confirmed / Announced / Estimate.
    static func markWord(_ basis: ReleaseBasis, german: Bool) -> String {
        switch basis {
        case .confirmed: return german ? "Bestätigt" : "Confirmed"
        case .announced: return german ? "Angekündigt" : "Announced"
        case .estimated: return german ? "Schätzung" : "Estimate"
        }
    }

    /// A row with a date carries a mark; an undated row ("Dates to come.") carries none.
    static func showsMark(_ item: ReleaseScheduleItem) -> Bool {
        item.isDisplayable && item.releaseAt != nil
    }

    /// The row's VoiceOver value: the basis word and the source attribution.
    static func spokenValue(_ item: ReleaseScheduleItem, copy: ReleaseCopy) -> String {
        [showsMark(item) ? markWord(item.basis, german: copy.german) : nil, copy.sourceAttribution(item)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// "Estimates don't send reminders." (the manga glance's caption for an estimate).
    static func estimateNote(german: Bool) -> String {
        german ? "Für Schätzungen gibt es keine Erinnerung." : "Estimates don't send reminders."
    }
}

// MARK: Bell (§6.2, §11.2 D14, §11.4)

nonisolated enum DetailReminderRule {
    /// D14: only an exact, non-estimated time from a confirmed or announced source, more than a minute
    /// ahead. An announced day, a window, an estimate or a past row never shows the bell.
    static func isEligible(_ item: ReleaseScheduleItem, now: Date = Date()) -> Bool {
        guard item.showsTime, item.basis == .confirmed || item.basis == .announced, !item.isPast,
              let at = item.releaseAt else { return false }
        return at.timeIntervalSince(now) > 60
    }

    /// The bell's title must be one the account follows (watching or rewatching): the release
    /// notification plan only covers those titles (`ReleasesStore.plannedReleaseNotifications`), so a
    /// bell on any other title would promise a reminder that never comes.
    static func isFollowed(_ status: ListStatus?) -> Bool {
        status == .current || status == .repeating
    }

    static func showsBell(_ item: ReleaseScheduleItem?, status: ListStatus?, now: Date = Date()) -> Bool {
        guard let item else { return false }
        return isFollowed(status) && isEligible(item, now: now)
    }

    /// VoiceOver: "Remind me when episode 8 airs" / "Reminder on for episode 8".
    static func label(_ item: ReleaseScheduleItem, isOn: Bool, german: Bool) -> String {
        let number = item.wholeUnitNumber
        switch item.unitKind {
        case .episode, .season:
            if let number {
                return isOn ? (german ? "Erinnerung für Folge \(number) an" : "Reminder on for episode \(number)")
                            : (german ? "Erinnere mich, wenn Folge \(number) läuft" : "Remind me when episode \(number) airs")
            }
            return isOn ? (german ? "Erinnerung für die nächste Folge an" : "Reminder on for the next episode")
                        : (german ? "Erinnere mich, wenn die nächste Folge läuft" : "Remind me when the next episode airs")
        case .chapter:
            if let number {
                return isOn ? (german ? "Erinnerung für Kapitel \(number) an" : "Reminder on for chapter \(number)")
                            : (german ? "Erinnere mich, wenn Kapitel \(number) erscheint" : "Remind me when chapter \(number) is out")
            }
            return isOn ? (german ? "Erinnerung für das nächste Kapitel an" : "Reminder on for the next chapter")
                        : (german ? "Erinnere mich, wenn das nächste Kapitel erscheint" : "Remind me when the next chapter is out")
        case .volume:
            if let number {
                return isOn ? (german ? "Erinnerung für Band \(number) an" : "Reminder on for volume \(number)")
                            : (german ? "Erinnere mich, wenn Band \(number) erscheint" : "Remind me when volume \(number) is out")
            }
            return isOn ? (german ? "Erinnerung für den nächsten Band an" : "Reminder on for the next volume")
                        : (german ? "Erinnere mich, wenn der nächste Band erscheint" : "Remind me when the next volume is out")
        }
    }

    /// The page toast after a bell tap (§11.4).
    enum Change: Equatable, Sendable { case on, off, denied, failed }

    static func toast(_ change: Change, german: Bool) -> String {
        switch change {
        case .on: return german ? "Erinnerung an. Kuro sagt dir Bescheid, wenn es so weit ist." : "Reminder on. Kuro tells you when it's out."
        case .off: return german ? "Erinnerung aus." : "Reminder off."
        case .denied: return german ? "Mitteilungen für Kuro sind aus. Du kannst sie in den Einstellungen einschalten."
                                    : "Notifications are off for Kuro. Turn them on in Settings."
        case .failed: return german ? "Erinnerung konnte nicht gesetzt werden." : "Couldn't set the reminder."
        }
    }

    static func settings(german: Bool) -> String { german ? "Einstellungen" : "Settings" }
}

// MARK: Season tab (§6.2)

nonisolated enum DetailSeasonTabRule {
    /// The tab shows for a proven chain with two or more numbered seasons, on a numbered season.
    static func tab(chainIsProven: Bool, numbered: [LadderSeason]) -> (number: Int, of: Int)? {
        guard chainIsProven else { return nil }
        let count = numbered.filter { $0.number != nil }.count
        guard count >= 2, let current = numbered.first(where: \.isCurrent)?.number else { return nil }
        return (current, count)
    }

    static func word(german: Bool) -> String { german ? "STAFFEL" : "SEASON" }
    static func of(_ total: Int, german: Bool) -> String { german ? "von \(total)" : "of \(total)" }
    static func spoken(_ number: Int, of total: Int, german: Bool) -> String {
        german ? "Staffel \(number) von \(total). Zeigt alle Staffeln." : "Season \(number) of \(total). Shows all seasons."
    }
}

// MARK: Episode stills guard (§6.4.3, D20)

nonisolated enum EpisodeStillPolicy {
    struct Verdict: Equatable { let showsSourceRows: Bool; let offset: Int }

    /// rows: the loaded `Episode` numbers; total: `anime.episodeCount`; priorEpisodes: the summed episode
    /// counts of the earlier numbered seasons when the ladder carries them (nil otherwise).
    static func verdict(numbers: [Int], total: Int?, priorEpisodes: Int?) -> Verdict {
        let reject = Verdict(showsSourceRows: false, offset: 0)
        guard !numbers.isEmpty else { return Verdict(showsSourceRows: true, offset: 0) }
        guard let total, total > 0 else {
            // 5. Unknown total: accepted when the list starts at 1.
            return (numbers.min() ?? 0) == 1 ? Verdict(showsSourceRows: true, offset: 0) : reject
        }
        // 1. More rows than the title has episodes (JJK S2: 24 rows for 23).
        if Set(numbers).count > total { return reject }
        // 2. Every number inside this season.
        if numbers.allSatisfy({ (1...total).contains($0) }) { return Verdict(showsSourceRows: true, offset: 0) }
        // 3. Absolute numbering after the earlier seasons (Apothecary S1 listed as 25-48).
        if let prior = priorEpisodes, prior > 0, numbers.allSatisfy({ ((prior + 1)...(prior + total)).contains($0) }) {
            return Verdict(showsSourceRows: true, offset: prior)
        }
        // 4. Anything else.
        return reject
    }
}

// MARK: Timeline (§6.4)

nonisolated enum DetailTimeline {
    /// Watched runs of three or more: the rows before the last two watched rows fold into one line.
    static func watchedRun(progress: Int, isTracked: Bool) -> ClosedRange<Int>? {
        guard isTracked, progress >= 3 else { return nil }
        return 1...(progress - 2)
    }

    /// The plain rows of the collapsed timeline (Up next is drawn as its own card, the watched run as
    /// its fold line). Tracked: the last two watched episodes, then the first loaded episode after Up
    /// next. Untracked: the first three loaded episodes.
    static func collapsedRows(progress: Int, isTracked: Bool, upNext: Int?, loaded: [Int]) -> [Int] {
        let sorted = Array(Set(loaded)).sorted()
        guard isTracked else { return Array(sorted.prefix(3)) }
        var rows: [Int] = progress >= 1 ? Array(max(1, progress - 1)...progress) : []
        let after = upNext ?? progress
        if let later = sorted.first(where: { $0 > after && $0 != upNext }) { rows.append(later) }
        return rows
    }

    /// The expanded timeline's plain rows: every loaded episode except Up next.
    static func expandedRows(loaded: [Int], upNext: Int?) -> [Int] {
        Array(Set(loaded)).sorted().filter { $0 != upNext }
    }

    /// Future rows from the schedule (at most three), never repeating a number already drawn.
    static func futureRows(_ upcoming: [ReleaseScheduleItem], drawn: Set<Int>, limit: Int = 3) -> [ReleaseScheduleItem] {
        Array(upcoming.filter { item in
            guard item.unitKind == .episode || item.unitKind == .chapter else { return false }
            guard let number = item.wholeUnitNumber else { return true }
            return !drawn.contains(number)
        }.prefix(limit))
    }

    /// A row is watched when its number is within the Library's progress.
    static func isWatched(_ number: Int, progress: Int, isTracked: Bool) -> Bool {
        isTracked && number >= 1 && number <= progress
    }

    /// "Episode 7" / "Folge 7" / "Ep. 7" titles say nothing new: they are left out.
    static func isGenericTitle(_ title: String?) -> Bool {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return true }
        return trimmed.range(of: #"^(Episode|Folge|Ep\.?)\s*\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func shownTitle(_ title: String?) -> String? {
        isGenericTitle(title) ? nil : title?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The heading's note: "6 of 23 watched" (tracked, known total), else "23 episodes".
    static func note(progress: Int, total: Int?, isTracked: Bool, german: Bool) -> String? {
        if isTracked, let total, total > 0 {
            return german ? "\(min(progress, total)) von \(total) gesehen" : "\(min(progress, total)) of \(total) watched"
        }
        guard let total, total > 0 else { return nil }
        return DetailFacts.count(total, .episode, german: german)
    }

    /// The small line above a row's title: "Ep. 5 · watched" / "F. 5 · gesehen" (manga: "Ch. 5 · read").
    static func smallLine(_ number: Int, watched: Bool, manga: Bool = false, german: Bool) -> String {
        let unit = manga ? (german ? "Kap. \(number)" : "Ch. \(number)") : (german ? "F. \(number)" : "Ep. \(number)")
        guard watched else { return unit }
        return unit + (manga ? (german ? " · gelesen" : " · read") : (german ? " · gesehen" : " · watched"))
    }

    /// The watched run's line: "Episodes 1–4 · watched" / "Folgen 1–4 · gesehen".
    static func runLine(_ run: ClosedRange<Int>, manga: Bool = false, german: Bool) -> String {
        let span = run.lowerBound == run.upperBound ? "\(run.lowerBound)" : "\(run.lowerBound)–\(run.upperBound)"
        if manga { return german ? "Kapitel \(span) · gelesen" : "Chapters \(span) · read" }
        return german ? "Folgen \(span) · gesehen" : "Episodes \(span) · watched"
    }

    static func show(german: Bool) -> String { german ? "Zeigen" : "Show" }
    static func hide(german: Bool) -> String { german ? "Ausblenden" : "Hide" }
    static func absoluteNumber(_ number: Int, german: Bool) -> String { german ? "Nr. \(number)" : "No. \(number)" }

    /// One element per row: "Episode 5, Premature Death, Friday 17 October, watched".
    static func spokenRow(number: Int, title: String?, date: String?, watched: Bool, german: Bool) -> String {
        var parts = [german ? "Folge \(number)" : "Episode \(number)"]
        if let title { parts.append(title) }
        if let date { parts.append(date) }
        if watched { parts.append(german ? "gesehen" : "watched") }
        return parts.joined(separator: ", ")
    }

    /// An episode's air day in `ReleaseCopy`'s day style ("Fri 17 Oct" / "Fr. 17. Okt."). A day-only
    /// `airDate` is read as its UTC calendar date (never a day early west of UTC); `airAt` is local.
    static func dayText(airAt: Date?, airDate: Date?, long: Bool, locale: Locale, timeZone: TimeZone) -> String? {
        let template = long ? "EEEEdMMMM" : "EEEdMMM"
        if let airAt {
            return ReleaseFormatterCache.shared.formatter(template, locale: locale, timeZone: timeZone).string(from: airAt)
        }
        guard let airDate else { return nil }
        let utc = TimeZone(identifier: "UTC") ?? timeZone
        return ReleaseFormatterCache.shared.formatter(template, locale: locale, timeZone: utc).string(from: airDate)
    }
}

// MARK: Cast rail (§6.7, D8)

nonisolated enum DetailCastRule {
    static let cap = 25

    /// MAIN and SUPPORTING first, in source order, at most 25; BACKGROUND only when neither exists, so
    /// the rail is populated whenever the catalogue holds characters.
    static func shown<T>(_ members: [T], role: (T) -> String) -> [T] {
        func rank(_ value: String) -> Int {
            switch value.uppercased() { case "MAIN": return 0; case "SUPPORTING": return 1; default: return 2 }
        }
        let ordered = members.enumerated().sorted { lhs, rhs in
            let l = rank(role(lhs.element)), r = rank(role(rhs.element))
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
        let leading = ordered.filter { rank(role($0)) < 2 }
        return Array((leading.isEmpty ? ordered : leading).prefix(cap))
    }

    /// "Main" / "Hauptrolle", "Supporting" / "Nebenrolle", "Background" / "Nebenfigur".
    static func roleWord(_ role: String, german: Bool) -> String? {
        switch role.uppercased() {
        case "MAIN": return german ? "Hauptrolle" : "Main"
        case "SUPPORTING": return german ? "Nebenrolle" : "Supporting"
        case "BACKGROUND": return german ? "Nebenfigur" : "Background"
        default: return nil
        }
    }

    /// The heading's note: "Japanese cast" when any card names a voice actor, else the count.
    static func note(count: Int, hasVoices: Bool, german: Bool) -> String {
        if hasVoices { return german ? "Japanische Besetzung" : "Japanese cast" }
        if german { return count == 1 ? "1 Figur" : "\(count) Figuren" }
        return count == 1 ? "1 character" : "\(count) characters"
    }

    static func spokenCard(name: String, role: String?) -> String {
        [name, role].compactMap { $0 }.joined(separator: ", ")
    }

    static func spokenVoice(name: String, character: String, german: Bool) -> String {
        german ? "\(name), Stimme von \(character)" : "\(name), voice of \(character)"
    }
}

// MARK: More like this (§6.8, §7.6, D7)

nonisolated enum DetailMoreLikeThisRule {
    /// Drops the page's own ladder titles (numbered seasons, extras, the source) and the title itself.
    static func filtered<T>(_ items: [T], key: (T) -> MediaKey, excluding: Set<MediaKey>) -> [T] {
        var seen = Set<MediaKey>()
        return items.filter { item in
            let k = key(item)
            return !excluding.contains(k) && seen.insert(k).inserted
        }
    }

    static func heading(german: Bool) -> String { german ? "Mehr davon." : "More like this." }
    static func note(german: Bool) -> String { german ? "Nach Gemeinsamkeiten mit diesem Titel" : "From what this title shares" }

    /// The card's line: "2019 · TV" (parts without a value are left out).
    static func cardLine(year: String?, format: String?, kind: MediaKind, german: Bool) -> String? {
        let formatWord = kind == .anime ? DetailFacts.animeFormatWord(format, german: german)
                                        : DetailFacts.mangaFormatWord(format, german: german)
        let yearText = year?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [yearText.flatMap { Int($0) != nil ? $0 : nil }, formatWord].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The account's results key (`@State`): another account never sees this one's list-filtered answer.
    static func stateKey(account: String?, kind: MediaKind, id: Int) -> String {
        "\(account?.lowercased() ?? "-")|\(kind.rawValue)|\(id)"
    }
}
