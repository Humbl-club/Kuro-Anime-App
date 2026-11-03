import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - Entity Sort Mode

/// A filter or sort option with a reader-facing word (EN/DE); `rawValue` stays the stable identity.
protocol EntityOptionTitled {
    var title: String { get }
}

enum EntitySortMode: String, CaseIterable, EntityOptionTitled {
    case rating = "RATING"
    case year = "YEAR"
    case era = "ERA"

    var title: String {
        switch self {
        case .rating: return KuroLocale.text("Rating", "Wertung")
        case .year: return KuroLocale.text("Year", "Jahr")
        case .era: return KuroLocale.text("Era", "Epoche")
        }
    }
}

enum EntityWorkIdentity {
    static func make(media: Media, role: String?, index: Int) -> String {
        "\(media.stableKey)-\(role ?? "none")-\(index)"
    }
}

enum EntityEraBucket: Int, CaseIterable {
    case current = 4
    case tens = 3
    case aughts = 2
    case classics = 1

    static func from(yearString: String) -> EntityEraBucket {
        let year = Int(yearString) ?? 0
        switch year {
        case 2020...:
            return .current
        case 2010...2019:
            return .tens
        case 2000...2009:
            return .aughts
        default:
            return .classics
        }
    }
}

enum CharacterMediaFilter: String, CaseIterable, EntityOptionTitled {
    case all = "ALL"
    case anime = "ANIME"
    case manga = "MANGA"

    var title: String {
        switch self {
        case .all: return KuroLocale.text("All", "Alle")
        case .anime: return "Anime"
        case .manga: return "Manga"
        }
    }
}

enum StaffRoleFilter: String, CaseIterable, EntityOptionTitled {
    case all = "ALL ROLES"
    case director = "DIRECTOR"
    case writer = "WRITER"
    case music = "MUSIC"
    case design = "DESIGN"

    var title: String {
        switch self {
        case .all: return KuroLocale.text("All roles", "Alle Rollen")
        case .director: return KuroLocale.text("Director", "Regie")
        case .writer: return KuroLocale.text("Writer", "Drehbuch")
        case .music: return KuroLocale.text("Music", "Musik")
        case .design: return KuroLocale.text("Design", "Design")
        }
    }

    static func from(role: String) -> StaffRoleFilter? {
        let normalized = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("director") {
            if normalized.contains("sound") || normalized.contains("music") {
                return .music
            }
            if normalized.contains("art") || normalized.contains("animation") || normalized.contains("character") {
                return .design
            }
            return .director
        }
        if normalized.contains("writer")
            || normalized.contains("script")
            || normalized.contains("screenplay")
            || normalized.contains("series composition")
            || normalized.contains("original creator")
            || normalized.contains("original story")
            || normalized.contains("story")
            || normalized.contains("scenario") {
            return .writer
        }
        if normalized.contains("music")
            || normalized.contains("sound")
            || normalized.contains("theme song")
            || normalized.contains("composer") {
            return .music
        }
        if normalized.contains("design")
            || normalized.contains("animation director")
            || normalized.contains("art director")
            || normalized.contains("art design") {
            return .design
        }
        return nil
    }
}

enum AuthorRoleFilter: String, CaseIterable, EntityOptionTitled {
    case all = "ALL"
    case story = "STORY"
    case art = "ART"
    case storyArt = "STORY & ART"

    var title: String {
        switch self {
        case .all: return KuroLocale.text("All", "Alle")
        case .story: return KuroLocale.text("Story", "Geschichte")
        case .art: return KuroLocale.text("Art", "Zeichnungen")
        case .storyArt: return KuroLocale.text("Story & art", "Geschichte & Zeichnungen")
        }
    }

    static func from(role: String) -> AuthorRoleFilter? {
        let normalized = role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasStory = normalized.contains("story")
        let hasArt = normalized.contains("art")
        if hasStory && hasArt {
            return .storyArt
        }
        if hasStory {
            return .story
        }
        if hasArt {
            return .art
        }
        return nil
    }
}

