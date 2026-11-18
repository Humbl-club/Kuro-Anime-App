# Catalogue sources without AniList — design

Date: 2026-11-09. Status: proposed (owner asked for "the alternative source plan").
Owner rule (2026-11-09): **the hourly AniList imports keep running until the replacement is
working.** Their **schedules** stay unchanged until the owner authorises the switch-off (Task
17). Their **code** is not unchanged: so that a switched part sticks, the AniList importers,
`release-intake` and `mirror-images` must learn to skip the parts that have switched (Task 15).
That code change is a deploy of AniList-path jobs and needs the owner's explicit approval
before it ships, separate from the switch-off.

Related: tracker-gaps spec `docs/superpowers/specs/2026-11-09-tracker-gaps-design.md` decision
D-A (AniList's current terms ban API use, including media data, in a competing tracker, and ban
mass collection). This design is option (2) of D-A.

## 1. What depends on AniList today (measured live, read-only, 2026-11-09)

| Area | Live size | Where it comes from | Used by |
|---|---|---|---|
| Catalogue rows | 21,867 anime, 41,899 manga | `bulk-import-anime` / `bulk-import-manga` (pg_cron `kuro-import-*-hourly` at :05/:35 and `*-weekly` at :00/:10, every hour) | everything |
| Identity | every row has `anilist_id`; `mal_id` on 20,338 anime / 33,381 manga (from AniList `idMal`) | importers | MAL import + export, crosswalks |
| Synopses | `description` on 20,536 anime / 39,379 manga, AniList text | importers | detail pages, search, safety scan |
| Own synopses | `synopsis_enhanced_state`: 6 ready, 2,415 pending, 19,446 failed (anime) | synopsis worker, rewriting AniList text | detail pages |
| Covers | anime: 18,099 copied into our Storage, 3,768 hotlinked from `s4.anilist.co`; manga: 600 copied, 41,299 hotlinked | importers + `mirror-images` (allowlist host `s4.anilist.co`) | every card |
| Tags | 430 AniList tags; 112,927 anime + 131,579 manga tag links with AniList ranks | importers | Taste vectors (`media_tag_vectors`, `taste_tag_stats`), realms, Discover, similar titles |
| Scores / popularity | `average_score`, `mean_score`, `popularity`, `trending`, `favourites` | importers | ranking in Discover, Search, Collection, Concierge |
| Adult flag | `is_adult` | importers | 18+ filtering everywhere |
| Credits | 100,258 characters, 42,621 staff, 1,737 studios (+ voice actors) | importers | detail credits, entity pages |
| Episodes | 51,761 rows from AniList `streamingEpisodes` (streaming titles + thumbnails) | importers | episode lists |
| External links | 92,322 rows | importers | "where to watch/read" links |
| Relations | 17,186 `media_relations` rows with source `anilist` (20 editorial) | importers + `media_relations_worker.js` | sequels, franchise grouping |
| Recommendation edges | 103,008 `media_rec_edges` with source `anilist` | `scripts/import_anilist_rec_edges.js` | Realm graph, recommendations |
| Airing times | `next_airing_at`, `next_episode_number`; 337 `release_events` | importers + `release-intake` (`kuro-release-intake-airing-hourly`) | Releases, alerts |
| User list import | user-initiated | `concierge-import-anilist` + app import flow | Concierge onboarding |

**Key fact that makes the swap possible:** every catalogue table and every user table keys on
Kuro's own `anime.id` / `manga.id`. `anilist_id` is a side column. User lists
(`anime_user_lists`, `manga_user_lists`) reference Kuro ids, so replacing the source never moves
a user's list (live: 40 + 13 list rows today, so the user-data risk is small now and grows with users).

## 2. Sources and what each may supply

Licence classes come from the 2026-11-09 terms review (tracker-gaps research). "Facts" means
uncopyrightable data (titles, dates, counts, formats, credits as facts, ids). Every class below
still needs the lawyer questions in §7, especially the EU database right.

