import KuroCore
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
//   - Every work card pushes its title inside the journey (`KuroCompactCard` → `routes.openMedia`; N5
//     pops back when the title is already in the stack).
//   - The page keeps what it loaded while it stays in the stack (Back never reloads it).
//   - `.routePresenter()` forwards to the journey; outside one (a legacy sheet) it opens a new journey.

/// Where the shrinking header starts and how far it runs, per hero shape.
enum EntityPageCollapse {
    /// Circle-portrait hero (character, staff, author): the bar fades in while the name, below the
    /// 120 pt portrait, passes under it.
    static let portraitStart: CGFloat = 140
    /// Name-only hero (studio): the bar fades in while the display-size name passes under it.
    static let nameOnlyStart: CGFloat = 24
    /// The fade's length in points of scroll.
    static let distance: CGFloat = 60
}

private extension View {
    /// The journey page frame every entity page shares: content below the 52 pt chrome, scroll-tied
    /// shrinking header, the chrome itself.
    func entityJourneyPage(title: String, collapse: Binding<CGFloat>, start: CGFloat) -> some View {
        self
            .kuroCollapseTracking(collapse, start: start, distance: EntityPageCollapse.distance)
            .background(Color.kuroBackground)
            .kuroJourneyChrome(title: title, collapseProgress: collapse.wrappedValue)
    }
}

// MARK: - Character page

struct CharacterDetailSheet: View {
    let character: Character
    @Environment(CatalogStore.self) private var catalog
    @State private var works: [Media] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating
    @State private var mediaFilter: CharacterMediaFilter = .all
    @State private var collapse: CGFloat = 0

    private var name: String { character.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman) }

    private var availableMediaFilters: [CharacterMediaFilter] {
        var filters: [CharacterMediaFilter] = [.all]
        if works.contains(where: { $0.kind == .anime }) { filters.append(.anime) }
        if works.contains(where: { $0.kind == .manga }) { filters.append(.manga) }
        return filters
    }

    private var filteredWorks: [Media] {
        works.filter { EntityWorks.matches($0.kind, filter: mediaFilter) }
    }

    private var sortedWorks: [Media] {
        switch sortMode {
        case .rating:
            return filteredWorks.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .year:
            let yearVal: (Media) -> Int = { Int($0.year) ?? 0 }
            return filteredWorks.sorted { yearVal($0) > yearVal($1) }
        case .era:
            return filteredWorks.sorted {
                let lhsEra = EntityEraBucket.from(yearString: $0.year).rawValue
                let rhsEra = EntityEraBucket.from(yearString: $1.year).rawValue
                if lhsEra != rhsEra { return lhsEra > rhsEra }
                return (Int($0.year) ?? 0) > (Int($1.year) ?? 0)
            }
        }
    }

    var body: some View {
        KuroJourneyAwareStack {
            ScrollView {
                VStack(spacing: KuroSpacing.lg) {
                    EntityHeroSection(
                        imageURL: character.imageLarge,
                        isCircle: true,
                        name: name,
                        nameNative: character.nameNative,
                        metadataLines: characterMetadata
                    )

                    EntitySectionLead(text: KuroLocale.text("Browse appearances by medium, rating, year or era.", "Auftritte nach Medium, Wertung, Jahr oder Epoche durchsehen."))

                    if availableMediaFilters.count > 1 {
                        EntityFilterBar(
                            options: availableMediaFilters,
                            selected: mediaFilter
                        ) { option in
                            mediaFilter = option
                        }
                    }

                    EntityWorksRail(
                        title: KuroLocale.text("Appears in", "Auftritte"),
                        subtitle: mediaFilter == .all
                            ? KuroLocale.text("Across anime and manga", "In Anime und Manga")
                            : KuroLocale.text("Filtered by medium", "Nach Medium gefiltert"),
                        items: sortedWorks.map { (media: $0, role: nil as String?) },
                        isLoading: isLoading,
                        sortMode: $sortMode
                    )
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroSpacing.lg)
            }
            .entityJourneyPage(title: name, collapse: $collapse, start: EntityPageCollapse.portraitStart)
        }
        .task {
            // Back to this page keeps what it loaded (no "Loading…" flash, no second read).
            guard isLoading else { return }
            works = await catalog.fetchMediaByCharacter(characterId: character.id)
            isLoading = false
        }
        // Forwards to the journey (pushes); outside one, the work cards open a new journey here.
        .routePresenter()
    }

    private var characterMetadata: [String] {
        var lines: [String] = []
        if let gender = character.gender, !gender.isEmpty {
            switch gender.lowercased() {
            case "male": lines.append(KuroLocale.text("MALE", "MÄNNLICH"))
            case "female": lines.append(KuroLocale.text("FEMALE", "WEIBLICH"))
            case "non-binary": lines.append(KuroLocale.text("NON-BINARY", "NICHTBINÄR"))
            default: lines.append(gender.uppercased())
            }
        }
        if let age = character.age, !age.isEmpty {
            lines.append(KuroLocale.text("AGE \(age)", "ALTER \(age)"))
        }
        return lines
    }
}

