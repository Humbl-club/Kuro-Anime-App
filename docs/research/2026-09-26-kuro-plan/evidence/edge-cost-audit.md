# Kuro edge-function calls, workload and metadata audit

Source-only audit, 26 September 2026, repository HEAD `697a5bc4548cc6b6492113f8481fb8bc8403030c`. No production queries, writes, requests, deployments or runtime benchmarks performed by this agent. This report describes current local source; deployed function versions/payloads/schedules need the parent’s live audit. Source call counts are not execution counts. SQL definitions are owned by the separate SQL audit.

## Coverage and register

`evidence/edge-call-register.csv` contains **229 source call sites** across all **16 local edge-function index.ts files**, plus the shared TypeScript file checked for calls. Breakdown: **146 table/query-builder calls, 56 RPC calls, 13 HTTP fetch calls, 10 Auth calls and 4 Storage calls**. One Storage site, `getPublicUrl`, constructs a URL locally and is **not** a network request. `auth-callback` has no server-side DB/RPC/Storage/fetch sites in local source; the other 15 functions contribute register rows.

Every lexical `.from(` / `.rpc(` call excluding JavaScript `Array.from` was reconciled against the register; no unmatched sites remained. Each row contains exact file/line, operation, table/RPC/endpoint, projection, filters/bounds, frequency/concurrency, retry/checkpoint behavior, source excerpt and the source-only evidence boundary. Dynamic anime/manga table names and variable HTTP endpoints are identified. The register is call-site exhaustive, not an exhaustive SQL query-plan or SDK-internal HTTP trace.

| Function | Sites | Workload character |
|---|---:|---|
| bulk-import-anime | 26 | Paged upstream reads, five titles concurrently, many per-entity writes |
| bulk-import-manga | 28 | Same pattern, duplicated author/staff persistence, optional placeholders |
| concierge-apply | 23 | Up to 100 concurrent item chains, reconciliation and undo logs |
| concierge-import-anilist | 3 | Auth/rate-limit plus serial AniList pages |
| concierge-parse | 10 | Nested concurrency: items and their search variants |
| concierge-recommend | 32 | Multiple rail builds and batched hydration, optional narration |
| concierge-resolve | 10 | One packed model request with budget bookkeeping |
| concierge-retrieve-assist | 5 | Cache, bounded candidate RPC, cache write |
| concierge-retrieve-feedback | 3 | Auth, rate-limit, one feedback insert |
| concierge-undo | 15 | Sequential read/restore chains |
| delete-account | 13 | User deletes plus global orphan-club scan and storage cleanup |
| manga-chapter-enrich | 28 | Sequential candidates, external matching, chapter batches |
| manga-source-review-action | 5 | Review/mapping writes plus optional one-title enrichment |
| mirror-images | 21 | Serial images, uploads and state writes |
| realm-describe | 7 | Three reads/title and model calls, one final batch write |
| auth-callback | 0 | HTML redirect handler |

**Counterevidence to a blanket “huge queries everywhere” diagnosis:** the edge table calls generally use explicit narrow projections. The only literal `select('*')` sites found are manga chapter/volume **HEAD exact counts**, which do not transfer all row bodies (`bulk-import-manga/index.ts:418`, `:437`). The larger risks here are query multiplication, SQL work behind limited RPC results, repeated unchanged writes, incomplete work budgets and unnecessary metadata reprocessing. A `LIMIT 10` response does not prove a cheap SQL plan; a HEAD count can still require database work.

All paths below are relative to `/Users/max/Kuro-Anime-App/supabase/functions/` unless explicitly labeled migrations.

## Highest-priority findings

### E1. Recommendation evaluates more rails than it displays and duplicates one

`concierge-recommend/index.ts:2406` caps preferred secondary choices at five. It builds the primary (`:2408`), builds the first fallback secondary (`:2435`), then builds all preferred secondaries again in `Promise.all` (`:2448`). The first secondary is consequently fetched twice when included in that array. Output is only two rails (`:2392`). This is a verified source duplication; its production frequency and latency are unmeasured.