| Source | Class | Use for | Limits |
|---|---|---|---|
| **Wikidata** (CC0) | green | id crosswalk (AniList P8729/P8731, MAL P4086/P4087, ANN P1985/P1984, AniDB P5646, MangaUpdates P11149, TheTVDB P4835, TMDB P4983/P4947, Open Library P648), titles en/ja, dates, episode counts, genres, relations (based on / follows / followed by), official website, Wikipedia article links | WDQS: 60 s per query, ≤ 5 parallel queries, User-Agent with working contact required |
| **Wikimedia pageviews** (CC0) | green | popularity and trending signal (monthly and 30-day views of the title's en/ja Wikipedia article) | User-Agent required; per-article REST calls |
| **MangaUpdates API** | green | manga backbone: titles, type, year, status, genres, categories (with votes), authors, publishers, related series, rating | already used by `release-intake`; ≥ 1.1 s spacing, one shared budget |
| **Open Library** | green | manga volume ISBNs and volume facts; covers only if §7 Q3 says yes | polite rate, User-Agent |
| **Anime News Network encyclopedia API** | amber | anime backbone for titles Wikidata lacks: titles, type, vintage, episodes, running time, genres/themes, staff and cast, companies, related titles, ratings | credit + link to ANN required on pages that show its data; batch ≤ 50 ids per request; published rate limit verified in Task 4 Step 1 |
| **TheTVDB** (paid licence) or **TMDB** (commercial agreement, ≤ 6-month cache) | amber, gate L1 | episodes, episode titles, air dates, next airing | one of the two, chosen after quotes |
| **Wikipedia text** (CC BY-SA) | amber, gate L2 | plot facts as input to own synopses | attribution + share-alike on the derived text |
| Kuro's own data | owned | editorial synopses, editorial tags, library-add counts, taste signals, typographic artwork (`KuroArtWordFill`, branded tiles) | — |

Considered and rejected: AniList, MAL/Jikan, Simkl, Trakt, Shikimori (terms forbid this use);
MangaDex (no ads or paid services); AnimeThemes (no commercial use); anime-offline-database
(archived 2026-07-04 and itself compiled from the forbidden sources, so the provenance problem
moves with it); Kitsu and AniDB (terms not reviewed; AniDB's tag data is the best tag source
available, so §7 Q6 asks for its terms check before excluding it for good).

**Coverage measured 2026-11-09** (Wikidata items carrying the AniList id that a Kuro row holds,
ranked by Kuro `popularity`):

| | top 1,000 | top 5,000 | top 10,000 | whole catalogue | titles in user lists |
|---|---|---|---|---|---|
| anime (21,867) | 949 (95 %) | 3,911 (78 %) | 5,966 (60 %) | 7,232 (33 %) | 32 of 34 |
| manga (41,899) | 734 (73 %) | 2,562 (51 %) | 3,904 (39 %) | 7,128 (17 %) | 12 of 12 |

So Wikidata is the crosswalk for well-known titles; ANN (anime) and MangaUpdates (manga) must
carry the long tail. The long tail may end up smaller than today: titles that no allowed source
knows are hidden from browsing (never deleted, never removed from a user's list; §4.6).

## 3. Architecture

Ingest stays offline and batch. **App read paths do not change**: the app keeps reading the
published `anime` / `manga` tables and their link tables. What changes is who writes them.

```
sources ──► catalogue-intake (Edge Function, one per run, per source handler)
              │  raw payload + licence + hash
              ▼
        catalogue_source_records ──► catalogue_id_links (crosswalk: Kuro id ↔ source id)
              │
              ▼  precedence policy (pure TS, per field)
        catalogue_shadow_values (what the new sources say, per Kuro title, per field)
              │
              ├─► comparator report (coverage, agreement with today's values)  [shadow phase]
              │
              ▼  only for field groups switched to 'new' in catalogue_cutover
        anime / manga / link tables (published), with field provenance
```

- **One Edge Function `catalogue-intake`** with handlers per source (`wikidata`, `ann`,
  `mangaupdates`, `pageviews`, `episodes`), plus `compose`, `publish`, `restore` (rollback)
  and `create` (new titles). Same auth as the
  importers (`IMPORT_SECRET` header, because pg_cron cannot send JWTs), the same lock/cursor/run
  helpers (`bulk-import-anime/persistence.ts`: `acquireImportLock`, `startImportRun`,
  `readTrackedCursorState`, ...), moved to `_shared/` without behaviour change.
- **Raw retained.** Every fetched record is stored with source, source key, licence code,
  fetch time and payload hash (AGENTS: retain raw intake data and provenance). Unchanged
  hashes write nothing.
- **Field groups** (cutover unit): `identity`, `titles`, `facts` (format, status, dates,
  episodes, duration, season, country), `relations`, `credits`, `popularity` (popularity,
  trending, average_score, mean_score, favourites), `tags`, `adult`, `synopsis`, `episodes`
  (episode rows + next airing), `links`, `images`.
- **`catalogue_cutover(field_group, mode)`**, mode `anilist` → `shadow` → `new`. Default
  `anilist` for every group. While a group is `anilist` or `shadow`, the published data is
  exactly what the AniList jobs write today. When a group is `new`, `publish` is its **only
  writer** and every AniList-path writer skips it. One shared map
  (`_shared/catalogue/field_groups.ts`) lists, per group, the main-row columns **and** the
  linked tables. Every writer reads it:

  | Writer | What it must skip when the group is `new` |
  |---|---|
  | importer, changed-payload path (`preserveExistingColumns` → update/upsert) | the group's main-row columns |
  | importer, unchanged-payload path (`processAnimeItem` writes `next_episode_number`, `next_airing_at`, `episodes`, `total_duration` directly) | `episodes`/`facts` columns |
  | importer, linked tables (`external_links`, `episodes` rows, studios, tags, characters, staff, voice actors, `media_relations` with source `anilist`) | links → `external_links`; episodes → `episodes` rows; credits → studios/characters/staff/voice actors; tags → `anime_tags`/`manga_tags`; relations → `media_relations` (source `anilist`) |
  | `release-intake` airing (`airing.ts` writes `next_episode_number`, `next_airing_at`) | `episodes` |
  | `mirror-images` (rewrites cover/banner columns) | `images` |

  **Linked tables have no source column** (only `media_relations` has one), so a group's
  linked rows are not split by source. Instead the group has a single writer at a time. At
  the switch to `new`, `publish` replaces that title's rows for the group (delete then insert,
  per title, in one short transaction), and from then on only `publish` writes them. Relations
  keep using the existing `source` column (`kuro` rows next to `anilist` rows; readers filter
  per mode).
- **Rollback from a snapshot, not from AniList.** When a group switches to `new`, `publish`
  first copies the group's current published values (main-row columns and linked rows) into
  `catalogue_rollback_snapshots`. Rollback sets the mode back to `anilist` and runs `restore`,
  which writes the snapshot back. This is database-only and needs no AniList requests: about
  64k titles in ≤ 500-row batches is a few hundred statements, minutes rather than days.
  Values AniList changed between the switch and the rollback come back with the importer's
  next normal changed-payload pass. A forced 64k-title AniList re-pull is never used: at the
  client's 25 requests/minute it would take hours of continuous calls, and it is the bulk
  collection AniList's terms ban. Snapshots are AniList-derived data and are deleted at Task
  17 (L4).
- **New titles.** Today a title gets a Kuro row only when the AniList importer inserts it
  (`mapping.ts`, `upsert … onConflict: 'anilist_id'`). After Task 17, `create` inserts rows
  from ANN, MangaUpdates and Wikidata (`anilist_id` is nullable on every catalogue table,
  verified live). Before inserting a candidate it checks for duplicates:
  1. an accepted link to that source key means the title already exists;
  2. a title match against existing rows (§3 identity rule) of ≥ the accepted threshold
     links the candidate instead of inserting it;
  3. anything ambiguous goes to the review list.

  Until Task 17, `create` only writes a "would create" report, because the AniList importer
  still inserts on `anilist_id` and a row created first by `create` would become a duplicate.
  The report measures how many candidates the importer also inserted within 7 days, which is
  the duplicate rate the creation rules must beat.
- **People, companies, characters.** Credits from ANN need person, company and character
  rows that today are AniList records keyed by `anilist_id`. `catalogue_id_links` also covers
  these entity kinds (`staff`, `studio`, `character`, `author`). Existing rows are linked
  through Wikidata (ANN person P1982 ↔ AniList staff P11227, ANN company P1983); otherwise
  they are matched by normalised name plus a shared title, and created with `anilist_id` null
  only when nothing matches. ANN cast entries carry character names but no images; characters
  are matched within one title by normalised name.
- **Visibility.** `anime.catalogue_visibility` / `manga.catalogue_visibility`
  (`visible` | `list_only`, default `visible`). Once the identity group is `new`, `publish`
  sets `list_only` on titles with no accepted link. Every browse, search, Discover, rail and
  recommendation read filters `visible`; list, export and detail reads do not filter. Before
  the identity switch every title stays `visible`, so nothing changes.
- **Precedence policy** (`_shared/catalogue/precedence.ts`, pure, unit-tested): for each field,
  an ordered list of sources plus a merge rule. Examples: anime titles: Wikidata label (en) →
  ANN main/official English title; native title: Wikidata ja label → ANN Japanese title; manga
  facts: MangaUpdates → Wikidata; anime episodes count: ANN → Wikidata → episode provider (L1);
  relations: union of Wikidata + ANN/MU related, with type mapped to Kuro's relation set
  (SOURCE, ADAPTATION, PREQUEL, SEQUEL, SIDE_STORY, SPIN_OFF), disagreements kept as `proposed`.
- **Identity matching** for titles with no Wikidata link: normalised title (romaji/English/
  native, punctuation and season markers handled) + start year ± 1 + format, against the ANN
  title report (anime) and MangaUpdates search (manga). A unique match with score ≥ the
  accepted threshold becomes `accepted`; anything else is `proposed` and goes to a review list.
  The matching input is our existing title data; it is used only to find the record in the
  allowed source, and the published values then come from that source (gate L4 confirms).
- **Popularity index**: `popularity` = a Kuro index built from Wikipedia pageviews (last 12
  months, en + ja), ANN/MU vote counts and Kuro library adds; `trending` = 30-day pageview
  change; `average_score` = Bayesian blend of ANN and MangaUpdates ratings mapped to 0–100. The
  columns keep their names, types and ranges, so every ranking query keeps working; their
  meaning changes, and §6 measures the ranking change before cutover.
- **Tags**: the 430 tag rows keep their Kuro ids (Taste vectors and realm data stay keyed),
  their AniList descriptions are rewritten, and the title-tag links are recomputed from ANN
  genres/themes, MangaUpdates genres + categories (vote share), Wikidata genre and editorial
  tags, with `rank` = source-weighted share 0–100. Tags no allowed source supports are retired
  (kept for history, never assigned). `media_tag_vectors` and taste profiles are then rebuilt
  by the existing jobs.
- **Adult flag** (safety): a title is adult if **any** source marks it adult (ANN erotica/
  hentai genres or age rating, MangaUpdates Adult/Hentai genres, Wikidata genre). A title that
  is adult today never becomes non-adult without owner review. A title whose sources carry no adult
  data keeps today's value while AniList is still running; after Task 17 a new title with no
  adult data is treated as adult (hidden wherever adult titles are hidden) until a source or
  the owner says otherwise.
- **Synopses** (gate L2): generated or written from structured facts and allowed text only
  (Wikipedia plot under CC BY-SA with attribution, editorial notes). The synopsis worker never
  receives an AniList description again. Top 1,000 titles get editorial review before
  publication.
- **Images** (gate L3): chosen option implemented; titles without licensed art use Kuro's
  typographic artwork. The current Storage copies of AniList-hosted art are covered by L4.
- **Recommendation edges**: Kuro's own `media_similar_titles` (tag-based, already built) plus
  Kuro taste signals replace AniList community edges; measured with
  `scripts/eval_realm_rec_gold.js` before cutover.
- **Attribution in the app**: title pages show a "Sources" line (e.g. "Data: Anime News
  Network, Wikidata"), with ANN linking to the title's ANN page whenever ANN data is shown; the
  legal site lists all sources and licences.

### 3.1 Throughput: how long a full pass takes

Each invocation has a ≤ 50 s budget. Titles are processed in priority order (in a user list →
curated rails → popularity), so the top tiers in §6 fill first. The counts are from the
2026-11-09 inventory.

| Source | Work for one full pass | Requests per run | Initial schedule | Initial pass | Refresh |
|---|---|---|---|---|---|
| Wikidata | 21,867 / 500 = 44 queries (anime) + 41,899 / 500 = 84 (manga) = 128 | 4 (1 in flight, ≥ 1 s apart, ≤ ~10 s each) | every 15 min = 384 queries/day | ~8 h | daily (one pass per day) |
| ANN matching | 1 title report per medium (raise `maxBytes` to 16 MiB for it) | 1 | with the first ANN run | minutes | weekly |
| ANN records | ~20,000 anime (≈ 5,700 ANN ids via Wikidata + title matches) / 50 per request = 400 | 45 (at 1 request/1.1 s until Task 4 verifies ANN's limit) | every 30 min = 2,160/day | ~4.5 h | weekly |
| MangaUpdates | ≈ 38,200 manga without a MangaUpdates id from Wikidata → 1 search each, plus 1 fetch per accepted match (≤ 41,899) ≈ 80,000 | 45 (1 request/1.1 s) | every 2 min except 03:30–04:20 (the window around `kuro-release-intake-manga-daily` at 03:50) ≈ 695 runs ≈ 31,000/day | ~2.6 days | monthly re-fetch ≈ 1,400/day = 31 runs/day |
| Pageviews | ≤ 14,400 titles with en/ja Wikipedia articles × 2 projects = 28,800 calls (one daily-granularity call covering 365 days per article gives both the 12-month total and last-30/previous-30) | ~200 (serial, ≥ 100 ms apart, measured in Task 6; the first estimate of 450 assumed parallel calls) | one run every 5 min (anime and manga jobs offset by 5 min, each every 10 min) = 288 runs/day ≈ 57,600 calls/day | ~12 h (144 runs) | weekly: Sunday 00:00–12:00 on the same grid = 144 runs ≈ 28,800 calls |
| compose / publish | DB only; only titles whose source records changed since the last compose | ≤ 5,000 titles | hourly at :55 / :58 | ~13 runs for the first full compose | hourly |

Sustained MangaUpdates traffic of ~1 request/1.1 s for ~2.6 days is within its published
spacing. The email to MangaUpdates (L7) describes it and asks whether a slower initial pass
is preferred; if so, the initial pass is stretched (every 4 min ≈ 5.2 days) and the §6
manga gates wait for it.

## 4. Binding constraints

1. **Owner rule:** the AniList job **schedules** (`kuro-import-anime-hourly`,
   `kuro-import-anime-weekly`, `kuro-import-manga-hourly`, `kuro-import-manga-weekly`,
   `kuro-release-intake-airing-hourly`, the `mirror-images-*` jobs) and `concierge-import-anilist`
   stay unchanged until Task 17, which needs the owner's explicit authorisation after §6 passes.
   The importer, `release-intake` and `mirror-images` **code** changes only to skip switched
   groups (Task 15), and that deploy needs its own explicit owner approval.
2. **No hosted change without authorisation:** migrations are prepared in
   `supabase/prepared-migrations/`, Edge Functions are built and tested offline, cron jobs are
   written as reviewed SQL and not scheduled. Each deploy/schedule is its own owner approval.
3. **Capacity:** client read paths and their payloads are unchanged, so the qualified p95
   budgets (Browse/Search ≤ 750 ms, Home/Detail ≤ 1200 ms, Discover ≤ 1500 ms) are not
   touched; any task that adds a column to a read path or an index must show the
   representative plan. Intake runs keep a ≤ 50 s time budget per invocation, batches of
   ≤ 500 rows per statement, short transactions outside HTTP waits, and an exclusive lock per
   handler (crash recovery by lock TTL, idempotent upserts by key + hash).
4. **Shared provider budgets:** MangaUpdates is already called by `release-intake`; the two
   schedules must not overlap, and the combined worst-case rate stays ≤ 1 request per 1.1 s.
   Each source handler has one limiter per isolate, and cron schedules are staggered so two
   handlers for the same source never run at once.
5. **Identity safety:** a Kuro title never changes its `id`. An accepted crosswalk link is
   unique per (source, source key, kind) and per (Kuro row, source). Merging or splitting
   catalogue rows is out of scope; such cases go to the review list only. `create` never
   inserts a row when an accepted link or an above-threshold title match exists.
6. **No title disappears from a user's list.** `list_only` titles stay readable through every
   list, export and detail page. For a list title that no allowed source knows, what it shows
   after Task 17 depends on L4. The default is a factual stub: display title, format and year.
   Every other AniList-derived field is removed; the title comes from the user's own import
   input where we have it.
7. **User-Agent:** `Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)` (the live
   legal host; `kuro.app` does not resolve, so today's `INTAKE_USER_AGENT` must not be reused).
8. **Release switches stay separate:** applying the migration, running shadow intake, and
   switching a field group to `new` are three separate steps.

## 5. Phases

0. **Gates** (owner + lawyer, §7). Shadow work on green sources can start before them.
1. **Foundation**: tables, shared helpers, User-Agent, column map.
2. **Identity**: Wikidata crosswalk, then ANN/MangaUpdates matching for the long tail.
3. **Shadow facts**: ANN, MangaUpdates, Wikidata facts, pageviews → shadow values;
   comparator report each run.
4. **Gated content**: episodes/airing (L1), synopses (L2), images (L3), tags, recommendations.
5. **Cutover** per field group, in this order: identity → titles → facts → relations →
   credits → links → popularity → adult → tags → episodes → synopsis → images. Each group
   stays in `new` for 14 days with the §6 checks green before the next one switches.
6. **AniList off** (Task 17, owner-authorised): disable the AniList jobs, enable `create` for
   new titles, then remove AniList-only content per L4 (snapshots included).

## 6. Success parameters (cutover gates)

Measured by the comparator (`catalogue_shadow_report_v1`) on live data, read-only, and
recorded in `docs/catalogue-sources-2026-11/` with the run id. Tiers: top 1k / top 5k by
current popularity, titles in any user list, titles in curated rails, whole catalogue.

| Group | Gate to switch to `new` |
|---|---|
| identity | 100 % of titles in user lists and curated rails have an accepted non-AniList link; ≥ 95 % of top 5k anime and ≥ 85 % of top 5k manga; 0 duplicate accepted links; title-match precision ≥ 99 % on a 200-title owner-reviewed sample |
| titles | 100 % of linked titles have a display title; native title ≥ 95 % in top 5k |
| facts | where both sources have a value: start year exact ≥ 98 %, format (mapped) ≥ 97 %, episode count for finished anime ≥ 97 %; every disagreement listed for review |
| relations | ≥ 90 % of today's SEQUEL/PREQUEL pairs among linked titles reproduced; no relation to an unlinked title |
| popularity | Spearman rank correlation with today's `popularity` ≥ 0.7 on top 5k; owner reviews the top 100 Discover order before and after |
| adult | 0 titles adult today become non-adult; every newly adult title listed |
| tags | median top-5 tag overlap with today ≥ 60 % on top 5k; `eval_realm_rec_gold.js` score ≥ baseline − 5 % relative |
| episodes | for currently airing titles, next airing time within 24 h of the provider; finished titles' episode counts match the facts group |
| synopsis | own synopsis on ≥ 95 % of top 5k and 100 % of titles in user lists; top 1k editorially reviewed |
| images | per L3 decision: licensed or Kuro artwork on 100 % of visible titles; 0 hotlinks to `s4.anilist.co` |
| new titles | the "would create" report over ≥ 14 days shows a duplicate rate ≤ 2 % against titles the AniList importer inserted, with every duplicate explained |
| AniList off | every group `new` for ≥ 14 days, no gate regressed, browse-visible share at or above the threshold the owner sets from the measured matching results after Tasks 4–5 (no fixed number now: Wikidata covers 17 % of manga, so the reachable share is unknown until matching runs; titles in lists unaffected); rollback rehearsed once per group on a local copy, with its duration recorded; owner authorises |

Performance:
- The only read-path change is the `catalogue_visibility = 'visible'` predicate on browse,
  search, Discover, rail and recommendation reads (Task 15b). Each changed function gets a
  representative plan against its p95 budget. Client select lists stay unchanged, apart from
  `data_sources` on the detail read.
- Intake runs finish inside budget, with 0 provider 429 streaks > 3 per day.
- Rollback duration is measured per group and recorded with the cutover approval.

Learning goals (not release criteria): share of searches with zero results before and after
cutover (event `search_zero_results`, denominator searches, reviewed by the owner 4 weeks after
the `titles` cutover).

## 7. Owner and lawyer gates

| Id | Question | Recommended default |
|---|---|---|
| L1 | Episodes and airing: TheTVDB (paid licence) or TMDB (commercial agreement, ≤ 6-month cache)? | Ask both for quotes; choose by price and anime coverage of currently airing titles |
| L2 | Synopses: own writing from facts only, or also Wikipedia plot text under CC BY-SA (attribution + share-alike on the synopsis)? | Own writing from facts, Wikipedia as input only if counsel agrees the output is not a derivative |
| L3 | Images: (a) Kuro typographic art for all, (b) licensed art from the L1 provider with attribution, (c) publisher press kits case by case | (a) everywhere now, (b) where the L1 licence covers display |
| L4 | AniList-derived data and its transitional uses. (a) What happens to stored data at Task 17: descriptions, tag ranks, scores, rec edges, the 18,699 Storage copies of covers, episode rows, rollback snapshots, `anilist_id` and AniList-derived `mal_id`. (b) May existing titles be used to find records in the new sources? (c) May today's AniList `popularity` ranking be used once to calibrate the Kuro popularity index (Task 10)? (d) What may a list title no allowed source knows keep showing: title, format, year? | (a) delete at Task 17, keep ids only if counsel says they are facts; (b) and (c) during the transition only; (d) a factual stub (title, format, year), using the user's own import text where we have it |
| L5 | AniList list import for users (`concierge-import-anilist`): keep, replace (users upload a file exported by a third-party tool) or remove? | Keep until Task 17, then remove; MAL XML and CSV imports stay |
| L6 | ANN attribution design (wording and link placement) acceptable to ANN? | "Data: Anime News Network" with a link on every title page that shows ANN data; email ANN to confirm |
| L7 | EU database right: do the planned extractions from ANN and MangaUpdates (substantial parts of their databases) need a written licence even with API terms? | Ask counsel; email both sources describing the use |
| Q6 | AniDB terms check (best available tag data) | Check before Task 11; exclude if non-commercial |

## 8. Out of scope

Merging duplicate catalogue rows, adding titles no allowed source knows, user-generated
catalogue edits, a public API, and any change to how user lists store titles.
