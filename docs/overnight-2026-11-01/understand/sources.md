# External data sources: research and decision record (lane: sources)

Date: 2026-11-01. Branch `kuro/overnight-2026-11-01`. This is a read-only audit. No source, git, simulator or remote-service state was changed. The only external calls were anonymous public read GETs/POSTs (search/GraphQL reads) against third-party APIs, each made once or twice.

Evidence labels used throughout:
- **[LIVE 2026-11-01]**: I sent the request quoted here on 2026-11-01 and saw the fields named.
- **[DOCS]**: read from the provider's own docs or terms page on 2026-11-01. A URL is given.
- **[SECONDHAND]**: from a search summary or third-party page. Not confirmed against primary text.
- **[UNVERIFIED]**: could not be reached or checked.

---

## 0. Read this first: three owner-level gates

These gates come before any engineering decision. None of them is a code problem.

### Gate 1: AniList Terms of Use vs Kuro's design (open question #1, not softened)

**[DOCS]** https://docs.anilist.co/guide/terms-of-use (fetched with curl; WebFetch got a 403) says, verbatim:
- "Using the AniList API as a backup or data storage service is strictly prohibited."
- "Hoarding or mass collection of data from the AniList API is strictly prohibited."
- "Use of the AniList API within competing, non-complementary services of the same nature is prohibited. This includes, but is not limited to, anime and manga list or tracker services. The restriction applies to all data provided through the API, including both user data and media data."
- Commercial: "may be used within commercial applications or services operating at less than $150 of revenue per month free of charge … greater than $150 of revenue per month will need to acquire a commercial license" (contact@anilist.co).

What Kuro does today:
- Kuro is a watchlist/collection app with personal anime and manga lists (CLAUDE.md "WHAT THIS APP IS"; tables `anime_user_lists`/`manga_user_lists`).
- Its whole catalog comes from AniList. The `catalog_backfill` track runs up to `maxPagesPerRun: 200` × `perPage: 25` with `runToEnd: true` (`supabase/functions/bulk-import-anime/handler.ts:95-110`) and writes to its own `public.anime` (≈21.7k rows estimated, `docs/overnight-2026-11-01/live/table-stats.txt:10`) and `public.manga` (155 MB total, `table-stats.txt:7`).
- Hourly cron imports run on top of that (CLAUDE.md "Cron jobs").
- The AniList list-import flow (`supabase/functions/concierge-import-anilist/paging.ts`) also reads user data.

As written, this design falls inside at least two of the prohibited categories: mass collection/storage, and a list/tracker service. That holds whether or not Kuro makes money. **Only the owner can resolve this**, by one of:
- (a) emailing AniList for written permission or a commercial licence;
- (b) moving the catalog backbone to a source whose licence allows it (see §4: no single source fully replaces AniList today);
- (c) accepting the risk knowingly.

Every "AniList = primary" row below assumes (a) or (c).

### Gate 2: Is Kuro commercial? Several verdicts flip on this

I found no StoreKit, paywall or ads code in `Kuro/`. A grep for `StoreKit|Product.products|paywall|monetiz` matched only realtime "subscription" code. A `+Monetization` extension existed historically (CLAUDE.md "Retired" list). Commercial status is therefore **unknown**. It changes the answer for:

| Source | Non-commercial | Commercial (ads, paid tier, App Store price, or revenue) |
|---|---|---|
| AniList | Allowed subject to Gate 1 | Free under $150/month revenue, otherwise licence required (still subject to Gate 1) |
| AnimeThemes | Allowed (ToS covers the "Site", which includes "mobile application related") | **Prohibited** unless "specifically endorsed or approved by us" (https://animethemes.moe/about/terms-of-service: "may not be used in connection with any commercial endeavors…"; "use the Site and/or the Content for any revenue-generating endeavor") |
| MangaDex | Allowed with credit to MangaDex and scanlation groups | **Prohibited**: "You CANNOT run ads or paid services on your website and/or apps … you must not be profiting from our API" (https://api.mangadex.org/docs/). Kuro already calls MangaDex in `supabase/functions/manga-chapter-enrich/mangadex.ts:7` |
| AnimeSchedule.net | Allowed with app token and visible credit | **Permission required**: "Ask us for permission before using the API for commercial purposes" (https://animeschedule.net/api/v3/documentation) |
| MyAnimeList official API / Jikan | MAL API agreement applies | MAL defines "Your Commercial Applications" separately and needs an agreement. MAL forbids scraping (§3(i) of https://myanimelist.net/static/apiagreement.html). Jikan is a scraper, so it is not recommended in any mode |
| Google Books | Allowed with key | "You may not charge users any fee for the use of your application" without a Google agreement (https://developers.google.com/books/terms) |
| MangaUpdates | Allowed: credit, reasonable spacing, caching | No commercial prohibition in the AUP (`https://api.mangaupdates.com/openapi.yaml` info block). The **only permissive manga release source found** |
| MusicBrainz / Wikidata / OpenLibrary | Allowed (CC0-style core data, see notes) | Allowed |
| Apple iTunes Search API | Promotional linking only | Same, "promote store content" only |
| Spotify Web API | Personal-use licence | Commercial falls outside grant (Developer Terms III.1.a). Avoid the API and use plain search URLs |

### Gate 3: No data-source attribution exists in the app

A grep of `Kuro/` for `data from|powered by|attribution|courtesy` matched only telemetry comments (`Kuro/Telemetry/InteractionTelemetry.swift:20,36-55`). These sources **require** visible credit: MangaDex ("MUST credit MangaDex" + groups), MangaUpdates ("You will credit MangaUpdates"), AnimeSchedule ("visible link or credit"), iTunes previews ("provided courtesy of iTunes"), anime-offline-database (ODbL attribution + share-alike on derived DB), and AniList (good practice; naming guidelines). **Recommendation:** one "Data sources" surface in Profile → About, plus a small per-surface source caption wherever a date or song comes from a third party (e.g. "Release info: MangaUpdates").

---

## 1. What Kuro ingests today (repo evidence)

| Path | Source | What it pulls | Citation |
|---|---|---|---|
| `bulk-import-anime` | AniList GraphQL | Core media fields, `nextAiringEpisode {episode airingAt timeUntilAiring}`, optional `streamingEpisodes {title thumbnail url site}`, `externalLinks {site url language color}`, and with relations: studios, tags, characters (10), staff (10) | `supabase/functions/bulk-import-anime/anilist.ts:37-82` (fragment lines 38-53, nextAiring line 70) |
| `bulk-import-manga` | AniList GraphQL | Core fields, `chapters volumes` (totals only), externalLinks, relations/staff/tags/characters | `supabase/functions/bulk-import-manga/anilist.ts:38-79` |
| Airing patch | AniList | On unchanged rows it still refreshes `next_episode_number` and `next_airing_at` | `supabase/functions/bulk-import-anime/mapping.ts:36-41`, full map `:79` |
| `manga-chapter-enrich` | MangaDex | Title search/mapping and **`/manga/{id}/aggregate` chapter numbers only (no dates)** | `supabase/functions/manga-chapter-enrich/mangadex.ts:7, 437-451, 453-482` |
| `series_enrichment_worker.py` (prepared, bounded) | AnimeThemes **JSON:API** + AniList/MAL art hosts | OP/ED song title + artists by exact AniList/MAL resource id | `scripts/series_enrichment_worker.py:24, 75-117` |
| AniList list import | AniList GraphQL | User lists (import) | `supabase/functions/concierge-import-anilist/paging.ts` |
| Local scripts | AniList GraphQL | Relations / recommendation edges / imports | `scripts/media_relations_worker.js`, `scripts/import_anilist_rec_edges.js`, `scripts/import_anilist_fast.js`, `scripts/import_anilist_local.js` |
| Releases UI | DB only | `user_airing_next` view (reads `anime.next_airing_at`) | `Kuro/Releases/ReleasesStore.swift:137` |

Storage that already exists and could hold more source data. Columns sit mostly unpopulated per row estimates, but estimates of 0 may just be stale stats:
- `public.episodes.air_at`, `air_date`, `stream_url`, `stream_site` (`supabase/migrations/20260807000000_baseline_capture_v1.sql:260-281`).
- `public.chapters.release_at`, `release_date`, but **`number integer not null`** (`baseline_capture_v1.sql:214`). Fractional chapters such as 1095.5 cannot be stored, and `mangadex.ts` counts them as `fractionalSkipped` (`mangadex.ts:425-427`).
- `public.volumes.release_date`, `release_at`, `isbn`, `price_jpy` (`baseline_capture_v1.sql:505-520`). There is no territory/edition column, so the JP and EN release of the same volume cannot coexist.
- **Discrepancy (reported, not explained):** `public.release_events` and `public.theme_links` appear in the live snapshot (`docs/overnight-2026-11-01/live/table-stats.txt:97` and `:117`, est. 0 rows). Their DDL exists only in `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql:330-341` (theme_links) and `:363-385` (release_events), not in `supabase/migrations/`. `catalogue_units` (`table-stats.txt:98`; DDL prepared `:268-293`) is in the same state.

### Intake defects found while mapping sources

1. **The "airing_or_releasing" and "recent_updates" tracks do not filter anything.** Both AniList queries are hard-coded `media(sort: POPULARITY_DESC, type: ANIME|MANGA)` (`bulk-import-anime/anilist.ts:57`, `bulk-import-manga/anilist.ts:56`). The track presets differ only in cursor, page size and delay (`bulk-import-anime/handler.ts:54-111`). `next_airing_at` therefore refreshes only when the popularity cursor next reaches a title's page, so less popular simulcasts go stale. Fix: §5.1.
2. **Rate budget mismatch.** AniList is degraded: **[LIVE 2026-11-01]** response header `x-ratelimit-limit: 30`, and **[DOCS]** "currently in a degraded state and is limited to 30 requests per minute", with a "1 minute timeout" on excess. The presets assume much more:
   - `catalog_backfill` `delayMs: 250` (≈240 req/min if the fetch is fast), `handler.ts:107`;
   - `airing_or_releasing` 120 ms, `:80`; `recent_updates` 100 ms, `:93`; `popularity_core` 0 ms, `:67`;
   - the delay is clamped to ≤250 ms (`handler.ts:159`).
   
   The 429 handler backs off `500·2^n` ms and ignores `Retry-After` (`bulk-import-anime/anilist.ts:20-23`). During AniList's 60-second penalty, every retry also returns 429 and burns attempts. At least 9 code paths call `graphql.anilist.co` (list in §1 above). Edge-function egress IPs vs the local Mac are separate budgets, but **[UNVERIFIED]** Supabase edge egress IPs may be shared with other tenants.
3. **The AnimeThemes JSON:API that the worker uses is deprecated.** **[DOCS]** https://api-docs.animethemes.moe/intro/jsonapi/ and `/intro/ratelimiting/`: "⚠️ The JSON:API is deprecated and it will be removed." Worker: `scripts/series_enrichment_worker.py:75-79`. Migration target verified in §3.1.
4. **`externalLinks` omits `type`.** **[LIVE]** AniList returns `type` (`STREAMING`/`INFO`/`SOCIAL`) but the query selects only `site url language color` (`bulk-import-anime/anilist.ts:39-40`). Classifying "where to watch" vs "official site" vs "social" currently means string-matching site names.

---

## 2. Certainty model (never fabricate dates)

Every date shown to a user must carry a certainty label. Proposed values:

| Label | Meaning | Allowed sources | UI copy pattern |
|---|---|---|---|
| `confirmed` | A provider published this exact instant or day for this unit | AniList `airingSchedule` instant; publisher/MANGA Plus listing; MangaUpdates/Google Books/OpenLibrary edition-level date tied to an ISBN and territory | "Ep 5 · Sun 15:00" / "Vol 116 · 4 Mar (JP)" |
| `estimated` | Derived by Kuro from observed cadence. Never stored as fact | Last N release instants from MangaDex/MangaUpdates; computed at read time | "Usually weekly · next expected around Sun 9 Nov" ("expected", "around", never a countdown) |
| `unknown` | No trustworthy signal | — | "No date announced" |
| `past` | Already released (last-known) | Any of the above | "Last chapter 1196 · 18 Oct" |

**Risk in the prepared home RPC:** the release query surfaces `release_events` rows with `status in ('scheduled','announced')` and no certainty field (`supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql:3377-3388`). `release_events` has `precision` (`instant|day|month|quarter|year|unknown`) and `status`, but **no certainty or source column** (`:363-385`). A cadence estimate written as `status='scheduled'` would show as fact. Recommendation, in order of preference:
1. **Compute estimates at read time** (SQL function or client) from stored past events, and never store them in `release_events`. Only `confirmed` rows go into the table.
2. If estimates must be stored, add `certainty text not null check (certainty in ('confirmed','estimated'))`, `source text not null`, and `source_url text`. Both the RPC and every UI renderer must branch on `certainty`, and a quality gate should fail on renderers that ignore it.

Also: `chapters.number` should become `numeric` (or add `number_text`) so 1095.5 can be represented. `volumes` needs `territory` + `edition_key` (JP original vs EN licence vs DE etc.), because the same volume ships on different dates per market (see the OpenLibrary evidence in §3.4).

---

## 3. Source dossiers

### 3.1 Songs / themes

#### AnimeThemes.moe: recommended primary for OP/ED (licence gated, see Gate 2)
- **Returns:** anime, animethemes (`type` OP/ED, `sequence`, `slug`), song (title; GraphQL adds `title.romaji/native`), artists/performances (`name.main/native`), entries (`episodes` range e.g. "1-13", `spoiler`, `nsfw`, `version`), videos (`link` e.g. `https://v.animethemes.moe/ShingekiNoKyojin-OP1.webm`, `resolution` 1080), images, studios, resources (external ids).
- **ID mapping:** exact by external resource. JSON:API `filter[site]=AniList&filter[external_id]=…`. GraphQL `findAnimeByExternalSite(site: ANILIST, id: [Int!])`. **The `id` arg is a list, so it batches many AniList ids per request.** `site` is enum `ResourceSite` (introspected). MyAnimeList ids are also supported.
- **Auth:** none for reads. **Rate limit [DOCS+LIVE]:** 90/min (`x-ratelimit-limit: 90` seen on both JSON:API and GraphQL), `Retry-After` on excess.
- **Licence/ToS:** API docs MIT (docs only). Site ToS forbids commercial use without endorsement (Gate 2). **Video files must not be rehosted.** Linking out to the animethemes.moe page is the safe pattern. Embedding the webm player is also a ToS question for a commercial app.
- **Freshness:** community-maintained. New-season themes appear within days to weeks **[SECONDHAND/inferred]**.
- **Reliability:** good; responded instantly.
- **Cost:** free. Donations encouraged.
- **[LIVE 2026-11-01] JSON:API:** `GET https://api.animethemes.moe/anime?filter[has]=resources&filter[site]=AniList&filter[external_id]=16498&include=resources,animethemes.song,animethemes.song.artists,animethemes.animethemeentries.videos&page[size]=5` → `Shingeki no Kyojin` 2013 Spring; resources `[('AniList',16498)]`; OP1 "Guren no Yumiya" / Linked Horizon, episodes "1-13", spoiler false, video 1080p webm; `links.next = null`.
- **[LIVE 2026-11-01] GraphQL (migration target, verified):** `POST https://graphql.animethemes.moe/` with
  ```graphql
  { findAnimeByExternalSite(site: ANILIST, id: [16498]) {
      title { romaji } slug year
      animethemes { type sequence slug
        song { title { romaji native } performances { artist { ... on Artist { name { main native } } } } }
        animethemeentries { episodes spoiler } } } }
  ```
  → same four themes; ED1 artist `name.native = 日笠陽子`. Header `x-ratelimit-limit: 90`.
- **Song streaming links:** `include=animethemes.song.resources` returned `[]` for AoT songs **[LIVE]**, so do not count on Spotify/Apple links from AnimeThemes.

#### Jikan v4 `/anime/{id}/themes` (MAL): not recommended
- **[UNVERIFIED]** `GET https://api.jikan.moe/v4/anime/16498/themes` timed out (TCP connect 20 s) on 2026-11-01 from this host. Repo `jikan-me/jikan-rest` is MIT and was pushed 2026-10-30 (GitHub API).
- Returns `openings[]`/`endings[]` as **free-text strings** (e.g. `"1: \"Guren no Yumiya\" by Linked Horizon (eps 1-13)"`). This is from training knowledge, **[SECONDHAND]**. It has to be parsed and is lower quality than AnimeThemes.
- Jikan scrapes MyAnimeList, and the MAL API agreement §3(i) forbids "data scraping, web scraping … to extract data from … MyAnimeList Content". Rate limits could not be confirmed ([SECONDHAND] 2020 issue: 30/min, 2/s).

#### AniList: no song data
AniList's Media type has no theme/song field. Only `trailer` (see §3.5).

#### MusicBrainz: enrichment, not discovery
- **Returns:** recordings, artists, releases, ISRCs, first-release-date, and URL relationships (Spotify/Apple/YouTube links exist as `url-rels` when contributed).
- **[LIVE]** `GET https://musicbrainz.org/ws/2/recording?query=紅蓮の弓矢 AND artist:"Linked Horizon"&fmt=json&limit=2` → count 69; `5caf2653-aa3d-4766-844a-d4e716a71fc1` 紅蓮の弓矢, Linked Horizon, `first-release-date 2013-07-10`.
- The romaji query `recording:"Guren no Yumiya"` returned **0**. You need the native title (AnimeThemes GraphQL gives `title.native`, often null) or artist-scoped browsing. Matching is fuzzy, so store the result as `match_state='search'` unless the MBID is confirmed.
- **Auth:** none. **Rate [DOCS]** https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting: about 1 req/s per IP, a meaningful User-Agent `App/version ( contact )` is required, 503 on excess, and do not poll at top-of-hour.
- **Licence:** core data CC0 **[SECONDHAND: the licence page was not fetched; widely documented]**.
- **Cost:** free.

#### Apple Music / iTunes Search API: outbound link only
- **[LIVE]** `GET https://itunes.apple.com/search?term=Linked Horizon Guren no Yumiya&entity=song&limit=2&country=DE` → `trackName 紅蓮の弓矢`, `trackViewUrl https://music.apple.com/de/album/…?i=666788983`, `previewUrl` present.
- **Terms [DOCS]** https://performance-partners.apple.com/search-api: "approximately 20 calls per minute". Previews must be "streamed only, and not downloaded, saved, cached"; artwork/previews only "to promote store content"; a badge is needed next to promo content.
- **Use:** a server-side, low-volume lookup stored as an outbound URL only, or simpler: no API, just a search deep link `https://music.apple.com/search?term=<artist+title>` (`match_state='search'`).

#### Spotify: no API use; search URL only
- **[DOCS]** https://developer.spotify.com/terms IV.3.1.a: "you may not store, aggregate or create compilations or databases of Spotify Content". III.1.a: the licence is "for private personal use". VI.7: extended quota is at Spotify's discretion.
- **Recommendation:** a plain URL `https://open.spotify.com/search/<urlencoded "artist title">` built on device. It involves no API, no stored Spotify content, and no key.

**Songs decision:** AnimeThemes (GraphQL, batched exact-id) → `theme_links` with `match_state='verified'` and `evidence='animethemes:<theme id>'`. Outbound "Listen" buttons use Apple/Spotify **search URLs** (`match_state='search'`). MusicBrainz is optional for release date/ISRC. **Fallback if AnimeThemes permission is refused (commercial):** none clean. Show no songs rather than scrape. MusicBrainz alone cannot map anime↔song reliably.

### 3.2 Next episode

#### AniList `airingSchedule` / `nextAiringEpisode`: primary (subject to Gate 1)
- **[LIVE 2026-11-01]** `POST https://graphql.anilist.co` (anonymous) with
  ```graphql
  query($a:Int,$b:Int){
    Page(page:1,perPage:5){ pageInfo{ total hasNextPage }
      airingSchedules(airingAt_greater:$a, airingAt_lesser:$b, sort:TIME){
        id airingAt episode timeUntilAiring mediaId media{ idMal title{romaji} status countryOfOrigin } } }
    Media(id:21){ nextAiringEpisode{episode airingAt}
      airingSchedule(notYetAired:true, perPage:3){ nodes{episode airingAt} }
      trailer{id site thumbnail} externalLinks{site type url language} streamingEpisodes{site title url} updatedAt } }
  ```
  `$a=now`, `$b=now+86400`. The response had airing rows with `airingAt` (unix seconds), `episode`, `mediaId` (= AniList id), and `media.idMal`. Media 21 (One Piece) returned `nextAiringEpisode {episode:1181, airingAt:1798985760}` plus the next three scheduled episodes. `externalLinks` came back with `type` (`STREAMING`, `INFO`).
  - `pageInfo.total` read 5000. **That is AniList's pagination cap, not a real count.** Do not use it as a volume estimate.
  - Header: `x-ratelimit-limit: 30`.
- **ID mapping:** native AniList id, plus `idMal`.
- **Freshness:** AniList staff and community keep schedules updated, delays included. Treat `airingSchedule` instants as `confirmed`, but re-fetch daily because delays rewrite them.
- **Reliability:** high, but the API is currently degraded (30/min).
- **Cost:** free under Gate 1/2 conditions.

#### AnimeSchedule.net API v3: secondary, gated
- **[DOCS]** https://animeschedule.net/api/v3/documentation{,/anime,/ratelimits} and `/api-terms-of-use`:
  - A Bearer application token is required for documented endpoints. "Public" no-token access has a "far less forgiving rate limit".
  - Global limit: **120 requests/minute**, IP- and app-based.
  - `GET /api/v3/timetables/{raw|sub|dub|all}?week=&year=&tz=` returns `episodeDate`, `episodeNumber`, `delayedFrom`, `delayedUntil`, `delayedText`, `airingStatus` (airing/aired/unaired/delayed-air), `airType`, and `streams[] {platform,url,name}`.
  - `/anime` takes `anilist-ids`, `mal-ids`, `anidb-ids` filters, and the anime `websites` object has `aniList`/`mal` (whether these are IDs or URLs is undocumented).
  - **ToS:** cache only "as needed for the normal operation", no AI training, visible credit, and commercial use needs permission.
- **Unique value:** **sub and dub air times** per platform (e.g. Crunchyroll sub release vs JP TV raw). AniList only knows the JP broadcast.
- **[UNVERIFIED live]:** needs a token, so I made no request.

#### LiveChart.me: excluded
- **[DOCS]** https://www.livechart.me/pages/terms: "Scrape any of the Services without the prior consent of LiveChart.me" is prohibited. No public API found.

**Next-episode decision:**
- **Primary:** AniList `airingSchedules` window sync (§5.1) → `release_events` (`kind='episode'`, `precision='instant'`, `certainty='confirmed'`, `source='anilist'`) and `anime.next_airing_at`.
- **Fallback / enrichment:** AnimeSchedule timetables (sub/dub per platform), only with a token and, if commercial, permission.
- **No schedule:** label `unknown`. For a finished season, show "Season finished".

### 3.3 Next manga chapter

#### MangaUpdates API v1: recommended primary for chapter release history (permissive AUP)
- **[DOCS]** `https://api.mangaupdates.com/openapi.yaml` info block: "Most API functions are public and do not require an account". Acceptable Use Policy: "You will credit MangaUpdates … use reasonable spacing between requests … employ caching". It prohibits deceive/illegal/spam/damage, and there is **no commercial prohibition**. Warranties: "no warranties about service availability, correctness".
- **[LIVE]** `POST https://api.mangaupdates.com/v1/series/search` body `{"search":"One Piece","perpage":2}` → `series_id 55099564912`, `url https://www.mangaupdates.com/series/pb8uwds/one-piece`, `last_updated.as_rfc3339 2026-10-03T17:52:36-07:00`.
- **[LIVE]** `GET https://api.mangaupdates.com/v1/series/55099564912` → keys include `status` ("115 Volumes (Ongoing)"), `licensed: true`, `completed: false`, `latest_chapter: 1196`, **`anime: {start: "Vol 1, Chap 1 (Chap 1 adapted in EP 4)", end: "Vol 113, Chap 1150 (As of EP 1180)"}`**, `publishers[]` (MANGA Plus English "1186 Chapters; Ongoing", Shueisha Original, VIZ Media…), `publications[]` (Shuukan Shounen Jump), `bayesian_rating 8.89`.
- **[LIVE]** `POST https://api.mangaupdates.com/v1/releases/search` body `{"search":"55099564912","search_type":"series","perpage":3}` → `total_hits 2307`; latest `chapter 1196, release_date 2026-10-18, groups [Viz, MANGA Plus]`, then 1195 → 2026-10-11 and 1194 → 2026-09-27. **All past releases. There are no future dates.**
- **ID mapping:**
  - No AniList id in the MU payload.
  - The bridge is MangaDex `links.mu` = base36 slug (`pb8uwds`). `int('pb8uwds', 36) == 55099564912` (computed), so it maps exactly to the MU numeric `series_id`.
  - MangaDex also carries `links.al` (AniList) and `links.mal`. Chain: AniList id → MangaDex (`links.al`) → `links.mu` → MU series.
  - The existing `manga_source_links` mapping table (`table-stats.txt:43`) is the natural home.
- **Rate:** undocumented beyond "reasonable spacing". Use ≤1 req/s with caching **[assumption]**.
- **Freshness:** community-entered, usually within a day of release for popular series **[SECONDHAND/inferred from 2026-10-18 entry]**.
- **Unique extras:** the `anime.start/end` adaptation coverage feeds "continue the story after the anime: read from ch. 1151". It maps to the prepared `adaptation_coverage` table (`series_home_foundation_v1.sql:343-357`). Label it as community data.
- **Cost:** free.

#### MangaDex API: official-chapter evidence and read links (licence gated, see Gate 2)
- **[LIVE]** `GET https://api.mangadex.org/manga?title=one piece&limit=1&contentRating[]=safe&contentRating[]=suggestive` → id `a1c7c817-4e59-43b7-9365-09675a149a6f`; `links {al:'30013', mal:'13', mu:'pb8uwds', kt, ap, bw, amz, cdj, ebj, raw:'https://shonenjumpplus.com/…', engtl:'https://mangaplus.shueisha.co.jp/titles/100020'}`; `status ongoing`; `lastChapter ''`.
- **[LIVE]** `GET https://api.mangadex.org/manga/a1c7c817-…/feed?translatedLanguage[]=en&order[publishAt]=desc&limit=3&includeFutureUpdates=1&includes[]=scanlation_group` → `total 15`; ch 1196 `publishAt 2026-10-18T15:10:58+00:00`, `externalUrl https://mangaplus.shueisha.co.jp/viewer/1030616`, `pages 0`, group `MangaPlus`; ch 1195 2026-10-11; ch 1194 2026-09-27 (break on 10-04).
  - For licensed titles MangaDex holds **only the official external chapters** (here 15 English entries, i.e. MANGA Plus's free window).
  - `includeFutureUpdates=1` returned no future rows, so MangaDex gives **no next-chapter date**.
- **Rate:** **[SECONDHAND]** about 5 req/s per IP globally, `/at-home/server` 40/min, 429 → temporary ban (search summary of `api.mangadex.org/docs/2-limitations`; the page sat behind a bot wall for curl).
- **Policy [DOCS]:** credit MangaDex and groups, no ads or paid services, honour removal requests.
- **Kuro today:** chapter counts via `/aggregate` (`mangadex.ts:437-451`). It does not store `publishAt` or `externalUrl`. Both are already in the feed and would give "Last chapter · 18 Oct · Read free on MANGA Plus".

#### MANGA Plus / Shueisha / K Manga / publisher schedules
- **No public API.** The MANGA Plus app uses an undocumented protobuf API. Reverse-engineering it would break its terms ([SECONDHAND/common knowledge]; not fetched). Excluded.
- **Cadence facts usable for estimation:**
  - Weekly Shōnen Jump is weekly with announced breaks.
  - The MangaDex `publishAt` series above shows Sunday ~15:10 UTC simulpub and a skipped week (2026-10-04).
  - So weekly cadence ≠ every week. Estimates must say "expected", and any break announced by a source overrides them.
- **AniList:** no chapter dates (only `chapters` total, null while releasing; `bulk-import-manga/anilist.ts:66`).

**Next-chapter decision:**
- **Past/last chapter (`past`):** MangaUpdates releases (permissive) as primary. MangaDex feed adds the official external read link, non-commercial only.
- **Next chapter:** **`estimated` from cadence at read time.** Use the median interval of the last 6–10 release dates. Show it only when the intervals are regular (e.g. IQR ≤ 2 days) and the last release is not older than 3× the median. Otherwise `unknown`. **Never `confirmed`** unless an official schedule source exists. None was found with an allowed API.

### 3.4 Next volume

| Candidate | Evidence | Verdict |
|---|---|---|
| **MangaUpdates** | `status` "115 Volumes (Ongoing)" [LIVE] gives the count only. No per-volume dates seen in `series/{id}` | Volume **count** (past) only |
| **Google Books API** | [LIVE] keyless request → **HTTP 429** "Quota exceeded … 'Queries per day'" (shared anonymous project). Needs a key. Terms [DOCS]: no user fees without agreement, honour removals | Candidate for EN edition `publishedDate` + ISBN-13 **with a key**. Dates for preorders are often present but can be placeholders **[SECONDHAND]**, so `confirmed` only if a full YYYY-MM-DD date comes with an ISBN |
| **OpenLibrary** | [LIVE] `GET https://openlibrary.org/search.json?q=one piece vol&publisher=VIZ&sort=new&limit=5&fields=title,publish_date,isbn,publisher,first_publish_year` → `ONE PIECE 112` with `publish_date ['2025-07-04','July 7th 2026','2026-07-07']`, ISBNs `197471652X`, `3551804974` (a **German** Carlsen ISBN). Work-level search **mixes editions and territories** | Only for ISBN-exact edition lookups (`/isbn/{isbn}.json`). [DOCS] 1 req/s anonymous, 3 req/s with UA+email, no bulk via API (use dumps) |
| **Wikidata** | [LIVE] SPARQL: One Piece manga item `Q28667972` has `P8731=30013` (AniList), `P4087=13` (MAL). 116 items link to it via `P179`/`P361`; latest dated is "One Piece, Volume 112: The Harley" `P577 2025-07-04` (JP), so it **lags** (MU reports 115). ISBN (`P212`) empty on the latest items. CC0 | Historical JP volume dates + id crosswalk. Not for "next" |
| **Wikipedia volume lists** | Not fetched. CC BY-SA; wikitext parsing is brittle | Not recommended for automation |
| **Publisher sites (VIZ, Kodansha USA, Yen Press, Seven Seas; Shueisha/Kodansha JP)** | No public APIs found. Penguin Random House has a registered "Enhanced API" with on-sale dates [SECONDHAND: developer.penguinrandomhouse.com blog]. Its coverage of distributed publishers (Kodansha USA, Seven Seas) is **[UNVERIFIED]** | Manual or editorial entry by the owner as `confirmed`, with the URL in `evidence`. A possible future B2B source |
| **Amazon (PA-API)** | Not researched in depth. Associates terms restrict use to affiliate-linking sales and require qualifying sales to keep access **[SECONDHAND]** | Excluded |

**Next-volume decision:**
- **Default `unknown`.**
- **`confirmed`** only for an edition-level record (ISBN + territory + full date) from Google Books (keyed) or OpenLibrary ISBN lookup, or an owner/editor entry with a publisher URL.
- **No cadence estimates for volumes.** Intervals of 3–5 months vary too much, and showing "Vol 116 expected Mar" would mislead. The exception is "Usually every ~4 months" as **descriptive copy** without a date.
- Requires `volumes.territory` and `edition_key` (§2).

### 3.5 Other high-value data

| Data | Source | Evidence | Recommendation |
|---|---|---|---|
| Trailers | AniList `trailer {id site thumbnail}` | [LIVE] field exists. Null for One Piece | Add to the anime query. Render as a YouTube/Dailymotion link or the official IFrame embed (YouTube embed terms allow the IFrame player) |
| Streaming links | AniList `externalLinks {site type url language}`, `streamingEpisodes` | [LIVE] `type: STREAMING` | Add `type` (+ `id`, `icon`, `notes`, `isDisabled` exist in AniList schema **[UNVERIFIED in this run]**) to the query. Already partially stored in `external_links` (33 MB, `table-stats.txt:12`) |
| Sub/dub platform times | AnimeSchedule `streams[]` | [DOCS] | Gated (token, commercial permission) |
| Official MANGA Plus / K Manga read links | MangaDex `links.engtl`, chapter `externalUrl` | [LIVE] | Non-commercial only (MangaDex policy). Alternatively AniList `externalLinks` for manga |
| Adaptation coverage ("read from ch. X after the anime") | MangaUpdates `anime.start/end` | [LIVE] | Store in `adaptation_coverage` with `evidence='mangaupdates:<id>'`, labelled community-sourced |
| Cross-site id mapping (AniList↔MAL↔Kitsu↔AniDB↔LiveChart…) | manami-project `anime-offline-database` | [LIVE GitHub] latest release `2026-27` published 2026-07-04 (**4 months stale; may be paused**). Licence **ODbL 1.0 + DbCL** (LICENSE file) | Useful for joining AnimeSchedule/Kitsu ids. ODbL share-alike applies to a derived DB that is publicly used, so prefer Wikidata (CC0) or MangaDex `links` |
| Studio/staff | AniList (already, `anilist.ts:48,52`) | repo | Keep. `perPage: 10` cap |
| News | ANN encyclopedia API **[UNVERIFIED]**, publisher RSS | not researched in depth | Out of scope tonight. No licence-clean aggregated feed identified |

---

## 4. Decision table

| Data type | Primary | Fallback | Certainty rule | Non-commercial verdict | Commercial verdict |
|---|---|---|---|---|---|
| Catalog backbone (titles, art, metadata) | AniList GraphQL | — (no licence-clean equivalent found; Kitsu/MAL not evaluated as replacements tonight) | n/a | **Gate 1 conflict** (tracker + mass collection) | **Gate 1 conflict** + licence above $150/mo |
| Next episode | AniList `airingSchedules` window sync | AnimeSchedule timetables (token) | AniList instant = `confirmed`; none = `unknown` | OK (Gate 1) | AniList licence threshold; AnimeSchedule needs permission |
| Episode sub/dub release per platform | AnimeSchedule | — | `confirmed` per `airType` | OK with token + credit | Permission required |
| Last chapter + date | MangaUpdates releases | MangaDex feed (official external chapters) | `past` | OK with credit | MangaUpdates OK; **MangaDex not allowed** |
| Next chapter | Kuro cadence estimate at read time | — | `estimated` only when regular; else `unknown`; never `confirmed` | OK | OK (computed by Kuro from MU dates) |
| Official read link | MangaDex `externalUrl`/`links.engtl` | AniList manga `externalLinks` | n/a | OK | Use AniList links only |
| Volume count | MangaUpdates `status` / AniList `volumes` | — | `past` | OK | OK |
| Next volume | Edition-level ISBN record (Google Books keyed / OpenLibrary ISBN) or editor entry | — | `confirmed` only with ISBN+territory+full date; else `unknown` | OK | Google Books: no user fees without agreement |
| OP/ED songs | AnimeThemes GraphQL (batched exact id) | none (show nothing) | exact id = `verified` | OK | **Permission required** |
| Listen links | Apple Music / Spotify **search URLs** built on device | iTunes Search API (≤20/min, link only) | `search` | OK | OK (no API data stored) |
| Song release date / ISRC | MusicBrainz | — | `search` unless MBID confirmed | OK | OK |
| Trailer | AniList `trailer` | — | n/a | OK (Gate 1) | Same |
| Adaptation coverage | MangaUpdates `anime` field | — | community-labelled | OK | OK |
| Id crosswalk | MangaDex `links` (manga), AniList `idMal`, Wikidata | manami (ODbL) | n/a | OK | MangaDex no; Wikidata OK |

Excluded outright: LiveChart (no-scrape clause), Jikan (MAL scraping), MANGA Plus private API, Amazon, Wikipedia scraping, Spotify Web API storage.

---

## 5. Intake and delivery recommendations

### 5.1 AniList airing-window sync (replaces relying on the popularity cursor for airing freshness)
- A new track/function runs hourly (offset from top-of-hour). It pages `Page(perPage:50){ airingSchedules(airingAt_greater: now-6h, airingAt_lesser: now+8d, sort: TIME) {...} }` until `hasNextPage=false`. Expected pages per run: on the order of 10–20 **[estimate; total count not measurable because `pageInfo.total` is capped]**.
- It upserts `release_events` (`kind='episode'`, `precision='instant'`, `source='anilist'`, `evidence='anilist:airingSchedule:<id>'`) and patches `anime.next_airing_at`/`next_episode_number` for the matching `anilist_id`.
- It deletes or marks `delayed` future events of the same media that disappeared from the window (delay handling).
- Unknown `mediaId`s (titles not in the catalog) go into an enqueue table instead of a full re-import.
- Optionally filter the catalog tracks with `status_in: [RELEASING, NOT_YET_RELEASED]` so `airing_or_releasing` matches its name (`anilist.ts:57`).

### 5.2 Shared AniList limiter
- One limiter config per egress: target ≤ **25 req/min** while degraded (30 hard), with burst ≤ 2.
- Honour `Retry-After` / `X-RateLimit-Reset` on 429 and pause the **whole track**, instead of `500·2^n` ms retries (`bulk-import-anime/anilist.ts:20-23`).
- Read `X-RateLimit-Remaining` and sleep when it is ≤ 3.
- Raise the `handler.ts:159` clamp: a 250 ms max is far below the ≥2.4 s spacing that 25/min needs.

### 5.3 AnimeThemes migration (if permitted)
- Replace the JSON:API `theme_query` (`scripts/series_enrichment_worker.py:75-79`) with GraphQL `findAnimeByExternalSite(site: ANILIST, id: [batch of ≤25])`. That is about 25× fewer requests.
- Keep the exact-id check and the "unknown, keep last-good" behaviour (`:104-106`).
- Store `episodes` ranges and the `spoiler` flag (hide spoiler-flagged themes by default).

### 5.4 MangaDex → richer, no extra calls (non-commercial only)
- Where `manga-chapter-enrich` already resolves a MangaDex id, one feed call (`order[publishAt]=desc&limit=10`) yields the last official chapter dates and read URLs. Store them in `chapters.release_at` plus a new `external_url`.
- Persist `links.mu`/`links.al` into `manga_source_links` to bridge MangaUpdates.

### 5.5 Delivery
- Ship one read-path RPC per detail page that returns `{last_unit, next_unit{at, precision, certainty, source}, themes[], trailer}`, so the client never computes certainty itself.
- Cadence estimate SQL: `percentile_cont(0.5)` over the last N `chapters.release_at` intervals. Return `certainty='estimated'` only when the regularity test passes.

---

## 6. Open questions (owner)

1. **AniList ToS (Gate 1):** Kuro is a list/tracker that mass-imports AniList into its own DB. Ask AniList for written permission or a licence, or decide a different backbone? This blocks calling the catalog "production ready" from a licensing standpoint.
2. **Commercial status (Gate 2):** will Kuro have ads, a paid tier, a purchase price or other revenue? If yes: AnimeThemes and AnimeSchedule need permission emails, MangaDex use must be removed from production (`manga-chapter-enrich`), and Google Books needs an agreement.
3. Live `release_events`/`theme_links`/`catalogue_units` exist while their DDL is only "prepared" (`table-stats.txt:97,98,117` vs `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql`). Which is authoritative?
4. Should cadence estimates be computed at read time (recommended) or stored with a `certainty` column?
5. Who owns the attribution surface and its wording (Gate 3)?
6. Register an AnimeSchedule application token and a Google Books API key? Both require owner accounts.

---

## 7. Sources consulted
- AniList: https://docs.anilist.co/guide/terms-of-use, https://docs.anilist.co/guide/rate-limiting, live https://graphql.anilist.co
- AnimeThemes: https://api-docs.animethemes.moe/, https://api-docs.animethemes.moe/intro/ratelimiting/, https://api-docs.animethemes.moe/intro/jsonapi/, https://animethemes.moe/about/terms-of-service, live api.animethemes.moe + graphql.animethemes.moe
- MangaDex: https://api.mangadex.org/docs/ (AUP), [SECONDHAND] https://api.mangadex.org/docs/2-limitations, live api.mangadex.org
- MangaUpdates: https://api.mangaupdates.com/openapi.yaml, live api.mangaupdates.com/v1
- AnimeSchedule: https://animeschedule.net/api/v3/documentation (+ /anime, /ratelimits), https://animeschedule.net/api-terms-of-use
- LiveChart: https://www.livechart.me/pages/terms
- MyAnimeList: https://myanimelist.net/static/apiagreement.html; Jikan repo https://github.com/jikan-me/jikan-rest
- MusicBrainz: https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting, live musicbrainz.org/ws/2
- Apple: https://performance-partners.apple.com/search-api, live itunes.apple.com/search
- Spotify: https://developer.spotify.com/terms
- Google Books: https://developers.google.com/books/terms, live googleapis.com/books/v1 (429)
- OpenLibrary: https://openlibrary.org/developers/api, live openlibrary.org/search.json
- Wikidata: live https://query.wikidata.org/sparql
- manami: https://github.com/manami-project/anime-offline-database (LICENSE, releases)
- PRH: https://developer.penguinrandomhouse.com (search summary only)
