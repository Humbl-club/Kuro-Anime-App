import Foundation
import KuroCore
import KuroLibrary

// MARK: - Entity page copy and rules (details-songs spec §9, §15; EN/DE, pure: every function takes `german`)
// Filter and sort words stay the shipped `CharacterMediaFilter` / `StaffRoleFilter` / `AuthorRoleFilter` /
// `EntitySortMode` titles. Status and role words come from `DetailCopy`.

enum EntityPageCopy {
    // MARK: Character

    static func characterEyebrow(title: String?, german: Bool) -> String {
        let word = german ? "Figur" : "Character"
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return word.uppercased() }
        return "\(word) · \(title)".uppercased()
    }

    /// A count as shown: "{n}+" when the reader stopped at its limit (the real number is larger: a capped
    /// read is never shown as a total, spec §5.4).
    static func number(_ count: Int, floor: Bool) -> String { floor ? "\(count)+" : "\(count)" }

    static func appearances(_ count: Int, german: Bool, floor: Bool = false) -> String {
        let n = number(count, floor: floor)
        if german { return count == 1 && !floor ? "1 Auftritt in Kuro" : "\(n) Auftritte in Kuro" }
        return count == 1 && !floor ? "1 appearance in Kuro" : "\(n) appearances in Kuro"
    }

    static func gender(_ raw: String?, german: Bool) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "male": return german ? "Männlich" : "Male"
        case "female": return german ? "Weiblich" : "Female"
        case "non-binary": return german ? "Nichtbinär" : "Non-binary"
        default: return raw
        }
    }

    static func age(_ raw: String?, german: Bool) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return german ? "Alter \(raw)" : "Age \(raw)"
    }

    static func japaneseVoice(german: Bool) -> String { german ? "JAPANISCHE STIMME" : "JAPANESE VOICE" }

    /// "Voice actor · 4 roles in Kuro"; the count part is left out while it loads (nil).
    static func voiceActorLine(roles: Int?, german: Bool, floor: Bool = false) -> String {
        let word = german ? "Sprecher·in" : "Voice actor"
        guard let roles, roles > 0 else { return word }
        return "\(word) · \(self.roles(roles, german: german, floor: floor))"
    }

    static func roles(_ count: Int, german: Bool, floor: Bool = false) -> String {
        let n = number(count, floor: floor)
        if german { return count == 1 && !floor ? "1 Rolle in Kuro" : "\(n) Rollen in Kuro" }
        return count == 1 && !floor ? "1 role in Kuro" : "\(n) roles in Kuro"
    }

    static func appearsIn(german: Bool) -> String { german ? "Kommt vor in." : "Appears in." }

    static func titles(_ count: Int, german: Bool, floor: Bool = false) -> String {
        let n = number(count, floor: floor)
        return german ? "\(n) Titel" : (count == 1 && !floor ? "1 title" : "\(n) titles")
    }

    static func inYourList(title: String, detail: String?, german: Bool) -> String {
        let lead = german ? "In deiner Liste: " : "In your list: "
        guard let detail, !detail.isEmpty else { return lead + title }
        return "\(lead)\(title) · \(detail)"
    }

    static func inYourListTitle(german: Bool) -> String { german ? "In deiner Liste" : "In your list" }
    /// VoiceOver group labels of the word rows.
    static func refineLabel(german: Bool) -> String { german ? "Werke filtern" : "Filter works" }
    static func sortLabel(german: Bool) -> String { german ? "Sortieren" : "Sort" }
    /// The shipped Browse word for the roles' order (MAIN first, then the anime's popularity).
    static func popular(german: Bool) -> String { german ? "Beliebt" : "Popular" }

    // MARK: Staff and author

    static func voiceEyebrow(german: Bool) -> String { german ? "STIMME · JAPANISCH" : "VOICE · JAPANESE" }

    /// The primary occupations as an eyebrow ("DIRECTOR · STORYBOARD"); nil when none.
    static func occupationEyebrow(_ occupations: [String]?) -> String? {
        let words = (occupations ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.prefix(3).joined(separator: " · ").uppercased()
    }

    /// "4 roles in Kuro · 1 in your list" (the list part only when it is not zero).
    static func rolesFacts(roles: Int, inList: Int, german: Bool, floor: Bool = false) -> String {
        let lead = self.roles(roles, german: german, floor: floor)
        guard inList > 0 else { return lead }
        return "\(lead) · \(inList) \(german ? "in deiner Liste" : "in your list")"
    }

    static func titlesInKuro(_ count: Int, german: Bool, floor: Bool = false) -> String {
        let n = number(count, floor: floor)
        return german ? "\(n) Titel in Kuro" : (count == 1 && !floor ? "1 title in Kuro" : "\(n) titles in Kuro")
    }

    static func rolesHeading(german: Bool) -> String { german ? "Rollen." : "Roles." }
    /// The roles fold: "All {n} roles", or "Show {n} roles" when the read stopped at its limit (not all).
    static func allRoles(_ count: Int, german: Bool, floor: Bool = false) -> String {
        if floor { return german ? "\(count) Rollen zeigen" : "Show \(count) roles" }
        return german ? "Alle \(count) Rollen" : "All \(count) roles"
    }
    static func fewerRoles(german: Bool) -> String { german ? "Weniger zeigen" : "Show fewer" }
    static func charactersYouKnow(german: Bool) -> String { german ? "Figuren, die du kennst." : "Characters you know." }
    static func worksHeading(german: Bool) -> String { german ? "Werke." : "Works." }
    static func allWorks(_ count: Int, german: Bool, floor: Bool = false) -> String {
        if floor { return german ? "\(count) Werke zeigen" : "Show \(count) works" }
        return german ? "Alle \(count) Werke" : "All \(count) works"
    }
    static func author(german: Bool) -> String { german ? "AUTOR·IN" : "AUTHOR" }
    static func readMore(german: Bool) -> String { german ? "Mehr lesen" : "Read more" }
    static func readLess(german: Bool) -> String { german ? "Weniger anzeigen" : "Show less" }

    // MARK: Studio

    static func studioFacts(titles: Int, animation: Bool, german: Bool, floor: Bool = false) -> String {
        let count = titlesInKuro(titles, german: german, floor: floor)
        guard animation else { return count }
        return "\(german ? "Animationsstudio" : "Animation studio") · \(count)"
    }

    static func mostLoved(german: Bool) -> String { german ? "Am beliebtesten." : "Most loved." }
    static func byYear(german: Bool) -> String { german ? "Nach Jahr." : "By year." }
    static func yearPageTitle(studio: String, year: Int) -> String { "\(studio) · \(year)" }
    static func moreInYear(_ count: Int, german: Bool) -> String { german ? "\(count) weitere" : "\(count) more" }

    // MARK: Works

    /// "TV", "Film", … (spec §15 format words); nil for an unknown or missing format.
    static func formatWord(_ raw: String?, german: Bool) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        switch raw.uppercased() {
        case "TV": return "TV"
        case "MOVIE", "FILM": return "Film"
        case "OVA": return "OVA"
        case "ONA": return "ONA"
        case "SPECIAL": return "Special"
        case "TV_SHORT": return german ? "TV-Kurzserie" : "TV short"
        case "MUSIC": return german ? "Musik" : "Music"
        case "MANGA": return "Manga"
        case "NOVEL", "LIGHT_NOVEL": return german ? "Light Novel" : "Light novel"
        case "ONE_SHOT": return german ? "One-Shot" : "One-shot"
        default: return nil
        }
    }

    /// "Anime · 2020" / "Manga · 2018" (the year only when known).
    static func mediumYear(kind: MediaKind, year: String, german: Bool) -> String {
        let medium = kind == .manga ? "Manga" : "Anime"
        guard let year = knownYear(year) else { return medium }
        return "\(medium) · \(year)"
    }

    /// "TV · Director" (each part only when known).
    static func workLine(formatRaw: String?, kind: MediaKind, role: String?, german: Bool) -> String {
        var parts: [String] = []
        parts.append(formatWord(formatRaw, german: german) ?? (kind == .manga ? "Manga" : "Anime"))
        if let role = role?.trimmingCharacters(in: .whitespacesAndNewlines), !role.isEmpty { parts.append(role) }
        return parts.joined(separator: " · ")
    }

    /// "Jujutsu Kaisen · Main · 2020" (each part only when known).
    static func roleLine(title: String, role: String, year: Int?, german: Bool) -> String {
        var parts = [title]
        if let word = DetailCopy.characterRole(role, german: german) { parts.append(word) }
        if let year, year > 0 { parts.append(String(year)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Ep. 6 / 23" / "F. 6 / 23", "Ch. 68" / "Kap. 68"; nil before the first unit.
    static func progress(_ progress: Int, total: Int?, kind: MediaKind, german: Bool) -> String? {
        guard progress > 0 else { return nil }
        let prefix: String
        switch kind {
        case .manga: prefix = german ? "Kap." : "Ch."
        default: prefix = german ? "F." : "Ep."
        }
        guard let total, total > 0 else { return "\(prefix) \(progress)" }
        return "\(prefix) \(progress) / \(total)"
    }

    /// A positive four-digit year from the catalogue's text year ("2020"); nil for "", "0", "TBA".
    static func knownYear(_ year: String) -> Int? {
        guard let value = Int(year.trimmingCharacters(in: .whitespacesAndNewlines)), value > 1900 else { return nil }
        return value
    }

    // MARK: Description

    /// AniList description as plain text: HTML removed (`TextNormalization`), spoiler blocks (`~!…!~`)
    /// dropped and `__bold__` markers removed. nil when nothing remains.
    /// AniList character descriptions open with metadata lines ("__Height:__ 190 cm"). They are lifted
    /// out of the prose (so the 4-line fold shows the story) and offered to the hero's facts line: at most
    /// two short ones, never age or gender (the hero has its own words for those).
    static func leadingFacts(_ raw: String?) -> (facts: [String], body: String?) {
        guard let text = TextNormalization.sanitizeMediaDescription(raw) else { return ([], nil) }
        var lines = text.components(separatedBy: "\n")
        var facts: [String] = []
        let pattern = #"^\s*__([^_\n]{1,32}?):?__:?\s*(.+?)\s*$"#
        while let first = lines.first {
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { lines.removeFirst(); continue }
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let keyRange = Range(match.range(at: 1), in: trimmed),
                  let valueRange = Range(match.range(at: 2), in: trimmed) else { break }
            let key = trimmed[keyRange].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ":", with: "")
            let value = trimmed[valueRange].replacingOccurrences(of: "__", with: "").trimmingCharacters(in: .whitespaces)
            lines.removeFirst()
            let skipped = ["age", "initial age", "gender", "alter", "geschlecht"]
            guard !skipped.contains(key.lowercased()), !value.isEmpty, value.count <= 24, facts.count < 2 else { continue }
            facts.append("\(key): \(value)")
        }
        return (facts, lines.joined(separator: "\n"))
    }

    /// `liftingFacts`: character pages move the leading metadata lines to the hero (`leadingFacts`);
    /// staff and author bios keep their text as written.
    static func description(_ raw: String?, liftingFacts: Bool = false) -> String? {
        guard var text = TextNormalization.sanitizeMediaDescription(liftingFacts ? leadingFacts(raw).body : raw) else { return nil }
        text = text.replacingOccurrences(of: #"(?s)~!.*?!~"#, with: "", options: [.regularExpression])
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
