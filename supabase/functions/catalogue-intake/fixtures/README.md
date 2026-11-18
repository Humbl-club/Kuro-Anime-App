# catalogue-intake fixtures

Unit tests never touch the network. Files here are either hand-written (marked in a `_note`
field or below) or real replies captured once, read-only, on 2026-11-18 with the User-Agent
`Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)`. Times are UTC.

| File | Origin |
|---|---|
| `wikidata_q123.json` | hand-written SPARQL JSON (Q123 scenario) |
| `wikidata_anime_live.json` | live WDQS reply, anime AniList ids 16498, 21355, 1 (13:07:28) |
| `wikidata_manga_live.json` | live WDQS reply, manga AniList ids 30002, 30013, 30001, 30003, 105778 (13:07:54) |
| `ann_report_sample.xml` | first 40 `<item>` rows of the live title report (12:59:48), closed with `</report>` |
| `ann_api_one.xml` | live `api.xml?anime=4658` (13:00:06), unmodified |
| `ann_api_batch.xml` | live `api.xml?anime=41045/9999999/16798` (13:00:08), unmodified; two unknown ids come back as `<warning>` |
| `mu_search_berserk.json` | live `POST /v1/series/search {"search":"Berserk","perpage":10}` (13:00), unmodified |
| `mu_search_sololeveling.json` | live search "Solo Leveling" (13:01), unmodified |
| `mu_series_berserk.json` | live `GET /v1/series/51239621230` (13:01), unmodified |
| `pageviews_berserk_en.json` | live `.../per-article/en.wikipedia/all-access/user/Berserk_(manga)/daily/20251118/20261117` (13:02), unmodified |
| `pageviews_missing_404.json` | live 404 body for a nonexistent ja.wikipedia article (13:02) |
| `wikidata_people_live.json` | live WDQS reply, ANN person ids 3610, 668, 3086, 68814, 4422 via P1982 with optional P11227 (13:23:08); only 68814 has an item, without an AniList staff id (Task 7b) |
| `wikidata_companies_live.json` | live WDQS reply, ANN company ids 8883, 160, 1850 via P1983 with en label (13:23:10): Feel, TV Asahi (Task 7b) |
| `mu_search_newest.json` | live `POST /v1/series/search {"orderby":"date_added","perpage":10}` (15:47:19 UTC 2026-11-18), unmodified; newest first, mixed Manga/Doujinshi, one Manga without a year |
| `mu_series_new_2853344834.json` | live `GET /v1/series/2853344834` (15:47:31), unmodified; a 2026 series Kuro does not hold |
| `ann_fixtures.ts` | GENERATED: the three ANN files above as strings (`deno test --no-prompt` has no file read permission); regenerate if a capture changes |

## Live requests made while building Tasks 3-6 (15 in total, all listed here)

| Source | URL pattern | Count | Time | Result |
|---|---|---|---|---|
| ANN | `https://www.animenewsnetwork.com/encyclopedia/api.php` (terms page, HTML) | 1 | 12:59:3x | 200, 102 kB |
| ANN | `.../encyclopedia/reports.xml?id=155&type=anime&nlist=all` | 1 | 12:59:48 | 200, 2.05 MB |
| ANN | `https://cdn.animenewsnetwork.com/encyclopedia/api.xml?anime=4658` | 1 | 13:00:06 | 200, 14 kB |
| ANN | `.../api.xml?anime=41045/9999999/16798` (batch, two unknown ids) | 1 | 13:00:08 | 200, 1.5 kB |
| MangaUpdates | `POST https://api.mangaupdates.com/v1/series/search` (Berserk, Solo Leveling) | 2 | 13:00-13:01 | 200 |
| MangaUpdates | `GET https://api.mangaupdates.com/v1/series/51239621230` | 1 | 13:01 | 200, 42 kB |
| Wikimedia | `https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/{project}/all-access/user/{title}/daily/20251118/20261117` | 3 | 13:02 | 200, 200, 404 |
| Wikidata Query Service | `POST https://query.wikidata.org/sparql` (application/sparql-query) | 5 | 13:05-13:07:54 | 502 after 47 s (first query design, 6 ids), 400 (invalid `WITH` placement), 200 (3 ids, 0.65 s), 200 (500 ids 1..500, 2.7 MB, 2.9 s, not stored), 200 (5 manga ids) |

