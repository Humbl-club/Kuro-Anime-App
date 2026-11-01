import Foundation
import KuroCore
import KuroLibrary

// MARK: - Manga detail rules (prototype fidelity, Task 7; spec §5.2; ref-detail-manga-390.png)
// Pure rules for the manga page: which chapter rows are real, the bookmark's words, whether the
// "Seen the anime?" card and "Read with the publisher" row have real data behind them, and the
// section input. Nothing here invents a total, a chapter title or an adaptation.

enum MangaDetailSections {
    /// True when the chapter list carries real information. A list whose every row is a bare
    /// placeholder ("Chapter 12", or no title) with no release date is hidden (spec §5.2 D6).
    static func chaptersAreReal(_ chapters: [MangaChapter]) -> Bool {
        guard !chapters.isEmpty else { return false }
        return chapters.contains { !isPlaceholder($0) }
    }

    /// A row with no date and a title that only repeats its number.
    static func isPlaceholder(_ chapter: MangaChapter) -> Bool {
        if chapter.releaseDate != nil || chapter.releaseAt != nil { return false }
        return realTitle(chapter) == nil
    }

    /// The chapter's own title, or nil when it is missing or only repeats "Chapter N".
    nonisolated static func realTitle(_ chapter: MangaChapter) -> String? {
        guard let title = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
              title.range(of: #"^chapter\s*\d+$"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        return title
    }

    /// The anime adaptation the ladder names: its primary adaptation when that is an anime, else the
    /// first anime among its adaptations. nil without one (the card is hidden, never filled in).
    static func animeAdaptation(in ladder: MediaLadderResponse) -> MediaLadderItem? {
        if let primary = ladder.primaryAdaptation, primary.mediaType.uppercased() == "ANIME" { return primary }
        return ladder.adaptations.first { $0.mediaType.uppercased() == "ANIME" }
    }

    /// The reading service the "Read with the publisher" row opens: the first legal read link whose
    /// URL passes the outbound check. nil hides the row.
    static func publisherLink(from links: [ProviderSheetItem]) -> ProviderSheetItem? {
        links.first { ProviderAvailabilityStore.validatedOutboundURL($0.url) != nil }
    }

    /// The bookmark's total: only a known, positive chapter count ("Ch. 24 / 25"); otherwise none.
    static func bookmarkTotal(chapterCount: Int?) -> Int? {
        guard let chapterCount, chapterCount > 0 else { return nil }
        return chapterCount
    }

    /// The line under "Your bookmark": the real total, the ongoing note, or nothing.
    static func bookmarkCaption(total: Int?, releasing: Bool, german: Bool) -> String? {
        if let total {
            if german { return "\(total) Kapitel" }
            return total == 1 ? "1 chapter" : "\(total) chapters"
        }
        guard releasing else { return nil }
        return german ? "Laufend · Gesamtzahl unbekannt" : "Ongoing · total unknown"
    }

    /// VoiceOver's reading of the bookmark ("Chapter 24 of 25" / "Chapter 24").
    static func bookmarkSpoken(progress: Int, total: Int?, german: Bool) -> String {
        if let total { return german ? "Kapitel \(progress) von \(total)" : "Chapter \(progress) of \(total)" }
        return german ? "Kapitel \(progress)" : "Chapter \(progress)"
    }

    /// The next chapter to advance to. A known total caps it; with no total (most releasing manga)
    /// the next chapter is offered, as the Home leaf key does — the catalogue has no release ceiling.
    static func nextChapter(progress: Int, chapterCount: Int?) -> Int? {
        DetailSectionPolicy.nextUnit(progress: progress, total: bookmarkTotal(chapterCount: chapterCount))
    }

    static func input(hasSynopsis: Bool, hasHook: Bool, clubPeople: Int, isTracked: Bool, chapters: [MangaChapter],
                      nextChapter: Int?, hasAdaptation: Bool, characterCount: Int, creditRows: Int,
                      hasPublisherLink: Bool, hasClubs: Bool) -> DetailInput {
        DetailInput(kind: .manga,
                    hasSynopsis: hasSynopsis,
                    hasHook: hasHook,
                    clubPeopleCount: clubPeople,
                    seasonCount: 0,
                    isTracked: isTracked,
                    // Placeholder chapters count as none: their list is hidden, Up next still shows.
                    unitCount: chaptersAreReal(chapters) ? chapters.count : 0,
                    hasNextUnit: nextChapter != nil,
                    hasSource: hasAdaptation,
                    songCount: 0,
                    characterCount: characterCount,
                    // "Read with the publisher" lives in "Behind the pages.": it keeps the section alive
                    // when no author credit exists (credits_cast_v1 off).
                    creditCount: creditRows + (hasPublisherLink ? 1 : 0),
                    hasClubs: hasClubs)
    }

    /// The publisher row's caption: the real service name, and how many more there are.
    static func publisherCaption(_ link: ProviderSheetItem, count: Int, german: Bool) -> String {
        guard count > 1 else { return link.title }
        let more = count - 1
        return german ? "\(link.title) und \(more) weitere" : "\(link.title) and \(more) more"
    }
}

enum MangaDetailCopy {
    static func chapter(_ number: Int, german: Bool) -> String { german ? "Kapitel \(number)" : "Chapter \(number)" }
    static func seriesOverview(german: Bool) -> String { german ? "Serienüberblick" : "Series overview" }
    static func bookmark(german: Bool) -> String { german ? "Dein Lesezeichen" : "Your bookmark" }
    static func chapterUnit(german: Bool) -> String { german ? "Kap." : "Ch." }
}

extension DetailCreditRow {
    /// "Behind the pages." rows from the manga's author credits: "Story & art", or "Story" and "Art"
    /// when two people share the work. Rows without a name are omitted; nothing is invented (the
    /// catalogue has no publisher field, so "English publisher" is not shown).
    static func manga(authors: [(author: Author, role: String)], german: Bool) -> [DetailCreditRow] {
        var rows: [DetailCreditRow] = []
        var seen = Set<String>()
        for item in authors {
            guard let name = item.author.nameFull?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            let role = item.role.lowercased()
            let label: String
            if role.contains("story") && role.contains("art") {
                label = german ? "Story & Zeichnungen" : "Story & art"
            } else if role.contains("story") || role.contains("original") {
                label = "Story"
            } else if role.contains("art") || role.contains("illustration") {
                label = german ? "Zeichnungen" : "Art"
            } else {
                continue
            }
            guard seen.insert("\(label)|\(name)").inserted else { continue }
            rows.append(DetailCreditRow(role: label, name: name, target: .author(item.author)))
            if rows.count == 3 { break }
        }
        return rows
    }
}
