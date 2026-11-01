import Foundation

// MARK: - Provider link builders (pure policy)
// The sheet item and the pure builders behind the detail pages' watch/read links: verified items
// (ranked, resolved against the catalog links), catalog items, the preferred primary, the provider
// matching/ranking keys and the availability status caption. Used by the ProviderAvailability owner
// (ProviderAvailabilityStore+DetailLinks.swift) to build one `ProviderLinkSnapshot`, and rendered by
// Kuro/Views/DetailPages/ProviderLinkViews.swift. No SwiftUI and no SDK here.


struct ProviderSheetItem: Identifiable, Equatable {
    let id: String
    let title: String
    let url: String
    let subtitle: String?
    let isVerified: Bool

    /// The badge on the sheet card (user-facing; no internal words such as "verified", rulebook §9).
    var badgeText: String {
        isVerified ? KuroLocale.text("Matched", "Passend") : KuroLocale.text("Provider catalogue", "Anbieterkatalog")
    }
    var accessibilityLabel: String {
        isVerified
            ? KuroLocale.text("Open \(title), matched to this title", "\(title) öffnen, passend zu diesem Titel")
            : KuroLocale.text("Open \(title) from the provider's catalogue", "\(title) aus dem Katalog des Anbieters öffnen")
    }
}

func makeVerifiedProviderItems(
    providers: [ProviderAvailabilityProvider],
    fallbackLinks: [ExternalLink],
    ranking: [String],
    preferredAudioLang: String?,
    preferredSubtitleLang: String?,
    originalLanguage: String?
) -> [ProviderSheetItem] {
    var seen = Set<String>()
    return providers
        .sorted { lhs, rhs in
            let left = providerRankingIndex(for: lhs.displayName, slug: lhs.slug, ranking: ranking)
            let right = providerRankingIndex(for: rhs.displayName, slug: rhs.slug, ranking: ranking)
            if left != right { return left < right }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        .compactMap { provider in
            let resolvedURL = provider.url ?? fallbackLinks.first(where: { providerMatches(site: $0.site, provider: provider) })?.url
            guard let resolvedURL, !resolvedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let key = "verified-\(provider.slug)"
            let matchedSubtitle = KuroLocale.text("Matched to this title.", "Zu diesem Titel passend.")
            guard seen.insert(key).inserted else { return nil }
            let note = ProviderAvailabilityNoteBuilder.bestNote(
                from: [provider],
                preferredAudioLang: preferredAudioLang,
                preferredSubtitleLang: preferredSubtitleLang,
                originalLanguage: originalLanguage
            )?.displayText
            return ProviderSheetItem(
                id: key,
                title: provider.displayName,
                url: resolvedURL,
                subtitle: note.map { "\(matchedSubtitle) \($0)" } ?? matchedSubtitle,
                isVerified: true
            )
        }
}

func makeCatalogProviderItems(
    from links: [ExternalLink],
    ranking: [String],
    fallbackSubtitle: String
) -> [ProviderSheetItem] {
    links
        .sorted { lhs, rhs in
            let left = providerRankingIndex(for: lhs.site, slug: nil, ranking: ranking)
            let right = providerRankingIndex(for: rhs.site, slug: nil, ranking: ranking)
            if left != right { return left < right }
            return (lhs.site ?? "").localizedCaseInsensitiveCompare(rhs.site ?? "") == .orderedAscending
        }
        .map { link in
            ProviderSheetItem(
                id: "catalog-\(link.id)",
                title: link.site ?? KuroLocale.text("Provider", "Anbieter"),
                url: link.url,
                subtitle: fallbackSubtitle,
                isVerified: false
            )
        }
}

func preferredPrimaryProviderItem(
    from items: [ProviderSheetItem],
    preferredSite: String?
) -> ProviderSheetItem? {
    guard let preferredSite else { return nil }
    let normalizedSite = normalizedProviderKey(preferredSite)
    return items.first { normalizedProviderKey($0.title) == normalizedSite }
}

func providerMatches(site: String?, provider: ProviderAvailabilityProvider) -> Bool {
    let siteKey = normalizedProviderKey(site)
    guard !siteKey.isEmpty else { return false }
    let displayKey = normalizedProviderKey(provider.displayName)
    let slugKey = normalizedProviderKey(provider.slug)
    return siteKey == displayKey || siteKey == slugKey || siteKey.contains(displayKey) || displayKey.contains(siteKey) || siteKey.contains(slugKey) || slugKey.contains(siteKey)
}

func providerRankingIndex(for site: String?, slug: String?, ranking: [String]) -> Int {
    let siteKey = normalizedProviderKey(site)
    let slugKey = normalizedProviderKey(slug)
    return ranking.firstIndex(where: { key in
        let normalized = normalizedProviderKey(key)
        return (!siteKey.isEmpty && (siteKey == normalized || siteKey.contains(normalized) || normalized.contains(siteKey)))
            || (!slugKey.isEmpty && (slugKey == normalized || slugKey.contains(normalized) || normalized.contains(slugKey)))
    }) ?? 999
}

func normalizedProviderKey(_ raw: String?) -> String {
    guard let raw else { return "" }
    let lowered = raw.lowercased()
        .replacingOccurrences(of: "&", with: "and")
        .replacingOccurrences(of: "+", with: "plus")
    let allowed = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
    return allowed
        .split(separator: " ")
        .joined(separator: " ")
}

func providerAvailabilityStatusCaption(
    status: MediaAvailabilityStatus?,
    requestedRefresh: Bool,
    hasVerifiedProviders: Bool
) -> String? {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    formatter.locale = KuroLocale.locale

    if hasVerifiedProviders, let lastRefreshedAt = status?.lastRefreshedAt {
        let when = formatter.localizedString(for: lastRefreshedAt, relativeTo: Date())
        return KuroLocale.text("Checked \(when).", "Geprüft \(when).")
    }
    if requestedRefresh || status?.status.lowercased() == "pending" {
        return KuroLocale.text("Checking where to find it now.", "Wir sehen gerade nach, wo es verfügbar ist.")
    }
    if let lastRefreshedAt = status?.lastRefreshedAt {
        let when = formatter.localizedString(for: lastRefreshedAt, relativeTo: Date())
        return KuroLocale.text("Last checked \(when).", "Zuletzt geprüft \(when).")
    }
    if let nextRefreshAt = status?.nextRefreshAt {
        let when = formatter.localizedString(for: nextRefreshAt, relativeTo: Date())
        return KuroLocale.text("Next check \(when).", "Nächste Prüfung \(when).")
    }
    return nil
}