// MARK: - Journey pages (navigation contract, docs/superpowers/specs/2026-11-02-navigation-contract-design.md)
//
// Character, staff, studio and author pages are JOURNEY PAGES (`JourneyPage.character/.staff/.studio/
// .author`, built by `JourneyPageView` in JourneyHost.swift). Open them with
// `routes.openCharacter/openStaff/openStudio/openAuthor(...)`; never build them inside a `.sheet`.
//   - No NavigationStack of their own inside a journey (`KuroJourneyAwareStack` adds one only while a
//     legacy sheet still presents them outside a journey) and no Close button of their own: back (when
//     pushed), ✕ (closes the whole journey, N3) and the shrinking header (H1–H3) come from
//     `.kuroJourneyChrome`, which also keeps edge swipe-back working (N2).
//   - Every work, character and voice tap pushes inside the journey (`routes.openMedia` / `openCharacter`
//     / `openStaff`; N5 pops back when the page is already in the stack, so character → voice actor →
//     the same character is bounded).
//   - The page keeps what it loaded while it stays in the stack (Back never reloads it).
//   - `.routePresenter()` forwards to the journey; outside one (a legacy sheet) it opens a new journey.
//
// Home's grammar (details-songs spec §9, 2026-11-03): `kuroPaper`, the 24 pt detail gutter at every width,
// the readable column on iPad, the portrait hero (or the studio's cover line), `DetailSectionHeading`s,
// refine and sort WORDS (no black pills), quiet rows and edge-peek rails (`EntityRailPeek`). Blocks without
// data are left out. The works and voice readers answer [] on failure, so a failed read hides its block
// rather than showing an invented "none" (spec §17.6).

/// Where the shrinking header starts and how far it runs, per hero shape.
enum EntityPageCollapse {
    /// Portrait hero (character, staff, author): the name sits beside the portrait at the top, so the bar
    /// fades in as soon as the name passes under it.
    static let portraitStart: CGFloat = 20
    /// Name-only hero (studio): the bar fades in while the display-size name passes under it.
    static let nameOnlyStart: CGFloat = 24
    /// The fade's length in points of scroll.
    static let distance: CGFloat = 60
}

private extension View {
    /// The journey page frame every entity page shares: paper, scroll-tied shrinking header, the chrome.
    func entityJourneyPage(title: String, collapse: Binding<CGFloat>, start: CGFloat) -> some View {
        self
            .kuroCollapseTracking(collapse, start: start, distance: EntityPageCollapse.distance)
            .background(Color.kuroPaper)
            .kuroJourneyChrome(title: title, collapseProgress: collapse.wrappedValue)
    }

    /// The page column: measured (rails take their card width from it), the readable column on iPad,
    /// content below the 52 pt chrome.
    func entityColumn(_ column: Binding<CGFloat>) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { column.wrappedValue = $0 }
            .kuroReadableWidth()
            .padding(.top, KuroJourneyChrome.barHeight + 8)
            .padding(.bottom, 40)
    }

    /// The 24 pt detail gutter (rails are never inside it).
    func entityGutter() -> some View { padding(.horizontal, EntityPageLayout.gutter) }
}

/// A section's heading (the detail page's `DetailSectionHeading`).
private struct EntityHeading: View {
    let title: String
    var note: String? = nil

    var body: some View {
        DetailSectionHeading(title: title, note: note)
            .entityGutter()
            .padding(.top, 30)
            .padding(.bottom, 4)
    }
}

/// Three quiet skeleton rows while a list loads.
private struct EntityLoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in KuroSkeleton(kind: .row) }
        }
        .entityGutter()
        .padding(.top, 8)
    }
}

/// The fold under a long list ("All 24 roles" / "Show fewer").
private struct EntityListFold: View {
    @Binding var isExpanded: Bool
    let expand: String
    let collapse: String

    var body: some View {
        KuroFoldButton(isExpanded: $isExpanded, expandLabel: expand, collapseLabel: collapse) { title, _ in
            HStack {
                Text(title)
                    .font(.detailSF(11, .medium, relativeTo: .footnote))
                    .foregroundStyle(Color.kuroInk)
                Spacer(minLength: 8)
                Text("→")
                    .font(.detailSF(11, .medium, relativeTo: .footnote))
                    .foregroundStyle(Color.kuroInk)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .entityGutter()
    }
}

// MARK: - Character page

struct CharacterDetailSheet: View {
    let character: Character
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroFoldMemory) private var folds
    @State private var works: [Media] = []
    @State private var isLoading = true
    @State private var voices: [VoiceActorCredit] = []
    @State private var voiceRoleCounts: [Int: Int] = [:]
    @State private var sortMode: EntitySortMode = .rating
    @State private var mediaFilter: CharacterMediaFilter = .all
    @State private var collapse: CGFloat = 0
    @State private var column: CGFloat = 0

    private var name: String { character.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman) }
    private var foldPage: String { "character:\(character.id)" }

