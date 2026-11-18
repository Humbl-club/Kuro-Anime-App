# AniDB: terms check (gate Q6) and decision

Checked 2026-11-18 with three polite GET requests (User-Agent `Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)`), no retries beyond them:

| Request | Result |
|---|---|
| `https://wiki.anidb.net/API` | HTTP 403, Cloudflare interstitial ("Just a moment ... Enable JavaScript and cookies to continue") |
| `https://wiki.anidb.net/HTTP_API_Definition` | HTTP 403, the same interstitial |
| `https://anidb.net/doc/tos` | HTTP 403, the same interstitial |

## Quoted lines

None. No page of AniDB's API or data terms could be read: every response was a bot challenge, not the published text. The challenge was not worked around (no browser automation, no further requests), because a bot challenge answered with more automated requests would be the wrong response to a site that has not allowed it.

## Decision

The use terms are **unclear** (unread), so under the plan's Q6 rule AniDB is **excluded**:
- `catalogue_tag_source_map.source` allows only `ann`, `mangaupdates` and `wikidata` (check constraint, tested in `supabase/tests/rls/123_catalogue_tag_sources_v1.sql`).
- `tags.ts` and `tag-map.csv` carry no AniDB rows; `parseTagMapCsv` drops any `anidb` row.
- Tags are built from ANN, MangaUpdates and Wikidata only.

Owner action to reopen: someone reads AniDB's current terms in a browser and records the lines here. Only a clearly commercial-compatible licence would admit AniDB, and that needs its own task.
