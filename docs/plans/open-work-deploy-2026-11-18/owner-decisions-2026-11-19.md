# Owner decisions locked 2026-11-19

Authorized by the owner: take legal/product decisions off their plate, keep
the user AniList list import (grandfathered — feature existed before AniList’s
policy change), and execute Runbook Part B.

| Id | Decision locked |
| --- | --- |
| L1 | Airing/episodes stay frozen until a commercial TMDB or TheTVDB agreement exists. Prefer TMDB when quotes are available. Task 9 waits. |
| L2 | Synopses from facts only. No Wikipedia text until counsel agrees. |
| L3 | Missing images use Kuro typographic art. |
| L4 | At Task 17, stored AniList-derived catalogue becomes a factual stub (not republished as living AniList data). |
| L5 | **Keep** `concierge-import-anilist` (user-triggered list import). Grandfathered; do not remove at Task 17 solely for the post-change ToS. |
| L6 | Attribution: credit ANN / MangaUpdates / Wikidata on detail once `catalogue_source_credit_v1` is safe to enable; Profile copy can wait for a wording pass. |
| L7 | Continue ANN (amber credit+link) and MangaUpdates API use as already built. Database-right / outbound email counsel remains a follow-up, not a stop on shadow/create. |
| Q6 | AniDB stays excluded (terms page blocked). |
| Adult | Only `is_adult` or genre `Hentai` counts as adult. Ecchi/yaoi stay non-adult unless flagged. |
| minYear | **2024** for `create` insert mode and MangaUpdates new-series intake. |
| Relations | Graph readers keep the union of AniList + Kuro edges until a relations cutover; `get_media_ladder` follows `catalogue_relation_source_v1()` after publish lands. |
| Tag map | Stays unpublished until a real map review (no auto-approve of `reviewed=no` rows). |
| D-G | W6 stays dark until a ≈10-series membership pilot is filled. |
| D-H | Overridden for this Part B authorization: raise the listed tracker flags after migrations (B6), without waiting for a separate qualify run. |
| 5c.1 Songs | Accept AnimeThemes already live (`media_themes_v1`); no rollback in this pass. |
| 5c.2 MangaDex | Accept release-intake MangaDex candidate links as today; no swap in this pass. |
| Cutover | **No field group switches to `new`** until comparator gates pass for that group. First shadow sample failed identity/titles. |

## Part B execution notes

- B8 (`100401` + `100500`) stays blocked until an app build without AniList-id reads is shipped and older TestFlight builds are retired (App Store Connect agreement still open).
- Publish migration + importer deploys proceed; cutover rows remain `anilist`.
