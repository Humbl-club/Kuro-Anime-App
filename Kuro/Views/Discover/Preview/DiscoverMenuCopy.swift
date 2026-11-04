import Foundation
import KuroCore
import KuroLibrary

// MARK: - Discover long-press preview, menu and feedback toasts: copy (EN / DE)
// Spec docs/superpowers/specs/2026-11-04-discover-usability-design.md §5.2, §5.3, §8. EXISTING strings
// are byte-identical to the shipped ones ("Vormerken", "Edit list entry", "Add to club…", the last four
// toast lines from `TastePlanCopy`); everything else is new here. Every view passes `german`
// (`KuroLocale.isGerman`), so tests can render both languages.

nonisolated enum DiscoverMenuCopy {
    // MARK: Menu (fixed order: Plan, Seen it, Not interested, Add to club…, Open)

    /// The Plan item mirrors the Plan key's action (`TastePlanAction`).
    static func planItem(_ action: TastePlanAction, medium: MediaKind, german: Bool) -> String {
        switch action {
        case .plan:
            if german { return "Vormerken" }
            return medium == .manga ? "Plan to read" : "Plan to watch"
        case .unplan: return german ? "Aus Geplant entfernen" : "Remove from Planned"
        case .edit: return german ? "Listeneintrag bearbeiten" : "Edit list entry"
        }
    }

    static func seenIt(medium: MediaKind, german: Bool) -> String {
        switch (medium, german) {
        case (.manga, false): return "Already read"
        case (.manga, true): return "Schon gelesen"
        case (_, false): return "Seen it"
        case (_, true): return "Schon gesehen"
        }
    }

    static func seenItSubtitle(german: Bool) -> String {
        german ? "Blendet es hier aus. Du kannst es als abgeschlossen eintragen."
               : "Hides it here. You can add it as Completed."
    }

    static func notInterested(german: Bool) -> String { german ? "Kein Interesse" : "Not interested" }

    static func notInterestedSubtitle(german: Bool) -> String {
        german ? "Blendet es aus und zeigt weniger davon." : "Hides it and shows fewer like it."
    }

    /// EXISTING (`DiscoverFrameMenu`).
    static func addToClub(german: Bool) -> String {
        german ? "Zu einem Club hinzufügen\u{2026}" : "Add to club\u{2026}"
    }

    static func open(german: Bool) -> String { german ? "Öffnen" : "Open" }

    // MARK: Toasts

    static func hidden(german: Bool) -> String {
        german ? "Ausgeblendet. Du siehst weniger davon." : "Hidden. You'll see fewer like it."
    }

    static func markedSeen(german: Bool) -> String {
        german ? "Als gesehen markiert." : "Marked as seen."
    }

    static func addAsCompleted(german: Bool) -> String {
        german ? "Als abgeschlossen eintragen \u{203A}" : "Add as Completed \u{203A}"
    }

    /// VoiceOver for the text action (no chevron spoken).
    static func addAsCompletedSpoken(german: Bool) -> String {
        german ? "Als abgeschlossen eintragen" : "Add as Completed"
    }

    /// EXISTING (`TastePlanCopy`).
    static func undo(german: Bool) -> String { TastePlanCopy.undo(german: german) }
    static func undone(german: Bool) -> String { TastePlanCopy.message(.undone, german: german) }
    static func dismiss(german: Bool) -> String { TastePlanCopy.dismiss(german: german) }

    /// Announced when a title is hidden (both answers).
    static func hiddenAnnouncement(german: Bool) -> String {
        german ? "Ausgeblendet. Rückgängig möglich." : "Hidden. Undo available."
    }

    /// The toast message for one answer.
    static func toast(_ feedback: DiscoverFeedback, german: Bool) -> String {
        switch feedback {
        case .notInterested: return hidden(german: german)
        case .seenIt: return markedSeen(german: german)
        }
    }

    // MARK: Preview

    /// "ANIME · NEW TO YOU": the medium, then the section's name when the caller gives one.
    static func previewKicker(kind: MediaKind, section: String?, german: Bool) -> String {
        var parts = [kindKicker(kind)]
        if let section = section?.trimmingCharacters(in: .whitespacesAndNewlines), !section.isEmpty {
            parts.append(section.hasSuffix(".") ? String(section.dropLast()) : section)
        }
        return parts.joined(separator: " · ").uppercased()
    }

    /// The kind kicker: identical in both languages.
    static func kindKicker(_ kind: MediaKind) -> String { kind == .manga ? "MANGA" : "ANIME" }

    /// "{year} · {format} · {n} eps · {status word}", skipping missing parts.
    static func previewFacts(kind: MediaKind, year: String?, formatRaw: String?, episodes: Int?, chapters: Int?,
                             statusRaw: String?, german: Bool) -> String? {
        var parts: [String] = []
        if let facts = DiscoverIssueCopy.facts(kind: kind, year: year, formatRaw: formatRaw, episodes: episodes,
                                               chapters: chapters, length: true, german: german) {
            parts.append(facts)
        }
        if let status = catalogStatusWord(statusRaw, kind: kind, german: german) { parts.append(status) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The catalogue's release status in reading form. "Fertig erschienen", not "Abgeschlossen" (the
    /// Completed list word, D10).
    static func catalogStatusWord(_ statusRaw: String?, kind: MediaKind, german: Bool) -> String? {
        switch statusRaw?.uppercased() {
        case "FINISHED": return german ? "Fertig erschienen" : "Finished"
        case "RELEASING":
            if kind == .manga { return german ? "Erscheint noch" : "Ongoing" }
            return german ? "Läuft" : "Airing"
        case "NOT_YET_RELEASED": return german ? "Angekündigt" : "Upcoming"
        case "HIATUS": return german ? "Hiatus" : "On hiatus"
        case "CANCELLED": return german ? "Eingestellt" : "Cancelled"
        default: return nil
        }
    }

    /// "Why it's here: {reason}." (nil without a reason).
    static func whyItsHere(_ reason: String?, german: Bool) -> String? {
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else { return nil }
        let sentence = reason.hasSuffix(".") ? reason : reason + "."
        return german ? "Warum es hier ist: \(sentence)" : "Why it's here: \(sentence)"
    }

    /// The section reasons the preview names (§8 "Why it's here").
    enum Reason: Equatable {
        case unseen, canon, airing, popular, classic
        case closeTo(String)

        func text(german: Bool) -> String {
            switch self {
            case .unseen: return german ? "noch nicht gesehen" : "unseen by you"
            case .canon: return german ? "in unserem Kanon" : "in our canon"
            case .airing: return german ? "läuft gerade" : "airing now"
            case .popular: return german ? "diese Woche beliebt" : "popular this week"
            case .classic: return german ? "ein Klassiker" : "a classic"
            case .closeTo(let title): return german ? "nah an \(title)" : "close to \(title)"
            }
        }
    }

    // MARK: Status word on owned rows ("mark" sections, R2)

    /// The Folio status word of a title on the list (EXISTING words, `FolioStatus`).
    @MainActor
    static func statusWord(_ status: ListStatus, medium: MediaKind, german: Bool) -> String {
        FolioStatus(listStatus: status).title(medium: medium, german: german)
    }

    // MARK: VoiceOver

    /// The VoiceOver custom actions (§5.2): Plan, Seen it, Not interested, Add to club.
    static func spokenPlan(_ action: TastePlanAction, medium: MediaKind, german: Bool) -> String {
        planItem(action, medium: medium, german: german)
    }

    /// "Anime: {title}" on the All issue only (§5.11).
    static func kindPrefixed(_ title: String, kind: MediaKind) -> String {
        (kind == .manga ? "Manga: " : "Anime: ") + title
    }
}
