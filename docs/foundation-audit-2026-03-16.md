# Foundation Audit — 500-User Readiness (2026-03-16)

## Scope
Runtime-first audit of `/Applications/Kuro/Kuro`, `/Applications/Kuro/supabase`, `/Applications/Kuro/scripts`, and `/Applications/Kuro/fastlane`, with topology cleanup and hot-path review grounded in the current repo rather than MCP metadata.

## Baseline
- App build: `xcodebuild -scheme Kuro -destination 'generic/platform=iOS' build`
- Supabase schema lint: `supabase db lint --linked`
- Unit tests and quality gates should remain green after this pass; rerun after topology changes.
- Current linked project URL source of truth: `scripts/project_public.env` -> `bkdifromsqxkndnllmdj`

## What changed in this pass
### Topology cleanup
| Before | After | Reason |
| --- | --- | --- |
| `PosterView.swift` | `Kuro/Views/PosterView.swift` | Removes compiled app source from repo root and keeps runtime Swift inside the app tree. |
| `CONCIERGE_FINAL_INTEGRATED.swift` | `scripts/legacy/CONCIERGE_FINAL_INTEGRATED.swift` | Debug prototype, not runtime app code. |
| `03_updated_edge_function.js` | `scripts/legacy/03_updated_edge_function.js` | Legacy importer draft; no longer masquerades as active root source. |
| `04_manga_edge_function.js` | `scripts/legacy/04_manga_edge_function.js` | Same. |
| `06_anime_edge_function_with_episodes.js` | `scripts/legacy/06_anime_edge_function_with_episodes.js` | Same. |
| `07_manga_edge_function_with_chapters.js` | `scripts/legacy/07_manga_edge_function_with_chapters.js` | Same. |
| `test_import.js` | `scripts/manual/test_bulk_import_anime.js` | Descriptive manual tool name. |
| `test_manga_import.js` | `scripts/manual/test_bulk_import_manga.js` | Descriptive manual tool name. |
| `test_manga_with_chapters.js` | `scripts/manual/test_bulk_import_manga_with_chapters.js` | Descriptive manual tool name. |
| `test_supabase_connection.js` | `scripts/manual/verify_supabase_connection.js` | Descriptive manual tool name. |

### Runtime hot-path improvement
- `Kuro/Services/SupabaseService.swift` now hydrates similar-title results with batched `IN (...)` fetches before falling back to per-ID fetches.
- This removes the avoidable ID-RPC -> one-network-call-per-title pattern from the detail-page similar-title path.

### Maintenance cleanup
- `.gitignore` now ignores local agent state under `.claude/` and Supabase CLI temp output under `supabase/.temp/`.
- Knowledge docs and comments now point at the moved runtime and legacy-script paths.

## Runtime topology and naming anomalies
### Fixed
- Runtime app source at repo root: fixed by moving `PosterView.swift` into `Kuro/Views/`.
- Root-level legacy scripts with numbered names: fixed by moving them under `scripts/legacy/`.
- Root-level manual verification scripts with vague names: fixed by moving them under `scripts/manual/` with action-oriented names.

### Still worth cleaning later
- Root contains multiple local design artifacts (`icon_comparison.html`, `kuro_final_comparison.html`, `kuro_home_screen_preview.png`, `kuro_meaningful_comparison.html`, `sumi_k_comparison.html`). They are not runtime code, but they still add root noise.
- `legacy_sql/` and `legacy_swift/` should stay clearly historical; keep new runtime work out of them.

## Oversized-file / refactor inventory
| File | Lines | Why it matters |
| --- | ---: | --- |
| `Kuro/Services/SupabaseService.swift` | 5885 | Main structural risk. One file owns auth, browse, search, clubs, social, detail, streaming, caching, and realtime. |
| `Kuro/Views/ClubDetailView.swift` | 2651 | Screen state, business rules, composition, and styling are all co-located. |
| `Kuro/Views/ConciergeView.swift` | 1883 | Heavy workflow state mixed with view layout. |
| `Kuro/Views/ConciergeComponents.swift` | 1664 | Large component surface with significant design drift. |
| `Kuro/Views/DetailPages/AnimeDetailView.swift` | 1652 | Multi-section detail orchestration and layout in one file. |
| `Kuro/Views/EditorialCollectionView.swift` | 1581 | Filtering, paging, and presentation co-located. |
| `Kuro/Views/EditorialDiscoverView.swift` | 1569 | View composition and content orchestration co-located. |
| `Kuro/Views/DetailPages/MangaDetailView.swift` | 1456 | Same issue as anime detail. |
| `Kuro/Views/BrowseView.swift` | 1336 | Filter state, pagination, and rendering tightly coupled. |
| `Kuro/Models/SupabaseModels.swift` | 1292 | Broad model surface, but lower urgency than the screen/service hotspots. |

## Design-system drift inventory
Count below is a coarse total of raw `.black` / `.white` plus `.font(.system(...))` usage in active runtime Swift files.