// MARK: - Staff page

struct StaffDetailSheet: View {
    let staff: Staff
    @Environment(CatalogStore.self) private var catalog
    @State private var works: [(media: Media, role: String)] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating
    @State private var roleFilter: StaffRoleFilter = .all
    @State private var mediaFilter: CharacterMediaFilter = .all
    @State private var collapse: CGFloat = 0

    private var name: String { staff.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman) }

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

    private var filteredWorks: [(media: Media, role: String)] {
        guard roleFilter != .all else { return mediumFilteredWorks }
        return mediumFilteredWorks.filter { StaffRoleFilter.from(role: $0.role) == roleFilter }
    }

    private var sortedWorks: [(media: Media, role: String)] {
        switch sortMode {
        case .rating:
            return filteredWorks.sorted { ($0.media.rating ?? 0) > ($1.media.rating ?? 0) }
        case .year:
            let yearVal: ((media: Media, role: String)) -> Int = { Int($0.media.year) ?? 0 }
            return filteredWorks.sorted { yearVal($0) > yearVal($1) }
        case .era:
            return filteredWorks.sorted {
                let lhsEra = EntityEraBucket.from(yearString: $0.media.year).rawValue
                let rhsEra = EntityEraBucket.from(yearString: $1.media.year).rawValue
                if lhsEra != rhsEra { return lhsEra > rhsEra }
                return (Int($0.media.year) ?? 0) > (Int($1.media.year) ?? 0)
            }
        }
    }

    private var railSubtitle: String {
        if roleFilter != .all { return KuroLocale.text("Filtered by role", "Nach Rolle gefiltert") }
        switch mediaFilter {
        case .all: return KuroLocale.text("All credited anime and manga work", "Alle Anime und Manga mit Nennung")
        case .anime: return KuroLocale.text("Credited anime work", "Anime mit Nennung")
        case .manga: return KuroLocale.text("Credited manga work", "Manga mit Nennung")
        }
    }

    var body: some View {
        KuroJourneyAwareStack {
            ScrollView {
                VStack(spacing: KuroSpacing.lg) {
                    EntityHeroSection(
                        imageURL: staff.imageLarge,
                        isCircle: true,
                        name: name,
                        nameNative: staff.nameNative,
                        metadataLines: [],
                        occupations: staff.primaryOccupations
                    )

                    EntitySectionLead(text: KuroLocale.text("Filter this filmography by medium, craft, rating, year or era.", "Filmografie nach Medium, Bereich, Wertung, Jahr oder Epoche filtern."))

                    if !availableMediaFilters.isEmpty {
                        EntityFilterBar(
                            options: availableMediaFilters,
                            selected: mediaFilter
                        ) { option in
                            mediaFilter = option
                            // A role the new medium does not have would leave the rail empty.
                            if !availableRoleFilters.contains(roleFilter) { roleFilter = .all }
                        }
                    }

                    if availableRoleFilters.count > 1 {
                        EntityFilterBar(
                            options: availableRoleFilters,
                            selected: roleFilter
                        ) { option in
                            roleFilter = option
                        }
                    }

                    EntityWorksRail(
                        title: KuroLocale.text("Filmography", "Filmografie"),
                        subtitle: railSubtitle,
                        items: sortedWorks.map { (media: $0.media, role: $0.role as String?) },
                        isLoading: isLoading,
                        sortMode: $sortMode
                    )
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroSpacing.lg)
            }
            .entityJourneyPage(title: name, collapse: $collapse, start: EntityPageCollapse.portraitStart)
        }
        .task {
            guard isLoading else { return }
            // Anime (`anime_staff`) and manga (`manga_staff`): an "Original work" credit reaches the manga.
            works = await catalog.fetchStaffWorks(staffId: staff.id)
            isLoading = false
        }
        .routePresenter()
    }
}

// MARK: - Author page

struct AuthorDetailSheet: View {
    let author: Author
    @Environment(CatalogStore.self) private var catalog
    @State private var works: [(media: Media, role: String)] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating
    @State private var roleFilter: AuthorRoleFilter = .all
    @State private var collapse: CGFloat = 0

    private var name: String { author.nameFull ?? DetailCopy.unknown(german: KuroLocale.isGerman) }

