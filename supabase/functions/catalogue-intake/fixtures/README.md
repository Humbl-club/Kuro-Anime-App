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
| `ann_fixtures.ts` | GENERATED: the three ANN files above as strings (`deno test --no-prompt` has no file read permission); regenerate if a capture changes |

## Live requests made while building Tasks 3-6 (total 15 before Task 4-6 captures, see below)

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