| File | Raw color hits | Raw system-font hits | Total drift |
| --- | ---: | ---: | ---: |
| `Kuro/Views/EditorialCollectionView.swift` | 100 | 40 | 140 |
| `Kuro/Views/ClubDetailView.swift` | 114 | 23 | 137 |
| `Kuro/Views/ConciergeComponents.swift` | 122 | 6 | 128 |
| `Kuro/Views/BrowseView.swift` | 80 | 23 | 103 |
| `Kuro/Views/EditorialDiscoverView.swift` | 63 | 37 | 100 |
| `Kuro/Views/Cards.swift` | 61 | 25 | 86 |
| `Kuro/Views/KuroRefinedCard.swift` | 44 | 27 | 71 |
| `Kuro/Views/EditorialSearchView.swift` | 50 | 12 | 62 |
| `Kuro/Views/ClubsView.swift` | 50 | 3 | 53 |
| `Kuro/Views/ConciergeView.swift` | 47 | 4 | 51 |
| `Kuro/Views/DetailPages/AnimeDetailView.swift` | 36 | 11 | 47 |
| `Kuro/Views/DetailPages/MangaDetailView.swift` | 34 | 10 | 44 |

### Notes
- The design system exists, but these counts show the effective style system still lives inside screen files.
- `Kuro/Views/PosterView.swift` was cleaned up during the move and now uses typography and color tokens instead of raw black/white for its placeholder state.

## Backend hot-path inventory
| User action | Backend path | Current shape | Risk |
| --- | --- | --- | --- |
| Open Discover | `discover_bundle` RPC + follow-up UI prefetch | Single-call bundle plus light image/friend-count prefetch | Acceptable if payload stays bounded; watch bundle growth. |
| Browse anime / manga | `browse_anime_page`, `browse_manga_page` | Server-driven keyset pages with bounded `p_limit` | Good base shape; avoid adding unbounded filters or client-side sorting regressions. |
| Search anime / manga | `search_anime_page`, `search_manga_page` | Server-paged search RPCs | Good shape if index coverage remains intact. |
| Open Collection | `collection_feed_page` plus list refresh | Server-driven feed paging | Good base shape; keep feed payload bounded. |
| Open club | `fetch_club_bundle` | Large nested JSON aggregation of club, members, rails, polls, reactions | Highest SQL hotspot in the repo; bounded by recent safety limits but still the heaviest bundle path. |
| Open detail / similar titles | `recommend_ids_similar_to_seeds` + title hydration | Now batched by ID chunks instead of per-ID fetch fanout | Improved in this pass; remaining risk is fallback per-ID fetch only for unresolved rows. |
| Open adaptation path | `get_media_ladder` | Single ladder RPC with bounded response | Acceptable, but content semantics still matter more than load. |
| Social activity | `title_comments`, `title_comment_reactions`, related RPCs | Small per-title interaction payloads | Acceptable if rollout stays bounded and club-sharing checks remain indexed. |

## 500-user risk table
| Priority | User action | Backend path | Current risk | Recommended next step | Expected impact |
| --- | --- | --- | --- | --- | --- |
| P1 | Open large clubs | `fetch_club_bundle` | Heaviest nested JSON path; still the most likely SQL hotspot under concurrent club traffic | Break bundle into base club payload + paged rails/polls if club usage grows materially | Reduces CPU and payload spikes on club open/refresh |
| P1 | General app data access | `SupabaseService` monolith | Change risk and regression risk, not raw latency | Split by domain extensions/services so future fixes stop landing in one 5.8k-line file | Faster changes, lower regression probability |
| P1 | UI consistency at scale | Screen-local hard-coded design | Large repeated styling logic increases maintenance and makes performance tuning harder | Tokenize top offender screens first | Lower rendering churn and clearer UI contract |
| P2 | Discover/Browse/Collection detail transitions | Mixed cached + fetched sections | Perceived jank from section pop-in rather than backend failure | Add consistent skeleton/loading states for delayed sections | Better perceived speed |
| P2 | Similar-title hydration | `recommend_ids_similar_to_seeds` + detail fetch | Mostly fixed; unresolved rows still fall back individually | Add a single RPC/view that returns display-ready related titles if fallback remains active in prod | Removes last fanout path |
| P3 | Root workspace readability | Local artifacts in repo root | Noise, not runtime latency | Move or ignore non-runtime design outputs | Cleaner operator surface |

## No-obvious-bottleneck conclusion
- No obvious repo-level blocker was found for 500 concurrently active users across Discover, Browse, Collection, Details, Clubs, Social Activity, and Concierge.
- Specific bottlenecks remain here:
  - `fetch_club_bundle` as the heaviest SQL bundle
  - `SupabaseService.swift` as the largest structural change risk
  - widespread design drift in high-traffic SwiftUI screens
- Confidence should come from targeted load tests against the linked Supabase project, not from code inspection alone.