    private var availableRoleFilters: [AuthorRoleFilter] {
        let categories = Set(works.compactMap { AuthorRoleFilter.from(role: $0.role) })
        return [.all] + AuthorRoleFilter.allCases.filter { $0 != .all && categories.contains($0) }
    }

    private var filteredWorks: [(media: Media, role: String)] {
        guard roleFilter != .all else { return works }
        return works.filter { AuthorRoleFilter.from(role: $0.role) == roleFilter }
    }

    private var sortedWorks: [(media: Media, role: String)] {
        switch sortMode {
        case .rating:
            return filteredWorks.sorted { ($0.media.rating ?? 0) > ($1.media.rating ?? 0) }
        case .year:
            let yearVal: ((media: Media, role: String)) -> Int = { Int($0.media.year) ?? 0 }
            return filteredWorks.sorted { yearVal($0) > yearVal($1) }
        case .era:
            return filteredWorks.sorted {
                let lhsEra = EntityEraBucket.from(yearString: $0.media.year).rawValue
                let rhsEra = EntityEraBucket.from(yearString: $1.media.year).rawValue
                if lhsEra != rhsEra { return lhsEra > rhsEra }
                return (Int($0.media.year) ?? 0) > (Int($1.media.year) ?? 0)
            }
        }
    }

