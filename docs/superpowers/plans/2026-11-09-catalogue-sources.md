# Catalogue Sources Without AniList — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a catalogue pipeline fed by sources whose terms allow Kuro's use (Wikidata, Anime News Network, MangaUpdates, Wikimedia pageviews, one licensed episode provider, Kuro's own data). Run it in shadow next to the untouched AniList imports, switch field groups over one at a time once measured gates pass, and only then switch AniList off with the owner's authorisation.

**Architecture:** One Edge Function `catalogue-intake` with a handler per source stores raw records and an id crosswalk. A pure precedence module composes per-title shadow values. A comparator measures coverage and agreement against today's values. A per-field-group cutover switch decides whether `publish` or the AniList importers write each group of published columns. App read paths stay as they are; the only app change is a source credit on title pages.

**Tech Stack:** Deno Edge Functions (TypeScript, `deno test`), PostgreSQL migrations prepared in `supabase/prepared-migrations/` with the local DB harness (`scripts/db/run_local_db_tests.sh`), Node report scripts, SwiftUI (`@Observable`) for the credit line.

**Spec:** `docs/superpowers/specs/2026-11-09-catalogue-sources-design.md` (read §3, §4 and §6 before any task). Scenarios: `docs/superpowers/specs/2026-11-09-catalogue-sources/catalogue-sources.feature`.

## Owner decision 2026-11-10: AniList stops early

The owner chose to stop calling AniList before the replacement is built: "save images, then stop".
- **Images:** covers and banners (anime and manga) are downloaded once into Storage by temporary `kuro-final-mirror-*` jobs. Character and staff photos are not, and the unsaved ones get a placeholder in the app.
- **When the download finishes:**
  - the four import jobs and `kuro-release-intake-airing-hourly` are disabled with `cron.alter_job(active := false)`;
  - the nightly `mirror-images-*` jobs were already disabled on 2026-11-10;
  - the temporary jobs are unscheduled.
- **Never asked:** Kuro never asked AniList for permission.

Consequences for this plan:
- **What `anilist` mode means now:** the values frozen at the stop. The comparator compares against those values.
- **Task 15 shrinks:** the importer skip work no longer protects against live overwrites. Its publish, snapshot and restore parts still apply.
- **Task 17 Step 2 is done early.** Steps 3–5 still apply.
- **Until then:**
  - new titles stop until Task 15c runs in `insert` mode, which now has priority over report-only measurement;
  - airing times freeze until Task 9 (gate L1);
  - Task 13 decides covers for titles created after the stop.
- **The owner rule below is superseded** where it says the schedules stay unchanged.

## Global Constraints

- Owner rule (superseded in part, see above):
  - The AniList job **schedules** (`kuro-import-anime-hourly`, `kuro-import-anime-weekly`, `kuro-import-manga-hourly`, `kuro-import-manga-weekly`, `kuro-release-intake-airing-hourly`, `mirror-images-*`) and `concierge-import-anilist` are not paused or rescheduled before Task 17.
  - The **code** of the importers, `release-intake` and `mirror-images` changes in Task 15 only, and only to skip switched groups. Deploying that change is an AniList-path deploy and needs the owner's explicit approval, separate from Task 17.
- No hosted action without its own owner approval: no migration apply, function deploy, cron schedule, secret or flag change. Tasks prepare and test offline only. Read-only live queries (Management API `/database/query` with `read_only: true`) are allowed for the comparator.
- New SQL is in `supabase/prepared-migrations/20261112100000_catalogue_sources_v1.sql` (+ later `20261112100100_…`, `20261112100200_…`). DB tests are `supabase/tests/rls/120_*` upwards. New tables have RLS enabled, no anon/authenticated grants and no client policy (service-only). New functions set `search_path = public, extensions`. SECURITY DEFINER only where named, with EXECUTE revoked from `public`, `anon` and `authenticated`.
- New SQL function bodies are `plpgsql` (the DB fixture rejects `sql` bodies that reference missing objects at create time).
- User-Agent for every source request: `Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)`.
- Source rate limits: Wikidata Query Service at most 1 query in flight per handler and ≥ 1 s between queries, each query ≤ 500 ids in `VALUES`. ANN at most 50 ids per `api.xml` request and the published limit, verified in Task 4 Step 1 (default ≥ 1.1 s spacing until verified). MangaUpdates ≥ 1.1 s spacing, never overlapping `release-intake`'s MangaUpdates run. Wikimedia REST ≥ 100 ms spacing.
- Schedules and pass lengths follow the throughput table in spec §3.1, which records requests per pass, runs per day, days to full coverage and refresh interval. Any change to a limit or a schedule updates that table in the same commit.
- Run budget ≤ 50 s per invocation (`timeBudgetMs`, as in `release-intake`). Writes are batched at ≤ 500 rows per statement. No transaction is held open across an HTTP wait. There is one lock per handler (`catalogue-intake:<handler>`, TTL 900 s).
- Kuro ids never change. User list rows are never touched.
- Field groups and their published columns are defined once, in `supabase/functions/_shared/catalogue/field_groups.ts` (Task 2), and used by both `publish` and the AniList importers.
- Commit with an explicit pathspec only, because other sessions stage files in the shared index. Commit messages end with the session's attribution lines.

## Review Focus

1. **A title found in two sources with conflicting ids** (Wikidata has two items for one AniList id, or ANN has two equal matches). Expected: no accepted link, and the conflict goes to the review list. Tests: Task 3 `duplicateAniListClaimLinksNothing`, Task 4 `ambiguousMatchIsProposed`.
2. **Rollback after a cutover**, including the linked rows. Expected: the snapshot is restored without AniList requests, values never go blank, and linked rows return exactly. Test: Task 15 `rollbackRestoresSnapshotWithoutBlanking`.
3. **The adult flag drifting to non-adult** because a new source lacks adult data. Expected: today's adult stays adult and lands on the review list. Test: Task 7 `adultNeverClearsWithoutReview`.
4. **Provider throttling mid-run** (429 with Retry-After, or a slow ANN batch near the budget end). Expected: a clean stop, the cursor kept, no partial-hash write. Tests: Task 4 `retryAfterPausesAndKeepsCursor`, Task 5 `budgetStopKeepsCursor`.
5. **Titles no allowed source knows, sitting in a user's list.** Expected: they stay visible with their stored title. Test: Task 15 `unlinkedListTitleStaysReadable` (SQL) and Task 16 `hiddenFromBrowseStaysInCollection` (Swift).

## Gate dependencies

- No gate needed: Tasks 1–8, 7b, 15, 15b, 15c and 16. Task 15d also needs none, but its hosted apply waits for an app release, then owner approval.
- Task 9 needs L1, Task 12 needs L2 and Task 13 needs L3.
- Task 10's calibration step needs L4(c); without it, the index ships uncalibrated and the popularity gate decides.
- Task 11 needs Q6 answered (AniDB in or out); it can start without AniDB.
- Task 14 needs owner-reviewed gold judgments.
- Deploying Task 15's importer, `release-intake` and `mirror-images` changes needs explicit owner approval.
- Task 17 needs every §6 gate, the owner's authorisation and L4/L5.

---

### Task 1: Catalogue source tables and cutover switch (SQL)