    /// All / Anime / Manga, only when the appearances span both (`EntityWorks.mediumFilters`).
    private var availableMediaFilters: [CharacterMediaFilter] { EntityWorks.mediumFilters(for: works.map(\.kind)) }

    private var shownWorks: [Media] {
        EntityWorks.sorted(works.filter { EntityWorks.matches($0.kind, filter: mediaFilter) }, mode: sortMode) { $0 }
    }

    /// The title the eyebrow names: the character's best-known anime, else their best-known work.
    private var leadTitle: String? {
        (works.first { $0.kind == .anime } ?? works.first).map { KuroCardText.sanitizeTitleForCard($0.title) }
    }

    private var facts: [String] {
        let german = KuroLocale.isGerman
        var facts: [String] = []
        if !isLoading, !works.isEmpty { facts.append(EntityPageCopy.appearances(works.count, german: german)) }
        if let gender = EntityPageCopy.gender(character.gender, german: german) { facts.append(gender) }
        if let age = EntityPageCopy.age(character.age, german: german) { facts.append(age) }
        return facts
    }

    var body: some View {
        let german = KuroLocale.isGerman
        KuroJourneyAwareStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EntityPageHero(imageURL: character.imageLarge, name: name, native: character.nameNative,
                                   eyebrow: EntityPageCopy.characterEyebrow(title: leadTitle, german: german),
                                   facts: facts)
                        .entityGutter()

                    if let text = EntityPageCopy.description(character.description) {
                        EntityDescription(text: text, isExpanded: folds.binding(page: foldPage, section: "about"))
                            .entityGutter()
                            .padding(.top, 20)
                    }

                    if !voices.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(Array(voices.prefix(3))) { voice in
                                EntityVoiceCard(staff: voice.staff, roleCount: voiceRoleCounts[voice.staff.id])
                            }
                        }
                        .entityGutter()
                        .padding(.top, 20)
                    }

                    appearsIn(german: german)

                    if let tracked = shownWorks.lazy.compactMap({ media in
                        library.entry(for: media.libraryKey).map { (media: media, entry: $0) }
                    }).first {
                        EntityInListLine(media: tracked.media, entry: tracked.entry)
                            .entityGutter()
                            .padding(.top, 20)
                    }
                }
                .entityColumn($column)
            }
            .entityJourneyPage(title: name, collapse: $collapse, start: EntityPageCollapse.portraitStart)
        }
        .task {
            // Back to this page keeps what it loaded (no skeleton flash, no second read).
            guard isLoading else { return }
            async let appearances = catalog.fetchMediaByCharacter(characterId: character.id)
            async let credits = catalog.fetchVoiceActors(forCharacter: character.id)
            works = await appearances
            voices = await credits
            isLoading = false
            for voice in voices.prefix(3) {
                let roles = await catalog.fetchVoiceRoles(forStaff: voice.staff.id)
                if !roles.isEmpty { voiceRoleCounts[voice.staff.id] = roles.count }
            }
        }
        // Forwards to the journey (pushes); outside one, the work tiles open a new journey here.
        .routePresenter()
    }

    @ViewBuilder
    private func appearsIn(german: Bool) -> some View {
        if isLoading {
            EntityHeading(title: EntityPageCopy.appearsIn(german: german))
            EntityLoadingRows()
        } else if !works.isEmpty {
            EntityHeading(title: EntityPageCopy.appearsIn(german: german),
                          note: EntityPageCopy.titles(works.count, german: german))
            EntityRefineSortRow(filters: availableMediaFilters, filter: $mediaFilter, sort: $sortMode)
                .entityGutter()
            EntityWorkRail(works: shownWorks.enumerated().map {
                EntityWorkItem(media: $0.element, role: nil,
                               id: EntityWorkIdentity.make(media: $0.element, role: nil, index: $0.offset))
            }, column: column)
            .padding(.top, 8)
        }
    }
}

// MARK: - Staff page

struct StaffDetailSheet: View {
    let staff: Staff
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @Environment(\.kuroFoldMemory) private var folds
    @State private var works: [(media: Media, role: String)] = []
    @State private var voiceRoles: [VoiceRole] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating
    @State private var roleFilter: StaffRoleFilter = .all
    @State private var mediaFilter: CharacterMediaFilter = .all
    @State private var collapse: CGFloat = 0
    @State private var column: CGFloat = 0
    @State private var showsAllRoles = false
    @State private var showsAllWorks = false