Each curated build can fetch anime and manga separately via `curated_rail_cards` (`:2166`, `:2169`), then fall back to algorithmic fill when too few titles survive (`:2366`). The algorithmic path uses `recommend_ids_premium` with limit 50 (`:1535`) and explicit media/boost/tag hydration queries (`:1572`, `:1576`, `:1582`). Some premium candidate context is shared elsewhere in this function; do not multiply every rail by every possible hydration call without tracing its path. Similarity separately calls `recommend_ids_similar_to_seeds` (`:2269`) and hydrates by type (`:2288`).

**Plan:** memoize rail-build promises by mode/type/constraints within a request, remove the guaranteed duplicate, then use a bounded secondary selection strategy that preserves diversity. Record rail candidates attempted, SQL calls, rows hydrated, time and selected coverage. Cache shared config/editorial mappings by version; avoid global user-result caches that omit user exclusions or state. Set a hard work budget and return a sound two-rail result without exhausting every alternative.

### E2. Parse and apply can produce request bursts despite bounded response sizes

Parse accepts up to 5,000 characters (`concierge-parse/index.ts:1058`), splits text without a separate item cap, runs every item concurrently (`:1135`), and executes all initial search variants concurrently per item (`:1174`). Low-confidence items add up to five denoised queries (`:1018`, `:1215`). Candidate output is capped at 3–15 per item (`:1062`), but this does not cap aggregate request fanout. There is also one alias lookup and potentially one existing-list lookup per item (`:1146`, `:1289`, `:1308`).

Apply caps input at 100 items (`concierge-apply/index.ts:148`) but starts all 100 mutation chains concurrently (`:180`). A normal applied item may need existing-row read, list write, alias read, alias write and session-item insert; completion/caught-up handling adds title and sometimes last-episode lookup. This is approximately 5–7 calls per applied item on those branches, not a measured runtime average. No deduplication guarantees unique media IDs before the comment claiming independence. The read/check and write are separate HTTP operations, so the “TOCTOU protection” comment is not an atomic compare-and-set guarantee.

**Plan:** bound item concurrency with a small configurable worker pool; batch alias and existing-list reads by media type; deduplicate identical normalized searches within the request; provide a structured provider-ID import path that avoids title-search fanout. Move apply plus undo/audit capture into a bounded transactional RPC with an idempotency key and expected row version. Preserve per-item conflict results. Test repeated IDs, concurrent user edits, partial failure and retries. Do not merely increase function timeouts.

### E3. Named import tracks do not change which upstream catalog rows are selected

Both bulk import queries always select `media(sort: POPULARITY_DESC, type: ANIME/MANGA)` (`bulk-import-anime/index.ts:283`; `bulk-import-manga/index.ts:302`). Presets named `airing_or_releasing`, `recent_updates` and `catalog_backfill` change run sizing/cursors, not upstream status filters or ordering. Therefore a configured “airing” track alone does not establish airing-first freshness. Parent should compare actual cron payloads and freshness distributions before drawing a live conclusion.

Anime’s `scheduleSafe` defaults to false (`bulk-import-anime/index.ts:130`), ignoring the preset’s `scheduleSafe` value; manga correctly inherits it (`bulk-import-manga/index.ts:143`). Most page/retry/budget request parameters have no global hard clamp outside the schedule-safe branch. Time-budget checks occur after a page and only in the `runToEnd` condition (anime `:224`, manga `:246`). A non-runToEnd request can exceed the nominal budget while processing its requested pages. Manga’s outer loop also remains bounded by `pagesPerBatch` (`:214`) even when runToEnd is true.

**Plan:** give each track an explicit query contract: popular catalog refresh; currently releasing schedules; recently updated metadata; deterministic catalog backfill. Persist the query/version with its cursor so incompatible cursor state cannot be reused. Apply hard page/item/deadline limits to all requests, including manual invocations. Check the remaining deadline before each network call and batch, not just after a full page. Keep source scheduling and metadata enrichment as separate jobs.

### E4. Bulk ingestion contains large per-title write amplification and nontransactional replacement

Both importers run five titles in parallel (`bulk-import-anime/index.ts:214`; `bulk-import-manga/index.ts:221`), but links, tags, people and relation edges are processed with individual serial DB calls inside each title. They first look up the title then upsert it. Even unchanged titles do a timestamp update (anime also refreshes schedule fields; anime `:320`, `:341`; manga `:340`, `:349`).