**Files:**
- Create: `supabase/prepared-migrations/20261112100000_catalogue_sources_v1.sql`
- Create: `supabase/tests/rls/120_catalogue_sources_v1.sql`
- Modify: `supabase/tests/pending_migrations.txt` (append the new file name)

**Interfaces:**
- Produces tables:
  - `catalogue_source_records(source text, source_key text, medium text check in ('anime','manga'), payload jsonb not null, payload_hash text not null, licence text not null, fetched_at timestamptz not null default now(), primary key (source, source_key, medium))`
  - `catalogue_id_links(id bigint identity pk, kind text check in ('anime','manga','staff','studio','character','author'), kuro_id int not null, source text, source_key text, method text check in ('wikidata','id_match','title_match','name_match','editorial'), confidence numeric(4,3), status text check in ('proposed','accepted','rejected'), created_at, decided_at)` with partial unique indexes `(source, source_key, kind) where status='accepted'` and `(kind, kuro_id, source) where status='accepted'`. `kuro_id` has no FK, because it is polymorphic over six tables (same pattern as `external_links`); a DB check trigger asserts the id exists in the table named by `kind` (`anime`, `manga`, `staff`, `studios`, `characters`, `authors`).
  - `catalogue_rollback_snapshots(field_group text, medium text, media_id int, payload jsonb not null, taken_at timestamptz not null, primary key (field_group, medium, media_id))`, service-only. `payload` holds the group's main-row columns and its linked rows for that title.
  - `catalogue_shadow_values(medium, media_id, field text, value jsonb, source text, computed_at, primary key (medium, media_id, field))`
  - `catalogue_cutover(field_group text pk check in ('identity','titles','facts','relations','credits','popularity','tags','adult','synopsis','episodes','links','images'), mode text not null default 'anilist' check in ('anilist','shadow','new'), changed_at timestamptz, changed_by text)` seeded with all 12 groups in `anilist`.
  - Columns `anime.data_sources text[]` and `manga.data_sources text[]`, nullable, default null.
- `source` values: `wikidata`, `ann`, `mangaupdates`, `pageviews`, `episodes_provider`, `editorial`.

- [ ] **Step 1: Write the failing DB test** `120_catalogue_sources_v1.sql`, with these assertions:
  - `has_table_privilege('anon', t, 'select')` and the same for `authenticated` are false for each of the five tables, and so are insert/update/delete.
  - A `staff` link to a nonexistent staff id raises the trigger's error.
  - `relrowsecurity` is true for each table.
  - `select count(*) from catalogue_cutover where mode='anilist'` is 12.
  - A second accepted link for the same `(source, source_key, kind)` raises `23505`, and so does a second accepted `ann` link for the same anime.
  - A link to a nonexistent `media_id` raises the trigger's error.
  - `catalogue_id_links` rows are removed when the anime row is deleted (cleanup trigger), and user list rows are untouched.
- [ ] **Step 2: Run it and confirm it fails** — `scripts/db/run_local_db_tests.sh --only 120_catalogue` should fail on the missing relation `catalogue_source_records`.
- [ ] **Step 3: Write the migration** with the tables, indexes, RLS, revokes, the existence trigger, the delete-cleanup triggers on `anime`/`manga`, the seed rows and the two columns.
- [ ] **Step 4: Run the test and confirm it passes** — the same command should pass. Also run the whole harness (`scripts/db/run_local_db_tests.sh`) and confirm no other file regresses (exit code as documented in `supabase/tests/README.md`).
- [ ] **Step 5: Commit** — `git add` the three files only, with message `catalogue: source tables, id links, shadow values, cutover switch (prepared)`.

### Task 2: Shared intake helpers, field groups and source HTTP client

**Files:**
- Create: `supabase/functions/_shared/catalogue/field_groups.ts`, `supabase/functions/_shared/catalogue/field_groups_test.ts`
- Create: `supabase/functions/_shared/catalogue/intake_persistence.ts` (moved helpers), `supabase/functions/_shared/catalogue/source_http.ts`, `supabase/functions/_shared/catalogue/source_http_test.ts`
- Modify: `supabase/functions/bulk-import-anime/persistence.ts` (re-export the moved helpers; no behaviour change)
- Modify: `supabase/functions/_shared/polite_fetch.ts` (add a text response mode)

**Interfaces:**
- Produces:
  - `export type FieldGroup = 'identity'|'titles'|'facts'|'relations'|'credits'|'popularity'|'tags'|'adult'|'synopsis'|'episodes'|'links'|'images'`
  - `export const FIELD_GROUP_COLUMNS: Record<'anime'|'manga', Record<FieldGroup, readonly string[]>>`. Anime facts are `format, status, start_date_year, start_date_month, start_date_day, end_date_year, end_date_month, end_date_day, episodes, duration, total_duration, season, season_year, country_of_origin, source`. Titles are `title_english, title_romaji, title_native, title_synonyms`. Popularity is `popularity, trending, average_score, mean_score, favourites`. Adult is `is_adult`. Synopsis is `description`. Images are `cover_image_large, cover_image_medium, cover_image_color, banner_image`. Episodes are `next_episode_number, next_airing_at`. Identity is `mal_id`. Manga uses the same groups, except facts are `format, status, start_date_*, end_date_*, chapters, volumes, country_of_origin, source` and episodes become `next_chapter_number, next_chapter_at` (live columns, 2026-11-09). `genres` belongs to tags. `site_url` and `age_rating` belong to links and adult respectively.
  - `export const FIELD_GROUP_TABLES: Record<'anime'|'manga', Partial<Record<FieldGroup, readonly string[]>>>`, the linked tables each group owns:
    - links → `external_links`
    - episodes → `episodes` (anime) / `chapters`, `volumes` (manga)
    - credits → `anime_studios`, `anime_characters`, `anime_staff`, `character_voice_actors` (anime) / `manga_authors`, `manga_characters`, `manga_staff` (manga)
    - tags → `anime_tags` / `manga_tags`
    - relations → `media_relations` rows with the writer's own `source`
  - `export function columnsOwnedByNew(medium, modes: Record<FieldGroup, Mode>): Set<string>`
  - `export function groupIsAniListOwned(group: FieldGroup, modes): boolean`. This is the single check every AniList-path writer uses before touching a group's linked tables.
  - `export async function readCutoverModes(supabase): Promise<Record<FieldGroup, Mode>>`. A read failure throws, so the importer fails closed and skips nothing.
  - `export const CATALOGUE_USER_AGENT = "Kuro-Catalogue/1.0 (+https://kuro-legal.vercel.app/kontakt.html)"`
  - `createPoliteClient({ ..., responseType?: 'json' | 'text' })`. `PoliteResponse` gains `text?: string`. Default `'json'` keeps every current caller unchanged.
  - `export function createSourceClient(source: 'wikidata'|'ann'|'mangaupdates'|'pageviews', limiter: PoliteLimiter, deps?)` sets the User-Agent header on every request.

- [ ] **Step 1: Write the failing tests:**
  - `field_groups_test.ts::everyPublishedColumnHasOneGroup`: for each medium, the union of groups has no duplicates and every column exists in the live column list pasted as a fixture (from the 2026-11-09 schema query).
  - `columnsOwnedByNewEmptyWhenAllAniList`
  - `columnsOwnedByNewReturnsFactsColumns`
  - `everyLinkedTableHasOneGroup`: each table listed in `FIELD_GROUP_TABLES` belongs to exactly one group per medium.
  - `source_http_test.ts::userAgentOnEveryRequest`: a fake fetch captures headers, and the UA equals `CATALOGUE_USER_AGENT`.
  - `textModeReturnsBody`
  - `jsonModeUnchangedForExistingCallers`