    var body: some View {
        KuroJourneyAwareStack {
            ScrollView {
                VStack(spacing: KuroSpacing.lg) {
                    EntityHeroSection(
                        imageURL: author.imageLarge,
                        isCircle: true,
                        name: name,
                        nameNative: author.nameNative,
                        metadataLines: []
                    )

                    EntitySectionLead(text: KuroLocale.text("Browse works by role, rating, year or era.", "Werke nach Rolle, Wertung, Jahr oder Epoche durchsehen."))

                    if availableRoleFilters.count > 1 {
                        EntityFilterBar(
                            options: availableRoleFilters,
                            selected: roleFilter
                        ) { option in
                            roleFilter = option
                        }
                    }

                    EntityWorksRail(
                        title: KuroLocale.text("Works", "Werke"),
                        subtitle: roleFilter == .all
                            ? KuroLocale.text("Story, art and complete works", "Geschichte, Zeichnungen und ganze Werke")
                            : KuroLocale.text("Filtered by author role", "Nach Autorenrolle gefiltert"),
                        items: sortedWorks.map { (media: $0.media, role: $0.role as String?) },
                        isLoading: isLoading,
                        sortMode: $sortMode
                    )
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroSpacing.lg)
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
    @State private var works: [Media] = []
    @State private var isLoading = true
    @State private var sortMode: EntitySortMode = .rating
    @State private var collapse: CGFloat = 0

    private var name: String { studio.name ?? DetailCopy.unknown(german: KuroLocale.isGerman) }

    private var sortedWorks: [Media] {
        switch sortMode {
        case .rating:
            return works.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        case .year:
            let yearVal: (Media) -> Int = { Int($0.year) ?? 0 }
            return works.sorted { yearVal($0) > yearVal($1) }
        case .era:
            return works.sorted {
                let lhsEra = EntityEraBucket.from(yearString: $0.year).rawValue
                let rhsEra = EntityEraBucket.from(yearString: $1.year).rawValue
                if lhsEra != rhsEra { return lhsEra > rhsEra }
                return (Int($0.year) ?? 0) > (Int($1.year) ?? 0)
            }
        }
    }

    var body: some View {
        KuroJourneyAwareStack {
            ScrollView {
                VStack(spacing: KuroSpacing.lg) {
                    VStack(spacing: KuroSpacing.sm) {
                        Text(name.uppercased())
                            .font(.kuroDisplay())
                            .foregroundColor(.kuroBlack80)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        if studio.isAnimationStudio == true {
                            Text(KuroLocale.text("ANIMATION STUDIO", "ANIMATIONSSTUDIO"))
                                .font(.kuroMicro(weight: .medium))
                                .tracking(1.4)
                                .foregroundColor(.kuroTextSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.kuroBlack06)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, KuroSpacing.lg)

                    EntitySectionLead(text: KuroLocale.text("The studio's work by rating, year or era.", "Die Werke des Studios nach Wertung, Jahr oder Epoche."))

                    EntityWorksRail(
                        title: KuroLocale.text("Productions", "Produktionen"),
                        subtitle: KuroLocale.text("Best-known productions", "Bekannteste Produktionen"),
                        items: sortedWorks.map { (media: $0, role: nil as String?) },
                        isLoading: isLoading,
                        sortMode: $sortMode
                    )
                }
                .padding(.horizontal, KuroDesignSpacing.padding)
                .padding(.top, KuroJourneyChrome.barHeight)
                .padding(.bottom, KuroSpacing.lg)
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

// MARK: - Shared Entity Hero Section

struct EntityHeroSection: View {
    let imageURL: String?
    var isCircle: Bool = true
    let name: String
    let nameNative: String?
    var metadataLines: [String] = []
    var occupations: [String]? = nil

    var body: some View {
        VStack(spacing: KuroSpacing.md) {
            if let urlStr = imageURL, let url = URL(string: urlStr) {
                KuroCachedAsyncImage(url: url, maxPixelSize: 120) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        heroPlaceholder
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.kuroBlack08, lineWidth: 0.5))
            } else {
                heroPlaceholder
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            }

            VStack(spacing: 4) {
                Text(name)
                    .font(.kuroHeadline())
                    .foregroundColor(.kuroBlack80)
                    .multilineTextAlignment(.center)

                if let native = nameNative, !native.isEmpty {
                    Text(native)
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                }

                if !metadataLines.isEmpty {
                    Text(metadataLines.joined(separator: " · "))
                        .font(.kuroMicro(weight: .light))
                        .tracking(1.0)
                        .foregroundColor(.kuroTextSecondary)
                }

                if let occupations, !occupations.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(occupations.prefix(3), id: \.self) { occ in
                            Text(occ.uppercased())
                                .font(.kuroMicro(weight: .medium))
                                .tracking(0.8)
                                .foregroundColor(.kuroTextSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(Color.kuroBlack06)
                                )
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, KuroSpacing.lg)
    }

    private var heroPlaceholder: some View {
        Circle()
            .fill(Color.kuroBlack06)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.kuroCustom(36, weight: .light, maxSize: 58))
                    .foregroundColor(.kuroBlack20)
            )
    }
}

// MARK: - Shared Entity Works Rail

struct EntityWorksRail: View {
    let title: String
    var subtitle: String? = nil
    let items: [(media: Media, role: String?)]
    let isLoading: Bool
    @Binding var sortMode: EntitySortMode

    private var cardWidth: CGFloat { 110 }
    private var identifiedItems: [(id: String, media: Media, role: String?)] {
        items.enumerated().map { index, item in
            (
                id: EntityWorkIdentity.make(media: item.media, role: item.role, index: index),
                media: item.media,
                role: item.role
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KuroSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.kuroCaption(weight: .semibold))
                        .tracking(1.6)
                        .textCase(.uppercase)
                        .foregroundColor(.kuroBlack80)
                        .accessibilityAddTraits(.isHeader)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.kuroMicro(weight: .regular))
                            .tracking(0.8)
                            .foregroundColor(.kuroTextTertiary)
                    }
                }

                Spacer()

                HStack(spacing: 0) {
                    ForEach(EntitySortMode.allCases, id: \.self) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            Text(mode.title)
                                .font(.kuroMicro(weight: sortMode == mode ? .semibold : .regular))
                                .tracking(1.0)
                                .textCase(.uppercase)
                                .foregroundColor(sortMode == mode ? .kuroBlack80 : .kuroTextTertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(sortMode == mode ? .isSelected : [])
                    }
                }
                .background(
                    Capsule().fill(Color.kuroBlack04)
                )
            }

            if isLoading {
                HStack(spacing: 8) {
                    KuroBusyMark(width: 24)
                    Text(KuroLocale.text("Loading…", "Wird geladen …"))
                        .font(.kuroCaption(weight: .light))
                        .foregroundColor(.kuroTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, KuroSpacing.lg)
            } else if items.isEmpty {
                Text(KuroLocale.text("No works found", "Keine Werke gefunden"))
                    .font(.kuroCaption(weight: .light))
                    .foregroundColor(.kuroInkQuiet)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, KuroSpacing.lg)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(identifiedItems, id: \.id) { item in
                            EntityWorkCard(media: item.media, role: item.role, width: cardWidth)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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

struct EntityFilterBar<Option: Hashable & EntityOptionTitled>: View {
    let options: [Option]
    let selected: Option
    let onSelect: (Option) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Text(option.title)
                            .font(.kuroMicro(weight: selected == option ? .semibold : .regular))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundColor(selected == option ? .white : .kuroBlack80)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selected == option ? Color.black : Color.kuroBlack04)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Entity Work Card (wraps KuroCompactCard + optional role subtitle)

struct EntityWorkCard: View {
    let media: Media
    let role: String?
    var width: CGFloat = 110

    var body: some View {
        VStack(spacing: 4) {
            KuroCompactCard(media: media, width: width)

            if let role, !role.isEmpty {
                Text(role.uppercased())
                    .font(.kuroCustom(8, weight: .regular, maxSize: 13))
                    .tracking(0.8)
                    .foregroundColor(.kuroTextTertiary)
                    .lineLimit(1)
                    .frame(width: width)
            }
        }
    }
}
