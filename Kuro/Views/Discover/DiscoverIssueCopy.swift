import Foundation
import KuroCore
import KuroLibrary

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
            // Non-breaking spaces keep "Ep. 7 at 21:30" one unit, so the time never wraps alone.
            if let episode = next.1.episode, episode > 0 {
                return german ? "Als Nächstes: \(next.0) · Folge\u{00A0}\(episode)\u{00A0}um\u{00A0}\(time)"
                              : "Next: \(next.0) · Ep.\u{00A0}\(episode)\u{00A0}at\u{00A0}\(time)"
            }
            return german ? "Als Nächstes: \(next.0)\u{00A0}um\u{00A0}\(time)" : "Next: \(next.0)\u{00A0}at\u{00A0}\(time)"
        }
        if let last = timed.max(by: { $0.1.airingAt < $1.1.airingAt }) {
            if let episode = last.1.episode, episode > 0 {
                return german ? "Zuletzt: \(last.0) · Folge\u{00A0}\(episode)" : "Last: \(last.0) · Ep.\u{00A0}\(episode)"
            }
            return german ? "Zuletzt: \(last.0)" : "Last: \(last.0)"
        }
        let names = entries.prefix(2).map(\.title)
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    // MARK: Contents and Browse (usability spec §5.10)

    /// "In this issue · 6 sections" / "In dieser Ausgabe · 6 Rubriken" (the view sets it in capitals).
    static func contentsEyebrow(sections: Int, german: Bool) -> String {
        if german { return "In dieser Ausgabe · \(sections) \(sections == 1 ? "Rubrik" : "Rubriken")" }
        return "In this issue · \(sections) \(sections == 1 ? "section" : "sections")"
    }

    /// "Tap to jump" / "Tippen zum Springen" (the trailing eyebrow).
    static func contentsTapToJump(german: Bool) -> String { german ? "Tippen zum Springen" : "Tap to jump" }

    /// "{n} new" / "{n} neu" in place of a contents entry's count.
    static func contentsNew(_ count: Int, german: Bool) -> String { german ? "\(count) neu" : "\(count) new" }

    /// "Jump to New to you, 8 titles" / "Zu Neu für dich springen, 8 Titel".
    static func contentsSpoken(name: String, count: Int, german: Bool) -> String {
        german ? "Zu \(name) springen, \(count) Titel" : "Jump to \(name), \(count) \(count == 1 ? "title" : "titles")"
    }

    /// The Browse link row: kicker "Everything" / "Alles" (new) and the shipped title.
    static func browseKicker(german: Bool) -> String { german ? "Alles" : "Everything" }
    static func browseTitle(german: Bool) -> String { german ? "Den Katalog durchstöbern" : "Browse the catalogue" }

    // MARK: Header (§5.10)

    /// The header title's VoiceOver label while Discover is the page.
    static func headerScrollToTop(german: Bool) -> String { german ? "Entdecken. Nach oben" : "Discover. Scroll to top" }

    // MARK: Section purposes (R1, §8)

    static func purposeNewToYou(german: Bool) -> String {
        german ? "Serien, die du noch nicht kennst. Jeden Morgen neu." : "Series you haven't seen. A new set each morning."
    }

    static func purposeBecauseYou(german: Bool) -> String {
        german ? "Ausgewählt nach dem, was du am meisten mochtest." : "Picked from what you loved most."
    }

    /// "Airing now. 3 new episodes out today." when today's rail holds titles, else the season line.
    static func purposeSeason(airingToday: Int, german: Bool) -> String {
        if airingToday > 0 {
            if german { return "Läuft gerade. Heute \(airingToday) \(airingToday == 1 ? "neue Folge" : "neue Folgen")." }
            return "Airing now. \(airingToday) new \(airingToday == 1 ? "episode" : "episodes") out today."
        }
        return german ? "Was diese Season läuft." : "What's airing this season."
    }

    static func purposeEssentials(count: Int, manga: Bool, german: Bool) -> String {
        switch (manga, german) {
        case (false, false): return "\(count) titles to know anime by. Our order, not a ranking."
        case (false, true): return "\(count) Titel, an denen man Anime kennt. Unsere Reihenfolge, kein Ranking."
        case (true, false): return "\(count) manga to know the medium by. Our order, not a ranking."
        case (true, true): return "\(count) Manga, an denen man das Medium kennt. Unsere Reihenfolge, kein Ranking."
        }
    }

    static func purposeMangaNewToYou(german: Bool) -> String {
        german ? "Manga, die du noch nicht kennst. Jeden Morgen neu." : "Manga you haven't read. A new set each morning."
    }

    /// D15: the source is AniList's trending value, never Kuro activity.
    static func purposeTrending(manga: Bool, german: Bool) -> String {
        switch (manga, german) {
        case (false, false): return "What anime fans are watching right now."
        case (false, true): return "Was Anime-Fans gerade schauen."
        case (true, false): return "What manga readers are reading right now."
        case (true, true): return "Was Manga-Fans gerade lesen."
        }
    }

    static func purposeClassics(manga: Bool, german: Bool) -> String {
        switch (manga, german) {
        case (false, false): return "Older series still worth an evening."
        case (false, true): return "Ältere Serien, die einen Abend wert sind."
        case (true, false): return "Older manga still worth a read."
        case (true, true): return "Ältere Manga, die sich noch lohnen."
        }
    }

    static func purposeTonightShelf(german: Bool) -> String {
        german ? "Eine Stimmung für heute Abend, nach deinem Geschmack." : "One mood for tonight, picked from your taste."
    }

    static func purposeHiddenGem(german: Bool) -> String {
        german ? "Ein Titel, den die meisten übersehen." : "One title most people miss."
    }

    // MARK: Why it's here (§8; the preview's foot, lane B)

    enum Reason: Equatable, Sendable { case unseen, canon, airing, popular, classic, closeTo(String) }

    static func reason(_ reason: Reason, german: Bool) -> String {
        let word: String
        switch (reason, german) {
        case (.unseen, false): word = "unseen by you"
        case (.unseen, true): word = "noch nicht gesehen"
        case (.canon, false): word = "in our canon"
        case (.canon, true): word = "in unserem Kanon"
        case (.airing, false): word = "airing now"
        case (.airing, true): word = "läuft gerade"
        case (.popular, false): word = "popular this week"
        case (.popular, true): word = "diese Woche beliebt"
        case (.classic, false): word = "a classic"
        case (.classic, true): word = "ein Klassiker"
        case (.closeTo(let title), false): word = "close to \(title)"
        case (.closeTo(let title), true): word = "nah an \(title)"
        }
        return german ? "Warum es hier ist: \(word)." : "Why it's here: \(word)."
    }

    // MARK: NEW markers (§5.8)

    /// The card tab: "NEW" / "NEU".
    static func newTab(german: Bool) -> String { german ? "NEU" : "NEW" }

    /// The heading marker: "3 new since Tue" / "3 neu seit Di"; over six days: "… since your last visit".
    static func newSince(_ count: Int, lastVisit: Date, now: Date, german: Bool, timeZone: TimeZone = berlin) -> String {
        let days = now.timeIntervalSince(lastVisit) / 86_400
        if days > 6 {
            return german ? "\(count) neu seit deinem letzten Besuch" : "\(count) new since your last visit"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: german ? "de_DE" : "en_GB")
        let weekday = calendar.component(.weekday, from: lastVisit)
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let name = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1].replacingOccurrences(of: ".", with: "") : ""
        return german ? "\(count) neu seit \(name)" : "\(count) new since \(name)"
    }

    // MARK: Trending refinement (D10)

    /// The refine words: "Any length · Up to 13 episodes · Over 50 episodes · Finished" (DE "Jede Länge ·
    /// Bis 13 Folgen · Über 50 Folgen · Fertig erschienen"). `DiscoverRailFilter`'s own labels stay for
    /// its other users.
    static func refineWord(_ filter: DiscoverRailFilter, german: Bool) -> String {
        switch (filter, german) {
        case (.all, false): return "Any length"
        case (.all, true): return "Jede Länge"
        case (.short, false): return "Up to 13 episodes"
        case (.short, true): return "Bis 13 Folgen"
        case (.long, false): return "Over 50 episodes"
        case (.long, true): return "Über 50 Folgen"
        case (.finished, false): return "Finished"
        case (.finished, true): return "Fertig erschienen"
        }
    }

    // MARK: Kind kicker (§5.11)

    /// "ANIME" / "MANGA" (identical in German).
    static func kindKicker(_ kind: MediaKind) -> String { kind == .manga ? "MANGA" : "ANIME" }

    /// VoiceOver prefix on All: "Anime: Frieren".
    static func kindSpoken(_ kind: MediaKind, title: String) -> String { "\(kind == .manga ? "Manga" : "Anime"): \(title)" }

    // MARK: Status word (R2, mark sections)

    /// The owned title's word on an index row's meta line: "Watching · Ep. 5" / "Schaue ich · F. 5",
    /// "Completed" / "Abgeschlossen" (the Folio words and unit abbreviations, EXISTING).
    @MainActor
    static func statusWord(_ status: ListStatus, progress: Int, kind: MediaKind, german: Bool) -> String {
        let word = FolioStatus(listStatus: status).title(medium: kind, german: german)
        guard status == .current || status == .repeating, progress > 0 else { return word }
        return "\(word) · \(FolioPolicy.unitShort(kind, german: german)) \(progress)"
    }

    // MARK: Progress hook (§5.9)

    static func progressHead(seen: Int, of total: Int, manga: Bool, german: Bool) -> String {
        switch (manga, german) {
        case (false, false): return "You've seen \(seen) of \(total)."
        case (false, true): return "\(seen) von \(total) gesehen."
        case (true, false): return "You've read \(seen) of \(total)."
        case (true, true): return "\(seen) von \(total) gelesen."
        }
    }

    static func progressUnderWay(_ title: String, german: Bool) -> String {
        german ? "\(title) läuft gerade." : "\(title) is under way."
    }

    static func progressToGo(_ remaining: Int, german: Bool) -> String {
        german ? "Noch \(remaining)." : "\(remaining) to go."
    }

    /// "You've seen 3 of 8 essential anime" (VoiceOver).
    static func progressSpoken(seen: Int, of total: Int, manga: Bool, german: Bool) -> String {
        switch (manga, german) {
        case (false, false): return "You've seen \(seen) of \(total) essential anime"
        case (false, true): return "\(seen) von \(total) unverzichtbaren Anime gesehen"
        case (true, false): return "You've read \(seen) of \(total) essential manga"
        case (true, true): return "\(seen) von \(total) unverzichtbaren Manga gelesen"
        }
    }

    // MARK: Moods (§5.4)

    static func moodsEyebrow(german: Bool) -> String { german ? "Lust auf" : "In the mood for" }

    @MainActor
    static func moodTitle(_ mood: DiscoverMood, likeTitle: String?, german: Bool) -> String {
        switch (mood, german) {
        case (.short, false): return "Something short"
        case (.short, true): return "Etwas Kurzes"
        case (.cozy, false): return "Cozy"
        case (.cozy, true): return "Gemütlich"
        case (.intense, false): return "Intense"
        case (.intense, true): return "Intensiv"
        case (.likeLastLoved, false): return "Like \(likeTitle ?? "")"
        case (.likeLastLoved, true): return "Wie \(likeTitle ?? "")"
        }
    }

    @MainActor
    static func moodSubtitle(_ mood: DiscoverMood, german: Bool) -> String {
        switch (mood, german) {
        case (.short, false): return "Short and complete"
        case (.short, true): return "Kurz und abgeschlossen"
        case (.cozy, false): return "Slow, warm, gentle"
        case (.cozy, true): return "Ruhig, warm, sanft"
        case (.intense, false): return "Dark and gripping"
        case (.intense, true): return "Düster und packend"
        case (.likeLastLoved, false): return "Because you finished it"
        case (.likeLastLoved, true): return "Weil du es beendet hast"
        }
    }

    @MainActor
    static func moodSymbol(_ mood: DiscoverMood) -> String {
        switch mood {
        case .short: return "timer"
        case .cozy: return "cup.and.saucer"
        case .intense: return "bolt"
        case .likeLastLoved: return "heart"
        }
    }

    // MARK: End (§5.7)

    static func endTitle(german: Bool) -> String { german ? "Für heute bist du durch." : "You're caught up for today." }

    static func endTally(sections: Int, titles: Int, german: Bool) -> String {
        if german { return "\(sections) \(sections == 1 ? "Rubrik" : "Rubriken"), \(titles) Titel." }
        return "\(sections) \(sections == 1 ? "section" : "sections"), \(titles) \(titles == 1 ? "title" : "titles")."
    }

    /// "You planned 2, hid 1 and marked 1 as seen." Only the parts above zero; nil when all are zero.
    static func endActions(planned: Int, hidden: Int, seen: Int, german: Bool) -> String? {
        var parts: [String] = []
        if german {
            if planned > 0 { parts.append("\(planned) vorgemerkt") }
            if hidden > 0 { parts.append("\(hidden) ausgeblendet") }
            if seen > 0 { parts.append("\(seen) als gesehen markiert") }
        } else {
            if planned > 0 { parts.append("planned \(planned)") }
            if hidden > 0 { parts.append("hid \(hidden)") }
            if seen > 0 { parts.append("marked \(seen) as seen") }
        }
        guard !parts.isEmpty else { return nil }
        let joined: String
        if parts.count == 1 {
            joined = parts[0]
        } else {
            joined = parts.dropLast().joined(separator: ", ") + (german ? " und " : " and ") + (parts.last ?? "")
        }
        if german { return joined.prefix(1).uppercased() + joined.dropFirst() + "." }
        return "You " + joined + "."
    }

    static func endTomorrow(german: Bool) -> String { german ? "Morgen früh kommt eine neue Ausgabe." : "A new issue tomorrow morning." }

    static func searchKicker(german: Bool) -> String { german ? "Etwas Bestimmtes" : "Something specific" }
    static func searchTitle(german: Bool) -> String { german ? "Suchen" : "Search" }
    static func moreListsEyebrow(german: Bool) -> String { german ? "Weitere Listen" : "More lists" }

    // MARK: Pinned index (§5.10, §8)

    @MainActor
    static func pinnedWord(_ section: DiscoverIssueSections.Section, german: Bool) -> String {
        switch (section, german) {
        case (.newToYou, false), (.becauseYou, false), (.mangaNewToYou, false): return "New"
        case (.newToYou, true), (.becauseYou, true), (.mangaNewToYou, true): return "Neu"
        case (.currentSeason, _): return "Season"
        case (.essentials, false), (.essentialsManga, false): return "Essentials"
        case (.essentials, true), (.essentialsManga, true): return "Kanon"
        case (.trending, false), (.trendingManga, false): return "Trending"
        case (.trending, true), (.trendingManga, true): return "Im Trend"
        case (.classics, false), (.classicsManga, false): return "Classics"
        case (.classics, true), (.classicsManga, true): return "Klassiker"
        case (.tonightShelf, false): return "Shelf"
        case (.tonightShelf, true): return "Regal"
        case (.hiddenGem, false): return "Gem"
        case (.hiddenGem, true): return "Juwel"
        }
    }

    /// On All, Manga new to you sits beside New to you: its pinned word is "Manga".
    @MainActor
    static func pinnedWord(_ section: DiscoverIssueSections.Section, issue: DiscoverIssueSections.Issue, german: Bool) -> String {
        if section == .mangaNewToYou, issue == .all { return "Manga" }
        return pinnedWord(section, german: german)
    }

    /// The pinned index's VoiceOver label.
    static func pinnedLabel(german: Bool) -> String { german ? "Rubriken" : "Sections" }

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

    // MARK: Fold (retired, D17)

    /// The retired fold's session-memory key (navigation contract F3). The page no longer reads it
    /// (D17); the constants stay for `KuroFoldMemory` callers and the earlier lanes' tests.
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

// MARK: - Contents (pure)

/// The "In this issue" block: the sections drawn on the page, in order, each a numbered jump link
/// with its real count (or "{n} new"). Every drawn section is named (at most six, R7).
nonisolated enum DiscoverContents {
    struct Entry: Equatable, Identifiable {
        /// The section's scroll anchor.
        let id: String
        let name: String
        let count: Int
        var newCount: Int = 0
    }

    /// "01" … the entry's number.
    static func number(_ index: Int) -> String { String(format: "%02d", index + 1) }

    /// The trailing word: "{n} new" when the section has NEW titles, else the count.
    static func trailing(_ entry: Entry, german: Bool) -> String {
        entry.newCount > 0 ? DiscoverIssueCopy.contentsNew(entry.newCount, german: german) : "\(entry.count)"
    }

    /// One column at accessibility sizes or in the compact column; two otherwise.
    static func columns(accessibility: Bool, column: CGFloat) -> Int {
        accessibility || DiscoverIssueLayout.isCompact(column: column) ? 1 : 2
    }

    /// The contents block shows when two or more sections are drawn.
    static func shows(_ entries: [Entry]) -> Bool { entries.count >= 2 }
}