- [ ] **Step 2: Run them and confirm they fail** — `cd supabase/functions/_shared && deno test catalogue/` should fail because the modules are missing.
- [ ] **Step 3: Implement** the modules. Move the lock/run/cursor helpers by re-export so that `bulk-import-anime` and `bulk-import-manga` tests stay green unchanged.
- [ ] **Step 4: Run the tests and confirm they pass:**
  - `deno test catalogue/` in `_shared`, and `deno test` in `_shared` overall;
  - `cd ../bulk-import-anime && deno test`, `cd ../bulk-import-manga && deno test`, and `cd ../release-intake && deno test` should all pass, unchanged.
- [ ] **Step 5: Commit** the listed files only.

### Task 3: Wikidata crosswalk and facts handler

**Files:**
- Create: `supabase/functions/catalogue-intake/index.ts`, `handler.ts`, `handler_test.ts`
- Create: `supabase/functions/catalogue-intake/wikidata.ts`, `wikidata_test.ts`, `fixtures/wikidata_*.json`

**Interfaces:**
- Consumes: Task 1 tables, Task 2 `createSourceClient`, `intake_persistence`.
- Produces:
  - `run(payload: { handler: 'wikidata'|'ann'|'mangaupdates'|'pageviews'|'compose'|'publish', medium?: 'anime'|'manga', limit?: number, timeBudgetMs?: number }, deps)`. Auth works like `bulk-import-anime/index.ts`: `x-import-secret` must equal `IMPORT_SECRET`, otherwise 401, and a missing secret gives 500.
  - `wikidataCrosswalk(deps, medium, kuroRows: {id, anilist_id}[]): Promise<{ linked: number; conflicts: Conflict[] }>`. It queries items by AniList property (P8729 anime, P8731 manga) in `VALUES` batches of ≤ 500. Per item it collects P4086/P4087 (MAL), P1985/P1984 (ANN), P5646 (AniDB), P11149 (MangaUpdates), P4835 (TheTVDB), P4983/P4947 (TMDB), P648 (Open Library), the en/ja labels and aliases, P577/P580/P582 dates, P1113 episode count, P136 genre, P144/P155/P156/P4969 relations, P856 official website and the enwiki/jawiki sitelinks.
  - It writes one `catalogue_source_records` row per item (`source='wikidata'`, `source_key=Q-id`, `licence='CC0-1.0'`), and accepted links with `method='wikidata'`, `confidence=1`.

- [ ] **Step 1: Write the failing tests:**
  - `linksThroughHeldAniListId`: the feature scenario "Wikidata links a title…", with fixture Q123.
  - `duplicateAniListClaimLinksNothing`: two items claim the same AniList id, so there are no accepted links and `conflicts.length === 1`.
  - `unchangedPayloadWritesNothing`: the same hash produces zero upserts, checked through a fake supabase recorder.
  - `batchesAtMost500Ids`: 1,201 rows give 3 queries.
  - `wrongSecretIs401`
  - `lockHeldReturnsSkipped`
- [ ] **Step 2: Run them and confirm they fail** — `cd supabase/functions/catalogue-intake && deno test` should fail because the module is missing.
- [ ] **Step 3: Implement** `handler.ts` (dispatch, lock, run record, cursor `catalogue-intake:wikidata:<medium>`) and `wikidata.ts`. Use SPARQL `SELECT … WHERE { VALUES ?aid { "…" } ?item wdt:P8729 ?aid . OPTIONAL … }` with string literals, because AniList ids are stored as strings in Wikidata.
- [ ] **Step 4: Run the tests and confirm they pass** with `deno test`.
- [ ] **Step 5: Commit.**

### Task 4: Anime News Network matching and records (anime long tail)

**Files:**
- Create: `supabase/functions/catalogue-intake/ann.ts`, `ann_test.ts`, `fixtures/ann_report_*.xml`, `fixtures/ann_api_*.xml`
- Create: `supabase/functions/_shared/catalogue/normalise_title.ts`, `normalise_title_test.ts`

**Interfaces:**
- Produces:
  - `normaliseTitle(raw: string): string` lowercases, applies NFKC, strips punctuation and the articles `the/a`, folds `season N`/`Nth season`/`part N`/roman numerals into a ` sN` suffix, and collapses whitespace.
  - `annMatch(kuro: {id, titles: string[], year: number|null, format: string|null}[], report: AnnReportRow[]): { accepted: Link[]; proposed: Link[] }`. A match is accepted only when exactly one candidate scores ≥ 0.92 and the runner-up is < 0.80. The score is title similarity (1.0 exact normalised, else token Jaccard), × 1.0 if the year is within ±1 (otherwise × 0.5), × 1.0 if the type maps (TV↔TV, movie↔MOVIE, OAV↔OVA, ONA↔ONA, special↔SPECIAL), otherwise × 0.7.
  - `annFetch(deps, ids: number[]): Promise<AnnRecord[]>` takes ≤ 50 ids per `https://cdn.animenewsnetwork.com/encyclopedia/api.xml?anime=…` request and parses titles (main, official English, Japanese, alternatives), type, vintage, number of episodes, running time, genres, themes, staff and cast (as facts), companies, related titles, ratings (votes, weighted score) and the ANN page URL. It stores records with `licence='ANN-credit-link'`.
  - The title report comes from `https://www.animenewsnetwork.com/encyclopedia/reports.xml?id=155&type=anime&nlist=all`, cached as a source record keyed `report:anime`.

- [ ] **Step 1: Verify ANN's published API terms and rate limit** on the ANN encyclopedia API page. Record the exact quoted lines (attribution, rate, batch size) in `docs/catalogue-sources-2026-11/sources/ann.md`. If they are stricter than the Global Constraints, update the constants in this task and record a ruling.
- [ ] **Step 2: Write the failing tests:**
  - `normalise_title_test.ts`, with 12 table cases including "Shingeki no Kyojin Season 2" → "shingeki no kyojin s2", "Re:ZERO -Starting Life in Another World-" → "re zero starting life in another world", and full-width characters.
  - `ann_test.ts::uniqueMatchAccepted` and `ambiguousMatchIsProposed` (the feature scenario).
  - `yearOffByTwoNotAccepted`
  - `batchesAtMost50Ids`
  - `parsesFixtureRecord`: fields from `fixtures/ann_api_one.xml`.
  - `retryAfterPausesAndKeepsCursor`: a 429 with `Retry-After: 30` near the budget end gives a clean stop, the cursor stays unchanged, and nothing is written for that batch.
- [ ] **Step 3: Run them and confirm they fail.**
- [ ] **Step 4: Implement** `normalise_title.ts` and `ann.ts`. Parse XML with `deno-dom` or a minimal XML parser (`jsr:@libs/xml`), chosen by what `deno.json` allows. Do not use regex parsing. Wire `handler: 'ann'` to match titles without an accepted ANN link (from Wikidata), then fetch records for accepted ids.
- [ ] **Step 5: Run the tests and confirm they pass**, then **commit**.