    /// Roles and works shown before the fold.
    static let foldedRoles = 8
    static let foldedWorks = 10

    private var name: String { staff.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman) }
    private var foldPage: String { "staff:\(staff.id)" }

    /// All / Anime / Manga, only when the filmography spans both (`EntityWorks.mediumFilters`).
    private var availableMediaFilters: [CharacterMediaFilter] {
        EntityWorks.mediumFilters(for: works.map(\.media.kind))
    }

    private var availableRoleFilters: [StaffRoleFilter] {
        let categories = Set(mediumFilteredWorks.compactMap { StaffRoleFilter.from(role: $0.role) })
        return [.all] + StaffRoleFilter.allCases.filter { $0 != .all && categories.contains($0) }
    }

    private var mediumFilteredWorks: [(media: Media, role: String)] {
        works.filter { EntityWorks.matches($0.media.kind, filter: mediaFilter) }
    }

    private var shownWorks: [(media: Media, role: String)] {
        let filtered = roleFilter == .all ? mediumFilteredWorks
            : mediumFilteredWorks.filter { StaffRoleFilter.from(role: $0.role) == roleFilter }
        return EntityWorks.sorted(filtered, mode: sortMode) { $0.media }
    }

    /// Roles whose anime is on the viewer's lists, one per character.
    private var knownRoles: [VoiceRole] {
        var seen = Set<Int>()
        return voiceRoles.filter { library.entry(for: $0.anime.key) != nil && seen.insert($0.character.id).inserted }
    }

    private var eyebrow: String? {
        voiceRoles.isEmpty ? EntityPageCopy.occupationEyebrow(staff.primaryOccupations)
            : EntityPageCopy.voiceEyebrow(german: KuroLocale.isGerman)
    }

    private var facts: [String] {
        let german = KuroLocale.isGerman
        if !voiceRoles.isEmpty {
            let inList = Set(voiceRoles.filter { library.entry(for: $0.anime.key) != nil }.map(\.anime.id)).count
            return [EntityPageCopy.rolesFacts(roles: voiceRoles.count, inList: inList, german: german)]
        }
        let titles = Set(works.map(\.media.stableKey)).count
        return titles > 0 ? [EntityPageCopy.titlesInKuro(titles, german: german)] : []
    }

    var body: some View {
        let german = KuroLocale.isGerman
        KuroJourneyAwareStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EntityPageHero(imageURL: staff.imageLarge, name: name, native: staff.nameNative,
                                   eyebrow: eyebrow, facts: facts)
                        .entityGutter()

                    if let text = EntityPageCopy.description(staff.description) {
                        EntityDescription(text: text, isExpanded: folds.binding(page: foldPage, section: "about"))
                            .entityGutter()
                            .padding(.top, 20)
                    }

                    if !voiceRoles.isEmpty {
                        EntityHeading(title: EntityPageCopy.rolesHeading(german: german),
                                      note: EntityPageCopy.popular(german: german))
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(showsAllRoles ? voiceRoles : Array(voiceRoles.prefix(Self.foldedRoles))) { role in
                                EntityRoleRow(role: role)
                            }
                        }
                        .entityGutter()
                        if voiceRoles.count > Self.foldedRoles {
                            EntityListFold(isExpanded: $showsAllRoles,
                                           expand: EntityPageCopy.allRoles(voiceRoles.count, german: german),
                                           collapse: EntityPageCopy.fewerRoles(german: german))
                        }
                    }

                    if !knownRoles.isEmpty {
                        EntityHeading(title: EntityPageCopy.charactersYouKnow(german: german))
                        EntityCharacterRail(roles: knownRoles, column: column)
                            .padding(.top, 8)
                    }

                    worksBlock(german: german)
                }
                .entityColumn($column)
            }
            .entityJourneyPage(title: name, collapse: $collapse, start: EntityPageCollapse.portraitStart)
        }
        .task {
            guard isLoading else { return }
            // Anime (`anime_staff`) and manga (`manga_staff`): an "Original work" credit reaches the manga.
            async let filmography = catalog.fetchStaffWorks(staffId: staff.id)
            async let roles = catalog.fetchVoiceRoles(forStaff: staff.id)
            works = await filmography
            voiceRoles = await roles
            isLoading = false
        }
        .routePresenter()
    }

    @ViewBuilder
    private func worksBlock(german: Bool) -> some View {
        if isLoading {
            EntityHeading(title: EntityPageCopy.worksHeading(german: german))
            EntityLoadingRows()
        } else if !works.isEmpty {
            let shown = shownWorks
            EntityHeading(title: EntityPageCopy.worksHeading(german: german),
                          note: EntityPageCopy.titles(shown.count, german: german))
            let refines = availableMediaFilters.count > 1 || availableRoleFilters.count > 1
            // One row when the words fit (refine left, sort right); otherwise the refine words scroll on
            // their own row and the sort words sit under them.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    if refines { staffRefineWords(german: german) }
                    Spacer(minLength: 8)
                    EntityWords(options: EntitySortMode.allCases, selection: $sortMode,
                                groupLabel: EntityPageCopy.sortLabel(german: german))
                }
                .entityGutter()
                VStack(alignment: .leading, spacing: 0) {
                    if refines {
                        ScrollView(.horizontal, showsIndicators: false) {
                            staffRefineWords(german: german)
                                .padding(.horizontal, EntityPageLayout.gutter)
                        }
                        .scrollClipDisabled()
                        .kuroSwipeExclusionZone()
                    }
                    EntitySortRow(sort: $sortMode)
                        .entityGutter()
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((showsAllWorks ? shown : Array(shown.prefix(Self.foldedWorks))).enumerated()),
                        id: \.offset) { index, work in
                    EntityWorkRow(media: work.media, role: work.role)
                        .id(EntityWorkIdentity.make(media: work.media, role: work.role, index: index))
                }
            }
            .entityGutter()
            if shown.count > Self.foldedWorks {
                EntityListFold(isExpanded: $showsAllWorks,
                               expand: EntityPageCopy.allWorks(shown.count, german: german),
                               collapse: EntityPageCopy.fewerRoles(german: german))
            }
        }
    }
}

