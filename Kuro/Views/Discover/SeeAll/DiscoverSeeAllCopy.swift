import Foundation
import KuroCore

// MARK: - See all and mood journeys: copy (EN / DE; spec 2026-11-04 §5.4, §5.5, §8)
// EXISTING: "Gerade beliebt", "Neu hinzugefügt" (Browse sort words). Every other string is new here.

enum DiscoverSeeAllCopy {
    static func sortLabel(german: Bool) -> String { german ? "Sortieren" : "Sort" }

    static func sortWord(_ word: DiscoverSeeAllSortWord, german: Bool) -> String {
        switch word {
        case .ownOrder(.curated): return german ? "Unsere Reihenfolge" : "Our order"
        case .ownOrder(.personal): return german ? "Für dich" : "For you"
        case .ownOrder(.airing): return german ? "Als Nächstes" : "Next to air"
        case .popular: return german ? "Am beliebtesten" : "Popular"
        case .newest: return german ? "Neueste" : "Newest"
        case .topRated: return german ? "Bestbewertet" : "Top rated"
        case .trending: return german ? "Gerade beliebt" : "Trending"
        case .justAdded: return german ? "Neu hinzugefügt" : "Just added"
        }
    }

    static func chip(_ chip: DiscoverSeeAllChip, medium: MediaKind, german: Bool) -> String {
        switch chip {
        case .tv: return "TV"
        case .film: return "Film"
        case .upTo13: return german ? "Bis 13 Folgen" : "Up to 13 episodes"
        case .over50: return german ? "Über 50 Folgen" : "Over 50 episodes"
        case .finished: return german ? "Fertig erschienen" : "Finished"
        case .releasing:
            if medium == .manga { return german ? "Erscheint noch" : "Ongoing" }
            return german ? "Läuft" : "Airing"
        case .hideMyList: return german ? "Meine Liste ausblenden" : "Hide my list"
        }
    }

    static func filtersLabel(german: Bool) -> String { german ? "Filter" : "Filters" }

    static func titles(_ count: Int, german: Bool) -> String {
        german ? "\(count) Titel" : (count == 1 ? "1 title" : "\(count) titles")
    }

    static func matches(_ count: Int, german: Bool) -> String {
        german ? "\(count) Treffer" : (count == 1 ? "1 match" : "\(count) match")
    }

    static func clearFilters(german: Bool) -> String { german ? "Filter löschen" : "Clear filters" }

    static func thatsAll(_ count: Int, german: Bool) -> String {
        german ? "Das sind alle \(count)." : "That's all \(count)."
    }

    static func loadingMore(german: Bool) -> String { german ? "Lädt weitere" : "Loading more" }

    static func nothingMatches(german: Bool) -> String {
        german ? "Nichts passt zu diesen Filtern." : "Nothing matches these filters."
    }

    /// NEW (not in §8): the no-filter empty line. "Haven't seen" only where the list hides owned titles.
    static func nothingHere(unseenOnly: Bool, german: Bool) -> String {
        if unseenOnly {
            return german ? "Hier ist gerade nichts, was du noch nicht kennst." : "Nothing here you haven't seen right now."
        }
        return german ? "Hier ist gerade nichts." : "Nothing here right now."
    }

    static func pageFailed(german: Bool) -> String {
        german ? "Weitere konnten nicht geladen werden. Erneut versuchen \u{2192}"
               : "Couldn't load more. Try again \u{2192}"
    }

    /// The section reason the preview names for a See all list (§8 "Why it's here").
    static func reason(_ kind: DiscoverSeeAllSection.OrderKind, section: DiscoverSectionKey,
                       medium: MediaKind = .anime, german: Bool) -> String {
        switch section {
        case .essentials: return DiscoverMenuCopy.Reason.canon.text(german: german)
        case .classics: return DiscoverMenuCopy.Reason.classic.text(german: german)
        case .newToYou, .becauseYou:
            return (medium == .manga ? DiscoverMenuCopy.Reason.unread : .unseen).text(german: german)
        case .currentSeason, .airingToday: return DiscoverMenuCopy.Reason.airing.text(german: german)
        case .trending, .topRated, .newlyAdded: return DiscoverMenuCopy.Reason.popular.text(german: german)
        }
    }
}

