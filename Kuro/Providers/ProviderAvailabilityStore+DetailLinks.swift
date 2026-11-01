import Foundation

#if canImport(Supabase)

// MARK: - Detail page provider links (watch / read)
// The one resolution behind the Anime and Manga detail action bars (formerly duplicated as
// `ActionButtons.refreshLinks` and `MangaActionButtons.refreshLinks`): the legal catalog links, and
// behind `streaming_availability_v1` the availability status (one read per media id within
// `detailAvailabilityTTL`), the provider v2 fetch (skipped when fetched within the same TTL) and the
// refresh-enqueue server write (cooldown-gated, decided from that same status read); then the
// verified-vs-catalog item lists (verified when any survive, otherwise the catalog fallback), the
// preferred primary, the note and the status caption. Every item passes `validatedOutboundURL(_:)`.
//
// Keys (kept from the pages): Anime is keyed on the viewer's progress, because its primary link is
// the provider of the next episode's stream link. A progress change therefore re-runs the resolution,
// but only the next episode's two-column stream link is new: the external links (CatalogStore), the
// status and the provider v2 answer come from their caches. Manga is keyed on the manga id, and its primary is
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
            // One status read per media id within `detailAvailabilityTTL` (the anime page re-resolves on
            // every progress change); the enqueue decision reuses it instead of reading it again, and a
            // requested refresh is reported by `requestedRefresh` (the caption says "Refreshing", also on
            // later resolutions within the enqueue cooldown), so the status is not re-read after the write.
            let statusRows = await detailAvailabilityStatusRows(mediaType: mediaType, mediaId: mediaId)
            availabilityStatus = statusRows?.first
            if shouldFetchDetailProviderAvailability(mediaType: mediaType, mediaId: mediaId, audio: preferredAudio) {
                let loaded = await loadProviderAvailabilityV2(
                    items: [(mediaType: mediaType, mediaId: mediaId)],
                    preferredAudioLang: preferredAudio,
                    preferredSubLang: nil,
                    includeUnknown: true
                )
                if loaded {
                    markDetailProviderAvailabilityFetched(mediaType: mediaType, mediaId: mediaId, audio: preferredAudio)
                }
            }
            if let statusRows {
                let enqueued = await enqueueAvailabilityRefresh(
                    mediaType: mediaType,
                    mediaId: mediaId,
                    reason: "detail_open",
                    knownStatusRows: statusRows
                )
                // The cached status predates a refresh enqueued within the cooldown: while it still
                // looks stale, the refresh is still pending, so the caption keeps saying "Refreshing"
                // on the next resolution (a progress change or a reopen) instead of falling back to
                // "Last checked <old date>".
                requestedRefresh = enqueued || (
                    isAvailabilityRefreshCoolingDown(mediaType: mediaType, mediaId: mediaId)
                        && Self.shouldQueueAvailabilityRefresh(statusRows.first)
                )
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
