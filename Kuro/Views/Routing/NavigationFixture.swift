import Foundation
import SwiftUI

#if DEBUG
// MARK: - Navigation fixture journey (DEBUG only)
//
// The navigation contract's UI tests (KuroUITests/NavigationContractUITests.swift, spec §5) run with
// `--kuro-fixture-host` (no network: every request fails locally), so no catalogue page can load real
// data. `--kuro-nav-fixture` opens, right after launch, a root journey built from REAL navigation parts
// (`JourneyHost`, `.kuroJourneyChrome`, `KuroInteractivePopEnabler`, `\.kuroRoutes`, the tool slot) over
// fixture pages:
//   - "Fixture level N" pages: a tall scroll body (rows `navfixture.row.<k>`), and buttons that push the
//     next level (`navfixture.next`), open the current level again (`navfixture.again`, N5: nothing
//     happens), open level 1 (`navfixture.first`, N5: pops back to it) and push a fixture title
//     (`navfixture.title`);
//   - the fixture title: the real `AnimeDetailPage` over preview content (characters push the real
//     character page; "Add to your list" opens the real tracking editor tool).
// Compiled for DEBUG only; release builds never contain it.

enum NavigationFixture {
    static let launchArgument = "--kuro-nav-fixture"

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    /// The fixture journey opens once per process (a rebuilt root never reopens it over a deep link).
    @MainActor static var didOpen = false

    /// Fixture level `n` (1 is the journey's first page).
    static func level(_ n: Int) -> JourneyPage {
        let title = KuroLocale.text("Fixture level \(n)", "Testebene \(n)")
        return .custom(AnyJourneyPage(id: "navfixture:level:\(n)", title: title) {
            NavigationFixturePage(level: n, title: title)
        })
    }

    /// The fixture title (a real anime detail page over preview content).
    static var titlePage: JourneyPage {
        .custom(AnyJourneyPage(id: "navfixture:title", title: "Fixture Title") {
            if let anime = fixtureAnime {
                AnimeDetailPage(anime: anime, preview: fixtureContent)
            } else {
                Text(verbatim: "Fixture Title")
            }
        })
    }

    private static var fixtureAnime: Anime? {
        let object: [String: Any] = [
            "id": 990_001, "is_adult": false, "genres": ["Drama"], "created_at": 0, "updated_at": 0,
            "title_english": "Fixture Title", "format": "TV", "status": "FINISHED", "episodes": 12,
            "season_year": 2024, "cover_image_color": "#2b3a55",
            "description": String(repeating: "A long fixture synopsis line that keeps the story folded. ", count: 24)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(Anime.self, from: data)
    }

    private static var fixtureContent: AnimeDetailContent {
        var content = AnimeDetailContent()
        content.characters = (1...4).map { index in
            (character: Character(id: 990_100 + index, anilistId: nil, nameFull: "Fixture Character \(index)",
                                  nameNative: nil, imageLarge: nil, description: nil, gender: nil, age: nil),
             role: "MAIN")
        }
        content.songs = (1...6).map {
            ThemeSong(kind: $0 % 2 == 0 ? .ending : .opening, sequence: $0, title: "Fixture Song \($0)",
                      artist: "Fixture Artist", episodes: "1–12")
        }
        return content
    }
}

/// One fixture level: a tall scroll body under the journey chrome (Back when pushed, ✕ always).
struct NavigationFixturePage: View {
    let level: Int
    let title: String
    @Environment(\.kuroRoutes) private var routes

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KuroSpacing.sm) {
                Text(title)
                    .font(.kuroTitle())
                    .foregroundStyle(Color.kuroInk)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("navfixture.level.\(level)")
                ForEach(1...30, id: \.self) { row in
                    Text(KuroLocale.text("Row \(row)", "Zeile \(row)"))
                        .font(.kuroBody())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .accessibilityIdentifier("navfixture.row.\(row)")
                }
                fixtureButton(KuroLocale.text("Next level", "Nächste Ebene"), id: "navfixture.next") {
                    routes.openPage(NavigationFixture.level(level + 1))
                }
                fixtureButton(KuroLocale.text("This level again", "Diese Ebene erneut"), id: "navfixture.again") {
                    routes.openPage(NavigationFixture.level(level))
                }
                fixtureButton(KuroLocale.text("Level 1 again", "Ebene 1 erneut"), id: "navfixture.first") {
                    routes.openPage(NavigationFixture.level(1))
                }
                fixtureButton(KuroLocale.text("Fixture title", "Testtitel"), id: "navfixture.title") {
                    routes.openPage(NavigationFixture.titlePage)
                }
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.top, KuroJourneyChrome.barHeight + KuroSpacing.md)
            .padding(.bottom, KuroSpacing.lg)
        }
        .background(Color.kuroCanvasPage)
        // No artwork: the compact bar (with the title) from the start.
        .kuroJourneyChrome(title: title, collapseProgress: 1)
    }

    private func fixtureButton(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.kuroBody(weight: .medium))
                .foregroundStyle(Color.kuroInk)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(KuroPressStyle())
        .accessibilityIdentifier(id)
    }
}
#endif