The first WDQS design (a subselect with all property branches as UNIONs) timed out at
the gateway for six ids; the named-subquery form (`WITH {...} AS %items`, `INCLUDE %items`)
answers 500 ids in about 3 s. AniList was never called; no Supabase or Kuro resource was touched.

## Live requests made while building Tasks 7 and 7b (6 in total, all Wikidata Query Service, 2026-11-18)

All `POST https://query.wikidata.org/sparql` (application/sparql-query), at least 2 s apart, with the User-Agent above. No other source was called; AniList never.

| Time (UTC) | Purpose | Result |
|---|---|---|
| 13:22:15 | label lookup of adult genre items (`VALUES ?l { "hentai"@en "erotic anime and manga"@en "ecchi"@en ... }`) | 200: Q172067 hentai, Q219559 ecchi, Q242488 yaoi, Q3249257 adult animation; "erotic anime and manga" did not resolve |
| 13:22:23 | usage count of those items as P136 on items with an AniList anime/manga id | 200: ecchi 432, hentai 143, yaoi 143; Q3249257 none |
| 13:22:37 | property label search "anilist" | 200: P8729, P8731, P11736 (character), P11227 (staff); no AniList studio property exists |
| 13:22:54 | first ANN person/company crosswalk draft (not kept: its OPTIONAL/BIND shape bound `?p` when `?v` was unbound) | 200 |
| 13:23:08 | people crosswalk, production query shape (`wikidata_people_live.json`) | 200 |
| 13:23:10 | company crosswalk, production query shape (`wikidata_companies_live.json`) | 200 |

Adult genre decision recorded in `map_wikidata.ts` (`WIKIDATA_ADULT_GENRES`): only hentai (Q172067) counts as adult.

## WDQS timeout measurement (review fix, 2026-11-18, 2 POSTs)

One 500-id query with the real production shape (buildQuery("anime", ids 1..500), 5,015 bytes, application/sparql-query),
User-Agent `Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)`, no AniList call. Two POSTs, 70 s apart:

| Time (UTC) | Result |
|---|---|
| about 14:10 | 429 after 21.1 s (no body; a rate limit on the shared egress, not the query). The polite client treats 429 as a clean stop. |
| 14:11:28 | 200 in 2.70 s total, 2,717,389 bytes (x-first-solution-millis 382, served by wdqs1020, CDN miss) |

Decision: the Wikidata client timeout is 45 s (TIMEOUT_MS.wikidata in _shared/catalogue/source_http.ts), about 16x the observed
2.7 s and under WDQS's own 60 s server limit; the 15 s default is too tight for a cold or busy server. The 8 MB response cap
stays (observed 2.7 MB, about 3x headroom). Single sample: re-measure before raising the batch size.

## Live requests made for MangaUpdates new series (Task 15c manga half, 5 in total, 2026-11-18)

All to `https://api.mangaupdates.com/v1` with the User-Agent above, at least 3 s apart. Never AniList.

| Time (UTC) | Request | Result |
|---|---|---|
| 15:46:56 | `POST /series/search {"search":"","orderby":"date_added","perpage":5}` | 400: `search` must be 1-400 characters when present (so the list is requested without `search`) |
| 15:47:03 | `POST /series/search {"orderby":"date_added","perpage":5}` | 200; newest first, `total_hits` capped at 10000, not stored |
| 15:47:19 | `POST /series/search {"orderby":"date_added","perpage":10}` | 200 (`mu_search_newest.json`); order identical to the previous reply |
| 15:47:22 | `POST /series/search {"orderby":"date_added","perpage":100,"page":2}` | 200, 100 results, 124 kB (paging and perpage 100 confirmed; not stored) |
| 15:47:31 | `GET /series/2853344834` | 200, 1.6 kB (`mu_series_new_2853344834.json`) |

Series ids are not ordered by time (they are hashes of the slug), so the handler keeps a seen list instead of a high-water mark.