extension StaffDetailSheet {
    /// All / Anime / Manga (when the filmography spans both), then the shipped craft words.
    @ViewBuilder
    fileprivate func staffRefineWords(german: Bool) -> some View {
        HStack(spacing: 24) {
            if availableMediaFilters.count > 1 {
                EntityWords(options: availableMediaFilters, selection: Binding(
                    get: { mediaFilter },
                    set: { option in
                        mediaFilter = option
                        // A role the new medium does not have would leave the list empty.
                        if !availableRoleFilters.contains(roleFilter) { roleFilter = .all }
                    }), groupLabel: EntityPageCopy.refineLabel(german: german))
            }
            if availableRoleFilters.count > 1 {
                EntityWords(options: availableRoleFilters, selection: $roleFilter,
                            groupLabel: EntityPageCopy.refineLabel(german: german))
            }
        }
    }
}

// MARK: - Author page

struct AuthorDetailSheet: View {
    let author: Author
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.kuroFoldMemory) private var folds
    @State private var works: [(media: Media, role: String)] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating
    @State private var roleFilter: AuthorRoleFilter = .all
    @State private var collapse: CGFloat = 0
    @State private var column: CGFloat = 0
    @State private var showsAllWorks = false

    static let foldedWorks = 10

    private var name: String { author.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman) }

    private var availableRoleFilters: [AuthorRoleFilter] {
        let categories = Set(works.compactMap { AuthorRoleFilter.from(role: $0.role) })
        return [.all] + AuthorRoleFilter.allCases.filter { $0 != .all && categories.contains($0) }
    }

    private var shownWorks: [(media: Media, role: String)] {
        let filtered = roleFilter == .all ? works : works.filter { AuthorRoleFilter.from(role: $0.role) == roleFilter }
        return EntityWorks.sorted(filtered, mode: sortMode) { $0.media }
    }

    var body: some View {
        let german = KuroLocale.isGerman
        let titles = Set(works.map(\.media.stableKey)).count
        KuroJourneyAwareStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EntityPageHero(imageURL: author.imageLarge, name: name, native: author.nameNative,
                                   eyebrow: EntityPageCopy.author(german: german),
                                   facts: titles > 0 ? [EntityPageCopy.titlesInKuro(titles, german: german)] : [])
                        .entityGutter()

                    if let text = EntityPageCopy.description(author.description) {
                        EntityDescription(text: text, isExpanded: folds.binding(page: "author:\(author.id)", section: "about"))
                            .entityGutter()
                            .padding(.top, 20)
                    }

                    if isLoading {
                        EntityHeading(title: EntityPageCopy.worksHeading(german: german))
                        EntityLoadingRows()
                    } else if !works.isEmpty {
                        let shown = shownWorks
                        EntityHeading(title: EntityPageCopy.worksHeading(german: german),
                                      note: EntityPageCopy.titles(shown.count, german: german))
                        EntityRefineSortRow(filters: availableRoleFilters, filter: $roleFilter, sort: $sortMode)
                            .entityGutter()
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array((showsAllWorks ? shown : Array(shown.prefix(Self.foldedWorks))).enumerated()),
                                    id: \.offset) { _, work in
                                EntityWorkRow(media: work.media, role: work.role)
                            }
                        }
                        .entityGutter()
                        if shown.count > Self.foldedWorks {
                            EntityListFold(isExpanded: $showsAllWorks,
                                           expand: EntityPageCopy.allWorks(shown.count, german: german),
                                           collapse: EntityPageCopy.fewerRoles(german: german))
                        }
                    }
                }
                .entityColumn($column)
            }
            .entityJourneyPage(title: name, collapse: $collapse, start: EntityPageCollapse.portraitStart)
        }
        .task {
            guard isLoading else { return }
            works = await catalog.fetchMangaByAuthor(authorId: author.id)
            isLoading = false
        }
        .routePresenter()
    }
}