// MARK: - Mood journeys

enum DiscoverMoodCopy {
    /// The mood's word (the key's label and the switch row): "Something short", "Cozy", "Intense",
    /// "Like {title}" (without a known title: "Like your favourite").
    static func word(_ mood: DiscoverMood, seedTitle: String?, german: Bool) -> String {
        switch mood {
        case .short: return german ? "Etwas Kurzes" : "Something short"
        case .cozy: return german ? "Gemütlich" : "Cozy"
        case .intense: return german ? "Intensiv" : "Intense"
        case .likeLastLoved:
            if let seedTitle, !seedTitle.isEmpty { return german ? "Wie \(seedTitle)" : "Like \(seedTitle)" }
            return german ? "Wie dein Favorit" : "Like your favourite"
        }
    }

    /// The key's subtitle (manga issue: the same words; the rails differ, not the promise).
    static func subtitle(_ mood: DiscoverMood, german: Bool) -> String {
        switch mood {
        case .short: return german ? "Für einen Abend oder ein Wochenende" : "An evening or a weekend"
        case .cozy: return german ? "Ruhig, warm, sanft" : "Slow, warm, gentle"
        case .intense: return german ? "Düster und packend" : "Dark and gripping"
        case .likeLastLoved: return german ? "Weil du es beendet hast" : "Because you finished it"
        }
    }

    /// The journey's purpose line.
    static func purpose(_ mood: DiscoverMood, seedTitle: String?, german: Bool) -> String {
        switch mood {
        case .short:
            return german ? "Kurz genug für einen Abend oder ein Wochenende."
                          : "Short enough for an evening or a weekend."
        case .cozy: return german ? "Warme, entspannte Geschichten zum Abschalten." : "Warm, low-stakes stories to unwind with."
        case .intense: return german ? "Düstere, ernste Geschichten, die packen." : "Dark, serious stories that grip."
        case .likeLastLoved:
            let title = seedTitle ?? (german ? "deinem Favoriten" : "your favourite")
            return german ? "Nah an \(title) in Ton und Themen." : "Close to \(title) in tone and themes."
        }
    }

    /// "BECAUSE YOU FINISHED {TITLE}" (like only).
    static func becauseEyebrow(_ title: String, german: Bool) -> String {
        (german ? "Weil du \(title) beendet hast" : "Because you finished \(title)").uppercased()
    }

    static func startHere(german: Bool) -> String { german ? "Fang hier an" : "Start here" }

    static func films(german: Bool) -> String { german ? "Filme" : "Films" }
    static func series(german: Bool) -> String { german ? "Serien" : "Series" }

    static func medium(_ kind: MediaKind) -> String { kind == .manga ? "Manga" : "Anime" }

    static func moodsLabel(german: Bool) -> String { german ? "Stimmung" : "Mood" }
    static func mediumLabel(german: Bool) -> String { german ? "Medium" : "Medium" }

    /// "Nothing {mood} left that you haven't seen."
    static func empty(_ mood: DiscoverMood, seedTitle: String?, german: Bool) -> String {
        switch mood {
        case .short: return german ? "Nichts Kurzes mehr, das du noch nicht kennst." : "Nothing short left that you haven't seen."
        case .cozy: return german ? "Nichts Gemütliches mehr, das du noch nicht kennst." : "Nothing cozy left that you haven't seen."
        case .intense: return german ? "Nichts Intensives mehr, das du noch nicht kennst." : "Nothing intense left that you haven't seen."
        case .likeLastLoved:
            let title = seedTitle ?? (german ? "deinen Favoriten" : "your favourite")
            return german ? "Nichts wie \(title) mehr, das du noch nicht kennst." : "Nothing like \(title) left that you haven't seen."
        }
    }

    /// The page title for the compact bar and VoiceOver.
    static func pageTitle(_ mood: DiscoverMood, seedTitle: String?, german: Bool) -> String {
        word(mood, seedTitle: seedTitle, german: german)
    }
}