### Task 5: MangaUpdates matching and records (manga backbone)

**Files:**
- Create: `supabase/functions/catalogue-intake/mangaupdates.ts`, `mangaupdates_test.ts`, `fixtures/mu_*.json`
- Read first: `supabase/functions/release-intake/manga.ts` (the existing MangaUpdates client usage)

**Interfaces:**
- Produces:
  - `muMatch(kuro, searchResults)`, with the same acceptance rule as `annMatch`, type map `Manga↔MANGA, Manhwa/Manhua↔MANGA + country, Novel↔NOVEL, One-shot↔ONE_SHOT`.
  - `muFetch(deps, seriesIds)` reads `GET https://api.mangaupdates.com/v1/series/{id}` and returns titles, associated names, type, year, status, completed, genres, categories with votes, authors, publishers, related series, bayesian rating, rating votes and the series URL (`licence='MU-API'`).
  - Search uses `POST https://api.mangaupdates.com/v1/series/search {search, perpage: 10}`, only for manga without an accepted MangaUpdates link from Wikidata.

- [ ] **Step 1: Write the failing tests:**
  - `uniqueMatchAccepted`
  - `manhwaMapsWithCountry`
  - `budgetStopKeepsCursor`
  - `parsesFixtureSeries`
  - `sharedSpacingAtLeast1100ms`: a fake clock records request times.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement**, reusing `createPoliteClient` with its own `PoliteLimiter(1_100)`.
- [ ] **Step 4: Run the tests and confirm they pass**, then **commit.**

### Task 6: Wikimedia pageviews records

**Files:**
- Create: `supabase/functions/catalogue-intake/pageviews.ts`, `pageviews_test.ts`

**Interfaces:**
- Produces `pageviewsFetch(deps, articles: {mediaKey, project: 'en.wikipedia'|'ja.wikipedia', title}[])`, which makes one call per article: `https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/{project}/all-access/user/{title}/daily/{start}/{end}` covering the last 365 days. That single response gives the 12-month total and the last-30 and previous-30 sums (spec §3.1 counts one call per article per project). It stores one record per Kuro title (`source='pageviews'`, `licence='CC0-1.0'`) containing `{total365: number, last30: number, prev30: number}`. Articles come from Wikidata sitelinks (Task 3).

- [ ] **Step 1: Write the failing tests:** `encodesTitlesWithSlashesAndSpaces`, `missingArticleStoresZeros` (a 404 means zeros, not an error) and `sumsBothProjects`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the tests and confirm they pass**, then **commit.**

### Task 7: Precedence, source mappers and composer

**Files:**
- Create: `supabase/functions/_shared/catalogue/precedence.ts`, `precedence_test.ts`
- Create: `supabase/functions/catalogue-intake/map_wikidata.ts`, `map_ann.ts`, `map_mangaupdates.ts`, `compose.ts`, `compose_test.ts`

**Interfaces:**
- Produces:
  - `type SourceValue = { source: Source; value: unknown }`
  - `export const PRECEDENCE: Record<'anime'|'manga', Record<string /*column*/, readonly Source[]>>`, using the spec §3 examples. Anime: `title_english` from wikidata, then ann; `title_native` from wikidata, then ann; `title_romaji` from ann, then wikidata; `format`/`episodes`/`duration` from ann, then wikidata. Manga: every facts column from mangaupdates, then wikidata.
  - `pick(column, medium, values: SourceValue[]): SourceValue | null`
  - `composeAdult(today: boolean|null, sourcesSayAdult: boolean[]): { value: boolean; review: boolean }` — true if any source says true. If `today === true` and no source says true, it returns `{ value: true, review: true }`.
  - `mapRelations(...)` maps to `SOURCE|ADAPTATION|PREQUEL|SEQUEL|SIDE_STORY|SPIN_OFF` only. A relation target without an accepted link is dropped.
  - Each `map_*.ts` exposes `toSourceValues(record): Record<column, unknown>`, using the Task 2 column names.
  - `compose(deps, medium, mediaIds)` upserts `catalogue_shadow_values` for every column that has a value, plus `data_sources` (the distinct sources used, ordered by count).

- [ ] **Step 1: Write the failing tests:**
  - `precedence_test.ts::firstSourceWithValueWins` (feature: "Precedence picks…").
  - `nullAndEmptyStringSkipped`
  - `adultAnySourceTrue`
  - `adultNeverClearsWithoutReview` (the feature scenario)
  - `relationToUnlinkedTitleDropped`
  - `compose_test.ts::writesDataSources`
  - `idempotentSecondRunNoWrites`
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.** The adult inputs are:
  - ANN genre `erotica` or theme `hentai`, or an age rating containing `AO`/`18+`;
  - MangaUpdates genres `Adult` or `Hentai`;
  - the Wikidata genre items for hentai and erotic anime/manga. Look up their Q-ids with a SPARQL label query in this step and record them, with the query, in the test fixture comment. Two Q-ids guessed while writing this plan did not resolve, so do not copy ids from memory.
- [ ] **Step 4: Run the tests and confirm they pass**, then **commit.**

### Task 7b: Credits: people, companies and characters

**Files:**
- Create: `supabase/functions/catalogue-intake/entities.ts`, `entities_test.ts`
- Modify: `supabase/functions/catalogue-intake/wikidata.ts` (adds a staff/company crosswalk query: items with P1982 ANN person ID and/or P11227 AniList staff ID; P1983 ANN company ID)

**Interfaces:**
- Consumes: `catalogue_id_links` kinds `staff`, `studio`, `character`, `author` (Task 1). ANN cast and staff from Task 4 records. MangaUpdates authors from Task 5 records.
- Produces:
  - `resolvePerson(deps, source, sourceKey, name, titleKuroId): Promise<{ kuroId: number; created: boolean } | { review: true }>`. Resolution order:
    1. an accepted link;
    2. a Wikidata crosswalk to an existing `staff.anilist_id`, which becomes an accepted `wikidata` link;
    3. a normalised-name match among people already credited on the same Kuro title (`name_match`, accepted only when unique);
    4. otherwise, insert a new `staff` row (`anilist_id` null) with the source key linked.

    The same applies to `resolveStudio`, and to `resolveAuthor` for manga.
  - `resolveCharacter(deps, titleKuroId, name)` matches only within that title's existing characters by normalised name. Otherwise it inserts a character with no image.
  - Compose writes shadow fields `credits:staff`, `credits:studios`, `credits:characters` (and `credits:authors` for manga) as jsonb lists of `{kuro_id, role}`.

- [ ] **Step 1: Write the failing tests:**
  - `wikidataPersonLinksExistingStaff`
  - `sameNameOnSameTitleReused`
  - `sameNameOnDifferentTitleNotMerged`: it creates a new row, or goes to review if the name matches two people.
  - `newPersonCreatedWithNullAniListId`
  - `characterMatchedOnlyWithinTitle`
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.** Creation of new rows happens here only in shadow mode; it writes `proposed` entity rows to the report. Real inserts happen once the `credits` group switches (Task 15), because until then the AniList importer remains the writer of these tables.
- [ ] **Step 4: Run the tests and confirm they pass**, then **commit.**

### Task 8: Comparator report