For an updated anime, a useful source call-count model is:

`2 title calls + L external links + (1 delete + E episode inserts when present) + 2×(studios + tags + characters + staff) + 1 relation delete + up to 2×R relation edges`.

Here R counts valid edges whose target lookup is attempted; unresolved targets omit the write. This excludes run bookkeeping, triggers and retries. It is an explanatory formula, not a usage forecast. Manga has analogous calls, plus optional placeholder counts/inserts; its same staff nodes are separately written into `authors/manga_authors` and `staff/manga_staff` (`bulk-import-manga/index.ts:453`, `:501`).

Anime deletes all existing episode rows before inserting upstream streaming episodes one by one (`bulk-import-anime/index.ts:415`, `:429`). A failed insert or interrupted request can leave partial coverage and erase richer independently enriched fields. Episode numbers are extracted from English “Episode N” or fall back to array position (`:418`), so source ordering is not a reliable canonical number. Relation replacement similarly deletes then resolves/inserts edges (`anime :534`, `:553`, `:559`; manga `:557`, `:576`, `:582`). Targets missing locally are dropped rather than queued for later resolution.

**Plan:** batch title-ID resolution per page, batch shared entity upserts and join rows, compare source fingerprints, and write only changed fields. Replace episode/relation sets transactionally with provider ownership boundaries, or merge source-owned keys while retaining richer data. Queue unresolved relation references by provider ID. Use source-specific episode IDs/labels when available and model uncertain numbering explicitly.

### E5. Checkpoints and locks do not provide a durable import guarantee

Cursor writes occur after the processing loop (`bulk-import-anime/index.ts:228`; manga `:249`), not after each committed page. Caught per-title errors increment results.errors but still advance the page and mark the run success. A hard timeout can replay a run’s earlier writes on retry; a partial item error can be skipped until a later full sweep. Cursor reads occur before acquiring the lock, and locked/skipped paths write cursor state. Concurrent launches can therefore retain stale cursor knowledge; exact race impact depends on schedules and table semantics.

`acquireImportLock` returns true on RPC errors/exceptions in both importers (`anime :618`, manga `:641`), manga enrichment (`manga-chapter-enrich/index.ts:1954`) and mirror-images (`:471`). The system can run concurrently precisely when lock health is uncertain. HTTP fetches generally lack AbortController deadlines. Bulk retry helpers use three default retries with exponential delay but no Retry-After handling or jitter (`anime :579`, manga `:602`). They treat any HTTP-200 JSON as success, and missing GraphQL data becomes an empty page; GraphQL errors may therefore look like end-of-catalog. The user-list AniList import explicitly checks GraphQL errors (`concierge-import-anilist/index.ts:162`), providing an existing pattern to reuse.

**Plan:** fail closed on coordination errors, acquire/claim before reading progress, use a lease token/fencing value, commit checkpoint with page writes, preserve a failed-item retry queue, and classify complete/partial/failed runs honestly. Separate retryable provider errors from invalid payloads and permission errors. Check GraphQL errors before advancing/wrapping. Give each request a deadline shorter than its lease and respect Retry-After. Avoid broad replay as the normal recovery mechanism.

## Manga chapter enrichment: useful safeguards and remaining costs

The enrichment worker has better bounds than bulk ingestion: default 20/max 200 candidates, default 45-second soft budget/max 120 seconds (`manga-chapter-enrich/index.ts:6`, `:287`); candidates are processed serially (`:223`); per-candidate state is persisted (`:252`); title searches are cached within the run (`:222`, `:1703`); requests are paced at default 3 RPS with 429 cooldown and retries (`:21`, `:1882`, `:1920`). These are useful foundations to preserve.

However:

- Candidate selection calls `get_manga_chapter_enrich_candidates` with a compatibility fallback on **any** error (`:433`, `:442`), potentially repeating expensive SQL for transient failures. Narrow fallbacks to known schema/signature errors and retire them after verified parity.
- Mapping reads/writes and review persistence also have compatibility retries (`:598`, `:608`, `:785`, `:802`, `:838`, `:847`). Make fallback usage visible rather than silently doubling work indefinitely.
- A title can cause several title searches (all aliases are considered), entity verification and per-language aggregate reads. Collision tie-breaking can request aggregate coverage for every candidate (`:1253`). The soft budget limits the normal loop but does not abort a hung fetch or stop a Retry-After sleep from exceeding the deadline.
- Chapter insertion reads existing numbers in chunks of 400 (`:1800`) then inserts missing rows (`:1824`). A duplicate-key race falls back to one insert per row (`:1827`), producing up to 400 extra calls per conflicted chunk. Use a conflict-safe batched insert/RPC and report inserted count.
- It performs exact per-title chapter counts (`:1837`); source review should establish the supporting `(manga_id, number)` index and whether that count can be maintained atomically with ingestion. Do not replace a small per-title count with a whole-table client scan.
- `updateMangaSyncFields` takes max provider chapter number and writes it into aggregate `manga.chapters` (`:1855`). This conflates maximum indexed/available chapter with final published total and can undo the product distinction required for ongoing manga.

**SQL handoff:** the SQL reviewer found a global chapter GROUP BY before candidate LIMIT in `supabase/migrations/20260221173000...:8`. That is a source plan risk, not measured duration. Ask for a bounded current query plan and table statistics; prioritize selecting due title IDs before aggregating their chapter counts, or use maintained per-title summaries if measurements justify them.

## Mirroring and descriptor generation

### Images

`mirror-images` first drains 50 priority assets (`:114`) with per-type batched row lookup (`:133`), then default 200 candidates per requested media group (`:47`). Groups/rows/assets are serial. A title can cause three fetches, three storage uploads, three state upserts and a final title-row update. Even missing/already mirrored assets write state (`:413`, `:427`). It uses explicit narrow projections and remote-only candidate filters (`:210`, `:246`), so this is not a full catalog image download on each call.

Remaining risks: no per-fetch timeout or response byte cap (`:359`, `:364`); mutable remote-only candidates combined with offset pagination (`:216`, `:252`) can skip work as earlier rows leave the result set; the lock is keyed by media-type combination and offset (`:61`) while priority draining is global, so different batches may touch the same priority assets. `overwrite` is recorded but storage upload always uses `upsert:true` (`:366`). The filename has no source revision/hash while the cache-control requests long immutable caching; changing bytes at the same URL needs careful cache semantics.

**Plan:** claim due assets atomically, track retry_after/attempt count and source fingerprint, use bounded concurrency and byte/deadline budgets, preserve source URL separately from mirrored URL, and avoid writing unchanged skipped state every run. Prefer stable queue/keyset progression over offsets into a shrinking candidate set. A source change should yield a new versioned URL when long immutable caching is used.

### Realm descriptors

`realm-describe` supports both anime and manga, one title or a batch capped at 25 (`:465`). It makes three per-title reads: explicit base fields (`:240`), all title tags then locally keeps eight (`:250`, `:260`), and realm membership (`:263`). Move top-tag order/limit into SQL if the metadata cardinality/plan warrants it. Small `realm_meta` is read once (`:101`).

Model calls permit two empty-response attempts, a 429 fallback model, and two validation attempts (`:327`, `:348`, `:378`). Successful outputs are buffered for the whole batch then written together (`:471`, `:499`), so a timeout late in a batch can lose already paid generation results. No edge-owned queue claim/lease or total time budget was found. External worker ownership must be verified before claiming concurrent duplicate generation happens in production.

**Plan:** bounded claims, source/model/prompt fingerprints, write progress in small durable batches before the deadline, retry only failed validation/provider outcomes and expose cost per accepted descriptor. Reuse unchanged descriptors. Keep deterministic routing independent of narration; note that local `concierge-resolve` does invoke Groq for disambiguation and realm generation emits structured classification-like fields, so current source differs from a blanket “Groq narration only” description.

## Other endpoints and correctness that can create waste

