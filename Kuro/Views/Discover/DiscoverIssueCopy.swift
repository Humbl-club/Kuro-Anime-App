import Foundation
import KuroCore

// MARK: - Discover issue copy (Discover + Clubs redesign §8; EN / DE)
// Every new Discover string lives here, pure, so tests pin it in both languages. Shipped strings are
// reused byte for byte from where they already live (route titles, "Browse the catalogue", "See all",
// "On your list", the Plan key and toast copy, the offline retry). Dates and clock times use
// `Europe/Berlin`, the zone the app's rail days use (`DiscoveryStore.isSameRailDay`).

nonisolated enum DiscoverIssueCopy {
    /// The zone every Discover date and time is read in.
    static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

    // MARK: Opening row

    /// "Today's issue · Tue 3 Nov" / "Heutige Ausgabe · Di 3. Nov" (the view sets it in capitals).
    static func openingKicker(now: Date, german: Bool, timeZone: TimeZone = berlin) -> String {
        "\(german ? "Heutige Ausgabe" : "Today's issue") · \(issueDate(now, german: german, timeZone: timeZone))"
    }

    /// "Edited for you." / "Für dich zusammengestellt."
    static func openingHeadline(german: Bool) -> String {
        german ? "Für dich zusammengestellt." : "Edited for you."
    }

    /// "Tue 3 Nov" / "Di 3. Nov": the weekday and month abbreviations without their full stops
    /// (de_DE writes "Di." and "Nov."), the day as a number.
    static func issueDate(_ date: Date, german: Bool, timeZone: TimeZone = berlin) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let locale = Locale(identifier: german ? "de_DE" : "en_GB")
        calendar.locale = locale
        let parts = calendar.dateComponents([.weekday, .day, .month], from: date)
        let weekdays = calendar.shortStandaloneWeekdaySymbols
        let months = calendar.shortStandaloneMonthSymbols
        let weekday = parts.weekday.flatMap { weekdays.indices.contains($0 - 1) ? weekdays[$0 - 1] : nil } ?? ""
        let month = parts.month.flatMap { months.indices.contains($0 - 1) ? months[$0 - 1] : nil } ?? ""
        let day = parts.day ?? 0
        let wd = weekday.replacingOccurrences(of: ".", with: "")
        let mo = month.replacingOccurrences(of: ".", with: "")
        return german ? "\(wd) \(day). \(mo)" : "\(wd) \(day) \(mo)"
    }

    // MARK: Issue switch

    /// The switch group's VoiceOver label (shipped with the old word row).
    static func switchLabel(german: Bool) -> String { german ? "Anzeigen" : "Show" }

    // MARK: Cover story

    /// The season-tab split of an eyebrow: "Today's pick" → ("Today's", "pick"),
    /// "Tipp des Tages" → ("Tipp", "des Tages"), "Hidden gem" → ("Hidden", "gem"). One word: no small part.
    static func tabParts(_ eyebrow: String) -> (small: String?, large: String) {
        let trimmed = eyebrow.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return (nil, trimmed) }
        let small = String(trimmed[..<space])
        let large = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        return large.isEmpty ? (nil, small) : (small, large)
    }

    /// The Hidden gem's eyebrow (shipped).
    static func hiddenGem(german: Bool) -> String { german ? "Verborgenes Juwel" : "Hidden gem" }

    /// "{n} in your clubs ›" (the shipped frame line plus the chevron).
    static func friendLine(_ count: Int, german: Bool) -> String {
        DiscoverFrameCopy.clubCount(count, german: german) + " ›"
    }

    /// "2016 · Movie", "2016 · TV · 12 eps", "1998 · Manga · 327 ch." Missing parts are skipped;
    /// nil when nothing is known. `length` false: year and format only (the cover story's fact row).
    static func facts(kind: MediaKind, year: String?, formatRaw: String?, episodes: Int?, chapters: Int?,
                      length: Bool, german: Bool) -> String? {
        var parts: [String] = []
        if let digits = year?.filter(\.isNumber), digits.count >= 4 {
            parts.append(String(digits.prefix(4)))
        }
        if let format = formatRaw?.trimmingCharacters(in: .whitespaces), !format.isEmpty {
            parts.append(DiscoverFrameCopy.formatName(format, german: german))
        }
        if length {
            if kind == .anime, let episodes, episodes > 0 {
                parts.append(german ? "\(episodes) \(episodes == 1 ? "Folge" : "Folgen")"
                                    : "\(episodes) \(episodes == 1 ? "ep" : "eps")")
            } else if kind == .manga, let chapters, chapters > 0 {
                parts.append(german ? "\(chapters) Kap." : "\(chapters) ch.")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// VoiceOver for the cover story: "Today's pick: Mushishi. Quiet, strange and kind. 2005, TV."
    static func storySpoken(eyebrow: String, title: String, argument: String?, facts: String?) -> String {
        var line = "\(eyebrow): \(title)."
        if let argument, !argument.isEmpty {
            line += " " + (argument.hasSuffix(".") ? argument : argument + ".")
        }
        if let facts, !facts.isEmpty {
            line += " " + facts.replacingOccurrences(of: " · ", with: ", ") + "."
        }
        return line
    }

    /// VoiceOver for a section feature (no eyebrow): "Mob Psycho 100. 2016, TV, 12 eps."
    static func featureSpoken(title: String, facts: String?) -> String {
        guard let facts, !facts.isEmpty else { return "\(title)." }
        return "\(title). " + facts.replacingOccurrences(of: " · ", with: ", ") + "."
    }

    // MARK: Airing today glance

    /// "Airing today" / "Läuft heute" (the shipped route title).
    static func glanceTitle(german: Bool) -> String { german ? "Läuft heute" : "Airing today" }

    /// "today" / "heute" under the count.
    static func glanceCountLabel(german: Bool) -> String { german ? "heute" : "today" }

    /// A clock time in Berlin, 24 h ("21:30").
    static func clock(_ date: Date, timeZone: TimeZone = berlin) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// One title on today's rail with its stated slot (if any).
    struct AiringEntry: Equatable {
        let title: String
        let slot: DiscoverAiringSlot?

        static func == (lhs: AiringEntry, rhs: AiringEntry) -> Bool {
            lhs.title == rhs.title && lhs.slot?.airingAt == rhs.slot?.airingAt && lhs.slot?.episode == rhs.slot?.episode
        }
    }

    /// The glance caption: the earliest stated slot still ahead ("Next: Mob Psycho 100 · Ep. 7 at
    /// 21:30"), else the latest one that has passed ("Last: Mob Psycho 100 · Ep. 7"), else the first
    /// two titles on the rail (nothing is stated, so no time is invented). Nil for an empty rail.
    static func glanceCaption(_ entries: [AiringEntry], now: Date, german: Bool, timeZone: TimeZone = berlin) -> String? {
        let timed = entries.compactMap { entry in entry.slot.map { (entry.title, $0) } }
        if let next = timed.filter({ $0.1.airingAt > now }).min(by: { $0.1.airingAt < $1.1.airingAt }) {
            let time = clock(next.1.airingAt, timeZone: timeZone)
            if let episode = next.1.episode, episode > 0 {
                return german ? "Als Nächstes: \(next.0) · Folge \(episode) um \(time)"
                              : "Next: \(next.0) · Ep. \(episode) at \(time)"
            }
            return german ? "Als Nächstes: \(next.0) um \(time)" : "Next: \(next.0) at \(time)"
        }
        if let last = timed.max(by: { $0.1.airingAt < $1.1.airingAt }) {
            if let episode = last.1.episode, episode > 0 {
                return german ? "Zuletzt: \(last.0) · Folge \(episode)" : "Last: \(last.0) · Ep. \(episode)"
            }
            return german ? "Zuletzt: \(last.0)" : "Last: \(last.0)"
        }
        let names = entries.prefix(2).map(\.title)
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    // MARK: Contents and Browse

    static func contentsEyebrow(german: Bool) -> String { german ? "In dieser Ausgabe" : "In this issue" }
    static func contentsMore(_ count: Int, german: Bool) -> String { german ? "+\(count) weitere" : "+\(count) more" }
    /// "New to you, 8 titles" (a contents entry for VoiceOver).
    static func contentsSpoken(name: String, count: Int, german: Bool) -> String {
        german ? "\(name), \(count) Titel" : "\(name), \(count) \(count == 1 ? "title" : "titles")"
    }

    /// The Browse link row: kicker "Everything" / "Alles" (new) and the shipped title.
    static func browseKicker(german: Bool) -> String { german ? "Alles" : "Everything" }
    static func browseTitle(german: Bool) -> String { german ? "Den Katalog durchstöbern" : "Browse the catalogue" }

    // MARK: Section summaries

    static func newToYouSummary(german: Bool) -> String { german ? "Noch nicht gesehen · täglich neu" : "Unseen by you · changes daily" }
    static func becauseYouSummary(german: Bool) -> String { german ? "Aus deinen Favoriten" : "From your favourites" }
    static func canonSummary(german: Bool) -> String { german ? "Der Kanon, in unserer Reihenfolge" : "The canon, in our order" }
    static func trendingSummary(german: Bool) -> String { german ? "Diese Woche auf Kuro" : "This week on Kuro" }

    /// A section heading with the editorial full stop ("New to you.").
    static func heading(_ title: String) -> String { title.hasSuffix(".") ? title : title + "." }

    // MARK: Marks, See all, index

    /// The tracked mark under a trio title (shipped words).
    static func onYourList(german: Bool) -> String { german ? "Auf deiner Liste" : "On your list" }

    /// "See all 8 ›" / "Alle 8 ansehen ›" (shipped "See all" / "Alle ansehen" with the count).
    static func seeAll(_ count: Int, german: Bool) -> String { german ? "Alle \(count) ansehen ›" : "See all \(count) ›" }
    /// VoiceOver for the same action (begins with "See all", which the UI tests look for).
    static func seeAllSpoken(_ count: Int, section: String, german: Bool) -> String {
        german ? "Alle \(count) ansehen, \(section)" : "See all \(count), \(section)"
    }

    /// The index number, "01".
    static func indexNumber(_ position: Int) -> String { String(format: "%02d", position) }
    /// "Number 1 in our order" / "Nummer 1 in unserer Reihenfolge": the curated order, never a rank.
    static func indexSpoken(_ position: Int, german: Bool) -> String {
        german ? "Nummer \(position) in unserer Reihenfolge" : "Number \(position) in our order"
    }

    /// The local refinement's group label.
    static func refineLabel(german: Bool) -> String { german ? "Diese Leiste eingrenzen" : "Refine this rail" }

    // MARK: Fold

    /// "Show 4 more sections" / "4 weitere Bereiche zeigen".
    static func foldShow(_ count: Int, german: Bool) -> String {
        if german { return count == 1 ? "1 weiteren Bereich zeigen" : "\(count) weitere Bereiche zeigen" }
        return count == 1 ? "Show 1 more section" : "Show \(count) more sections"
    }

    /// "Show fewer" / "Weniger zeigen" (shipped).
    static func foldFewer(german: Bool) -> String { german ? "Weniger zeigen" : "Show fewer" }

    /// The fold's trailing names: "Classics, Top rated +2 ⌄" (the first two names, then the rest).
    static func foldTrailing(names: [String], expanded: Bool) -> String {
        let shown = names.prefix(2).joined(separator: ", ")
        let rest = names.count - min(2, names.count)
        let mark = expanded ? "⌃" : "⌄"
        if shown.isEmpty { return mark }
        return rest > 0 ? "\(shown) +\(rest) \(mark)" : "\(shown) \(mark)"
    }

    /// The fold's session memory (navigation contract F3): page "discover", section "more".
    static let foldPage = "discover"
    static let foldSection = "more"

    // MARK: States

    /// The offline band over earlier content: the bold lead and the rest.
    static func offlineLead(german: Bool) -> String { german ? "Du bist offline." : "You're offline." }
    static func offlineRest(german: Bool) -> String {
        german ? "Du siehst die zuletzt geladene Ausgabe." : "Showing the last issue you loaded."
    }
    /// "Try again →" (the shipped retry words with the arrow of the ink-rule action).
    static func retry(german: Bool) -> String { KuroBrandedCopy.retryTitle(german: german) }

    /// The empty page: "Nothing to show yet." and the line that names only what is on screen.
    static func emptyTitle(german: Bool) -> String { german ? "Noch nichts zu zeigen." : "Nothing to show yet." }
    static func emptyMessage(browseOffered: Bool, german: Bool) -> String {
        if browseOffered {
            return german ? "Zieh zum Aktualisieren, oder durchstöbere den Katalog." : "Pull to refresh, or browse the catalogue."
        }
        return german ? "Zum Aktualisieren ziehen." : "Pull to refresh."
    }
}

// MARK: - Contents line (pure)

/// The "In this issue" line: the sections drawn on the page, in order, with their real counts.
nonisolated enum DiscoverContents {
    struct Entry: Equatable, Identifiable {
        /// The section's scroll anchor.
        let id: String
        let name: String
        let count: Int
    }

    struct Line: Equatable {
        let names: [Entry]
        /// "+n more": hidden page sections plus the folded ones; nil when nothing is left out.
        let more: Int?
        /// Where "+n more" scrolls: the first section not named, or the fold.
        let moreTarget: String?
    }

    /// The fold's scroll anchor.
    static let foldAnchor = "discover.fold"

    /// Nil when fewer than two sections are drawn (the line is omitted; Browse may still show).
    static func line(page: [Entry], folded: Int, limit: Int = DiscoverIssueLayout.contentsNames) -> Line? {
        guard page.count >= 2 else { return nil }
        let names = Array(page.prefix(limit))
        let hidden = page.count - names.count
        let more = hidden + folded
        let target: String? = hidden > 0 ? page[names.count].id : (folded > 0 ? foldAnchor : nil)
        return Line(names: names, more: more > 0 ? more : nil, moreTarget: target)
    }
}