**Files:**
- Create: `supabase/prepared-migrations/20261112100100_catalogue_shadow_report_v1.sql`, `supabase/tests/rls/121_catalogue_shadow_report_v1.sql`
- Create: `scripts/catalogue_shadow_report.js`, `scripts/catalogue_shadow_report.test.js`
- Create: `docs/catalogue-sources-2026-11/README.md`, which describes the report folder and the run-id rule.

**Interfaces:**
- Produces `catalogue_shadow_report_v1(p_medium text, p_sample int default 20) returns jsonb` (SECURITY DEFINER, service role only). Per field group and tier (`top1k`, `top5k`, `in_lists` from `*_user_lists`, `curated` from `curated_rail_items`, `all`), it returns `{covered, compared, agreed, disagree_sample[]}`. Agreement rules come from spec §6: start year exact, format mapped, episodes exact for `FINISHED`, title compared after `normaliseTitle`-equivalent SQL (lower, unaccent, punctuation stripped). It also returns identity gate counts and the adult review list size.
- `scripts/catalogue_shadow_report.js --medium anime|manga --out docs/catalogue-sources-2026-11/runs/<date>-<medium>.json` calls the RPC via the service key from the environment and writes JSON plus a Markdown summary comparing each §6 gate (pass/fail/insufficient).

- [ ] **Step 1: Write the failing DB test** `121_…`: on a fixture of 6 anime (2 agreeing, 1 disagreeing on year, 1 uncovered, 1 in a user list, 1 curated), the report returns the exact counts per tier. EXECUTE is denied to anon and authenticated.
- [ ] **Step 2: Write the failing Node test**: `gateEvaluation` maps report JSON to pass/fail/insufficient. Fewer than 30 compared rows in a tier gives `insufficient`, never `pass`.
- [ ] **Step 3: Run both and confirm they fail.**
- [ ] **Step 4: Implement both.**
- [ ] **Step 5: Run both and confirm they pass**, then **commit.**

### Task 9: Episodes and airing provider (gate L1)

**Files:**
- Create: `supabase/functions/catalogue-intake/episodes_provider.ts`, `episodes_provider_test.ts`
- Create: `docs/catalogue-sources-2026-11/sources/episodes-provider.md` (licence summary, cache limit, attribution)

**Interfaces:**
- Produces `episodesFetch(deps, links)` for the provider chosen in L1, keyed by the TheTVDB (P4835) or TMDB (P4983) id from the crosswalk. It returns episode rows `{number, title, air_date, runtime}` and `next_airing_at`. TMDB data is refetched at least every 6 months (cache limit) through `fetched_at`. Its shadow fields are `next_episode_number`, `next_airing_at`, and `episodes:list` (jsonb list).

- [ ] **Step 1: Do not start until L1 is decided.** Record the decision and licence lines in the source doc.
- [ ] **Step 2: Write the failing tests:**
  - `nextAiringWithin24hOfProvider` (feature)
  - `cacheOlderThanLimitRefetched`
  - `finishedShowHasNoNextAiring`
- [ ] **Step 3: Run them and confirm they fail.**
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run the tests and confirm they pass**, then **commit.**

### Task 10: Kuro popularity index

**Files:**
- Create: `supabase/functions/_shared/catalogue/popularity.ts`, `popularity_test.ts`
- Modify: `supabase/functions/catalogue-intake/compose.ts` (popularity group)

**Interfaces:**
- Produces `popularityIndex(input: {views12m: number /* total365 */; votes: number; libraryAdds: number}): number`. The result is an integer on the same scale as today's `popularity` column: `round(views12m/12 * 0.02 + votes * 1 + libraryAdds * 50)`. The coefficients are starting values; Step 4 calibrates them against today's ranking.
- `trendingIndex(last30, prev30): number` returns `round(max(0, last30 - prev30) / 100)`.
- `scoreIndex(ann?: {weighted: number; votes: number}, mu?: {bayesian: number; votes: number}): number | null` gives a 0–100 vote-weighted blend (ANN 0–10 × 10, MU 0–10 × 10), or null below 20 combined votes.

- [ ] **Step 1: Write the failing tests:** `monotonicInViews`, `nullScoreUnder20Votes`, `trendingNeverNegative` and `scalesToIntegerColumn`.
- [ ] **Step 2: Run them, confirm they fail, implement, then run them and confirm they pass.**
- [ ] **Step 3: Wire the functions into compose (shadow only).**
- [ ] **Step 4: Calibrate (needs L4(c)).** Comparing against today's AniList `popularity` is itself a use of AniList data. Only do this step if counsel allows it under L4(c); otherwise skip it, ship the starting coefficients and let the owner's Discover top-100 review decide. If allowed, run compose plus the comparator read-only on live data and compute the Spearman correlation against today's `popularity` for the top 5k. Adjust the coefficients until the correlation is ≥ 0.7 or the coefficients stop improving it, and record the values and the result in `docs/catalogue-sources-2026-11/runs/`. Never fit to AniList `trending` or scores directly beyond this one rank check.
- [ ] **Step 5: Commit.**

### Task 11: Kuro tag assignments

**Files:**
- Create: `supabase/prepared-migrations/20261112100200_catalogue_tag_sources_v1.sql`, `supabase/tests/rls/122_catalogue_tag_sources_v1.sql`
- Create: `supabase/functions/_shared/catalogue/tags.ts`, `tags_test.ts`
- Create: `docs/catalogue-sources-2026-11/tag-map.csv` (source label → Kuro tag id, reviewed by the owner)

**Interfaces:**
- Produces:
  - `catalogue_tag_source_map(source text, source_label text, tag_id int references tags(id), weight numeric, primary key(source, source_label))`, service-only.
  - `tags.description_kuro text` and `tags.retired_at timestamptz` columns. AniList descriptions stay in `description` until Task 17.
  - `assignTags(sourceLabels: {source, label, votes?: number}[], map): {tag_id: number; rank: number}[]`. Rank is the source-weighted share 0–100. A MangaUpdates category counts only with ≥ 2 positive votes. At most 20 tags per title.
  - Compose writes the shadow field `tags:list`.

- [ ] **Step 1: Build the first `tag-map.csv`.** Map every ANN genre/theme, every MangaUpdates genre, the top 500 MangaUpdates categories by frequency and the Wikidata genres seen in records to the existing 430 tag ids by name. Leave unmatched labels blank. This is for owner review; it is not a guess at completeness.
- [ ] **Step 2: Write the failing tests:**
  - `tags_test.ts::rankIsWeightedShare`
  - `categoryNeedsTwoVotes`
  - `capsAt20`
  - `unmappedLabelIgnored`
  - DB `122`: map rows are service-only, a retired tag is never returned by `assign` input, and Taste reads are unaffected (existing `media_tag_vectors` definition unchanged).
- [ ] **Step 3: Run them, confirm they fail, implement, then run them and confirm they pass.**
- [ ] **Step 4: Write the 430 Kuro tag descriptions** (`description_kuro`) as one reviewed SQL data file in the same migration. They are written fresh, never paraphrased from AniList's text.
- [ ] **Step 5: Commit.**

### Task 12: Synopsis input without AniList text (gate L2)

