import Foundation
import SwiftUI

// MARK: - Source credit (catalogue Task 16)
// Title pages name the sources that actually supplied the title's published values (`data_sources`, written
// by the catalogue composer) and link where a licence requires it: Anime News Network asks for a credit and a
// link to its encyclopedia on pages that show its data. Pure mapping; no I/O, no view.
// - Unknown codes are never shown. AniList is never named as a source: it is neither a source of the new
//   values nor one Kuro credits (owner decision 2026-11-10). Kuro's own data ("editorial", "composer", "kuro")
//   names no outside source, so a title without any named source shows no line.
// - Wording (L6, spec §7) is the spec's default, "Data: Anime News Network, Wikidata" / "Daten: ...", and is
//   awaiting owner sign-off, and ANN's, before release.

enum DataSourceCredit {

    /// ANN's encyclopedia: the link when a title has no ANN link of its own (spec: a link on every page that
    /// shows ANN data).
    nonisolated static let annEncyclopedia = URL(string: "https://www.animenewsnetwork.com/encyclopedia/")!

    /// The L1 episode provider is not chosen yet (plan gate L1): a neutral name until it is.
    nonisolated static func episodesProviderName(german: Bool) -> String {
        german ? "Episodendaten-Anbieter" : "Episode data provider"
    }

    /// Display name of a source code, or nil for a code that is never credited.
    nonisolated static func displayName(for code: String, german: Bool = false) -> String? {
        switch code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ann": return "Anime News Network"
        case "wikidata": return "Wikidata"
        case "mangaupdates": return "MangaUpdates"
        case "pageviews": return "Wikimedia"
        case "episodes_provider": return episodesProviderName(german: german)
        default: return nil
        }
    }

    /// Credited names in the given order, each once.
    nonisolated static func displayNames(for sources: [String]?, german: Bool = false) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for code in sources ?? [] {
            guard let name = displayName(for: code, german: german), seen.insert(name).inserted else { continue }
            names.append(name)
        }
        return names
    }

    /// "Data: Anime News Network, Wikidata" / "Daten: ...". Nil for an empty or nil list, or when no code names
    /// an outside source.
    nonisolated static func line(for sources: [String]?, german: Bool) -> String? {
        let names = displayNames(for: sources, german: german)
        guard !names.isEmpty else { return nil }
        return (german ? "Daten: " : "Data: ") + names.joined(separator: ", ")
    }

    /// The line only while `catalogue_source_credit_v1` is on.
    nonisolated static func visibleLine(for sources: [String]?, flagOn: Bool, german: Bool) -> String? {
        flagOn ? line(for: sources, german: german) : nil
    }

    nonisolated static func attributedVisible(for sources: [String]?, externalLinks: [ExternalLink], flagOn: Bool, german: Bool) -> AttributedString? {
        flagOn ? attributed(for: sources, externalLinks: externalLinks, german: german) : nil
    }

    /// The link of a source's credit. ANN: the title's own ANN link from `external_links` (matched by site
    /// name or by host, https only), else the encyclopedia. Other sources carry no link.
    nonisolated static func link(source: String, externalLinks: [ExternalLink]) -> URL? {
        guard source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ann" else { return nil }
        for link in externalLinks where !link.isDisabled {
            guard let url = URL(string: link.url), url.scheme?.lowercased() == "https",
                  let host = url.host?.lowercased(),
                  host == "animenewsnetwork.com" || host.hasSuffix(".animenewsnetwork.com") else { continue }
            return url
        }
        return annEncyclopedia
    }

    /// The credit as one attributed line, with ANN's name linked. Nil when there is no line.
    nonisolated static func attributed(for sources: [String]?, externalLinks: [ExternalLink], german: Bool) -> AttributedString? {
        guard let line = line(for: sources, german: german) else { return nil }
        var text = AttributedString(line)
        if let url = link(source: "ann", externalLinks: externalLinks),
           displayNames(for: sources, german: german).contains("Anime News Network"),
           let range = text.range(of: "Anime News Network") {
            text[range].link = url
            text[range].underlineStyle = .single
        }
        return text
    }
}
