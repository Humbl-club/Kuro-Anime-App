import SwiftUI

// MARK: - About > Data sources & credits (spec D11)
// Names every source whose data Kuro shows, what it supplies and a link to it, plus the
// non-affiliation line. Plain hairline rows on white; no logos (brand marks are their owners').
// Navigation contract: pushed inside Profile's journey (Back + edge swipe-back, ✕ collapses the journey);
// the headline scrolls under the compact bar.

struct DataSourcesView: View {
    @State private var collapse: CGFloat = 0

    var body: some View {
        let german = KuroLocale.isGerman
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: KuroDesignSpacing.lg) {
                VStack(alignment: .leading, spacing: KuroDesignSpacing.md) {
                    Text(german ? "Datenquellen und Danksagung." : "Data sources and credits.")
                        .kuroRoleText(.headline)
                        .foregroundStyle(Color.kuroInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Rectangle().fill(Color.kuroInk).frame(width: 46, height: 2)
                    Text(german
                         ? "Kuro zeigt Daten dieser Dienste. Danke an alle, die sie pflegen."
                         : "Kuro shows data from these services. Thank you to everyone who maintains them.")
                        .font(.kuroBody())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(KuroDataSource.all) { source in
                        DataSourceRow(source: source, german: german)
                        Rectangle().fill(Color.kuroHairline).frame(height: 0.5)
                    }
                }

                VStack(alignment: .leading, spacing: KuroDesignSpacing.sm) {
                    Text(german ? "Musik" : "Music")
                        .kuroRoleText(.title)
                        .foregroundStyle(Color.kuroInk)
                        .accessibilityAddTraits(.isHeader)
                    Text(german
                         ? "„Anhören“ öffnet eine Suche in Apple Music oder Spotify. Kuro speichert nichts von dort."
                         : "“Listen” opens a search in Apple Music or Spotify. Kuro stores nothing from them.")
                        .font(.kuroBody())
                        .foregroundStyle(Color.kuroInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(german
                     ? "Kuro ist mit keinem dieser Dienste verbunden. Titel, Bilder und Namen gehören ihren Rechteinhabern."
                     : "Kuro is not affiliated with any of these services. Titles, artwork and names belong to their owners.")
                    .font(.kuroMeta())
                    .foregroundStyle(Color.kuroInkQuiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, KuroDesignSpacing.padding)
            .padding(.top, 64)
            .padding(.bottom, KuroDesignSpacing.xxl)
            .kuroReadableWidth()
        }
        .kuroCollapseTracking($collapse, start: 0, distance: 64)
        .background(Color.kuroCanvasPage.ignoresSafeArea())
        .kuroJourneyChrome(title: ShellJourneyPages.dataSourcesTitle, collapseProgress: collapse)
    }
}

private struct DataSourceRow: View {
    let source: KuroDataSource
    let german: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.name)
                .font(.kuroCustom(15, weight: .medium, relativeTo: .headline, maxSize: 30)).tracking(-0.2)
                .foregroundStyle(Color.kuroInk)
            Text(source.use(german: german))
                .font(.kuroBody())
                .foregroundStyle(Color.kuroInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let url = source.url {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text(source.host)
                            .font(.kuroMeta(weight: .medium))
                            .underline(true, color: Color.kuroInk)
                        Image(systemName: "arrow.up.right")
                            .font(.kuroCustom(11, weight: .medium, relativeTo: .caption1, maxSize: 18))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.kuroInk)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(german ? "\(source.name) öffnen, \(source.host)" : "Open \(source.name), \(source.host)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, KuroDesignSpacing.md)
        .accessibilityElement(children: .contain)
    }
}
