# Anime News Network encyclopedia API: terms as published

Read 2026-11-18 (13:00 UTC) from `https://www.animenewsnetwork.com/encyclopedia/api.php`
(one GET, 200). Quoted lines are verbatim from that page. This is a reading of published terms,
not legal advice; gate L6 (attribution wording) and L7 (database right) in the design stay open.

## Quoted lines

Attribution and link (Terms of Service):
- "We provide this API free of charge but you must"
- "list Anime News Network as the source of the data"
- "include a link to the relevant Encyclopedia entry (like "full details at Anime News Network") on any page that displays anime/manga/person details"

Rate (Usage Limits):
- "The API is rate-limited to 1 request per second per IP address;"
- "requests over this threshold will be delayed."
- "If you would rather make 5 requests close together every 5 seconds, use nodelay.api.xml instead;"
- "but requests over the 1/s threshold will get a 503 error."

Batch size:
- "Please note that you can only batch up to 50 titles at once."
- Batching syntax: repeat the `anime`/`manga`/`title` parameter, or use a slash-separated list (`api.xml?anime=4658/41045`).

Caching and use pattern:
- "Details for a single title can contain a lot of data so please try to spare our poor servers by fetching (and then caching) details from this API only as needed."
- "...cache them for a week (older titles especially tend not to change so much)."
- Reports: "a typical usage scenario would be to make an initial import with `reports.xml?id=155&type=anime&nlist=all` and then do a daily import of newly added titles with `reports.xml?id=155&type=anime&nlist=50`".

## Ruling against the plan's constants

| Item | Plan | ANN published | Decision |
|---|---|---|---|
| Spacing | at least 1.1 s until verified | 1 request/s/IP, extra requests delayed | keep 1.1 s (`PoliteLimiter(1_100)`); no change |
| Batch | at most 50 ids | up to 50 titles | keep 50 (`ANN_BATCH`) |
| Cache | weekly refresh in spec 3.1 | "cache them for a week" | keep weekly (`WEEK_MS`) for records and for the title report |
| Attribution | "Data: Anime News Network" plus link (L6) | name ANN and link the encyclopedia entry on every page showing ANN data | matches; Task 16 must link `https://www.animenewsnetwork.com/encyclopedia/anime.php?id=<id>` (stored as `url` in each record) |

Differences worth the owner's attention:
- The terms name pages that display "anime/manga/person details": person and company credits taken
  from ANN need the link too (Task 7b credits).
- The full title report is a daily-import feed in ANN's own words (`nlist=all` once, then
  `nlist=50` daily). Kuro refetches the full report weekly (about 2 MB, one request), which is within
  the stated pattern; a daily `nlist=50` delta would be lighter and is a possible later change.
- The report URL host is `www.animenewsnetwork.com`; `api.xml` is served from
  `cdn.animenewsnetwork.com` (the host the page itself names).
- ANN plot summaries and picture URLs are deliberately not stored (not listed in the plan; text rights are
  an L2 question).