- **AniList user import:** default 200/max 400 total entries, pages 10–50, types sequential (`concierge-import-anilist/index.ts:250`, `:283`). No upstream retry/deadline. It fetches ratings/IDs/update time then turns records into title text (`:89`); only eight preview samples keep metadata (`:188`). Confirm reuses that text. Structured ID import avoids repeated fuzzy catalog searches and preserves fields; use resumable pagination for full lists.
- **RAG retrieval:** bounded 10-candidate RPC and a one-hour cache are good (`concierge-retrieve-assist/index.ts:45`, `:262`). The cache key receives normalized query, locale and constraints but omits mediaType (`:77`, `:232`), while the RPC uses mediaType (`:264`). Anime/manga results can be cross-served for otherwise identical keys; test and version corrected keys. Cache errors currently fall through; error responses may become cached empty results. Distinguish legitimate no-match from backend failure.
- **Resolve/narration:** reserve/finalize budgeting exists and narration limits output to 260 tokens/eight titles (`concierge-recommend/index.ts:2648`). Resolve packs 20 items/max ten choices (`concierge-resolve/index.ts:204`). Model fetches lack deadlines; resolve’s outer error catch returns without finalizing reserved budget (`:296`). Some rate-limit/budget calls inspect `.data.allowed` without checking `.error`; fail-closed claims require explicit error handling, since SDK errors usually resolve as objects rather than throw.
- **Undo:** reads all items in one session (`concierge-undo/index.ts:100`) and restores sequentially. Apply caps each new session at 100, but undo query itself has no explicit bound/pagination for legacy sessions. It marks the session cancelled even if individual undos fail (`:251`). Progress/status checks do not compare rating/notes, which can allow overwriting subsequent edits in those fields. Use an atomic expected-version restore and retain retryable per-item failures.
- **Account deletion:** `delete-account/index.ts:119` scans all creatorless clubs then counts memberships per club, unrelated to the size of the deleting user’s footprint. Scope cleanup to affected clubs or run a separate bounded orphan-maintenance job. Storage `.list(userId)` has no explicit pagination (`:143`), so completeness must be verified; a single default page is not proof of complete removal. Keep deletion semantics/authorization unchanged while making work bounded.
- **Review action:** mapping upsert, review approval and downstream enrichment are separate (`manga-source-review-action/index.ts:105`, `:124`, `:211`). The response already distinguishes mapping-saved/status-failed. Make approval idempotent and do not require repeated expensive enrichment when only the review marker needs retry.

## Metadata fetched, retained, discarded and still missing

| Source area | Verified useful data already retained | Waste/gap or opportunity |
|---|---|---|
| Anime core | Titles/aliases, provider IDs, partial start/end dates, format/status, genres, source, adult flag, scores/popularity, next episode/time | `hashtag`, `title.userPreferred`, cover `extraLarge`, `timeUntilAiring` are requested but not persisted. Drop redundant fields unless there is an explicit product need; `timeUntilAiring` is derivable. Do not store every source field merely because it exists. |
| Anime schedules | AniList next episode/time are written on fresh and unchanged paths | Track query is not releasing-filtered. `episodes` falls back to next episode minus one, conflating aired-so-far with final total (`bulk-import-anime/index.ts:314`). Separate these semantics for progress and upcoming UI. |
| Streaming episodes | Title, thumbnail, duration, stream URL/site | No future schedule date from this query; delete/reinsert destroys independently enriched dates/metadata. The fallback index is not authoritative episode identity. |
| Manga core | Titles/aliases, provider IDs, chapter/volume aggregate counts, partial dates, external links, creators/tags | `next_chapter_number` and `next_chapter_at` are explicitly written null in every stale full import (`bulk-import-manga/index.ts:369`). A future enrichment writer would be erased unless ownership is separated. ISBN, edition language, publisher release schedule and volume dates are not supplied by this AniList query. |
| Manga source aggregate | Existing mapping identity and integer chapter coverage | Aggregate language probes return the first language with chapters, then optionally all-language fallback (`manga-chapter-enrich/index.ts:1730`). Persisted chapter rows keep only number/generic title (`:1818`), dropping language/provenance and decimal/extra labels. This cannot support “latest official chapter in my language” or forthcoming edition alerts. |
| Relations | Supported source/adaptation/prequel/sequel/side-story/spin-off local-ID edges | Query fetches target titles, format and cover but local write only needs ID/type/relation; remove unused payload or deliberately use it to stage unresolved referenced targets. Missing local target currently means lost relation until another successful sweep. |
| People/tags | Compact top-ten characters/staff, roles, descriptions, tag rank/spoiler flags | These fields can support credits and explanatory discovery. Manga staff is duplicated into authors and staff; preserve role semantics and reduce repeated writes. Top-ten is an intentional partial catalog, not complete credits. |
| External links | Site, URL, language, color | Already useful for official destinations, but not evidence of country/audio/subtitle-specific availability, exact edition or affiliate eligibility. Version/source identity and stale-link removal rules are needed before richer claims. |
| Enriched copy/images | Separate state tables and cached/mirrored content exist | Both bulk upserts reset synopsis state to pending (`anime :385`, manga `:387`) and send upstream image URLs again. Unless a database trigger/merge layer protects them, unrelated source updates can cause unnecessary re-enrichment/remirroring. Verify with SQL owner before claiming measured churn. Use per-field source hashes/ownership. |