**Files:**
- Modify: `scripts/synopsis_enrichment_worker.swift` (the prompt input)
- Create: `supabase/prepared-migrations/20261112100300_synopsis_inputs_v2.sql` (a new `get_synopsis_enrichment_candidates_v2` returning shadow facts + allowed text instead of `description`), plus DB test `123_synopsis_inputs_v2.sql`

**Interfaces:**
- `get_synopsis_enrichment_candidates_v2(p_medium text, p_limit int)` returns `(media_id, title, facts jsonb, allowed_text text, allowed_text_licence text)`. `allowed_text` is null unless L2 allows Wikipedia text. It never selects `description`.

- [ ] **Step 1: Do not start until L2 is decided.**
- [ ] **Step 2: Write the failing DB test**: on a fixture whose `description` holds the sentinel `ANILIST-SENTINEL-7f3a`, no column of any row the function returns contains the sentinel. This tests the output, not the function text, which comments or names like `description_kuro` would confuse. EXECUTE is limited to service_role.
- [ ] **Step 3: Write a failing worker test** (`synopsisInputHasNoAniListText`, Swift script test or a fixture run): the built prompt contains no text from a fixture AniList description.
- [ ] **Step 4: Implement both, then run them and confirm they pass.** Editorial review for the top 1k is tracked as an owner checklist in `docs/catalogue-sources-2026-11/synopsis-review.md`.
- [ ] **Step 5: Commit.**

### Task 13: Images (gate L3)

**Files:**
- Modify: `supabase/functions/mirror-images/source_fetch.ts` (`APPROVED_SOURCE_HOSTS` gains only the L3-approved host)
- Modify: `supabase/functions/catalogue-intake/compose.ts` (images group)
- Modify: the card artwork fallback owner. Find it with `python3 scripts/agents/policy.py --files '*Artwork*.swift'` and `--files '*HomePagePicture*.swift'` (where `KuroArtWordFill` lives).

**Interfaces:**
- Images group shadow values: `cover_image_large`/`cover_image_medium` come from the approved provider, or null, meaning Kuro typographic art. `banner_image` is null unless licensed.

- [ ] **Step 1: Do not start until L3 is decided.**
- [ ] **Step 2: Write the failing tests:**
  - `mirror_run_test.ts::onlyApprovedHostsMirrored` (the new host is accepted and `s4.anilist.co` is still accepted until Task 17);
  - a Swift snapshot test showing that a card with a nil cover renders `KuroArtWordFill` with the title.
- [ ] **Step 3: Run them, confirm they fail, implement, then run them and confirm they pass**, then **commit.**

### Task 14: Recommendations without AniList edges

**Files:**
- Modify: `scripts/eval_realm_rec_gold.js` (add arm (d): Kuro similarity on shadow tags, read from an exported shadow tag file)
- Create: `eval/realm_rec_gold/judgments_owner.jsonl` (owner-reviewed judgments for the 100 seeds)

**Interfaces:**
- Arm (d) computes cosine similarity over the shadow tag vectors (`tags:list`, rank-weighted) within the same realm gate as arm (b). The report prints precision@10 for (a)–(d) on `judgments_owner.jsonl`.

- [ ] **Step 1: Have the owner review the judgments.** Copy the current heuristic judgments to `judgments_owner.jsonl` and have the owner review them. Heuristic judgments derived from AniList edges are not used for the gate.
- [ ] **Step 2: Write a failing Node test** `armDUsesOnlyShadowTags`: with an injected fixture, arm (d) never reads `media_rec_edges`.
- [ ] **Step 3: Implement, then run the test and confirm it passes.** Run the eval read-only and record the precision@10 of each arm in `docs/catalogue-sources-2026-11/runs/`. The gate is (d) ≥ (b) − 5 % relative.
- [ ] **Step 4: Commit.** Switching the recommend RPCs off `media_rec_edges` is part of the `tags` cutover in Task 15. Only the eval change lands here.

### Task 15: Single writer per group: publish, snapshot/restore, and every AniList-path writer skips switched groups

**Files:**
- Create: `supabase/functions/catalogue-intake/publish.ts`, `publish_test.ts`, `restore.ts`, `restore_test.ts`
- Modify: `supabase/functions/bulk-import-anime/mapping.ts` and `supabase/functions/bulk-import-manga/mapping.ts`, covering three write paths, each with its own test:
  1. **Changed-payload path:** drop `columnsOwnedByNew(medium, modes)` in `preserveExistingColumns`, before the update and before the insert upsert.
  2. **Unchanged-payload path:** in `processAnimeItem`, the `existing && !isStale` branch writes `next_episode_number`, `next_airing_at`, `episodes` and `total_duration` directly. Drop the same columns from that `patch`. Apply the equivalent change to the manga branch (`next_chapter_number`, `next_chapter_at`, `chapters`, `volumes`).
  3. **Linked tables:** skip the `external_links`, `episodes`, studios, tags, characters, staff and voice-actor writes and the `media_relations` (`source='anilist'`) replace for each group where `groupIsAniListOwned(group, modes)` is false.
- Modify: `supabase/functions/bulk-import-anime/handler.ts`, `supabase/functions/bulk-import-manga/handler.ts`: read modes once per run (`readCutoverModes`) and pass them down.
- Modify: `supabase/functions/release-intake/airing.ts` (skip the `next_episode_number`/`next_airing_at` update while `episodes` is not AniList-owned; release events keep being recorded) and `release-intake/handler.ts` (read modes once per run).
- Modify: `supabase/functions/mirror-images/mirror_run.ts` (skip titles whose `images` group is not AniList-owned).
- Modify the tests: `bulk-import-anime/handler_test.ts`, `bulk-import-manga/handler_test.ts`, `release-intake/handler_test.ts`, `mirror-images/mirror_run_test.ts`.
- Create: `supabase/tests/rls/124_catalogue_publish_lists.sql`, `docs/catalogue-sources-2026-11/cron-prepared.sql`, `supabase/functions/catalogue-intake/cron_schedule_test.ts`

**Interfaces:**
- `publish(deps, medium, mediaIds)`, for each group whose mode is `new`:
  - **First publish of a group (switch moment):** write the title's current main-row columns and linked rows for that group to `catalogue_rollback_snapshots`. Then replace them from `catalogue_shadow_values`: main-row columns by update, and linked rows by deleting that title's rows in the group's tables and inserting the shadow list, in one transaction per batch of ≤ 500 titles. Relations write `media_relations` rows with `source='kuro'` and leave `anilist` rows alone. Readers pick the source per mode, which is part of this task: the relation read RPCs are found with `policy.py --rpc` and filtered to `source = 'kuro'` once relations are `new`, each with a DB test.
  - **Later runs:** update only titles whose shadow values changed.
  - It also writes `data_sources`, plus the credits entities created through Task 7b resolution (real inserts allowed now, because `publish` is the only writer).
- `restore(deps, group)` writes the snapshot back (main-row columns plus linked rows) in ≤ 500-row batches and records its duration in `import_runs`. It makes no AniList requests.
- Every AniList-path writer facing a failed mode read throws, failing closed: the page or run fails and writes nothing.

