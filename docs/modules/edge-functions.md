# Edge functions: ownership and keep/split decisions

Current semantic ownership updated7October. Earlier E7 counts/differential results below are historical unless explicitly refreshed. Source under `supabase/functions/` wins; this document does not establish deployment parity. Current acceptance/gaps: [integrated executor](../handoffs/2026-10-07-integrated-testflight-execution.md).

## Layout rule

- One directory per deployed slug. `index.ts` is the entrypoint and stays thin where a split
  exists. Extra modules are **flat siblings** in the same directory (`./router.ts`), or
  `../_shared/*.ts` for code several functions bundle (precedent: `_shared/normalization.ts`).
  No nested folders.
- Tests (`*_test.ts`, `*_test_support.ts`, `*.fixture.json`) live next to the code and are never
  imported by an `index.ts`, so they are not part of a deployed bundle (checked with
  `deno info` / `deno bundle`). `_shared/test_fake_supabase.ts` is test-only for the same reason.
- Run everything offline: `deno test --no-prompt supabase/functions/<fn>/` (no permissions,
  no network, no Supabase).

## Split in E7

| Function | Modules | Tests | Gate |
|---|---|---|---|
| concierge-recommend | `index.ts` (thin: env, supabase-js, fetch, clock), `handler.ts` (request seam + run orchestration, F51), `router.ts` (pure routing rules + `routePrimaryMode` chain), `rail_policy.ts` (pure item building, secondary ranking/choice), `catalog_repository.ts` (catalog/cache/flag reads, mode cache, run logs, retrieve-assist seed), `narration.ts` (Groq transport + kill switch/budget adapter), `curated_copy.ts` (EN/DE rail copy, curator note) | `handler_test.ts` (8: limiter denial/failure, mode cache, F73 one build per rail, F76 non-numeric limit, narration failure, reservation accounting), `router_test.ts` (75 offline cases, 22 German-only alternatives), `router_corpus_test.ts` (67 corpus cases), `router_test_support.ts`, `router_modes.fixture.json`, `../_shared/test_query_fake.ts` | `test_router_offline.sh`, `test_concierge_corpora.sh`, `test_edge_functions.sh` |
| concierge-parse | `index.ts` (thin), `handler.ts` (request seam + per-line run, F51), `parse_repository.ts` (alias/search/existing-entry/config/log boundary), `search_plan.ts` (pure query plan + candidate scoring), `rules.ts` (pure parser, `parseLine`), `../_shared/alias_normalization.ts` (F31) | `handler_test.ts` (9: anonymous caller, limiter denial/failure, search failure, ambiguous line, existing-entry projection, 2 alias-compatibility, F76 non-numeric limitPerItem), `rules_corpus_test.ts` (6 tests: 107 corpus cases against their intended outcome, all pass, see below; title punctuation; post-participle slot phrases (R1); completion fallback scope (A3); F72; multi-title), `../_shared/alias_normalization_test.ts` (5, incl. F82 progress-free key and season identity), `../_shared/alias_roundtrip_test.ts` (1: Apply records -> Parse finds, incl. a legacy-key row) | `test_concierge_corpora.sh`, `test_edge_functions.sh` |
| concierge-apply | `index.ts` (thin: env, user client + service-role client), `handler.ts` (request flow: JWT user, limiter gate, validate-all, catalog progress reads, ONE `apply_import_session` call, optional effects after commit), `apply_plan.ts` (F14 identity validation, insert/update write variants, F15 season note, `expected` compare set, outcome mapping); the write is the SQL transaction `apply_import_session` (prepared `20261005130000_import_apply_undo_transactions.sql`) | `handler_test.ts` (19), SQL `supabase/tests/rls/70_import_apply_undo_transactions.sql` | `test_edge_functions.sh`, `local-db` |
| concierge-undo | `index.ts` (thin), `handler.ts` (JWT user, limiter gate, ONE `undo_import_session` call), `undo_plan.ts` (request validation, result -> HTTP mapping); compare-and-revert is the SQL transaction `undo_import_session` (same migration) | `handler_test.ts` (8, sessions built by the real apply handler), SQL test as above | `test_edge_functions.sh`, `local-db` |
| delete-account | `index.ts` (thin: env + supabase-js), `handler.ts` (request flow: method, env, JWT user only, best-effort Apple revocation, outcome -> HTTP; success body `{ success: true }` unchanged), `deletion.ts` (pure ordered policy: 1 `begin_account_deletion` write barrier, fail fast; 2 `delete_user_concierge_data` under the user's JWT, fail fast, refusal 403; 3 required and all attempted: `delete_account_club_memberships` (the club lifecycle shared with `leave_club`; no global orphan sweep), the four TEXT tables for both id spellings (`userIdSpellings`, F16), Storage `media/<userId>`, profile; 4 GoTrue admin delete LAST; every step idempotent, retry-safe), `adapters.ts` (service-role vs user-JWT clients; the two lifecycle RPCs must answer `success: true`), `real_client_shapes.ts` (compile-only check against supabase-js). SQL: prepared, NOT deployed `20261005140000_account_deletion_write_barrier.sql` + `20261005150000_club_membership_lifecycle_and_privacy.sql`; deploy both before this function. Deployment prerequisites: read-only `supabase/tests/prerequisites/delete_account_prereqs.sql` (F45) | `deletion_test.ts` (17), `handler_test.ts` (20, incl. barrier-RPC failure and partial-cleanup retry through the real handler + adapters); SQL `rls/50_*`, `51_*`, `65_*`, two-session `concurrency/90_*`, `91_*` | `test_edge_functions.sh`, `local-db` |

Corpus acceptance (F27-F29, 2026-10-05). Every corpus case is asserted against its **intended**
outcome. The gate has three kinds of case: as authored; **adjudicated** (the canonical fixture
carries an `adjudication` block with `decision`, `intended_slots` / `intended_ambiguity` and
`rationale`, next to the untouched authored `expected_*`; the shape gate validates the block);
and **known defects** (`KNOWN_DEFECTS` / `KNOWN_DIVERGENCES` in the tests: intended outcome known,
production output pinned, printed, and failing on any change). Current state: router 67/67,
parser 107/107 give the intended outcome; 0 known defects; 8 parser cases adjudicated.

Principle used for every parser verdict: **write safety** (contract F30). Material uncertainty about
title, status or progress must lead to a clarification or the weaker status, never to an unreviewed
stronger write; a clarification that cannot lead to a write is not import-relevant. Secondary
principle: English and German phrasings with the same meaning give the same slots.

| Case | Input | Intended outcome | Decision and rationale |
|---|---|---|---|
| `router_de_005` | romantisches Anime empfehlung | `romcom` | Defect, fixed (F28). The German base form `romantisch` now routes like English `romantic` (strong-genre romance rule); the closed `GERMAN_VIBE_FORMS` allowlist folds its five inflections. Note: the v7 config lists `romantisches` as a `romance_serious` synonym; it stays a scoring-fallback signal only. |
| `router_de_029` | schauriges Anime Empfehlung | `horror_supernatural` | Defect, fixed (F28). `schaurig` was in both horror rules, but none of its inflections were folded; five forms added to `GERMAN_VIBE_FORMS`. |
| `parser_en_009` | I watched Steins;Gate to the end | COMPLETED, completed, no clarification | Defect, fixed (F27). A `;` between two non-space characters is title punctuation (Steins;Gate, Robotics;Notes); only a spaced `;` separates titles. |
| `parser_de_012` | ich habe Steins;Gate bis zum Ende geschaut | COMPLETED, completed, no clarification | Defect, fixed (F27), same rule in the German perfect path. |
| `parser_de_022` | ich habe Berserk Manga gelesen bis Kapitel 200 | READING, chapter 200, MANGA, no clarification | Defect, fixed (F27). The German perfect splitter keeps the progress / rating / completion phrases after the participle (never free commentary: "ich habe Vinland Saga gesehen und fand es super" searches `Vinland Saga`, review R1); with several titles they stay on the last title only (as the English path does), so other titles are asked rather than given another title's progress. |
| `parser_de_050` | ich habe AoT bis zur letzten Folge geschaut | COMPLETED, completed | Defect, fixed. EN/DE asymmetry: "bis zur letzten Folge" contains "bis ... Folge" and was read as partial progress before the explicit completion was checked (the English branches check completion first). Apply already stored COMPLETED via `completed`, so the preview disagreed with the write. |
| `parser_en_046` | I finished season three episode five of AoT | WATCHING, S3E5 | Defect, fixed. An explicit position (episode/chapter/volume N, SxE, NxM) after "I finished" names where the user is; COMPLETED is a stronger write than the text supports. Trade-off: "I finished Naruto episode 220" (a finale) now gives WATCHING at 220, the weaker write, which the user can complete. F72 (lead ruling): the same rule now applies to bare "finished/completed/done" and German "fertig/abgeschlossen/beendet" ("finished AoT up to episode 5", "Naruto episode 220 completed", "Naruto Folge 220 fertig" -> WATCHING at the position; "zu Ende" / "komplett" and explicit completion phrases stay COMPLETED), and "up to" / "to" before a unit + number leaves the title query. |
| `parser_en_055`, `parser_de_046`, `parser_de_052` | ... halfway / zur Hälfte / teilweise | WATCHING, no clarification | Defect, fixed. A soft partial word already answers "Finished or still watching?" (still watching); the question is no longer repeated. One helper (`hasSoftPartialProgress`) serves `parseStatus` and `detectAmbiguity`. |
| `parser_de_018` | Mob Psycho 100 alles gesehen | COMPLETED, completed, no clarification | Defect, fixed. An explicit completion phrase with no other status rule is a completion (before: no status, so a title-only "add or seed?" question, whose "import" answer stored PLANNING); only on a list-style line: a subject pronoun, a wish/plan verb or a question ("I want to watch all of it") keeps no status (review A3). The bare-number unit question no longer fires on a COMPLETED line: a number cannot refine a completion write (Apply takes completed progress from the catalog total), so on numbered titles ("Mob Psycho 100", "86") it was moot and a unit answer wrote title digits as progress. |
| `parser_de_013` | angefangen Berserk Band 3 | READING, volume 3 | Corrected expectation (fixture). `angefangen` with a manga unit is reading; the EN twin `parser_en_012` expects READING. |
| `parser_en_011`, `parser_en_025`, `parser_de_004` | I have watched ... / ich habe ... geschaut | WATCHING + `status_unclear` | Corrected expectation (fixture). Past-tense "watched" with no completion phrase or progress leaves COMPLETED vs WATCHING materially uncertain, so the parser asks instead of an unreviewed write. |
| `parser_en_039` | watched it | no status, `intent_unclear` | Accepted production (fixture). Title-less fragment: no silent write is possible; the title-only rule asks import-or-seed, the clarification the corpus expects. |
| `parser_de_037` | geschaut | no status, no clarification | Accepted production (fixture). The title is empty after stripping the participle: no candidate, nothing to import or clarify. |
| `parser_en_040`, `parser_de_038` | at 12 / bei 12 | `intent_unclear` | Accepted production (fixture). The unit question needs a status or parsed progress that makes the number a progress value; without a title both clarifications block a write, and a unit answer would have no title to attach to. |

Also fixed with the F27 segmentation repair, as new finding F71: a `.` after an honorific
(`Dr. Stone`, `Mr. Osomatsu`) or `No.` before a number (`Kaiju No. 8`) no longer ends the clause.

Alias keys (F31): `_shared/alias_normalization.ts` is the one alias policy. Parse looks a line up
with `aliasLookupKeys(raw)` = [strong key, legacy Apply key when different]; a strong-key row wins
over a legacy-key row, then more hits win (one query, at most 4 rows). `legacyApplyAliasKey` is the
weaker key the deployed concierge-apply has written so far (read-compatibility only), so existing
`title_aliases` rows stay findable without a data migration. concierge-apply records with
`normalizeAliasKey` (its handler imports it from the shared module; no local copy remains), so the key
Apply records is the first key Parse looks up. `_shared/alias_roundtrip_test.ts` proves it through both
real handlers on one store: Apply's alias reorders the next Parse, and a legacy-key row is found too.
F82 (lead ruling): the strong key ignores EXPLICIT progress phrases (a unit with its number, with an
optional "up to/until/till/to/bis/bei": "episode 50", "ep 51", "e50", "Kapitel 200", "Folge 3 von 220",
"Band 3"), so "naruto episode 50" and "naruto episode 51" share the key `naruto` and an alias carries
across progress updates; bare numbers stay ("Mob Psycho 100", "86"). One progress vocabulary
(`PROGRESS_PHRASE_SOURCES`) serves the key and the parser's post-participle phrase rule. Deliberate
deviation from the literal ruling, pending lead confirmation: a SEASON number is kept as catalog identity,
normalized to one token in every notation ("season 2", "Staffel 2", "S2E5", "2x05" -> `s2`), because the
catalog keeps one entry per season, an alias adds +0.80 to one media_id while a season match adds +0.18,
and auto-apply fires at >= 0.85: a season-free key would pull the Season 2 entry above Season 3 and write
that progress onto the wrong row. Flip: remove the `SEASON_TOKEN` step and add `staffel|season` to the
progress units in `_shared/alias_normalization.ts`. Nothing is persisted under the strong key yet (Apply's
switch is not deployed); rows written by the deployed Apply stay readable through the legacy key. The
parse response `aliasNorm` and feedback `p_alias_norm` change accordingly for progress-bearing lines
(no Swift reader).

Apply / Undo transaction contract (P2-R2, wire v2; prepared, NOT deployed, 2026-10-05):
- **One transaction per Apply** (`apply_import_session(p_user_id, p_session_id, p_idempotency_key, p_items)`,
  SECURITY DEFINER, `search_path = public, extensions`, EXECUTE for `service_role` only; the handler
  passes the JWT user). Accepted list writes, their journal rows (`previous_values` = before image,
  `after_values` = what was written) and the session `draft -> applied|failed` transition commit
  together; a journal or session error rolls everything back (HTTP 500 `{error, status:"failed",
  retryable:true}`). Conflicts (`expected` compare-and-set under the row lock) and rows the table
  rejects (class 22/23, e.g. an unknown catalog id) are item outcomes with a fixed message
  (`Unknown title` / `Value rejected`, never schema names): `status` `partial`, still undoable.
  Lock order: both functions lock every existing target row (anime then manga, ascending id) before
  the first write, so a concurrent manual edit of one of those rows waits instead of deadlocking
  (a concurrent manual INSERT of the same new title can still deadlock: 500 retryable). `idempotencyKey` (unique per user) replays the stored outcome (`replayed:true`, no write).
  Import-origin taste marking: the RPC sets and clears `taste_import_context` inside the transaction.
- **One transaction per Undo** (`undo_import_session(p_user_id, p_session_id)`): most recent applied
  session only (409); items in descending request order (results reported in request order); per
  item under the row lock, an unchanged add is deleted, an update reverts only
  the fields still equal to its after image; later edits / deletions are kept and listed in `skipped`
  (`edited_since_import` with `fields`, `deleted_since_import`); malformed journal before values are
  kept and listed in `warnings`; any error rolls back and the session stays `applied`; an already
  undone session is 200 with empty `reverted`. Journals written before the migration (after image
  only in `action.after`) stay undoable.
- **Validation before any write (F14):** `mediaId` a JSON integer 1..2147483647, `mediaType`
  ANIME|MANGA, `status` in the medium's list_type vocabulary; otherwise HTTP 400
  `{error, code:"INVALID_ITEM", index}`. A season number below 1 makes no S/E note (no clamp to 1).
- **Season/episode notes (F15, changed):** `S{n}E{m}` is only a NEW anime row's notes; an existing
  row's notes change only with explicit `notes` (which Undo restores). Replaces the former retained
  overwrite behaviour.
- **Side effects:** required = inside the transaction (list writes, journal, session, taste origin);
  optional = after commit, best-effort, skipped on a replay (`title_aliases` hit, recorded with the
  shared `normalizeAliasKey`; `log_concierge_run`).
- Deploy order: migration first, then both functions; Swift reads the new fields in wave 2.

Invariants kept in every split: deployed slug, request/response shapes, JWT-derived user only
(`client.auth.getUser()`, never the body), rate-limit kinds, deterministic routing (Groq is
narration only in concierge-recommend), `sanitizeForLLM` before prompts.

## realm-describe (deployed, dormant): keep cohesive, do not refactor

- **What it does** (`realm-describe/index.ts`, 536 lines): Groq writer for Realm Graph descriptors.
  Auth `x-import-secret == IMPORT_SECRET` (`:440-444`), service-role client. Body is one title
  or `{batch:true, limit<=25}` drained from `media_realm_llm_pending` (`:415-428, :464-508`).
  Builds a prompt with `sanitizeForLLM` (`:66`, `:306`, `:311`), calls Groq
  (`GROQ_MODEL_REALM`, default `llama-3.3-70b-versatile`, `:449-450`; 429 fallback
  `llama-3.1-8b-instant`, `:345-352`), validates against a closed vocabulary and writes through
  `upsert_media_realm_llm(p_rows)` (`:410`).
- **Who calls it**: only the manual Mac driver `scripts/realm_descriptor_worker.js:155`
  (`callDescribe`, IMPORT_SECRET). The pg_cron drains were unscheduled
  (`20260802120000_pause_realm_describe_cron_again.sql:5-7`). `CURRENT_APP_STATE.md:17179-17183`
  records the decision to stop using Groq for descriptors; the corpus was written by an agent
  pass through `scripts/realm_llm_pass_submit.js`, and the function "is not the active writer".
- **Relation to Taste**: catalog-side, not a Taste surface. `upsert_media_realm_llm` (service_role
  only since `20260802017000`) -> `media_realm_llm` -> membership deltas -> realm membership /
  tier views read by the Taste deck and the realm rails. No Swift code calls the function.
- **Policy note**: it is Groq *classification* (realms, tone, register, pacing), outside the
  "Groq narration only" rule; acceptable only because it is offline, secret-gated and dormant.
- **The vocabulary exists five times** (24 tone words, 4 registers, 3 pacings):
  1. `supabase/functions/realm-describe/index.ts:14-21`
  2. `scripts/realm_descriptor_validate_selftest.js:7-14` (plus a 3-slug `REALMS` stub at `:15`;
     it tests its own copy, not the function)
  3. `scripts/realm_llm_pass_submit.js:52-59` (the path that actually wrote the corpus)
  4. `scripts/realm_llm_salvage_swarm.js:20-27` (one-shot salvage)
  5. SQL `upsert_media_realm_llm`, latest body `supabase/migrations/20260802014000_realm_llm_upsert_rate_budget.sql:102-106` (tone), `:117` (register), `:120` (pacing); table CHECKs in `20260731170000_media_realm_llm_v1.sql:67-68`.
  The SQL function is the authority: any drift in the JS copies is rejected at upsert time.
- **Decision: keep cohesive, untouched.** Reasons from the code: no active caller (manual driver
  only, cron removed, product decision recorded), no consumer of its output besides the SQL
  upsert that already enforces the vocabulary, and a refactor would only move a dormant Groq
  classifier. Revisit only if the function is reactivated; then extract `descriptor.ts`
  (vocabulary, validation, prompt) to replace copies 2-4, or retire the slug.

## contact-submit (2026-11-02, prepared, NOT deployed)

`index.ts` (env, supabase-js clients, Resend `fetch`) / `handler.ts` (pure validation, CORS allow-list, honeypot, JWT classification, keyed IP hash, limiter mapping, insert, notification text) / `handler_test.ts` (27 offline tests with fakes: `deno test --no-prompt supabase/functions/contact-submit/`). Serves the legal site's `kontakt.html` (anon key) and the app's `SupportStore` (user session). Deploy with `--no-verify-jwt` after the prepared migration `20261102100000_contact_messages.sql`; set `CONTACT_IP_HASH_SECRET`, optionally `RESEND_API_KEY` + `CONTACT_NOTIFY_TO` + `CONTACT_NOTIFY_FROM`.

## Other functions: what stays cohesive and why

| Function | Decision | Reason (from the code) |
|---|---|---|
| concierge-recommend | extracted (F51): thin `index.ts`; `handler.ts` request seam + run; `rail_policy.ts`; `catalog_repository.ts`; `narration.ts`; `curated_copy.ts`; `router.ts` | The former 1,300-line `serve` closure mixed four failure policies: required limiter (fail closed, 503), catalog reads (throw vs degrade per read, documented in `catalog_repository.ts`), optional paid narration (never alters the deterministic rails; kill switch and both budgets must answer yes; each reservation released exactly once) and presentation copy. The run itself stays one function in `handler.ts`: its state (seed query/override, retrieval-assist outcome, top-genre promise) has a request lifetime and is shared by routing, rail building and the curator note, so splitting it further would only pass that state around. Old vs new handler: identical responses and call multisets on 320 controlled requests (scratch differential, not shipped), before the two lead-ruled changes: F73 builds the fallback secondary only when no candidate exists (each rail built once; before, `preferred[0]` was built twice and an error in that duplicate build failed the request) and F76 treats a non-finite `limit` as 8. |
| concierge-parse | extracted (F51): thin `index.ts`; `handler.ts` request seam + per-line run; `parse_repository.ts`; `search_plan.ts`; `rules.ts` | Repository = the only data access (alias lookup by `aliasLookupKeys`, `search_titles`, existing entry, config, feedback/run logs) with its error contract; `search_plan.ts` = the ranking policy (fan-out, boosts, denoised pass, thresholds), unchanged arithmetic. Anonymous parse stays a public contract: no user-scoped read or write without a verified user. Old vs new: identical responses and non-alias calls on 48 controlled requests (scratch differential). |
| concierge-apply / concierge-undo | split done (handler + plan + SQL transaction) | They are the only edge writers of the list tables. Policy (validation, write variants, outcome mapping) is TypeScript; atomicity, compare-and-set/revert, journal, idempotency and session transitions are the two SQL functions. |
| manga-chapter-enrich | Split matching/provider/persistence; keep run lifecycle cohesive | Thin `index.ts` calls `runChapterEnrich`; `matching.ts` owns pure identity scoring, `mangadex.ts` owns bounded provider calls, `repository.ts` owns DB outcomes. Run owns lock, time budget, metrics and candidate/search cache for one invocation. Reviewed fixes honor aliases before single/external/title selection, stop after failed deactivation and treat failed/malformed current-mapping reads as unknown rather than absent. Legacy missing-column fallback is explicit. No additional split merely for size. Focused actual-run regressions passed locally; latest SQL/hosted mapping remains separate. |
| bulk-import-anime / bulk-import-manga | Thin entries with medium-owned handler, AniList transport and mapping; shared persistence | Each slug preserves secret gate and its medium contract. `handler.ts` owns one lock/cursor/run lifecycle; `anilist.ts` provider I/O and `mapping.ts` conversion are separate. Shared anime `persistence.ts` owns lock/cursor policy used by Manga. Failed lock admission does not import/release; failed primary write preserves cursor. Historical focused suites are recorded inF51; no installed worker/deployment parity inferred. |
| concierge-import-anilist | Auth/limiter entry plus testable run, paging and field policy | `index.ts` authenticates and fails closed on limiter error; `run.ts`, `paging.ts`, `lines.ts`, `list_policy.ts`, `structured.ts` separate provider streams from conversion/job input. Old truncated type error is repaired. Both-media checkpoints/fidelity and XML share native structured jobs; required MAL account ingestion is a distinct unfinished connector path. |
| mirror-images | Run/repository/source-fetch/storage seams; one bounded run lifecycle | `mirror_run.ts`, `mirror_repository.ts`, `source_fetch.ts`, `mirror_storage.ts` own separate orchestration, persistence, source validation and Storage policies. Source fetch uses approved HTTPS AniList CDN, manual checked redirects, a5MiBcap and one10sheaders/body/redirect deadline. Failed image fetch preserves catalog URL. Historical tests are source/local evidence; current live Storage and deployment identities remain unqualified. |
| concierge-retrieve-assist / -feedback | Assist run/cache seam; keep small feedback entry cohesive | Assist entry authenticates/limits, then `runRetrieveAssist` owns typed medium-scoped retrieval/cache. Outages are not cached as no-match. Recommendation reader rejects wrong medium, malformed confidence and unsafe/fractional identity. Feedback remains one validated RLS insert lifecycle. Both staged features remain disabled; source tests do not prove production activation or privacy retention. |
| concierge-resolve | Keep dormant; budget policy extracted | No app caller and not enabled by this release. `resolve_budget.ts` classifies acquired/denied/unavailable reservations and finalizes only acquired scopes once. Earlier budget-leak description is superseded by repair evidence; this does not authorize Groq classification activation. |
| auth-callback | Keep static fallback response cohesive | Branded callback HTML remains a small standalone fallback. No new activation/auth-setting change by this continuation. |
| manga-source-review-action | Thin composition entry and testable admin handler | `handleReviewAction` owns the admin review transaction/forwarding; unchanged slug and typed input/output. Chapter run consumes the persisted accepted/rejected decision; independent policy is not copied into the entrypoint. |

## Integrated backend acceptance and release boundary

Recommendation orchestration retains one request lifetime: seed/assist decisions, top-genre promise and deterministic rail output. Optional Groq narration has its own transport/budget policy and total deadline; timeout cannot change rail selection, and only acquired reservations are released. Chapter sequencing retains lock/budget/candidate lifetime; provider/matching/persistence policies have separate seams. Deletion keeps ordered safety policy: barrier first, required cleanup acknowledged, GoTrue last; Apple revocation is bounded best effort. These are semantic KEEP rulings, not line-count waivers.

The deletion adapter now requires the SQL contract's exact `success:true`, not null/empty transport success. New focused tests exercise actual adapters, aliases/deactivation, lost metadata reads, held provider headers/body and budget accounting. Independent source acceptance and retained local outcomes are in `docs/handoffs/2026-10-07-integrated-release-evidence/`; no new deployment or hosted-provider call occurred. Effective schema/grants/function source/version manifests, final SQL, live disposable cleanup and exact installed TestFlight remain mandatory. Historical function versions and migration lists must not be presumed current.

Final 7 October alias-memory read ruling: this is an identity authority, so missing schema, lookup error or malformed decision response cannot be treated as no prior rejection. Only successful validated rows/empty array permit matching. Final repair and actual-run regression independently accepted; no hosted deployment.
