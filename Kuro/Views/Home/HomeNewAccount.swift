import KuroCore
import KuroLibrary
import SwiftUI

// MARK: - New-account Home (prototype-fidelity pass, plan Task 8; amendment 5)
// The feed block of the prototype's new-account Home (`ref-home-new-{anime,manga}-{390,320,430}.png`,
// PROTOTYPE_SPEC.md §4 "New-account Home"): ＋, "Your stories belong here.", "Import your list to
// bring your place with you." and "Explore Taste ←". Below the prototype's block, in its language,
// the owner-approved additions (spec §5.3, amendment 5): the Import action, then "A first favourite."
// with up to four real starter titles (story cards with a one-tap Plan key, the same cards as Taste).
//
// Integration (embedded by `HomeView.newAccountShelf` since Task 10):
// - It is the feed only. The medium switch, the "YOUR COLLECTION / Begin here." opening line
//   (`HomeOpeningLine`, Task 4) and the page footer (`HomeFooter`, Task 5) belong to HomeView; the
//   coming-up glance is hidden for a new account (PROTOTYPE_SPEC §8.3).
// - Environment: `DiscoveryStore`, `LibraryStore`, `LibraryActions`, `\.kuroRoutes` (the pager's).
// - `onImport` opens the import chooser (HomeView's `showImportChooser`); `onExploreTaste` moves the
//   pager to Taste.
// - The picks read only `DiscoveryStore.ensureDiscoverBundle()` (the launch's one bundle read, shared
//   with Discover and Taste; never a forced reload). A failed or empty read hides the picks row; the
//   block above stands on its own. Each pick is then completed from the catalogue
//   (`TasteCardDetails`: the premise under its title, as on Taste).
// - The first pick's cover fills the selected medium word (`onLeadArt`), the same rule as Taste
//   (amendment 16), so the switch reads the same on both pages.
// - The mount condition is latched. The first one-tap Plan here adds the account's first title, so a
//   live `allEntries.isEmpty` check would unmount this block under the user's finger. The pager
//   (`ContentView`) decides "new account" once, when the Library first reports `.loaded` with no entries
//   (`TastePageCopy.latchNewAccount`), keeps it until the Library leaves `.loaded` (sign-out, account
//   switch), and `HomeShelfPolicy.showsNewAccount` keeps the block until a title is in progress.
// - Plan results: `HomeView` installs `.tastePlanHost(controller)` outside its ScrollView, so the toast
//   with Undo sits at the screen foot. Without a host (fixtures), this block installs its own, and the
//   toast is drawn at the foot of the block instead.

struct HomeNewAccount: View {
    let medium: MediaKind
    let onImport: () -> Void
    let onExploreTaste: () -> Void
    /// The first pick's cover per medium, for the selected medium word (nil: none yet).
    let onLeadArt: (MediaKind, String?) -> Void

    init(medium: MediaKind, onImport: @escaping () -> Void, onExploreTaste: @escaping () -> Void,
         onLeadArt: @escaping (MediaKind, String?) -> Void = { _, _ in }) {
        self.medium = medium
        self.onImport = onImport
        self.onExploreTaste = onExploreTaste
        self.onLeadArt = onLeadArt
    }

    @Environment(DiscoveryStore.self) private var discovery
    /// The picks' premises (`TasteCardDetails`); nil in fixtures without one.
    @Environment(CatalogStore.self) private var catalog: CatalogStore?
    @Environment(LibraryStore.self) private var library
    /// The Home page's Plan controller, when HomeView installed one (`tastePlanHost`).
    @Environment(TastePlanController.self) private var hostPlans: TastePlanController?
    @State private var ownPlans = TastePlanController()

    /// The loaded picks per medium (empty until the bundle answers; stays empty when it fails).
    @State private var picks: [MediaKind: [TasteCard]] = [:]
    /// The block's own width (0 until the first layout), for the prototype's small-phone values.
    @State private var width: CGFloat = 0

    var body: some View {
        let content = HomeNewAccountContent(medium: medium, picks: picks[medium] ?? [], width: width,
                                            onImport: onImport, onExploreTaste: onExploreTaste)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: medium) { await loadPicks(for: medium) }
        if hostPlans != nil {
            content
        } else {
            content.tastePlanHost(ownPlans)
        }
    }

    private func loadPicks(for medium: MediaKind) async {
        if let loaded = picks[medium] {
            onLeadArt(medium, loaded.first?.media.imageURL)
            return
        }
        guard let bundle = await discovery.ensureDiscoverBundle() else { return }
        let cards: [TasteCard] = medium == .anime
            ? (bundle.anime.newToYou + bundle.anime.essentials).map(TasteCard.init(anime:))
            : (bundle.manga.newToYou + bundle.manga.essentials).map(TasteCard.init(manga:))
        let tracked = Set(cards.map(\.key).filter { library.isTracked($0) })
        let chosen = FirstFavouritePicks.pick(from: cards, max: HomeNewAccountCopy.pickCount(medium), excluding: tracked)
        onLeadArt(medium, chosen.first?.media.imageURL)
        let filled = await TasteCardDetails.hydrate(chosen, catalog: catalog)
        guard !Task.isCancelled else { return }
        picks[medium] = filled
    }
}