- [ ] **Step 1: Write the failing tests:**
  - `bulk-import-*/handler_test.ts::cutOverGroupColumnsNotWritten` (changed payload, feature "The AniList importer leaves a cut-over group alone");
  - `unchangedPayloadPathSkipsEpisodesGroup`: `updatedAt` is unchanged and the next episode moved, with the `episodes` group set to `new`, so no update is sent;
  - `unchangedPayloadPathSkipsFactsEpisodeCount`;
  - `linkedTablesSkippedPerGroup`: with `links` set to `new`, no `external_links` call is made, while `tags` on `anilist` still writes `anime_tags`;
  - `modeReadFailureFailsPage`;
  - `release-intake/handler_test.ts::airingUpdateSkippedWhenEpisodesNew`, while release events are still recorded;
  - `mirror_run_test.ts::switchedImagesNotRewritten`;
  - `publish_test.ts::onlyNewGroupsWritten`;
  - `firstPublishSnapshotsThenReplacesLinkedRows`;
  - `relationsKeepAniListRowsAndAddKuroRows`;
  - `restore_test.ts::rollbackRestoresSnapshotWithoutBlanking`: switch to `new`, publish, set the mode back to `anilist`, then restore. The main-row columns and linked rows equal the pre-switch state, no column is null at any step, and the fake AniList client receives zero requests.
  - DB `124::unlinkedListTitleStaysReadable`: a manga in a user list with no links keeps its row, title and list membership after a publish run.
- [ ] **Step 2: Run them and confirm they fail.** Run `deno test` in `catalogue-intake`, `bulk-import-anime`, `bulk-import-manga`, `release-intake` and `mirror-images`, plus `scripts/db/run_local_db_tests.sh --only 124`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they pass**, including every existing test in those five folders unchanged.
- [ ] **Step 5: Rehearse rollback locally.** On the local DB harness with a 2,000-title fixture, switch each group to `new`, publish, then restore. Record each group's restore duration in `docs/catalogue-sources-2026-11/rollback-rehearsal.md`, which is the spec §6 "rollback rehearsed" input.
- [ ] **Step 6: Commit.** Deploying the changed importers, `release-intake` and `mirror-images` is an AniList-path deploy. List it in the commit body as "needs explicit owner approval before deploy". No group may be switched to `new` in production until that deploy is live.
- [ ] **Step 7: Prepare the cron SQL from spec §3.1, but do not apply it.** Write it in `docs/catalogue-sources-2026-11/cron-prepared.sql`:
  - wikidata every 15 min;
  - ann every 30 min;
  - mangaupdates every 2 min, skipping 03:30–04:20 (a time-window guard inside the handler, plus the cron expression);
  - pageviews every 5 min on the initial pass, then Sunday 00:00–06:00;
  - compose hourly at :55;
  - publish hourly at :58.
  Write `cron_schedule_test.ts` with these tests:
  - `muNeverOverlapsReleaseIntake` parses both schedules plus the handler guard;
  - `passLengthsMatchSpecTable` recomputes each source's initial pass and refresh from the constants and the 2026-11-09 counts, and fails if they differ from §3.1 by more than 10 %.

### Task 15b: Browse visibility (`list_only` titles)

**Files:**
- Create: `supabase/prepared-migrations/20261112100400_catalogue_visibility_v1.sql`, `supabase/tests/rls/125_catalogue_visibility_v1.sql`
- Create: `docs/catalogue-sources-2026-11/visibility-readers.md` (inventory of every browse/search/Discover/rail/recommendation reader)

**Interfaces:**
- Columns `anime.catalogue_visibility` / `manga.catalogue_visibility text not null default 'visible' check in ('visible','list_only')`.
- `publish` sets `list_only` on titles without an accepted link, and only once the `identity` group is `new`.
- Every browse, search, Discover, rail and recommendation reader adds `catalogue_visibility = 'visible'`. List, export, detail and import-resolution readers do not.

