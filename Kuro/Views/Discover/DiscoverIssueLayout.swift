import CoreGraphics

// MARK: - Discover issue layout (Discover + Clubs redesign §6.1, §6.5; Home grammar G§7)
// The Discover page's measured literals, in one place so the page and its tests agree. Every value is
// copied from Home (`HomeView`, `HomeSceneCard`, `HomeCalendarCard`, `KuroPosterMediumSwitch`) or from
// the spec's 390 pt drawing; widths always come from the measured container, never the screen.
// `DiscoverLayout` (shared with Browse, Search and Taste) is left as it is: this enum is Discover's own.

nonisolated enum DiscoverIssueLayout {
    // MARK: Page frame

    /// Home's gutter: 20 pt, 16 pt when the measured container is ≤ 330 pt (`HomeView.swift:262-264`).
    static func gutter(container: CGFloat) -> CGFloat {
        container > 0 && container <= 330 ? 16 : 20
    }

    /// The compact column (≤ `KuroMediumSwitch.smallPhoneContainer`, 328 pt): the prototype's small sizes.
    static func isCompact(column: CGFloat) -> Bool {
        column > 0 && column <= 328
    }

    /// Top of the content under the header (Home's 7).
    static let top: CGFloat = 7
    /// Between the opening blocks (opening row → switch is 6; switch → story → glance → contents 12).
    static let openingToSwitch: CGFloat = 6
    static let openingStack: CGFloat = 12
    /// Above the first section after the contents line, then between sections (the calendar's 32).
    static let firstSection: CGFloat = 28
    static let section: CGFloat = 32
    /// Section heading → its content (the calendar heading's 17).
    static let headingToContent: CGFloat = 17
    /// Heading → purpose line, and purpose line → content (usability spec §5.6).
    static let headingToPurpose: CGFloat = 6
    static let purposeToContent: CGFloat = 14
    /// Above the mood keys and above the end block (usability spec §4).
    static let moods: CGFloat = 12
    static let end: CGFloat = 32
    /// Each section claims its shown titles plus this many unclaimed ones as its refill reserve (§5.1).
    static let reserve = 6
    /// At most this many sections on the page; the rest are More lists (R7, D7).
    static let sectionCap = 6

    // MARK: Issue switch

    /// The three-word switch: 28 pt words, 24 pt in the compact column (owner choice §11.5: three
    /// words must fit the SE column without scaling).
    static func switchWordSize(column: CGFloat) -> CGFloat {
        isCompact(column: column) ? 24 : 28
    }

    /// The switch row's minimum height (hairline included).
    static let switchMinHeight: CGFloat = 50

    // MARK: Cover story

    /// Today's pick with a banner: 2.2 : 1 (159 pt tall in the 350 pt column).
    static let coverBannerAspect: CGFloat = 2.2
    /// The feature of a section, and the Hidden gem: Home's scene window, 3.25 : 1 (108 pt at 350).
    static let featureBannerAspect: CGFloat = 3.25

    /// The art window's height for `column` at `aspect`.
    static func artHeight(column: CGFloat, aspect: CGFloat) -> CGFloat {
        guard column > 0, aspect > 0 else { return 0 }
        return (column / aspect).rounded()
    }

    /// The Plan key's column on the material foot (Home's 112 pt progress column, 96 compact). The key
    /// keeps at least this width and grows only as far as its own label needs, so "Plan to watch" and
    /// "Auf deiner Liste" are never cut.
    static func footKeyColumn(compact: Bool) -> CGFloat { compact ? 96 : 112 }

    /// The cover-only spread's cover (manga, or anime without a banner): 132 × 198, 104 × 156 compact.
    static func spreadCover(compact: Bool) -> CGSize {
        compact ? CGSize(width: 104, height: 156) : CGSize(width: 132, height: 198)
    }

    /// The cover-only spread's cap (P14): never taller than this outside accessibility sizes.
    static let spreadMaxHeight: CGFloat = 220

    /// A section feature without a banner: the spread capped at 160 pt (a 2 : 3 cover at that height).
    static let featureSpreadHeight: CGFloat = 160
    static func featureSpreadCover(compact: Bool) -> CGSize {
        let height = compact ? 144 : featureSpreadHeight
        return CGSize(width: (height * 2 / 3).rounded(), height: height)
    }

    /// The spread's height: the cover's, unless the panel's own copy needs more (accessibility sizes).
    static func spreadHeight(cover: CGSize, panelHeight: CGFloat) -> CGFloat {
        max(cover.height, panelHeight)
    }

    // MARK: Sections

    /// Items a feature-plus-trio section shows below its feature: three covers, four on the iPad
    /// column, two at accessibility sizes (two columns).
    static func trioColumns(regularWidth: Bool, accessibility: Bool) -> Int {
        if accessibility { return 2 }
        return regularWidth ? 4 : 3
    }

    /// Trio columns are 14 pt apart.
    static let trioSpacing: CGFloat = 14

    /// One trio cover's width across `column`.
    static func trioCoverWidth(column: CGFloat, columns: Int) -> CGFloat {
        let count = CGFloat(max(1, columns))
        return max(0, ((column - trioSpacing * (count - 1)) / count).rounded(.down))
    }

    /// Rows an index (Essentials, the folded sections) shows before "See all".
    static let indexRows = 5
    /// On the All issue, which carries both media, an index shows three rows (integration review,
    /// rhythm §6.1: the page ran ~3,000 pt against the ~1,900 target). Every title stays one
    /// "See all" away; the Anime and Manga issues keep five. Owner decision recorded in REPORT.md.
    static let allIssueIndexRows = 3
    static func indexRows(onAll: Bool) -> Int { onAll ? allIssueIndexRows : indexRows }
    /// The quiet-row recipe with its minimum height raised to 76.
    static let indexRowMinHeight: CGFloat = 76
    /// The index row's Plan key: at least 96 pt wide (84 compact), growing only for its label.
    static func indexKeyWidth(compact: Bool) -> CGFloat { compact ? 84 : 96 }
    /// The widest an index row's key grows ("Plan to watch" fits; "Auf deiner Liste" scales down).
    static func indexKeyMaxWidth(compact: Bool) -> CGFloat { compact ? 96 : 112 }

    /// The horizontal rails (Trending, Tonight's shelf, Manga new to you on All): covers 14 pt apart,
    /// up to 10, sized by the edge-peek rule (details-songs spec §5.1) so a slice of the next cover
    /// always shows: 100 × 150 at 390 (visible 370), 112 × 168 at 320 and on the iPad column.
    static let railSpacing: CGFloat = KuroRailPeek.spacing
    static let railCap = 10

    /// The rail's cover for a content `column` and page `gutter`: the rail spans the column plus its
    /// trailing gutter (it bleeds to the screen or readable-column edge) and starts at the gutter, so
    /// the visible width is `column + gutter` (§5.1: 390 → 370, 320 → 304, iPad 680 → 660).
    static func railCover(column: CGFloat, gutter: CGFloat) -> CGSize {
        let width = KuroRailPeek.cardWidth(visible: column + gutter)
        return CGSize(width: width, height: KuroRailPeek.coverHeight(width: width))
    }

    /// A contents entry's row (usability spec §5.10).
    static let contentsRow: CGFloat = 44

    /// A section with more items than it shows offers "See all".
    static func offersSeeAll(total: Int, shown: Int) -> Bool { total > shown }
}

