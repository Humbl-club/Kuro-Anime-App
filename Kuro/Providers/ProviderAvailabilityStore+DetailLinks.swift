import Foundation

#if canImport(Supabase)

// MARK: - Detail page provider links (watch / read)
// The one resolution behind the Anime and Manga detail action bars (formerly duplicated as
// `ActionButtons.refreshLinks` and `MangaActionButtons.refreshLinks`): the legal catalog links, and
// behind `streaming_availability_v1` the availability status, the provider v2 fetch, the
// `enqueueAvailabilityRefreshIfStale` server write (cooldown-gated) and the status re-read; then the
// verified-vs-catalog item lists (verified when any survive, otherwise the catalog fallback), the
// preferred primary, the note and the status caption. Every item passes `validatedOutboundURL(_:)`.
//
// Keys (kept from the pages): Anime is keyed on the viewer's progress, because its primary link is
// the provider of the next episode's stream link; Manga is keyed on the manga id, and its primary is
// the first item. The Manga chapter rows open `getBestLegalReadLink` (the first legal catalog link)
// instead of this snapshot; that divergence is preserved as found (a product question, not changed).
//
// Supersession: the pages call these from `.task(id:)`. SwiftUI cancels a superseded run, and a
// cancelled resolution returns nil, so the caller never publishes a stale link set.

/// The provider links one detail page renders.
struct ProviderLinkSnapshot: Equatable {
    /// The link the action button opens directly when `all` has one item.
    let primary: ProviderSheetItem?
    /// The verified items when any survive, otherwise the catalog fallback.
    let all: [ProviderSheetItem]
    /// The availability line under the action bar.
    let note: String
    /// Verification freshness ("Verified 2 days ago.", "Refreshing verified availability now.").
    let statusCaption: String?
}

extension ProviderAvailabilityStore {

    /// The watch links of an anime detail page, keyed on the viewer's `progress`: the primary is the
    /// item matching the stream site of episode `progress + 1` (else the first item). Returns nil when
    /// the calling task was cancelled (a superseded `.task(id:)` run must not publish).
    func resolveWatchLinks(
        animeId: Int,
        originalLanguage: String?,
        progress: Int?,
        locale: String = Locale.current.identifier
    ) async -> ProviderLinkSnapshot? {
        let preferredAudio = locale.lowercased().hasPrefix("de") ? "de" : "en"
        let nextEpisode = max(1, (progress ?? 0) + 1)
        let episodeLink = await catalog.getStreamLinkForEpisode(animeId: animeId, episodeNumber: nextEpisode)
        let links = await fetchLegalWatchLinks(mediaId: animeId, locale: locale)
        return await resolveDetailLinks(
            mediaType: "ANIME",
            mediaId: animeId,
            links: links,
            ranking: animeProviderRanking,
            preferredAudio: preferredAudio,
            preferredSubtitle: preferredAudio,
            originalLanguage: originalLanguage,
            catalogSubtitle: "Catalog link only. Availability may vary by region.",
            unverifiedNote: "Availability, audio, and subtitle options may vary by region.",
            preferredSite: episodeLink?.site
        )
    }

    /// The read links of a manga detail page, keyed on the manga id; the primary is the first item.
    /// Returns nil when the calling task was cancelled.
    func resolveReadLinks(
        mangaId: Int,
        locale: String = Locale.current.identifier
    ) async -> ProviderLinkSnapshot? {
        let preferredAudio = locale.lowercased().hasPrefix("de") ? "de" : "en"
        let links = await fetchLegalReadLinks(mediaId: mangaId, locale: locale)
        return await resolveDetailLinks(
            mediaType: "MANGA",
            mediaId: mangaId,
            links: links,
            ranking: mangaProviderRanking,
            preferredAudio: preferredAudio,
            preferredSubtitle: nil,
            originalLanguage: nil,
            catalogSubtitle: "Catalog link only. Reading rights may vary by region and publisher.",
            unverifiedNote: "Reading availability may vary by region and publisher.",
            preferredSite: nil
        )
    }

    /// The shared middle of both resolutions. The flag is read once per resolution.
    private func resolveDetailLinks(
        mediaType: String,
        mediaId: Int,
        links: [ExternalLink],
        ranking: [String],
        preferredAudio: String,
        preferredSubtitle: String?,
        originalLanguage: String?,
        catalogSubtitle: String,
        unverifiedNote: String,
        preferredSite: String?
    ) async -> ProviderLinkSnapshot? {
        let isStreamingAvailabilityEnabled = flags.isStreamingAvailabilityV1Enabled
        var availabilityStatus: MediaAvailabilityStatus? = nil
        var requestedRefresh = false
        if isStreamingAvailabilityEnabled {
            availabilityStatus = await mediaAvailabilityStatus(mediaId: mediaId, mediaType: mediaType)
            await fetchProviderAvailabilityV2(
                items: [(mediaType: mediaType, mediaId: mediaId)],
                preferredAudioLang: preferredAudio,
                preferredSubLang: nil,
                includeUnknown: true
            )
            requestedRefresh = await enqueueAvailabilityRefreshIfStale(
                mediaType: mediaType,
                mediaId: mediaId,
                reason: "detail_open"
            )
            if requestedRefresh {
                availabilityStatus = await mediaAvailabilityStatus(mediaId: mediaId, mediaType: mediaType)
            }
        }
        let verifiedAvailability = isStreamingAvailabilityEnabled
            ? providerAvailability(mediaId: mediaId, mediaType: mediaType)
            : []
        let verifiedItems = makeVerifiedProviderItems(
            providers: verifiedAvailability.filter { !$0.isStale },
            fallbackLinks: links,
            ranking: ranking,
            preferredAudioLang: preferredAudio,
            preferredSubtitleLang: preferredSubtitle,
            originalLanguage: originalLanguage
        ).filter { Self.validatedOutboundURL($0.url) != nil }
        let catalogItems = makeCatalogProviderItems(
            from: links,
            ranking: ranking,
            fallbackSubtitle: catalogSubtitle
        ).filter { Self.validatedOutboundURL($0.url) != nil }
        let availabilityNote = isStreamingAvailabilityEnabled
            ? bestProviderAvailabilityNote(
                mediaId: mediaId,
                mediaType: mediaType,
                preferredAudioLang: preferredAudio,
                preferredSubtitleLang: preferredSubtitle,
                originalLanguage: originalLanguage
            )
            : nil
        let displayedItems = verifiedItems.isEmpty ? catalogItems : verifiedItems
        let primary = preferredPrimaryProviderItem(
            from: displayedItems,
            preferredSite: preferredSite
        ) ?? displayedItems.first
        let note: String
        if !verifiedItems.isEmpty {
            note = availabilityNote?.displayText ?? "Verified providers for this title."
        } else if isStreamingAvailabilityEnabled {
            note = "Catalog links only. Verified availability is still being refreshed."
        } else {
            note = unverifiedNote
        }
        // A superseded run (the page's `.task(id:)` moved on or the page went away) publishes nothing.
        guard !Task.isCancelled else { return nil }
        return ProviderLinkSnapshot(
            primary: primary,
            all: displayedItems,
            note: note,
            statusCaption: providerAvailabilityStatusCaption(
                status: availabilityStatus,
                requestedRefresh: requestedRefresh,
                hasVerifiedProviders: !verifiedItems.isEmpty
            )
        )
    }
}
#endif