- [ ] **Step 1: Inventory the readers.** List every SQL function and matview that serves browse, search, Discover, rails or recommendations. Find them with `python3 scripts/agents/policy.py --rpc <name>` for each RPC the app calls; the app's calls come from `rg "\.rpc\(\"" Kuro`. Record the latest definition file for each. The inventory is the task's scope; each later step covers every row in it.
- [ ] **Step 2: Write the failing DB test** `125`: for each listed reader, a `list_only` fixture title is absent, and the same title is still returned by the list read, the export identity lookup and the detail read.
- [ ] **Step 3: Run it and confirm it fails.**
- [ ] **Step 4: Implement.** Use new function versions (`…_v2` or `CREATE OR REPLACE`, matching each function's existing pattern; DROP+CREATE where the return type changes). Add a partial index only where a representative plan needs one. Record each plan against its p95 budget in `docs/catalogue-sources-2026-11/visibility-plans.md`.
- [ ] **Step 5: Run the test and confirm it passes**, plus the whole DB harness, then **commit.**

### Task 15c: New titles from allowed sources

**Files:**
- Create: `supabase/functions/catalogue-intake/create.ts`, `create_test.ts`

**Interfaces:**
- `create(deps, medium, { mode: 'report' | 'insert' })`. Candidates are:
  - ANN report ids with no accepted link (anime);
  - MangaUpdates series newer than the last run with no accepted link (manga);
  - Wikidata items carrying ANN/MangaUpdates ids with no accepted link.

  For each candidate:
  1. an accepted link means skip;
  2. a title match against existing Kuro rows that meets the §3 identity rule means add a link (not a row);
  3. ambiguous candidates go to review;
  4. otherwise, in `insert` mode, insert the row with `anilist_id` null, the shadow values for every group, `catalogue_visibility='visible'` and the accepted link, in one transaction.

  `report` mode writes the would-create list to `import_runs.results` only.
- Mode stays `report` until Task 17. In report mode, the comparator adds `new_titles` gate counts: candidates the AniList importer also inserted within 7 days count as would-be duplicates.

- [ ] **Step 1: Write the failing tests:**
  - `acceptedLinkSkips`
  - `aboveThresholdMatchLinksInsteadOfInserting`
  - `ambiguousGoesToReview`
  - `reportModeWritesNoRows`
  - `insertModeCreatesRowWithLinkAndNullAniListId`
  - `secondRunIsIdempotent`
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they pass**, then **commit.**

### Task 15d: AniList ids leave public reads

Owner request 2026-11-10: keep `anilist_id` privately (it is the Wikidata/ANN crosswalk key), but no app read, public table read or RPC returns it.

**Files:**
- Create: `docs/catalogue-sources-2026-11/anilist-id-readers.md` (inventory)
- Create: `supabase/prepared-migrations/20261112100500_anilist_id_private_v1.sql`, `supabase/tests/rls/126_anilist_id_private_v1.sql`
- Modify: `Kuro/Catalog/CatalogColumns.swift` (character/staff/author embeds), `Kuro/Catalog/CatalogStore.swift:513` (studios), `Kuro/Catalog/CatalogCreditsModels.swift`, `Kuro/Catalog/CatalogVoiceModels.swift`, `Kuro/Catalog/CatalogStore+ExportIdentities.swift`, `Kuro/Views/DetailPages/ExternalLinksSection.swift` (AniList button removed; MAL stays), `Kuro/Views/Home/SeriesDetailViews.swift`, `Kuro/Views/Routing/NavigationFixture.swift`
- Modify: `Packages/KuroModules/Sources/KuroLibrary/LibraryExportInput.swift`, `LibraryExportTabular.swift`, `Packages/KuroModules/Tests/KuroLibraryTests/LibraryExportTests.swift` (the Kuro CSV drops its AniList id column; MAL XML is unaffected, and it is the format AniList itself imports)

**Interfaces:**
- Live inventory, 2026-11-10:
  - anon and authenticated can read `anilist_id` on 12 tables: `anime`, `manga`, `authors`, `chapters`, `characters`, `curated_rail_items`, `episodes`, `rag_entity_index`, `staff`, `studios`, `tags`, `volumes`;
  - 6 matviews: `mv_{anime,manga}_{trending,top_rated,newly_added}`;
  - 2026-11-18: `mv_{anime,manga}_newly_added` are **dropped** here instead of rebuilt (backend latency step 1c, parked: `supabase/prepared-migrations/20261109200200_discover_newly_added_base_v1.sql` switches `discover_bundle`'s newly-added rails to the base tables; regenerate it from the live body). Rebuild the other four;
  - RPCs whose result has AniList columns: `anime_cast_v1`, `character_voice_actors_v1`, `staff_voice_roles_v1`, `rag_retrieve_candidates`;
  - invoker functions that read the column: `_is_blessed_canon`, `anime_cast_v1`, `character_voice_actors_v1`, `staff_voice_roles_v1`. A column revoke breaks these unless they stop reading it or become definer functions.
- Grants: on each table, `REVOKE SELECT … FROM anon, authenticated`, then `GRANT SELECT (<every other column>)`. The test asserts the column list equals the table's columns minus `anilist_id`, so a later column cannot silently go ungranted unnoticed. Matviews are rebuilt without the column. Changed RPCs are DROP+CREATE with the same names and argument lists.
- jsonb definer RPCs (`curated_rail_cards`, `discover_bundle`, `discover_section_page_v1`): the test asserts no `anilist_id` key in their output.
- **Rollout order (load-bearing):**
  1. Ship an app build that no longer reads the column.
  2. The owner confirms older builds are retired.
  3. Only then apply the migration. Applied first, the revoke breaks credits, voices and detail reads in older builds.

- [ ] **Step 1: Write the inventory** from live read-only queries (`has_column_privilege`, `pg_get_function_result`, matview definitions) and `rg anilist Kuro Packages`. The inventory is the task's scope.
- [ ] **Step 2: Write the failing tests:**
  - DB `126`: anon/authenticated `has_column_privilege(..., 'anilist_id', 'SELECT')` is false on every listed table and matview; every listed RPC runs as anon and returns no AniList column or key; `_is_blessed_canon` and the voice RPCs still return the same rows as before.
  - Swift: `CatalogColumnsTests/noSelectNamesAnilistId`; `ExternalLinksSection` renders MAL only; `LibraryExportTests/kuroCSVHasNoAniListColumn`.
- [ ] **Step 3: Run them and confirm they fail.**
- [ ] **Step 4: Implement** the app change and the prepared migration.
- [ ] **Step 5: Run them and confirm they pass**, plus the DB harness, the package tests and the focused app suites. Then **commit.** The hosted apply follows the rollout order and needs owner approval.

### Task 16: Source credit on title pages

**Files:**
- Modify: `Kuro/Catalog/CatalogColumns.swift` (detail select adds `data_sources`, and only the detail select)
- Modify: `Kuro/Catalog/CatalogModels.swift` (`dataSources: [String]?`, coding key `data_sources`)
- Modify: `Kuro/Views/DetailPages/Prototype/DetailPage.swift` (credit line)
- Create: `Kuro/Catalog/DataSourceCredit.swift` (pure mapping from source code to display name and link)
- Create: `KuroTests/DataSourceCreditTests.swift`
- Modify: `web/legal/datenschutz.html` and `web/legal/impressum.html`, or a new `web/legal/quellen.html` linked from both (sources and licences list, DE and EN)

**Interfaces:**
- `enum DataSourceCredit { static func line(for sources: [String], german: Bool) -> String?; static func link(source: String, externalLinks: [ExternalLink]) -> URL? }` — `ann` → "Anime News Network" (link from the title's ANN external link), `wikidata` → "Wikidata", `mangaupdates` → "MangaUpdates", `episodes_provider` → the L1 name. An empty or nil list returns nil, and no line is shown.
- German line: "Daten: Anime News Network, Wikidata". English line: "Data: Anime News Network, Wikidata". Body sans, secondary colour, from `KuroDesignSystem` tokens.

- [ ] **Step 1: Write the failing tests:**
  - `DataSourceCreditTests/lineOrdersAsGiven`
  - `nilWhenEmpty`
  - `germanLine`
  - `annLinkUsesExternalLink`
  - `hiddenFromBrowseStaysInCollection`: a Collection fixture holding a title with `data_sources == nil` and no links shows the stored title.
- [ ] **Step 2: Run them and confirm they fail** — `xcodebuild test` on the owned iPhone 17 Pro simulator UUID, `-only-testing:KuroTests/DataSourceCreditTests`.
- [ ] **Step 3: Implement.** Add a UI assertion to the existing detail UI test fixture (`--kuro-nav-fixture`) that the line is present when `data_sources` is set.
- [ ] **Step 4: Run the tests and confirm they pass.** Run `check_navigation.sh` and the design gate.
- [ ] **Step 5: Commit.**

### Task 17: Switch AniList off (owner-authorised hosted change)

**Files:**
- Create: `docs/catalogue-sources-2026-11/ANILIST-OFF.md` (runbook plus receipt)
- Create: `supabase/prepared-migrations/<timestamp>_anilist_content_removal_v1.sql` (per L4; written only after L4)

- [ ] **Step 1: Preconditions** — every field group has been `new` for ≥ 14 days, the last 3 comparator runs pass every §6 gate, L4 and L5 are decided, and the owner gives written authorisation for this exact step.
- [ ] **Step 2: Disable the AniList jobs.** Disable the jobs with `cron.alter_job(..., active := false)`, not `cron.unschedule`, so the change can be reverted:
  - `kuro-import-anime-hourly`
  - `kuro-import-anime-weekly`
  - `kuro-import-manga-hourly`
  - `kuro-import-manga-weekly`
  Then set `release-intake` to its non-AniList airing source (Task 9) and remove `s4.anilist.co` from `APPROVED_SOURCE_HOSTS` (deploy). Remove or replace the AniList list import per L5.
- [ ] **Step 2b: Switch `create` to `insert` mode** (Task 15c) in the prepared cron SQL. This is its own owner-approved schedule change.
- [ ] **Step 3: Watch for 7 days.** The comparator must still pass, the Discover top 100 must stay as the owner reviewed it, and the importer `import_runs` show no new AniList runs.
- [ ] **Step 4: Remove AniList-only content per L4**, rollback snapshots included, using the prepared migration with its own DB test and its own approval. List titles that no allowed source knows keep the L4(d) stub (spec §4 rule 6), and the DB test asserts every user-list title still has a display title afterwards.
- [ ] **Step 5: Update the state docs and memory.**

---

## Evidence and acceptance

Each task records its exact test commands and outputs in its commit message body. Comparator runs go to `docs/catalogue-sources-2026-11/runs/` with a run id. A field group counts as accepted only with three consecutive passing daily runs and the owner's recorded approval.
