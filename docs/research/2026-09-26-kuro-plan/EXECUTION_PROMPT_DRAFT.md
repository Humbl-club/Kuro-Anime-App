# Kuro — comprehensive execution prompt

Status: draft for design agreement, 26 September 2026. This document is not authorization to execute changes or deploy. Use it after Max agrees the proposed screen direction and starts the implementation initiative. Unresolved details must remain explicit; do not turn an earlier rejected mockup into the default.

## Mission and source of truth

Improve Kuro into a quiet, distinctive, effortless anime and manga tracking app. Align UI, data requests, persistence, ingestion, privacy and background work with the user's actual tasks. Preserve reliable existing foundations; repair correctness and unnecessary work before expanding promises.

Read `AGENTS.md`, `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, this document, `CURRENT_DECISIONS_AND_AUDIT.md`, the complete `KURO_FULL_REVIEW.md`, and the call registers in this directory. Resolve conflicts using Max's latest explicit decisions first, then current verified implementation, then clearly labelled proposals. Older documents may contain superseded screen designs. The original research is qualitative evidence, not a market-share survey or proof a competitor still lacks a feature.

Start by recording working tree status, HEAD, existing edits, migration/function/flag state as necessary and the exact phone build used for tests. Preserve unrelated work, particularly the local AuthView composition. The approved welcome reference is GitHub `b943e457fd2b611bafa6a52dcbbada417d5b727a`, `codex/kuro-onboarding-no-tv`; use it as a visual reference, not permission to replace the current branch wholesale. GitHub, local, installed, TestFlight and public-release proof are separate.

Keep SwiftUI with `@Observable`, existing design tokens and Supabase. No Combine, second networking stack, speculative MongoDB migration, broad database rewrite or parallel tracking truth. Source reading is mandatory before modifying each relevant area. Extract modules incrementally when required by the work.

## Product constraints

- Animation belongs to welcome/authentication only. Preserve the approved scene/composition and removal of the TV. Home and the rest of the app are quiet and static except restrained functional transitions.
- Preserve top navigation and swiping. Home is the first signed-in destination. Search and broad browsing belong to Discover, separate from Home.
- Persist an explicit Anime/Manga selection. Pass it through request parameters, caches, paging, progress vocabulary and recommendations. No accidental mixed payload followed by local hiding.
- Home shows current titles, relevant changes and upcoming releases/seasons, club context and small useful recommendations/snippets. Determine first-screen hierarchy through the agreed phone design, not a huge editorial hero by default.
- Collection is a visual shelf with an accessible compact option, canonical statuses and optional named shelves. Search covers the entire selected library, including unloaded items. Status, progress and shelf membership are separate.
- Social relationships exist only through clubs. Profiles show identity by default; activity requires opt-in and authorized shared-club access. Do not create a public friend/follow graph.
- Taste is optional. Existing feature flags do not establish value or approve prominence.
- Keep text short and clear. Status colors remain monochrome unless Max explicitly approves a limited change. Cover-derived accent exploration is optional; original artwork retains color. Use haptics for meaningful confirmed interactions, not every scroll or failed action.
- Keep core tracking, discovery, history, import/export, sorting and correction free. Any partner feature must be useful without compromising relevance or adding friction.
- Songs/playback remain a scoped decision: OP/ED metadata and verified link-outs are the narrow proposal. Full OST, background cues and native playback require distinct source/rights and UX decisions. Do not autoplay or fetch music per image.

## Phase 0 — settle the design contract

Present a small coherent phone prototype that covers: approved welcome to auth, returning Home, empty Home, Anime and Manga Discover/search, Collection with statuses and personal shelves, club overview/detail, identity profile with activity off/on, and one detail page. Cover smaller phone widths, large text, keyboard, loading, offline, failure and no-data states. Use realistic bounded content and minimal labels. Mark mock content as such. Do not reuse the rejected first-login, Home, agenda, Collection or email layouts.

Resolve exactly: destination order and whether Browse/Concierge/Taste become Discover entries; Home's immediate balance of updates and continuation; where release history lives; private shelf creation/membership/order semantics; identity fields and activity controls; music scope; any artwork-derived accent treatment. A separate agenda is optional, not a required extra navigation destination.

For each screen, document the user job, essential first-paint fields, later fields, primary/secondary action, accessibility behavior, and the approved layout reference. Verify the user's intent before committing uncertain visual decisions. Implement only agreed states; continue independent correctness work if separately authorized.

Exit: an explicit decision record and screen/data contract. Visual agreement is distinct from authorization for hosted writes or releases.

## Phase 1 — establish a baseline and reproducible schema

Reconcile the static registers against the new working tree. They cover client calls and call sites, all 16 local Edge entry points, scripts/research executables and historical cron declarations, plus 49 client RPC names and selected dependencies. Preserve distinctions among requests, wrappers, local storage URL helpers, realtime declarations and actual SQL work. Resolve dynamic targets during runtime tracing rather than claiming static exhaustiveness proves runtime completeness.

Instrument trace IDs and resource ownership without logging tokens, private list notes or club messages. For representative cold/warm launch, media switch, rapid swipe, debounced search, pagination, detail, +1/Undo, batch edits, import, club reaction, foreground/reconnect and account switch, record request count, duplicate count, bytes, cancellations, retries, latency distribution and visible outcome. Record feature flags, account/library size and cache state. Avoid extrapolating p95 from a handful of samples.

Use current statement/cron statistics before expensive diagnostics. Map HTTP/RPC -> SQL, RLS, triggers and downstream jobs. Obtain representative plans in isolation; production EXPLAIN ANALYZE/load tests are not automatically authorized. A LIMIT on output is not a bound on work. Separate frontend latency from background worker duration and database cost from Edge, egress, Storage, Realtime, external APIs and local computation. Set explicit proposed budgets after baseline measurement; do not invent current capacity or monthly savings.

Fix the documented fresh-bootstrap path in an isolated database: late baseline dependencies, missing `user_lists` CREATE, realm-tier table/matview mismatch and expected grants/policies/indexes. Compare current view definitions before adopting legacy ones. Preserve applied migration history and define an upgrade route. Validate empty setup and upgrade separately; no production reset.

Exit: reproducible baseline, schema contract, supported-job registry and measurable budgets for critical interactions. Record all blocked device/environment checks explicitly.

## Phase 2 — tracking and session correctness

Read and repair rating-scale mismatch across AddToListSheet, progress mutation, imports and storage constraints. Define one normalized rating contract with explicit conversions and null behavior; do not silently lose ratings or notes when changing progress.

Replace broad post-mutation refresh chains with canonical mutation outcomes and targeted invalidation. Reconcile Home, Collection and details through shared state. Preserve Undo, optimistic feedback, server conflict handling and per-item batch outcomes. Scope full library reads deliberately; use pagination or bounded membership/status summaries rather than assuming a single unlimited response is complete.

Guard responses and rollbacks by account epoch and request generation. Centralize sign-out/account-switch cancellation and clearing of lists, derived lookups, club bundles, social counts, provider preferences, seen timestamps, pending signals, realtime subscriptions and scheduled local airing reminders. Existing reminder IDs are title-only; namespace/reconcile them by account and cancel private reminders at sign-out or permission loss. Keep only genuinely public metadata across accounts. Test slow replies arriving after a switch.

Correct valid-empty versus request-failure handling in Browse/Search/Collection and ancillary sections. Repair cancellation loops and finite retry policy in image-slot waiting, feature flags, Taste signals and analytics replay as identified in the client audit. Ensure a cancelled request cannot resume a polling/yield loop indefinitely. Verify image decoding/cache identity for size variants; optimize based on observed memory/render costs.

Exit checks: repeated +1 and Undo; simultaneous views; offline failure/retry; stale response; rating/notes preservation; unknown total; large library beyond API page cap; same numeric anime/manga ID; sign-out mid-request and account switch. A basic progress mutation must not refresh both complete libraries and the mixed feed.

## Phase 3 — remove background amplification and make ingestion durable

Separate change-driven franchise/component/entry-point refresh from the five-minute similarity batch, preserving relation/cut freshness even when stale seeds are empty. Retain advisory overlap control and last-good serving rows. Measure unchanged idle and active-backlog cases, temp work and foreground contention. Reassess daily re-staling/realm dependencies before changing schedules; do not blindly stop jobs to make metrics look better.

Separate the relations worker's 1,000-title default coverage report from every queue poll. Batch/cache diagnostics and make reporting explicit. Verify actual installed launchd path/config before touching a job; installer cadence is not activation proof. Maintain a registry of job owner, trigger, tables, leases, rate/byte/time budget, checkpoint, completion evidence and stop mechanism. Distinguish current cron from 74 historical schedule declarations.

Make imports genuinely support backfill versus current/changed-title refresh. Track names must match query filters/order. Acquire leases before reading cursor state, fail safely on lock uncertainty, use fencing/idempotency, persist progress with successful writes, and retain failed items for bounded retry. Detect GraphQL errors even on HTTP 200. Respect provider rate headers/Retry-After and permissions, use abortable deadlines, finite jittered retry and honest complete/partial/failed run states.

Batch IDs, shared entities and joins per bounded page; skip unchanged source fields by fingerprint. Preserve source ownership of enriched synopsis, mirrored images, episode dates, manga release fields and language/edition metadata. Replace sets atomically or merge source-owned keys; never delete a valid relation/episode set and leave it half empty on interruption. Queue unresolved external relation IDs instead of dropping them.

Repair indefinite recommendation-edge 5xx retries. Make MangaDex duplicate conflicts stay batched rather than falling back to hundreds of calls. Distinguish final total, maximum indexed chapter/episode, current position and consumed amount; preserve fractional/extra chapters and provenance. Do not overwrite independently enriched fields with null/source defaults.

Review mirror queue claims, shrinking-result offset pagination, priority overlap, timeout/size caps and immutable URL versioning. Persist accepted descriptor generation in bounded durable chunks; scope model budgets and deadlines. The current source has Groq disambiguation/structured generation beyond the documented narration-only policy: explicitly resolve that discrepancy rather than silently expanding or deleting behavior.

Exit checks: interrupt after commit; expired lease; duplicate worker; provider 429/403/500; GraphQL errors; malformed response; no-progress run; unchanged metadata; source removal; unresolved relations; image revision; empty queue. Prove bounded calls, durable resume and last-good-data preservation.

## Phase 4 — align SQL and request contracts with persistent scope

Create a typed account/device preference and explicit scope propagation using existing media identities/models. Define default selection and whether cross-device sync is desired; do not infer scope from taste. Include medium, user where private, effective filters/status/shelf/sort/cursor and region/language where relevant in keys. Reset stale cursors and cancel/discard obsolete requests.

Retain useful Collection/Browse keyset paging. Align Search expressions/indexed candidates while preserving exact/native/prefix/fuzzy ranking and safety rules. Compare plans for short queries, typos, empty queries, common filters and deep pages. Use fixed relevance fixtures before changing candidate limits. Address social batch caps and legacy identifier casts without a risky blanket ID migration.

Deduplicate identical recommendation rail builds, batch parse/apply lookups and limit shared concurrency. Correct RAG cache keys to include media type; distinguish backend failure from empty results. Audit Undo's partial-failure status and expected-version checks for rating/notes. Scope account-deletion cleanup and verify paginated storage deletion completeness using isolated fixtures, without deleting real accounts.

Review identified RLS initplan/foreign-key issues and realm-tier uniqueness with data/plan evidence. Do not delete unused indexes based only on counters or assume a missing PK can be added without checking duplicates. Verify exact matview refresh behavior and reader contention before switching strategy.

Exit: no accidental second-medium requests, correct scoped caching, bounded server inputs, stable paging and preserved search recall. Match changes to representative plans and measured interaction budgets.

## Phase 5 — build Home, Discover and Collection from the agreed design

Give Home a bounded initial payload: current items/progress, relevant qualified updates, permitted club summary and optional recommendation reason. New person/title activity surfaces stay gated until Phase 6's server-enforced opt-in contract is implemented; membership-only identity summaries must not accidentally expose activity. Move the consent dependency earlier if Home needs it at launch. Reuse existing calls if they meet budgets; introduce a narrow aggregation only if it removes measured waste. Do not hide global scans inside one RPC. Main actions stay usable while secondary enrichment fails. Empty accounts get an easy first title/import route; Taste and tutorials remain optional.

Move intentional search/browse into Discover while preserving filters, scroll, query and deep-link compatibility. Do not maintain two inconsistent search implementations. Make visible-title metadata decoration batched and consumer-driven. Disabled capabilities cannot appear as functioning filters or personal recommendations.

Make Collection shelf-first with easy progress and a compact view where useful. Implement status partitions and optional name-only shelf creation. Store shelf membership separately, support deliberate ordering and multiple membership, define duplicate/limit behavior and enforce ownership/RLS. Removing a shelf or membership never deletes progress/history. Server-search unloaded titles; counts/sorts must reflect the declared whole-library/filter semantics. Provide simple, reversible multi-select actions with per-item outcomes.

Use selected medium's vocabulary and proper model: anime episodes, manga chapters/volumes and unknown totals. Avoid assuming total==current max. Preserve original import IDs and structured fields; improve resume/pagination, reconciliation and export fidelity rather than converting everything into fuzzy title text. Preserve timestamps only when supplied; do not invent historical completion dates.

Exit: agreed phone-state comparison; first useful action, one-handed reach, VoiceOver, Dynamic Type, Reduce Motion and EN/DE labels; large/empty libraries; loading/offline/failure; no clutter or needless scroll; measured call budgets pass.

## Phase 6 — clubs, identity profiles and consent

Build identity profiles within the club relationship model. Explicitly define which name/avatar/bio fields are visible and to whom. Activity/progress/history/notes/taste are separately governed; opt-in must be enforced in server projections and policies, not hidden after downloading. Decide how existing status-sharing memberships transition without silently publishing new fields.

Use one observable club detail state and a scoped realtime owner. A cache update must reach visible views. Filter/deduplicate delivered events, handle own mutation echoes, successful empty membership caches, subscribe failure/retry, backgrounding and leave/remove actions. Remove unused loading/prefetch work only after proving its consumer is obsolete.

Make club entry, invite/join, rails, polls and shared-title context obvious with minimal explanatory text. Do not add direct friendships, followers or public activity discovery. A profile visit must not fetch an entire library by default.

Exit: two-member clubs and clubs with three or more members, plus an outsider, in isolation; explicitly decide whether to preserve the current Club ACTIVE threshold that withholds member statuses below three members and reconcile it with title-level sharing-rank visibility; activity off/on; different overlapping-club privacy settings; last shared-club removal; archived club; stale caches; realtime reconnect; malicious endpoint access; no duplicated events or unintended private payloads.

## Phase 7 — releases, details and music

Separate follow-release intent from merely saving a title. Define which statuses receive updates and opt-in reminders, notification history/read state if agreed, and cancellation when intent changes. Use explicit franchise/season relations for sequel notices; do not equate a TV season announcement with a scheduled episode. Distinguish broadcast, regional legal availability, original manga chapter, translated chapter and edition release.

Serve bounded relevant events with source, certainty and checked-at timestamps. No future date means unknown coverage unless verified otherwise. Do not promise a calendar from empty/stale timestamps. Establish source coverage/age metrics and a bounded pilot before broader rollout.

Details render identity and tracking first, then qualified relations/credits and expanded entities on demand. Paginate prolific entity works; avoid fetching full biographies for a tiny preview. Audit unused available fields and existing mappings before adding another source. Each field needs a UI purpose, provenance, freshness and deletion rule.

If OP/ED is approved, verify source permission/access and run an ID-matched metadata pilot. Model production -> theme -> song/credits -> version/episode coverage, preserving ambiguity and raw nullable episode strings. Batch and cache authorized metadata, including negative matches; track child updates and deleted records. Link only to verified official destinations. Do not infer soundtrack relationships for manga from the title alone. Audio playback is a distinct follow-up with an authorized player and user control; no hidden YouTube audio, scraped audio or unauthorized caching.

Keep provider availability at its current rollout until source/cost/coverage and freshness meet agreed criteria. Consolidate duplicate status/V2/legacy reads and full locale keys before enabling. No data-source permission or rollout authority is inferred from code existing.

Exit: representative airing/finished/missing/sequel/split-cour titles; manga unknown/decimal/edition-language cases; stale/outage behavior; no wrong music matches; no blocking detail dependency; real source/rights/coverage evidence. Expose partial support honestly.

## Phase 8 — polish, usefulness and monetization experiments

Apply the approved typography, spacing, artwork and compact hierarchy consistently. Use haptics/transitions only where they confirm meaningful changes; honor accessibility/system preferences and prevent duplicate feedback on retries. Cover-derived accents require an explicit design decision and contrast tests. Auth motion must stop outside authentication.

Measure first successful save/import, successful progress update, return-to-current-title use, meaningful discovery/save, release usefulness and club participation. Distinguish analytics correlation from causal retention lift; compare optional Taste/recommendations with an editorial baseline. Collect no unnecessary private notes/history, and define consent/retention for analytics. Do not use streak pressure or notification volume as a substitute for value.

Only after core usefulness, test neutral official-book/edition link-outs or clearly labelled publisher-funded samples/benefits as described in the monetization research. Verify native-app programme eligibility and current terms. Preserve all relevant noncommercial options, ranking independence, visible disclosure, no interstitials and no tracking requirement to use the app. Do not enroll/contact partners or publish sponsored material without authorization. Revenue estimates must label traffic, conversion, eligibility and commission assumptions; no guaranteed income.

Exit: meaningful user benefit and no degradation in task completion, latency, readability or trust. Remove an experiment if it adds friction without benefit.

## Release discipline and completion contract

Work in reviewable phases. After each, update all three canonical state/plan documents and the permitted memory update note, including changed files and current counts. Add focused tests where behavior/risk warrants them; avoid tests that merely mirror visual constants. Run required relevant checks once, expanding only for unresolved failures. Preserve exact build/commit identity for every visual/runtime claim.

Before any deployment or hosted write requiring approval, finish the concrete code, migrations, fixtures, rollback plan and validation evidence so approval concerns a reviewable result. Do not ask repeatedly for already-granted authority. Do not change source permissions, credentials, source programmes, production schedules or rollout flags just to finish a plan.

For each phase report: resulting user behavior; files/contracts changed; tests and observed request/SQL improvements; source vs deployed status; unresolved limits; rollback. Attach any created PR. Completion means agreed behavior, data integrity, privacy, scoped/bounded requests, validated ingestion and confirmed release status for the authorized scope—not merely a green build, a large diff or uploaded source.