// MARK: - Studio page

struct StudioDetailSheet: View {
    let studio: Studio
    @Environment(CatalogStore.self) private var catalog
    @Environment(LibraryStore.self) private var library
    @State private var works: [Media] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating
    @State private var collapse: CGFloat = 0
    @State private var column: CGFloat = 0

    /// "Most loved." shows the studio's best-rated works; "By year." indexes all of them.
    static let railCap = 12

    private var name: String { studio.name ?? DetailCopy.unknown(german: KuroLocale.isGerman) }

    private var tracked: [(media: Media, entry: LibraryEntry)] {
        works.compactMap { media in library.entry(for: media.libraryKey).map { (media: media, entry: $0) } }
    }

    var body: some View {
        let german = KuroLocale.isGerman
        KuroJourneyAwareStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EntityStudioHero(name: name,
                                     facts: isLoading || works.isEmpty ? nil
                                        : EntityPageCopy.studioFacts(titles: works.count, animation: studio.isAnimationStudio == true,
                                                                     german: german),
                                     column: column)
                        .entityGutter()
                        .padding(.top, 8)

                    if !tracked.isEmpty {
                        EntityTrackedGlance(works: tracked)
                            .entityGutter()
                            .padding(.top, 20)
                    }

                    if isLoading {
                        EntityHeading(title: EntityPageCopy.mostLoved(german: german))
                        EntityLoadingRows()
                    } else if !works.isEmpty {
                        let loved = Array(EntityWorks.sorted(works, mode: sortMode) { $0 }.prefix(Self.railCap))
                        EntityHeading(title: EntityPageCopy.mostLoved(german: german),
                                      note: EntityPageCopy.titles(works.count, german: german))
                        EntitySortRow(sort: $sortMode)
                            .entityGutter()
                        EntityWorkRail(works: loved.enumerated().map {
                            EntityWorkItem(media: $0.element, role: nil,
                                           id: EntityWorkIdentity.make(media: $0.element, role: nil, index: $0.offset))
                        }, column: column)
                        .padding(.top, 8)

                        let years = EntityWorks.byYear(works)
                        if !years.isEmpty {
                            EntityHeading(title: EntityPageCopy.byYear(german: german))
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(years) { group in
                                    EntityYearRow(group: group, studioName: name)
                                }
                            }
                            .entityGutter()
                        }
                    }
                }
                .entityColumn($column)
            }
            .entityJourneyPage(title: name, collapse: $collapse, start: EntityPageCollapse.nameOnlyStart)
        }
        .task {
            guard isLoading else { return }
            works = await catalog.fetchAnimeByStudio(studioId: studio.id)
            isLoading = false
        }
        .routePresenter()
    }
}

// MARK: - Shared lead line (kept for the legacy cast directory, `CastSection.swift`)

struct EntitySectionLead: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.kuroMicro(weight: .regular))
            .tracking(0.8)
            .foregroundColor(.kuroTextTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