/// The new-account feed as values (also the fixture renders): the invitation block, then the picks.
struct HomeNewAccountContent: View {
    let medium: MediaKind
    let picks: [TasteCard]
    let width: CGFloat
    let onImport: () -> Void
    let onExploreTaste: () -> Void

    @Environment(\.tasteGerman) private var germanOverride

    private var german: Bool { germanOverride ?? KuroLocale.isGerman }
    private var metrics: TasteMetrics { TasteMetrics(pageWidth: width) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FirstRunInvitation(
                headline: HomeNewAccountCopy.headline(german: german),
                line: HomeNewAccountCopy.line(german: german),
                bottomPadding: picks.isEmpty ? 70 : 26
            ) {
                KuroOutlineButton(HomeNewAccountCopy.exploreTaste(german: german), action: onExploreTaste)
                    .accessibilityLabel(HomeNewAccountCopy.exploreTasteSpoken(german: german))
                KuroOutlineButton(HomeNewAccountCopy.importList(german: german), action: onImport)
            }

            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    TasteSectionHeading(title: TastePageCopy.firstFavourite(german: german),
                                        medium: medium, metrics: metrics)
                    TasteStoryList(cards: picks, medium: medium, metrics: metrics)
                }
                .padding(.horizontal, metrics.paperGutter)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The new-account Home's words, EN/DE (PROTOTYPE_SPEC.md §7.1).
nonisolated enum HomeNewAccountCopy {
    static func headline(german: Bool) -> String {
        german ? "Hier gehören deine Geschichten hin." : "Your stories belong here."
    }

    static func line(german: Bool) -> String {
        german ? "Importiere deine Liste und nimm deinen Stand mit." : "Import your list to bring your place with you."
    }

    /// The prototype's button: Taste is the page to the left, so the arrow points left.
    static func exploreTaste(german: Bool) -> String {
        german ? "Geschmack entdecken ←" : "Explore Taste ←"
    }

    static func exploreTasteSpoken(german: Bool) -> String {
        german ? "Geschmack entdecken" : "Explore Taste"
    }

    static func importList(german: Bool) -> String {
        german ? "Liste importieren" : "Import your list"
    }

    /// Starter titles under "A first favourite.": anime one landscape and two portrait cards; manga
    /// two rows of the two-column grid (spec §5.3: 3–4).
    static func pickCount(_ medium: MediaKind) -> Int {
        medium == .anime ? 3 : 4
    }
}

// MARK: - The invitation block (shared with the Collection empty state)

/// The prototype's `.empty-home` block: a light ＋, a bold headline, one muted line and the actions,
/// centred. SF 42 w200 `#858b84` ＋ (26 below), SF 24 w700 −0.8 headline, SF 13/18.2 `#646b65` line at
/// most 24ch wide (14 above, 24 below), 44 pt outline buttons; padding 50 / 25 / 70.
struct FirstRunInvitation<Actions: View>: View {
    let headline: String
    let line: String?
    var bottomPadding: CGFloat = 70
    let actions: Actions

    init(headline: String, line: String?, bottomPadding: CGFloat = 70, @ViewBuilder actions: () -> Actions) {
        self.headline = headline
        self.line = line
        self.bottomPadding = bottomPadding
        self.actions = actions()
    }

    /// `max-width: 24ch` at 13 pt (the "0" advance of SF 13 is about 8.2 pt), scaled with the text.
    @ScaledMetric(relativeTo: .footnote) private var lineWidth: CGFloat = 197

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "＋")
                .font(.kuroCustom(42, weight: .thin, relativeTo: .largeTitle, maxSize: 64))
                .foregroundStyle(Color(hex: "858B84"))
                // The prototype's 58.8 pt line box around the 42 pt glyph.
                .padding(.vertical, 4)
                .padding(.bottom, 26)
                .accessibilityHidden(true)
            Text(headline)
                .font(.kuroCustom(24, weight: .bold, relativeTo: .title2, maxSize: 44))
                .tracking(-0.8)
                .foregroundStyle(Color.kuroInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // The prototype's 33.6 pt line box (SF 24 sets 28.6).
                .padding(.vertical, 2.5)
                .accessibilityAddTraits(.isHeader)
            if let line {
                Text(line)
                    .font(.kuroCustom(13, relativeTo: .footnote, maxSize: 26))
                    .lineSpacing(2.7)
                    .foregroundStyle(Color(hex: "646B65"))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: lineWidth)
                    // 14 pt margin plus the 18.2 pt line box's leading above the first line (SF 13 sets
                    // 15.5; measured, the glyphs land at the reference's y).
                    .padding(.top, 16.35)
            }
            VStack(spacing: 10) { actions }
                // 24 pt margin plus the line box's leading below the last line.
                .padding(.top, line == nil ? 24 : 24.35)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 25)
        .padding(.top, 50)
        .padding(.bottom, bottomPadding)
        .accessibilityElement(children: .contain)
    }
}
