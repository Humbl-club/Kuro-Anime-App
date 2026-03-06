# Kuro Filter + Drilldown Wiring Audit

Last updated: 2026-03-06

This audit classifies every visible drilldown, filter, and sort surface by how it is actually implemented in code.

Verdict classes:
- `backend_wired`: UI control changes a server query / RPC / backend-backed fetch
- `client_only_intentional`: UI refines already-fetched local data and is acceptable as a local affordance
- `latent_backend_not_exposed`: backend support exists but the current UI does not expose it
- `broken_or_misleading`: UI suggests broader power than the implementation actually has

| Surface | User expectation | Actual data source | Verdict | Fix needed |
|---|---|---|---|---|
| Anime detail `STUDIO` | Tap studio and browse its work | Supabase join query via `fetchAnimeByStudio` | backend_wired | No |
| Anime detail `CREDITS` | Tap staff and browse filmography | Supabase join query via `fetchAnimeByStaff` | backend_wired | No |
| Anime detail `CAST` | Tap character and browse appearances | Supabase join queries via `fetchMediaByCharacter` | backend_wired | No |
| Manga detail `CREATED BY` | Tap author and browse works | Supabase join query via `fetchMangaByAuthor` | backend_wired | No |
| Manga detail `CAST` | Tap character and browse appearances | Supabase join queries via `fetchMediaByCharacter` | backend_wired | No |
| Entity sheet sort `RATING / YEAR / ERA` | Re-order creator/studio works | Client-side sort over backend-fetched media lists | client_only_intentional | No |
| Character sheet filter `ALL / ANIME / MANGA` | Narrow appearances by medium | Client-side filter over backend-fetched combined list | client_only_intentional | No |
| Staff sheet filter `ALL ROLES / DIRECTOR / WRITER / MUSIC / DESIGN` | Narrow filmography by craft | Client-side role categorization over backend-fetched credits | client_only_intentional | No |
| Author sheet filter `ALL / STORY / ART / STORY & ART` | Narrow works by author role | Client-side role categorization over backend-fetched credits | client_only_intentional | No |
| Search query | Search titles across anime/manga | `search_anime_page` / `search_manga_page` RPCs | backend_wired | No |
| Search scope `ALL / ANIME / MANGA` | Limit search media type | Search mode + backend page fetch selection | backend_wired | No |
| Search filter strip `TRENDING / NEW / CLASSICS / HIDDEN GEMS / AIRING` | Narrow search via curated flags | Existing `SearchFilters` mapped to RPC params | backend_wired | Added in this pass |
| Browse sort `POPULAR / TRENDING / TOP RATED / NEW` | Reorder browse results globally | `browse_anime_page` / `browse_manga_page` RPC params | backend_wired | No |
| Browse genre | Filter browse by genre | Browse RPC param `p_genre` | backend_wired | No |
| Browse status | Filter browse by status | Browse RPC param `p_status` | backend_wired | No |
| Browse length | Filter browse by episode/chapter range | Browse RPC params `p_min_*` / `p_max_*` | backend_wired | No |
| Browse decade | Filter browse by year range | Browse RPC params `p_min_year` / `p_max_year` | backend_wired | No |
| Browse format | Filter browse by format | Browse RPC param `p_format` | backend_wired | No |
| Browse anime/manga toggle | Switch browse catalog | Separate anime/manga browse RPCs | backend_wired | No |
| Discover type segmentation | Show anime, manga, or both rails | Client-side section gating over discover bundle payload | client_only_intentional | No |
| Discover rail chips (`Short / Long / Completed`) | Refine one rail only | Client-side filtering inside section components | client_only_intentional | Clarified as `REFINE THIS RAIL` |
| Discover `See All` sheets | Open full contents of the rail | Client-side full-sheet over already-fetched editorial rail items | client_only_intentional | Clarified as `EDITORIAL RAIL` |
| Collection status filter | Show titles by list status | Backend collection fetches scoped by list status | backend_wired | No |
| Collection media type filter | Show anime, manga, or both | Client-side filter over collection feed | client_only_intentional | No |
| Collection sort `LAST UPDATED / TITLE / RATING / MY RATING / PROGRESS` | Reorder personal library | Client-side sort over collection feed + local list metadata | client_only_intentional | No |
| Collection search | Search inside your library | Client-side search over collection items already in memory | client_only_intentional | No |
| Collection streaming service/language filters | Refine by provider/language | Client-side filtering over cached provider-availability metadata | client_only_intentional | No |

## Decisions locked by this pass

- Browse remains the primary backend-filtered discovery surface.
- Search is no longer query-only in practice; it now exposes the backend-supported refinement flags already present in `SupabaseService.SearchFilters`.
- Discover remains editorial-first. Any local rail chips are explicitly presented as rail refinements, not global search controls.
- Collection remains intentionally local-first once the user library has been fetched.
- Entity sheets are now editorial drilldowns with one extra filter layer, not raw sortable dumps.