The right principle is “fetch and persist what a named user feature or operational quality check needs.” New metadata should have source, timestamp, confidence/date precision, ownership and downstream consumer. A larger catalog count does not itself improve the user's tracking or discovery experience.

## Executable work sequence for the parent plan

**1. Establish a cheap baseline.** Use existing logs/pg_stat_statements/edge run summaries first. Capture counts, p50/p95 duration, retries, rows touched/returned and bytes for representative requests. Distinguish warm cache, cold cache and error branches. Avoid repeatedly scanning enormous tables or fetching row bodies to compute metrics. Current source identifies targets; it does not justify an arbitrary database upgrade.

**2. Remove known duplication without changing ranking.** Memoize recommendation builds and shared metadata; bound parser/apply concurrency; batch ID/alias/current-state reads. Use fixed fixtures for anime, manga, mixed scopes, constraints and large imports. Require identical recommendation eligibility and explicit conflict outcomes while reducing call count.

**3. Make ingestion bounded and resumable.** Hard-clamp request sizes, enforce network deadlines and provider budgets, fix actual track query semantics, fail closed on locks, persist checkpoints with writes and retain failed items. Test interruption after the first committed page and show resume without losing or needlessly redoing it. Expose complete/partial/failed states and a finite next action.

**4. Batch and isolate writes.** Provider adapters produce typed source records; a bounded page writer resolves IDs/upserts changed rows; separate episode/relation/metadata jobs respect ownership. Use small RPC modules by purpose, not a giant function containing all catalog operations. Keep auth/rate-limit/deadline/telemetry helpers shared and provider-specific mapping logic separate. Preserve the existing Swift/API contracts until independently migrated.

**5. Add product-relevant metadata.** Fix original-total versus available-progress semantics; preserve language/provenance; stage edition-level release/ISBN identity; expose current next-airing data only where freshness is verified. Do not launch “where to watch/read” or manga release promises from empty provider/date columns. Run tiny deterministic source samples before widening coverage.

**6. Roll out with budgets and rollback.** Baseline one representative user request and one small job per family, then broaden only if the bounded criteria pass. Define hard per-invocation title/query/byte/time limits; alert on repeated no-progress runs, stale leases and retry exhaustion. Pause the job/feature through explicit controls rather than letting an endless retry loop compete with interactive traffic. Deployment and hosted writes remain the parent's separately authorized phase.

Suggested acceptance evidence: recommendation no duplicate mode builds; parse/apply maximum observed concurrency matches configured pool; no cursor advance for unrecorded failure; retry after timeout resumes committed work; unchanged metadata does not reset enrichment; chapter/episode updates preserve independent richer fields; no unsupported dates or language availability invented; budget/error paths return actionable status; both anime and manga fixtures pass. Performance targets should be set after the baseline, not fabricated in this source report.

## SQL coordination and live boundaries

The SQL reviewer reported `search_titles` uses indexed trigram candidates and `curated_rail_cards` uses narrow rail lookup—retain these strengths. `recommend_ids_premium` and chapter-enrichment candidate selection have potentially expensive aggregations that warrant bounded plan verification. Similarity has a precomputed serving path; do not attribute every request to its legacy fallback scorer. Exact migration evidence belongs in the SQL register.

Parent supplied earlier live catalog counts/future-date sparsity and rating constraints. Those are valuable separate live evidence but were not re-measured here, and are not substituted for deployed edge parity or query-performance measurements. This audit made no repository changes; only the requested `/tmp` report/register and a local `/tmp` generator were written.
