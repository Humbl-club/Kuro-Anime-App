import Foundation

#if canImport(Supabase)

// MARK: - External Links & Streaming Helpers
// Legal watch/read links (public): the title's external links (CatalogStore) filtered to the strict
// legal allowlists and ordered by priority, the viewer's locale language and the provider ranking.

extension ProviderAvailabilityStore {

    private func normalizedLocaleLanguage(_ locale: String?) -> String {
        let source = (locale ?? Locale.current.identifier).lowercased()
        if source.hasPrefix("de") { return "de" }
        return "en"
    }

    func normalizedExternalLanguage(_ raw: String?) -> String {
        let source = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if source.isEmpty { return "unknown" }
        if source.hasPrefix("de") || source.contains("german") || source.contains("deutsch") { return "de" }
        if source.hasPrefix("en") || source.contains("english") { return "en" }
        if source.hasPrefix("ja") || source.contains("japanese") { return "ja" }
        if source.hasPrefix("ko") || source.contains("korean") { return "ko" }
        if source.hasPrefix("zh") || source.contains("chinese") || source.contains("mandarin") { return "zh" }
        return "other"
    }

    private func isAllowedMangaLegalProvider(_ site: String?) -> Bool {
        guard let site, !site.isEmpty else { return false }
        let normalized = site.lowercased()
        return mangaLegalProviderAllowlist.contains(where: { normalized.contains($0) })
    }

    private func isAllowedAnimeLegalProvider(_ site: String?) -> Bool {
        guard let site, !site.isEmpty else { return false }
        let normalized = site.lowercased()
        return animeLegalProviderAllowlist.contains(where: { normalized.contains($0) })
    }

    private func languageRank(for link: ExternalLink, locale: String?) -> Int {
        let target = normalizedLocaleLanguage(locale)
        let language = normalizedExternalLanguage(link.language)
        if language == target { return 0 }
        if language == "en" || language == "de" { return 1 }
        if language == "unknown" { return 2 }
        return 3
    }

    private func providerRank(for link: ExternalLink, ranking: [String]) -> Int {
        let site = (link.site ?? "").lowercased()
        return ranking.firstIndex(where: { site.contains($0) }) ?? 999
    }

    /// The outbound-link scheme allowlist: http and https only. The one predicate behind the legal-link
    /// filter below and `validatedOutboundURL(_:)`.
    nonisolated static func isValidHttpURL(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("http://") || normalized.hasPrefix("https://")
    }

    /// The single outbound-URL validator for every provider, episode and chapter link a detail page
    /// opens: trims, encodes spaces and turns a bare host ("www.example.com") into https. Guarantee: a
    /// non-nil result is an http/https URL with a non-empty host. Any other scheme (javascript:, file:,
    /// kuro:, custom) is rejected before adding a scheme. A bare host with a port must include its
    /// explicit http/https scheme, avoiding ambiguous `scheme:value` input. Input
    /// `URL(string:)` cannot parse (a malformed host: backslash, `[`, bare `%`, NUL, newline) is
    /// rejected, not percent-encoded; non-ASCII hosts and paths (CJK, IDNA) parse natively.
    nonisolated static func validatedOutboundURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed.replacingOccurrences(of: " ", with: "%20")
        if !isValidHttpURL(candidate) {
            guard !candidate.contains("://"),
                  URLComponents(string: candidate)?.scheme == nil else { return nil }
            candidate = "https://\(candidate)"
        }
        guard let url = URL(string: candidate),
              isValidHttpURL(url.absoluteString),
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    func fetchLegalWatchLinks(mediaId: Int, locale: String? = nil) async -> [ExternalLink] {
        let links = await catalog.fetchExternalLinks(mediaType: "ANIME", mediaId: mediaId)
        return links
            .filter { !$0.isDisabled }
            .filter { Self.isValidHttpURL($0.url) }
            .filter { isAllowedAnimeLegalProvider($0.site) }
            .sorted { lhs, rhs in
                let lhsTuple = (lhs.priority ?? 999, languageRank(for: lhs, locale: locale), providerRank(for: lhs, ranking: animeProviderRanking))
                let rhsTuple = (rhs.priority ?? 999, languageRank(for: rhs, locale: locale), providerRank(for: rhs, ranking: animeProviderRanking))
                if lhsTuple != rhsTuple { return lhsTuple < rhsTuple }
                return (lhs.site ?? "").localizedCaseInsensitiveCompare(rhs.site ?? "") == .orderedAscending
            }
    }

    func fetchLegalReadLinks(mediaType: String = "MANGA", mediaId: Int, locale: String? = nil) async -> [ExternalLink] {
        guard mediaType.uppercased() == "MANGA" else { return [] }
        let links = await catalog.fetchExternalLinks(mediaType: "MANGA", mediaId: mediaId)
        return links
            .filter { !$0.isDisabled }
            .filter { Self.isValidHttpURL($0.url) }
            .filter { isAllowedMangaLegalProvider($0.site) }
            .sorted { lhs, rhs in
                let lhsTuple = (lhs.priority ?? 999, languageRank(for: lhs, locale: locale), providerRank(for: lhs, ranking: mangaProviderRanking))
                let rhsTuple = (rhs.priority ?? 999, languageRank(for: rhs, locale: locale), providerRank(for: rhs, ranking: mangaProviderRanking))
                if lhsTuple != rhsTuple { return lhsTuple < rhsTuple }
                return (lhs.site ?? "").localizedCaseInsensitiveCompare(rhs.site ?? "") == .orderedAscending
            }
    }

    func getBestLegalReadLink(manga: Manga, locale: String? = nil) async -> (url: String, site: String, label: String)? {
        let links = await fetchLegalReadLinks(mediaId: manga.id, locale: locale)
        guard let best = links.first else { return nil }
        let siteLabel = (best.site ?? "Reader").uppercased()
        return (best.url, best.site ?? "Reader", "READ ON \(siteLabel)")
    }
}
#endif
