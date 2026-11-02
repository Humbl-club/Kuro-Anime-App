# Detail pages (Anime / Manga)

Where the two media detail pages live after the E5 decomposition (review: [large-file review §4.1](../plans/2026-10-05-modular-architecture-large-file-review.md)). The Anime and Manga designs stay distinct; only shared chrome, shared policy and the load documentation moved. No new target, no screen-model type.

## Files

| File | Holds |
| --- | --- |
| `Kuro/Views/DetailPages/AnimeDetailView.swift` | Anime page and its own sections (hero, title, meta line, next up, episodes + sheet, action bar, similar, next pick) |
| `Kuro/Views/DetailPages/MangaDetailView.swift` | Manga page and its own sections (hero, title, meta line, chapters + sheet, volumes, action bar, similar, next pick) |
| `Kuro/Views/DetailPages/DetailSharedComponents.swift` | Chrome both pages render: scroll-offset key, synopsis, genres, sub-genre chips, utility button, back button, credits/ladder skeletons |
| `Kuro/Views/DetailPages/ProviderLinkViews.swift` | Provider presentation: `ProviderSelectionSheet`, its explainer and link cards, the brand mark |
| `Kuro/Providers/ProviderLinkBuilders.swift` | Pure link policy: `ProviderSheetItem`, the verified/catalog item builders, preferred primary, provider matching/ranking keys, status caption |
| `Kuro/Providers/ProviderAvailabilityStore+DetailLinks.swift` | The watch/read link resolution (owner) |
| `Kuro/Design/FlowLayout.swift` | The wrapping layout primitive (also used by Browse, Profile, AddToList, Credits) |

## Loading (one documented coordinator per page)

Initial/keyed loaders use SwiftUI `.task(id:)` (or `.task`) with cancellation and run-generation publication guards. Unit-sheet sentinels launch a retained paging task that is explicitly cancelled and invalidated on reset/dismissal; requested offsets are fenced before append. Preview generations also retain the requested next-unit number; stale runs cannot reset newer loading state. Row limits: similar 14, sub-genre tags 12 (one row read, trimmed client-side), unit previews 10, unit sheets 50 per page, the next-episode stream link 1, chapter status one row. **Not row-limited:** the credits queries (every studio/staff/cast or author/cast row of the title), the ladder RPC and the title's external links. The same table is the header comment of each page file.

| Loader (Anime / Manga) | Key | Work | Lifetime |
| --- | --- | --- | --- |
| Screen | media id | top tags, similar, ladder → `enqueueMediaRelationRefreshIfNeeded` (server write, cooldown) → FM synopsis | page |
| Credits | id + `credits_cast_v1` | studios/staff/cast or authors/cast | page |
| Units preview (`EpisodesSection` / `ChaptersSection`) | next unit number | next 10 units (Manga: + chapter status + best legal read link) | section |
| Units sheet (`EpisodeListSheet` / `ChapterListSheet`) | sheet appear + load-more | paged units | sheet |
| Watch / read links (`ActionButtons` / `MangaActionButtons`) | viewer progress / manga id | `resolveWatchLinks` (Anime: + stream link of episode progress + 1) / `resolveReadLinks` (below) | action bar |
| `DetailBetweenUs` ("Between us.": `ClubActivityCard` from `ClubActivitySection.swift`, `FriendsActivitySection`) | own `.task` | club activity, friend comments | section |

## Provider-link snapshot (owner: ProviderAvailability)

`ProviderAvailabilityStore.resolveWatchLinks(animeId:originalLanguage:progress:)` and `resolveReadLinks(mangaId:)` return one `ProviderLinkSnapshot { primary, all, note, statusCaption }`. They replace the two ~70-line `refreshLinks` copies that lived in the views. Steps: (Anime only) the stream link of episode `progress + 1` (`getStreamLinkForEpisode`, one row), which picks the primary; legal catalog links; behind `streaming_availability_v1` (read once per resolution): status, provider v2 fetch, `enqueueAvailabilityRefreshIfStale` (server write, 10-minute cooldown), status re-read; verified items when any survive, otherwise the catalog fallback; note and caption.

- **Keys kept from the pages.** Anime is keyed on progress (the primary is the provider of episode `progress + 1`); Manga on the id (the primary is the first item).
- **Supersession.** A cancelled resolution returns nil, and the page publishes only a non-nil snapshot from a task that was not cancelled. A superseded `.task(id:)` run therefore cannot overwrite a newer link set.
- **One outbound-URL validator.** `ProviderAvailabilityStore.validatedOutboundURL(_:)`, built on the `isValidHttpURL` allowlist (http/https only), is used for every provider, episode and chapter link the pages open. Guarantee: a non-nil result is http/https with a non-empty host. Malformed hosts are rejected, not percent-encoded.
- **Known divergence (kept).** Manga chapter rows open `getBestLegalReadLink` (the first legal catalog link), while the action bar uses the verified-or-catalog snapshot. This is a product question; the code keeps today's behavior.

Tests: `KuroTests/DetailProviderLinksTests.swift` (owner over StubPostgREST, plus the validator guarantee over a hostile corpus); the builder tests are in `DetailTruthfulnessTests` (`KuroTests.swift`).
