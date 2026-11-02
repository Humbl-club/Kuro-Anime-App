COPY-READY STARTING PROMPT FOR CLAUDE CODE OR ANOTHER CODING MODEL

Fully execute the Kuro whole-codebase modularity completion contract below in /Users/max/Kuro-Anime-App. This is a continuation of the existing uncommitted migration, not a new rewrite. Read this entire handoff, its F01-F70 finding register, the existing architecture brief/contracts/ledger, AGENTS.md, CLAUDE.md, the canonical current-state documents and the active product master before changing related code. Revalidate the working tree; review baseline HEAD was 471c609943d2374c6dda940aebdfde2fcb077d50 on kuro/taste-overhaul. Use current source, not the old completion headline, as evidence.

The objective is to finish modular ownership and correctness across the entire current production codebase: Swift app/domain/adapters/presentation, all sixteen current edge-function source entrypoints, effective PostgreSQL RPC/RLS/view contracts, active workers, dashboards, runners and quality gates. Every active capability must have one state/write/lifecycle owner, a narrow typed boundary, explicit dependencies, integrated real callers and appropriate failure tests. A folder move, an index, a green characterization test or a package count is not sufficient.

Local implementation autonomy is granted for the refactors, related repairs, interface changes, forward migration preparation, deterministic tests and documentation needed by this contract. These requested changes are the applicable scope under project rules, including separating workflows, capability-private models/requests, backend handlers/provider/repository policies and worker internals. Preserve SwiftUI, @Observable, the approved Anime/Manga designs and existing supported behavior, feature-flag semantics, provider/source identity and operational external entrypoints. Do not introduce a generic event bus, service locator, dynamic plugin system, universal repository framework or a target for every file. Do not add unrelated product features.

Use specialist sub-agents with exclusive file ownership, at most five active including the lead. Sequence shared contracts and lifecycle fixes first; parallelize independent native/backend/worker slices only after interfaces are frozen. The lead owns composition, shared files, integration, documentation and final acceptance. At least one reviewer must be independent of the implementations it reviews. Agent reports are leads until the lead verifies the integrated source and evidence. Do not let every agent run the whole suite.

First preserve the dirty/untracked source and prove a fixture-only verification path. Repair known lifecycle and mutation defects before distributing more state. Import the supplied reproductions into the existing appropriate test suites where useful, correcting them to assert intended behavior. The supplied reproduction tests intentionally assert the current defect; their passing status proves reproduction, not correctness. Temporary artifacts are optional leads: if unavailable, recreate the bounded test from the described trigger using actual production code.

Process every finding F01-F70. Each entry needs a disposition: FIXED with evidence, ACCEPTED-COHESIVE with demonstrated reason for a structural proposal, CLOSED-NOT-A-DEFECT with source/contract evidence, BLOCKED with the exact external prerequisite, or PRODUCT-GATE-SEPARATE where this handoff explicitly distinguishes new product work. Never silently drop a finding or use these statuses to waive a confirmed required defect. More findings discovered during execution must enter the same register; this register is not a ceiling on inspection. Distinguish retained defects, introduced defects, privacy decisions and unverified risks.

Follow the module matrix and acceptance gates below. Inspect all active edge/worker paths even if unchanged or rarely committed. Complete semantic extractions where responsibilities, lifetimes, provider boundaries or independent failure policies diverge. Genuinely cohesive modules can remain large, with a concrete justification. No hard line cap is imposed. A review threshold prompts reasoning; it cannot force pointless splits or excuse broad mixed orchestration.

Define the affected HTTP/RPC/edit contracts before implementation. Keep deployed slugs, known request/response compatibility and installed wrapper/label/port/report contracts stable unless this contract requires an explicit documented correction. Preserve historical migrations/checksums; use new forward migrations for database changes. A SECURITY DEFINER aggregate requires explicit caller authorization, safe search_path, minimum grants and sharing-level checks. Keep JWT-derived user identity; never accept a raw client user_id as authority. Preserve safe defaults, bounded concurrency/retries and source-ID matching/unresolved relation evidence.

Default policy decisions for the local repair proposal: private individual club activity must not be retrievable through raw table reads; authorized aggregate counts must remain correct. Treat owner/admin removal separately from voluntary leave: removed users require explicit restoration before rejoining; voluntary leavers may use a still-valid invite only with accurate copy. Exclude departed-member activity from current-member aggregates or implement an explicitly justified existing-product retention rule. Record these choices and check them against the current product authority. Do not invent a new removal screen or reactivate dormant server classifiers. If a real product conflict remains, finish independent work and identify that one required decision precisely.

Use the existing seams and the smallest meaningful verification for each failure. Add one test per distinct invariant or external boundary failure, not one per getter or mechanical move. Do not run production-backed UI tests, local_cd.sh, exporters, live providers or a deployment as a verification shortcut. Add a supported fixture-only host configuration before integrated UI verification. Verify actual selected test counts; exit 0 with zero tests is not evidence. Repeat a suite only after a relevant change, failure or invalidated evidence.

Deployment, production writes, credential changes, installed-job changes, paid infrastructure, external communication and destruction of unrelated work remain explicit approval boundaries. Do not run them. Approved read-only verification can be prepared/performed under applicable project permissions. Never substitute production for a missing test stack. Keep unavailable Auth/Storage/Realtime/PostgREST/production-equivalence qualification BLOCKED, finish independent code work and provide the exact recovery path. Do not call a hard gate passed because the blocked work is disclosed.

Update the three canonical state/implementation documents and project-required memory through the applicable authorized workflow after actual initiatives. Reconcile stale current instructions and inventories; preserve historical records as historical. Save exact source identity, relevant dirty-file digests, changed paths, contracts, executed checks/counts, finding dispositions and remaining gates in the repository handoff. Do not commit, push, deploy or discard unrelated edits unless separately authorized.

Finish only after the integrated whole-codebase source satisfies the local architecture/correctness gates and every finding has an honest disposition. Report any unavailable external/product gates separately. If a mandatory gate remains failed or blocked, state NOT COMPLETE for that scope. Do not label it COMPLETE-WITH-DISCLOSED-GAPS. Deliver a senior-developer navigation guide, current ownership/dependency/caller map, complete finding ledger, final exact-source evidence and concrete pending deployment/qualification commands. Include no schedules, days or effort estimates.

END STARTING PROMPT

1. WHAT THIS HANDOFF CONTAINS AND WHAT IS KNOWN

This is the full register of findings identified in this review and the current migration's supporting source/evidence documents. It contains 70 classified entries, not 70 demonstrated new regressions. Some are reproduced defects; some are source-confirmed risks; some are architecture requirements, retained product decisions or missing qualification. Each entry states its evidence, repair and closure check. It is not a guarantee that an unknown defect cannot exist; implementation must audit the complete current owner/caller inventory and add newly discovered findings.

Review source: uncommitted working tree based on HEAD 471c609943d2374c6dda940aebdfde2fcb077d50, branch kuro/taste-overhaul. No PR URL was supplied and no deployment/production proof was obtained. The source hashes and working-tree status embedded in Appendix A distinguish this dirty tree from HEAD. Revalidate before applying changes. Unrelated prototype and user edits exist and must be preserved.

Verified review evidence:
- Four isolated simulator tests using actual Swift SDK and controlled in-process HTTP reproduced: late failed sign-in clearing B; same-account revoked friend response; tracking invalidation refilled by old parse; old-account comment result returned after A-to-B. They were run as 3 + 1 tests and actual xcresult counts were checked.
- Apply/Undo production handlers were exercised with the existing controlled database. Returned errors, partial outcomes, later edits/deletions and invalid identifiers produced the defects in F08-F14. This is not live PostgREST/PostgreSQL proof.
- An additional actual-handler probe returned a rate-limit RPC error and confirmed Apply still writes (F32).
- The repository PostgreSQL harness was rerun: 321 assertions passed, 5 BLOCKED markers and 9 FINDING markers. The fixture includes three prepared SQL fixes. It is an audited schema, not full replay or hosted equality.
- A focused PostgreSQL interleaving file ran five assertions demonstrating post-cleanup row survival, notes-only access under simulated deleted-user claims and the orphan count/join/delete race. A normal post-deletion insert was blocked by a taste-event FK; no claim of unrestricted post-deletion inserts is made.
- Package 39-test and Apply/Undo/delete 50-test checks were green in the review; green happy-path/characterization tests did not close these new failure paths. The author's final 310-test app artifact was inspected; the new review did not rerun all 310 merely to repeat it.
- 138 production Swift source files in the app and package Sources matched the isolated tested copy. The copied test host's URL/key were replaced by fixture values. No canonical application source was modified by this review.
- One individual Swift selector selected zero tests. It was excluded, corrected to the full method selector, and the intended one-test result was confirmed. Do not reuse the empty result bundle as evidence.

Appendix A embeds the reproduction source, results, local test summaries, source hashes and working-tree status in this same document. References to evidence/filename elsewhere in this document refer to the matching embedded appendix entry; no separate attachment is required. These probes are not production code or intended final tests. The raw xcresult bundles are still at /private/tmp/kuro-deep-probes-run2.xcresult and /private/tmp/kuro-deep-comment-probe-run2.xcresult if present. Importing these tests requires the existing KuroTests harness and a safe host; adapt absolute file import paths if the checkout differs. Recreate tests from the register if scratch artifacts have expired.

Already achieved work to retain:
- SupabaseService family retired; capability owners and one composition root exist.
- KuroCore/KuroLibrary/KuroSupabase have real compiled boundaries and typed tracking contracts.
- Library field-specific mutations, sequencing and a single projection are useful foundations.
- Typed routes, shared connected-card placement, detail shared chrome/provider policy extraction, and pure Concierge routing/reconciliation extraction already exist.
- The local DB guard and controlled HTTP harness are useful existing seams.
Do not redo these successful extractions just to change names. Close the remaining invariants and boundaries.

2. PRIORITIES AND THE MEANING OF COMPLETELY MODULAR

Weights are trade-off priorities, not acceptance points:
- 35% correctness, account isolation, permission lifecycle and mutation recovery.
- 25% ownership, narrow contracts, independent changes and developer navigation.
- 20% supported behavior and external/internal contract compatibility.
- 10% meaningful verification against actual production code.
- 10% simplicity, small coherent changes and efficient execution.
A failed mandatory gate cannot be outweighed by more folders, tests or packages.

A completed module must state:
- The capability and invariant it owns; actual current consumers.
- Its state and lifetime: public app-lifetime data, account data, membership data, screen/draft state, worker run state or persistent checkpoint.
- Its API contracts, dependencies, permitted calls and typed errors/outcomes.
- Its one mutation execution owner and authoritative state; all other snapshots are explicitly derived and invalidated/versioned.
- How obsolete work is cancelled/rejected before send, publication, returned private outcome and cleanup.
- Its external boundary: SDK/HTTP/DB/provider/filesystem/notification layer, kept behind the capability API.
- Its tests and practical add/remove/change path.

All active source needs ownership; not every file needs a package, protocol or class. Keep three current package targets unless a demonstrated access-control/test/consumer boundary warrants another. A new compiled target is useful when it removes concrete forbidden access or permits necessary independent verification. A folder alone cannot enforce privacy, and a package alone cannot fix behavior.

One module may contain several cohesive files. No universal maximum line count. Use roughly 500 nonblank lines for a file, or roughly 80 for a function, as an advisory review prompt if helpful; neither is a failure threshold. Generated data, fixtures and immutable historical SQL are not split to satisfy a metric. Review even small files when they mix authority or lifetime. Required splits follow a real seam: different owner, consumer, state lifetime, external dependency or failure policy. Record only meaningful large-file rulings, not paperwork for every tiny file.

3. REQUIRED NATIVE MODULE MATRIX

Use existing capability folders and patterns. Suggested internal file roles below describe ownership, not compulsory names or a requirement to create empty layers. Put private implementation behind access control and a focused dependency check. Move neutral shared values once; never duplicate them.

Identity:
  Contracts: authenticated identity, account generation, auth attempt, permission context, typed auth outcome.
  Implementation: AuthService SDK transport; SessionController single transition funnel; account-scoped teardown; callback rules; production SDK event mapping.
  Required: F01-F05, F16, F33, F46, F48. Do not split the ordering invariant across independently mutating owners.

Library:
  Contracts: MediaKey, LibraryEntry/knowledge, explicit FieldChange, mutation outcome, account-bound changes and derived invalidation.
  Implementation: current LibraryStore; LibraryActions; one actual adapter; realtime; explicit change sinks/refresh hook.
  Required: F06-F16, F21-F23, F33. Preserve serialization/field masks; check server writers and Undo against the same ownership contract. No view writes raw list tables and no second authoritative array.

Catalog / Recommendations:
  Contracts: truly shared Anime/Manga/media identity and narrow read/hydration APIs.
  Implementation: public caches, detail/entity/credits/ladder reads and batched recommendation hydration.
  Required: F23-F24, F50, F53. Remove legacy unwritten state; preserve AniList IDs and sourced relations, unresolved edges and medium identity. Avoid N+1 export/detail fetches.

Discovery / Browse / Search:
  Contracts: rails/page/cursor/query values and stateless page APIs where already appropriate.
  Implementation: current owner stores plus a screen-owned generation for filter/cursor/personalized display lifetime.
  Required: F02, F24, F47, F50, F55. Public cache lifetime differs from personalized rails. Preserve filters, ancillary-format defaults, cursor order and approved layout.

Collection:
  Contracts: visible feed/page projection, filter/paging state and batching semantics over Library.
  Implementation: CollectionStore, existing deferral helpers, views holding only selection/rendering state where safe.
  Required: F20-F22, F47, F50. One final batch refresh, justified live reads, no second list-write authority.

Clubs / Social:
  Contracts: club identity and membership/permission generation; authorized bundle/activity snapshots; typed mutation/error outcomes; small persistence/realtime APIs.
  Implementation: ClubsStore and realtime coordinator; SocialActivityStore; server aggregate contract; account-scoped preferences.
  Required: F03-F04, F07, F17, F34-F42. Recheck both success and failure; old bundles/activities cannot reach the view after invalidation; raw SQL and Realtime policy agree with aggregate privacy. Keep transitions/rejoin/teardown serialized safely.

Providers:
  Contracts: public registry/availability and legal outbound links; account provider preferences; membership-scoped shared-provider snapshot.
  Implementation: current builders/detail snapshot; separate preference state from public cache where their lifetime/access API diverges.
  Required: F03/F04 audit of analogous paths, F53, F68. Narrow callers must not have to know Supabase rows or change another capability's cache internals. Preserve country/audio/subtitle semantics and flag-off catalog fallback.

Releases / Notifications:
  Contracts: upcoming catalog data, account tracking-derived airing projection, notification permission/outcome and ownership.
  Implementation: ReleasesStore + ReminderScheduler + LiveNotificationCenter boundary.
  Required: F05, F19, F50. Public episode data can survive accounts; account reminders cannot. Cleanup must remain safe across every suspension.

Imports / Concierge:
  Contracts: parse/reconcile/clarify/preview/apply/Undo/export types, explicit ambiguity rules and recoverable mutation outcomes.
  Implementation: current production pure rules; ImportsService transport; session-local workflow model where task/draft/order needs testing; concise rendering.
  Required: F02, F06, F08-F15, F27-F33, F51, F55. Actual view consumers must use the extracted rules; no duplicated private policy in Profile/Concierge or copied test parser. Preserve approved inline editorial UX.

Taste / DeviceIntelligence:
  Contracts: actual reachable Taste signal owner, retry/outbox semantics, FMProvider capabilities and medium/source-scoped cache identity.
  Implementation: current TasteStore; actual mounted TastePicks surface; AppleFMService availability/provider seam; explicit dormant/dead classification.
  Required: F04, F18, F25-F26, F33, F63-F65. Do not manufacture a new Taste UI or offline platform to justify dead code. Server Groq stays narration-only in active paths.

Telemetry:
  Contracts: attributed events with bounded best-effort behavior and ownership; outbound-link events.
  Implementation: current account-scoped queue and fire-and-forget owner.
  Required: audit against F01-F04/F33 and scope index F70. An obsolete event must not be relabeled as a new account's event. Optional analytics failure must not abort a successful business transaction.

Navigation / Shared presentation / Design / Infrastructure:
  Contracts: typed routes and nearest presenter; pure design tokens/card/image helpers; narrow retry/load/cache primitives.
  Implementation: existing KuroRoutes, SharedCards, DetailSharedComponents, ProviderLinkViews, FlowLayout, design tokens, ImagePipeline and public detail cache.
  Required: F02, F47, F53-F55, F68-F69. Keep connected cards near their reviewed capability/neutral presentation home; do not turn Design into an SDK-aware feature bag. Avoid a growing Common/Misc/Utils dumping ground.

Composition / AppShell:
  One composition root creates/configures the SDK client and connects owners once. It owns construction, not feature business policy. Root/pager files receive only requested modular/lifecycle changes; preserve dirty user work and approved gestures/header.
  Required: F01-F05, F46-F48, F54, F61-F62, F70. Explicit safe test composition is selected before production singleton creation.

4. REQUIRED BACKEND MATRIX: ALL SIXTEEN CURRENT SOURCE ENTRYPOINTS

Entry slugs stay stable. A thin entrypoint wires environment/platform adapters and delegates the request/run; a short cohesive endpoint need not gain three artificial files. Each active mixed endpoint must expose its real run handler to controlled-boundary tests. Follow existing Deno flat sibling/shared patterns where useful; no folder-depth metric or gratuitous new framework.

concierge-parse:
  Keep rules.ts; add real request/run seam, one alias-normalization policy, candidate/search/alias/current-entry repository boundary. Preserve fan-out bounds, feedback rules and result shape. Test request auth/rate errors, search failure, an ambiguous line and existing-entry projection in the production run.

concierge-recommend:
  Keep router.ts; extract real handler/run, rail selection/secondary-rail policy, repository/cache boundary and bounded narration/budget adapter. Test rate denial/error, catalog/cache outcome, narration failure retaining deterministic recommendations and reservation cleanup. The 1,300-line serve remainder must not be waived for lack of an existing offline consumer.

concierge-apply:
  Keep the handler/plan foundation; establish database-owned atomic business write+journal/session transition, checked required outcomes, valid identifiers, coherent partial contract and retry identity. Alias/taste/analytics side effects have explicit required/optional meaning. Tests use real policy/handler and qualified SQL transaction.

concierge-undo:
  Keep the handler/plan foundation; version/after-image conditional compensation, absence/edit conflicts, partial retry and accurate terminal session status. No blind upsert over later edits or silent journal loss. Preserve import-origin taste semantics explicitly.

delete-account:
  Keep handler/adapters/deletion separation; close all-user-keyed cleanup/write races, current club lifecycle and safe orphan cleanup, required Storage/profile/table cleanup, Auth deletion order and retries. Revalidate real grants/table types/bucket. No production delete to qualify tests.

concierge-import-anilist:
  Separate supported request/cached-text validation, provider paging/limits, line conversion and run orchestration where they diverge. Fix the documented truncated request type. Preserve public-list-only behavior, S/E/rating/status meaning and finite item/provider limits.

bulk-import-anime / bulk-import-manga:
  Keep two external jobs. Separate AniList provider transport/rate handling, medium mapping, persistence/checkpoint and job orchestration. Share only actually identical stable primitives (about 100 helper lines are candidates); keep medium-specific models/fields explicit. Prove lock release/cursor progression on a controlled provider failure and a successful batch.

manga-chapter-enrich:
  Separate MangaDex transport/rate policy, deterministic identity/matching policy, mapping/review persistence and bounded enrichment orchestration. Preserve lock/finally, time budget, unresolved mappings/review state and source IDs. Test one ambiguity/mapping boundary and one interrupted/provider-failure run. Being absent from a Home UI spec does not remove it from current backend architecture scope.

manga-source-review-action:
  Keep short admin request handling cohesive if actual boundaries agree; make authorization/allowed action/affected mapping ownership explicit. Controlled handler test checks admin action and rejected caller without live enrichment writes. Trigger/re-enrich contract remains stable.

mirror-images:
  Extract bounded mirror run, source validation/fetch adapter, destination storage adapter and cursor/lock/report owner. Resolve F66. Preserve valid existing image paths/URLs and no destructive fallback when provider/storage fails.

concierge-retrieve-assist / concierge-retrieve-feedback:
  Keep small cohesive handlers if demonstrated. Define retrieval query/policy and feedback authorization/identity boundaries; reuse provider/repository seams only where concrete. Cover the actual protected request/run, not only JSON shape. Preserve rag_assist_v1 behavior and do not activate it by refactoring.

auth-callback:
  Keep cohesive static fallback where appropriate. One auth redirect contract and allowlisted target semantics; no custom scheme/link or generated Info.plist regression. Verify existing request/template behavior with a small fixture check rather than a browser snapshot for every email type.

concierge-resolve / realm-describe:
  Explicit dormant/legacy policy under F64. Do not activate prohibited server classification. If retained as deployable/manual source, type-check and define contracts, ownership and safe budgets/limits; fix Resolve lifecycle if retained. Realm vocabulary copies should use one production authority or a verified generated contract, not copied test-only enums. A planned local retirement does not authorize deleting deployed slugs/cron/config.

Cross-function rules:
- JWT user comes from verified auth, not request body.
- Required limiter/budget errors fail closed for writes/paid calls.
- Every mutation has an explicit idempotency/retry contract; an upsert alone does not establish exactly-once journaling/side effects.
- Bounded retries/concurrency/timeouts; provider and catalog identity remain typed.
- Preserve output compatibility or deliberately prepare a versioned transition with consumer tests.
- No test_fake/support modules imported into production entrypoint dependency graphs.

5. SQL IS PART OF MODULARITY

Historical migrations remain immutable history. Do not split/reorder them for file length, renumber old files, regenerate checksums for edited history or make a second manually maintained copy of every function body. The authoritative effective implementation is the latest applicable migration definition; a generated signature/ownership index links to it.

Maintain a current capability contract index for:
- Catalog / provider/source relations and availability.
- Identity/user ownership and legacy TEXT/UUID compatibility.
- Library lists, transactional import journal/compensation and change identity.
- Clubs membership lifecycle, authorized aggregates, raw RLS, realtime publication and roles.
- Social comments/reactions/friend visibility.
- Taste signals, profiles, budgets and recompute state.
- Operations queues, locks, checkpoints, catalog safety/synopsis/provider workers and housekeeping.

For each changed RPC/view/table, record input/output/error contract, owner, caller, grants, RLS, SECURITY INVOKER/DEFINER, search_path, transactional scope and relevant dependencies/indexes. New SQL is a cohesive forward migration belonging to a capability, rehearsed safely. Database modularity is about these boundaries and transactions, not mandatory schemas-per-feature or synthetic SQL modules.

F34 and F36 must be repaired together: raw row privacy and usable aggregate counts. Do not tighten SELECT in isolation and break the UI, or flip DEFINER and reveal private tracking. F35 needs a stated membership policy. F37-F39 require transactional lifecycle/cleanup coordination with writers/joins. F16/F40/F41/F43-F45 are explicit effective-schema prerequisites; do not infer live parity from a partial fixture.

6. ACTIVE WORKERS, DASHBOARDS, RUNNERS AND TOOLING

Preserve externally consumed wrapper paths, labels, ports, report filenames, installer env precedence and lock/checkpoint format unless an explicit compatible transition is prepared. Internals can be extracted without renaming those entrypoints. Do not install/start jobs during refactor by inference.

Synopsis enrichment:
  Separate synopsis quality/postprocessing policy, FM/generation provider boundary, candidate/write RPC adapter, run/backlog/retry orchestration and report serialization. Preserve raw source text and non-destructive variant writes, metrics and independent locks. Offline test uses fake candidates/provider/RPC/filesystem, actual policy/run.

Catalog safety:
  Separate term/uncertainty decision policy, source candidate/result persistence, run retry/backlog and report generation. Keep uncertain outcomes and audit evidence explicit; preserve isolation from synopsis lock/label/report/port.

Provider availability:
  Separate provider/source-ID matching and country/audio/subtitle normalization, provider transport/budget, repository/refresh queue and run/report state. Preserve feature flags/non-default rollout and honest unknown availability. No source guessing or name-only identities.

Media relations:
  Separate AniList relation transport, type/relation normalization, ID resolver, replacement/preservation rules, queue/checkpoint/backfill/coverage run and report serializer. Preserve unresolved edges and prior valid sourced relations; do not erase a valid set on provider failure.

Dashboards/installers/runners:
  Separate report parsing/status projection from HTTP serving where the failure/consumer seam is real. Share one simple public config/root resolver; preserve pipeline-specific credentials/locks/labels. Fix F57-F58 compatibility with the canonical checkout. Keep stable CLI wrappers around moved internals; update Swift compile commands and CI source discovery.

Quality gates/CI/Fastlane:
  Inspect before invoking; keep deployment separate. Standard verification runs the existing meaningful handler suites and actual architecture checks. Schema setup completeness and skipped/blocked checks are reported truthfully. Fix F59/F60/F61/F70. No exporter, hosted rail audit or production-linked UI run is a default offline test.

Scope classification:
  Inventory all current scripts from script-classification.csv, including active manual runbooks, DB helpers, data generators and CI paths. Pure one-off/generator scripts may remain cohesive with a named owner and no active runtime state. Dormant/legacy/generated/research/prototype material must be classified, not erased or refactored merely to inflate completion. User-owned browser prototypes remain protected; if their code is included in a requested future architecture scope, obtain that scope explicitly rather than overwriting current design work.

7. DEPENDENCY AND MAINTENANCE RULES

- Composition may depend on every owner to construct/connect it; it contains no business write policy.
- Feature callers depend on narrow declared capability APIs or neutral shared contracts, not another feature's private storage/tasks/cursors/SDK client.
- UI imports no Supabase/PostgREST/Auth/Functions/Storage/Realtime payload types. Capability adapters can use SDK internally.
- Library is the only local tracking authority. Collection/Discover/Club/import snapshots are versioned derived values. Server writers are explicitly mapped and notify/refresh through the one Library integration path.
- Account, membership, tracking revision, screen request and worker run generations are distinct when their lifetimes differ. Do not substitute one account check for all five.
- Required business effects and optional telemetry are distinct; the latter may be best-effort without compromising the former.
- No duplicate canonical media models, parser/router implementations or normalization vocabularies.
- Shared infrastructure must be neutral, small and used by real consumers. Avoid a new broad shared-service facade.
- New feature addition has a localized path: capability API/implementation/tests, composition registration, necessary route registration and generated ownership documentation. It should not require edits to unrelated capability internals or a broad RPC-param dump.
- Feature removal has a localized path: disconnect real callers/routes, cancel/clear owned state/tasks/subscriptions, remove composition and local files/tests, update inventory. Remote schema/data/endpoint removal is separately prepared and approved. Prove locality by tracing one representative capability addition/change and removal in a scratch analysis; no need to invent a fake shipped feature.

8. SUCCESS GATES FOR THIS COMPLETION PASS

G0 Source preservation / safe verification:
  Exact commit plus dirty/untracked inventory/digests and unrelated work protection. Unit/UI hosts use fixture-only config with isolated auth storage and denied production network. Evidence references the actual tested tree and configuration. No unauthorized deployment/writes.

G1 Account / permission / pending-work lifecycle:
  F01-F05/F33/F42 and every audited private equivalent resolved. Old work cannot send under another account, publish/return private state, clear a newer draft/error/identity, remove newer reminders or resurrect a revoked snapshot. Real SDK delayed success/failure tests and membership-change checks run. Separate real Realtime qualification if unavailable.

G2 Mutation / projection / recovery coherence:
  One execution owner and authoritative projection per mutation/state. F06-F15/F21/F31/F32/F38/F39 resolved. Writes/journals/transitions are atomic or have a deliberately recoverable partial contract; retries/Undo are safe and derived snapshots are current. Actual transaction boundary has database evidence; fake DB checks alone do not close SQL concurrency.

G3 Whole-codebase architectural coverage:
  Complete current owner/caller/state/dependency/write inventory across native, all sixteen edge source entrypoints, effective SQL, active operations and CI. Matrix completed; divergent active seams extracted and real callers integrated. Deliberately cohesive/dormant code has evidence-backed disposition. No forbidden internal access, duplicate authority or unowned active path.

G4 External / product compatibility:
  Field scales/identity/null/error shapes, flags, paging, routes, approved layout, provider locales/source relations, operational entrypoints/reports/checkpoints preserved or explicitly corrected. F16/F17/F20/F29/F30/F34-F45/F68 addressed at the required qualified boundary. Sixteen journey checklist has current evidence. External deployed parity remains a separate exact-target gate; local changes do not prove it.

G5 Proportionate verification:
  Production rules/handlers/worker runs tested at existing meaningful seams. Four native reproduced defects and handler/SQL recovery defects assert intended behavior after repair. F43-F50 are resolved or explicitly BLOCKED. Critical Deno suites are in the gate path, selected test counts are nonzero, characterized product defects are not miscounted as acceptance, screen request/channel counts are bounded.

G6 Maintainability / simplicity:
  F51-F58/F69/F70 addressed; short documented APIs/lifetimes guide a senior developer. No compulsory package count/line cap/framework, no unnecessary model duplication, no abstract layer without an invariant/consumer/test benefit. Remaining large cohesive files have evidence. Necessary shared contract edits are coordinated; adding/removing a capability avoids unrelated internals.

G7 Truthful handoff / current documentation:
  F59-F62/F70 addressed; current-state technical/plain documents, implementation status, project guidance and module map agree. Final finding ledger and exact-source independent review are saved. Closed original E8 extractions remain closed. Every required open item has a current gate; source/fixture/hosted/deployed/release proof are labeled separately.

Statuses:
  PASS = all required evidence for that defined scope succeeded on current integrated source.
  FAIL = a required behavior/structure check is wrong or failed.
  BLOCKED = a stated required prerequisite/environment is unavailable; no inferred pass.
  NOT APPLICABLE = explicit evidence shows the path is dormant/removed/outside current production scope, with compatibility preserved; never a way to ignore an active defect.
  A product-master durability/capacity gate can remain separately scoped under F63 without commissioning unrelated work, but no durability/release claim may be made.

Acceptance does not require production deployment during this task. It does require honest local completion and prepared compatibility/qualification work. If a required qualified test cannot run, the corresponding acceptance remains BLOCKED. The final report can say source repairs are implemented and locally tested; it cannot say all mandatory gates passed.

9. TEST POLICY: SUFFICIENT WITHOUT OVER-TESTING

- Reuse the actual AccountLifecycle/Identity SDK/StubPostgREST harness and existing Library/Import/Club suites. Convert supplied defect probes to intended assertions in those suites; do not ship a parallel copied policy implementation.
- Cover distinct transition mechanisms and invariant failures, not every method/provider permutation. Same shared funnel tests can support multiple callers after actual SDK mapping has been checked.
- For Apply/Undo, cover valid add/update, later edit/deletion, returned journal/finalization errors, mixed partial outcome, interrupted compensation/retry, invalid ID and limiter error. Test business transaction concurrency in PostgreSQL once per distinct transaction invariant.
- For Clubs SQL, test raw access and aggregates together at all three privacy levels with real roles; exercise removal/rejoin/current-member count behavior and actual event qualification when available.
- For backend extraction, one representative real run/handler success and failure per distinct orchestration/provider lifecycle, plus focused pure-rule cases already available. Do not repeat provider faults in every forwarding wrapper.
- For workers, actual run policy with controlled providers/repositories/filesystem/clock; one interruption/provider-failure check proves checkpoint/cleanup. Never run the real worker against linked production as a test.
- For UI, group automation by route/presenter wiring; selective manual fixture journey evidence can qualify appropriate visual/interaction parts. Use state-based waits. No screenshot-per-component or exhaustive gesture matrix.
- Use request counters for cold/warm/remount/batch representative flows; no generic performance platform or large load test solely for modularity.
- Run affected slices during work. Once integrated, run required existing package/app/Deno/structural/docs/local DB checks on final source, and the selected safe UI checks. A build-and-test run supplies build evidence; no duplicate identical build is needed. Run a separate Release build only if build settings/resources/conditional paths need qualification or the required project gate requires it.
- Inspect mandatory gate scripts and separate those requiring a hosted target. Never silently skip a hard requirement or mark zero-test success as proof. A skipped or missing environment test is recorded with its recovery path.
- No coverage percentage, mutation-score quota, endless final re-review or test count target. Use a short scratch mutation only where needed to establish a guard test actually fails; restore it exactly.

10. EXECUTION ORDER AND REQUIRED DELIVERABLES

Phase A: snapshot and test isolation. Confirm scope, instructions, current product authority, all owner/caller/state inventories and safe test configuration. Reproduce disputed high-risk findings using supplied bounded triggers.
Phase B: Identity/private lifetime/credential dispatch fixes and one cohesive mutation/journal/recovery contract. Freeze shared contracts before extraction proceeds.
Phase C: native owner/private model/workflow cleanup and complete backend run/policy/provider/repository boundaries. Parallelize disjoint files only. Keep central composition and SQL contracts lead-owned.
Phase D: SQL privacy/membership/cleanup transactions and active worker/operational internals; preserve wrappers/contracts and qualify effective schema requirements. Backend modules remain part of completion, not an optional follow-up.
Phase E: real consumer integration, safe UI journeys, request/channel-count checks, current documentation and final exact-tree verification. Independent reviewer checks fixes and evidence, including account/permission failure and database transaction cases.

Deliver:
1. Current module/navigation map with actual APIs, owner/state/lifetime/dependencies and add/remove instructions.
2. Complete F01-F70 disposition register, plus any newly discovered items, with source/test/contract evidence and genuine blockers.
3. Native/backend/SQL/worker matrix marking each active capability completed and each dormant/legacy path classified.
4. Changed-path list, prepared forward migrations and compatibility decisions.
5. Exact final source/digests and verification commands/results/actual test counts.
6. Honest gate table and independent integrated review.
7. Pending approved-target qualification/deployment sequence with prerequisites; no unauthorized execution.
8. Updated canonical state/implementation/guidance/inventories under project rules.

11. FULL FINDING REGISTER

The entries below are the actionable register. Source paths are relative to /Users/max/Kuro-Anime-App unless they point to evidence or an explicitly named SDK checkout. Line references are review locators and must be revalidated after changes. Priorities label impact/qualification obligation, not automatic proof of a current production incident. Original-source comparisons confirmed retained Apply/Undo/deletion patterns; additional source risks must be classified honestly by the implementer.

F01 — Obsolete authentication failure clears a newer successful account
Evidence: REPRODUCED: real Swift SDK / controlled HTTP
Priority: P1
Owner: Identity
Sources: Kuro/Identity/SessionController.swift:230; evidence/DeepReviewProbes.swift:lateFailedSignInEndsB
Problem: A delayed failed sign-in for A calls endSession after B has successfully signed in. The isolated SDK probe confirms B becomes unauthenticated. Similar unguarded failure paths exist for Apple/restore and require tracing; those additional paths were not separately reproduced.
Required action: Give authentication attempts an explicit generation. Recheck both successful and failed completions before publishing identity, clearing a session, reporting an error or bootstrapping. Preserve the central transition order.
Closure check: Hold A failure, complete B sign-in, release A: B remains authenticated and retains its projection and error state. Cover the shared failure funnel rather than duplicating every provider test.

F02 — Private presentation state survives direct A-to-B transition
Evidence: SOURCE-CONFIRMED; integrated UI reproduction outstanding
Priority: P1
Owner: AppShell / Discovery / Concierge / Clubs
Sources: Kuro/KuroApp.swift:156; Kuro/Views/EditorialDiscoverView.swift:17,393; Kuro/Views/ConciergeView.swift
Problem: RootView keeps the ContentView branch while isAuthenticated remains true. Discover has a local model and one-time initial load; Concierge holds conversation, selections, drafts and tasks. Store clearing alone does not clear these private presentation copies. The historical review assumed sign-out unmounting covered all transitions.
Required action: Scope private presentation lifetime to account generation, reset drafts/conversations/selections and cancel work, then reload for the new account. Choose targeted resets or an account-scoped subtree identity; avoid resetting all public caches and approved navigation unnecessarily.
Closure check: An integrated A-to-B journey with populated Discover, Concierge and an open private sheet reveals no A data or drafts, and B loads once. Same-user token refresh preserves legitimate state.

F03 — Friend activity can return after same-account club revocation
Evidence: REPRODUCED: real Swift SDK / controlled HTTP
Priority: P1
Owner: Social / Clubs / detail presentation
Sources: Kuro/Social/SocialActivityStore.swift:108,117; Kuro/Clubs/ClubsStore.swift:181; Kuro/Views/DetailPages/FriendsActivitySection.swift:14,87
Problem: invalidateFriendProjection clears count work, but fetchFriendActivityForTitle checks account identity only. A delayed response from revoked membership is returned. The detail section retains activity and only keys its task to mediaId; if another club remains, hasClubs remains true.
Required action: Add a permission/membership generation to Social snapshots, reject stale responses and reset/refetch the section on permission change. Distinguish account change, membership change and public catalog lifetime.
Closure check: Hold activity, revoke one club while keeping another, release: revoked friend comments/progress are neither returned nor rendered. Current authorized friend activity can be reloaded.

F04 — Successful private mutation completions bypass account guards
Evidence: REPRODUCED for Social; SOURCE-CONFIRMED for Club success-side effects
Priority: P1
Owner: Social / Clubs / Taste
Sources: Kuro/Social/SocialActivityStore.swift:130; Kuro/Clubs/ClubsStore.swift:341,501,518; Kuro/Taste/TasteStore.swift:214; evidence/DeepReviewProbes.swift:staleCommentMutationReturns
Problem: An A comment response is handed out after B becomes current. Social mutations do not capture/check context. Club create/join and success cache evictions have incomplete context checks. Taste can return accepted=true for an ended account even though its Library hook is guarded. This contradicts the claim that every private completion is fenced.
Required action: Capture account and applicable permission scope for every private operation. Recheck before success-side effects, errors, refreshes and returning private outcomes. The view must also reject obsolete completion before clearing a newer draft. Audit the complete method inventory, not just the reproduced example.
Closure check: Delayed old-account success and failure cannot change the new account caches, drafts, loading/error state, selections or routes. Reuse the existing SDK harness for representative mutation families.

F05 — Reminder cleanup can remove newer-account notifications
Evidence: SOURCE-CONFIRMED race; notification scheduling interleaving not executed
Priority: P2
Owner: Identity / Releases
Sources: Kuro/Identity/SessionController.swift:417,462; Kuro/Releases/ReminderScheduler.swift:156
Problem: Session cleanup awaits channel removal or pending notification lookup and then deletes unscoped airing-* IDs. A new account can become current during either suspension. The nil-account check before an await does not protect the later delete.
Required action: Bind notification identifiers and cleanup to owner/generation, or serialize the ownership transition safely. Recheck after asynchronous lookups; do not remove a newer owner marker. Keep restored-own-account reminders and sign-out ordering correct.
Closure check: Pause old cleanup, establish B and its reminders, resume cleanup: B reminders and ownership survive. Ended A reminders are removed.

F06 — Tracking cache invalidation is undone by an in-flight parse
Evidence: REPRODUCED: real Swift SDK / controlled HTTP
Priority: P2
Owner: Imports / Library
Sources: Kuro/Imports/ImportsService.swift:82,129; Kuro/Imports/ImportReconciler.swift:197; evidence/DeepReviewProbes.swift:staleParseRefillsCache
Problem: dropTrackingCopies clears only completed cache entries. A parse already in flight later republishes an old existing_entry response; account context remains valid. Cache TTL is 600 seconds. Reconciliation prefers a provided server existing_entry, so fresh Library knowledge does not necessarily repair the stale copy.
Required action: Introduce a tracking revision for parse loads/cache, cancel or supersede loads on relevant changes, and reject pre-change completion. Define precedence between current Library knowledge and a versioned parser snapshot.
Closure check: Begin parse, make a Library change, release old parse: it cannot repopulate a usable stale cache or drive an outdated Apply preview. A new parse/explicit rebase uses current state.

F07 — Older club bundle is returned despite a newer accepted cache entry
Evidence: SOURCE + existing controlled test prove stale return; screen publication traced
Priority: P2
Owner: Clubs / ClubDetail
Sources: Kuro/Clubs/ClubsStore.swift:436; Kuro/Views/ClubDetailView.swift:410; KuroTests/ClubsContractTests.swift:1047,1091
Problem: The store refuses to replace a newer cached bundle but returns the older response anyway. ClubDetailView assigns it. The existing test expects PLANNING from the old caller while the cache holds CURRENT, characterizing the undesired behavior.
Required action: Return the accepted newest snapshot or reject superseded loads. Prefer a monotonic request generation to wall-clock ordering. Cover the caller, not only the cache.
Closure check: An old request finishing after the post-write refresh cannot restore an old status/progress/rating in the screen. Rewrite the characterization expectation into the intended invariant.

F08 — Undo overwrites later edits to fields the import wrote
Evidence: REPRODUCED: actual Apply/Undo handlers with controlled database
Priority: P1
Owner: Imports backend
Sources: supabase/functions/concierge-undo/undo_plan.ts:43; evidence/undo-reproductions.jsonl
Problem: Import rating 8 to 9, manually edit to 10, Undo restores 8 without warning. modifiedSinceImport compares list_type/progress only, while restoration can write rating and notes. This is retained behavior, not attributed as a new migration regression.
Required action: Compare every field being reverted against the imported after-image, including nullable rating/notes. Perform comparison and conditional change atomically; an application-level read then write still races with a concurrent edit.
Closure check: Later edits to written rating/notes/status/progress survive Undo. Unrelated fields remain untouched. Add one controlled database race for compare-and-revert, not a combinatorial test matrix.

F09 — Undo resurrects an entry deleted after an update import
Evidence: REPRODUCED: actual handlers with controlled database
Priority: P1
Owner: Imports backend
Sources: supabase/functions/concierge-undo/undo_plan.ts:76; evidence/undo-reproductions.jsonl
Problem: A current=null row skips the modified-state test and an update with previous_values is restored by upsert. A deliberate deletion after import is reversed silently. Retained behavior.
Required action: Treat absence after an update as a later user change. Specify add/update/remove compensation independently; do not conflate restoring an import with recreating subsequently deleted data.
Closure check: Import update, delete row, Undo: row stays absent and the response explains the skipped compensation. Normal untouched update Undo still works.

F10 — Apply succeeds when its item journal insert fails
Evidence: REPRODUCED: actual handlers / returned PostgREST-shaped error
Priority: P1
Owner: Imports backend / SQL transaction owner
Sources: supabase/functions/concierge-apply/handler.ts:296,399; evidence/kuro-deep-handler-probes.jsonl
Problem: List write succeeds, import_session_items insert returns an error, Apply ignores it and reports success. Undo reads no journal item, reports success with no reverted rows, and leaves the imported row. Retained defect.
Required action: Make list write plus journal creation a cohesive transaction. Required journal errors must not be best-effort. Checking the error only after the list write does not establish atomicity or recovery.
Closure check: Injected journal failure yields no unjournaled accepted mutation. Successful Apply always has an executable journal. Test the real transaction against PostgreSQL and handler error translation once.

F11 — Apply ignores session-finalization failure
Evidence: REPRODUCED: actual handler / returned database error
Priority: P1
Owner: Imports backend
Sources: supabase/functions/concierge-apply/handler.ts:455; evidence/kuro-deep-handler-probes.jsonl
Problem: Failure of the status update leaves a draft session, yet Apply reports success. Undo then returns No applied session to undo while the row remains. Retained defect.
Required action: Check required state transitions and tie them to recoverable transaction outcomes. Distinguish required accounting from optional analytics. Prevent duplicate execution after a lost acknowledgment.
Closure check: Failed finalization cannot be reported as completed Apply. Retrying uses the established operation identity and resolves the same outcome without duplicated business writes.

F12 — Partially successful Apply cannot be undone and is hidden by UI
Evidence: REPRODUCED: actual handlers; UI path SOURCE-CONFIRMED
Priority: P1
Owner: Imports backend / Concierge presentation
Sources: supabase/functions/concierge-apply/handler.ts:455; supabase/functions/concierge-undo/handler.ts:80; Kuro/Views/ConciergeView.swift:1067
Problem: One valid manga add and one anime conflict produce a persistent successful write and status failed. Undo only searches applied sessions and returns 404. The UI shows generic failure and omits a partial-success summary/action. Retained behavior.
Required action: Choose an explicit coherent transaction contract: atomic all-or-nothing, or item-level partial outcomes with recoverable journal and Undo eligibility. Preserve current callers or deliberately version the contract. Surface accepted items and failed/conflicted items accurately.
Closure check: Mixed input leaves either no accepted writes or an accurately reported, reversible partial result. Retrying never loses the original before-image or silently reclassifies an original add into an unrelated update.

F13 — Failed Undo is marked cancelled and cannot be retried
Evidence: REPRODUCED: actual handlers / transient delete failure
Priority: P1
Owner: Imports backend
Sources: supabase/functions/concierge-undo/handler.ts:190; evidence/kuro-deep-handler-probes.jsonl
Problem: Undo collects a transient per-item error, marks the whole session cancelled anyway, and returns success=false. A retry returns 404 while the row remains. The cancellation update error is also ignored. Retained defect.
Required action: Record per-item compensation state or use a safe transaction. Mark complete only after required work succeeds. Support retry without compensating already-reverted items again.
Closure check: Fail one compensation, remove the fault, retry: unfinished work completes, completed work remains correct, and session state matches the actual result.

F14 — Identifier clamping changes invalid input into title 1
Evidence: REPRODUCED: actual Apply handler
Priority: P2
Owner: Imports validation
Sources: supabase/functions/concierge-apply/apply_plan.ts:64; evidence/kuro-deep-handler-probes.jsonl
Problem: 0, -4 and null media IDs are accepted as media ID 1 because Number coercion and clamping are used for identity. Retained defect. Other identity/candidate-index coercions deserve the same review.
Required action: Reject non-integer, non-positive, out-of-range or missing identities. Validate status against the supported medium-specific vocabulary. Keep quantity clamping separate from identifier validation.
Closure check: These inputs return validation errors and send no list write. Valid Anime/Manga IDs remain distinct even with the same numeric value.

F15 — Season/episode annotations overwrite existing user notes
Evidence: DOCUMENTED retained behavior; pinned in real handler tests
Priority: P2
Owner: Imports policy
Sources: docs/modules/edge-functions.md; supabase/functions/concierge-apply/handler.ts:257; Kuro/Imports/ImportReconciler.swift:writesSeasonNote
Problem: An import with S/E data and no explicit notes synthesizes S{n}E{m} and writes it over stored anime notes. The new provided-fields-only claim has an exception that can discard authored notes.
Required action: Preserve existing notes when notes were not explicitly edited. Keep structural season/episode annotations separate, or use a reviewed non-destructive representation. Carry this distinction in the edit/journal contract.
Closure check: Existing authored notes survive a progress/season-only import and its Undo. Explicit note edits still apply and compensate correctly.

F16 — Native UUID casing disagrees with captured list RLS
Evidence: FIXTURE-REPRODUCED mismatch; live parity UNVERIFIED
Priority: P1 qualification blocker
Owner: Library adapter / Identity / SQL
Sources: Packages/KuroModules/Sources/KuroCore; Kuro/Identity/AuthService.swift; supabase/tests/rls/10_user_lists.sql:60; docs/plans/2026-10-05-modular-architecture-completion-report.md:47
Problem: Swift uuidString is passed as upper-case TEXT; captured RLS compares auth.uid()::text in lower case. The fixture rejects upper-case IDs containing hex letters. A fake backend using the same string for both sides can conceal this mismatch.
Required action: Inspect approved read-only effective policies/data before choosing normalization. Canonicalize at one adapter boundary, preserve supported historical rows, and prepare a forward migration if legacy casing requires it. Do not blanket-rewrite user IDs or production rows.
Closure check: Real SDK request plus qualified RLS accepts the authenticated owner and denies another user, for UUIDs containing letters. Historical casing is handled without duplicate or lost rows.

F17 — SDK decodes detail while PostgREST sends details
Evidence: SOURCE-CONFIRMED and characterized; server still denies forbidden actions
Priority: P2
Owner: Club error adapter
Sources: Kuro/Clubs/ClubError.swift or ClubsStore error mapping; supabase-swift Sources/PostgREST/PostgrestError.swift; docs/plans/2026-10-05-modular-architecture-execution-ledger.md
Problem: Structured SQL DETAIL codes are lost at decoding in the reviewed SDK. This harms duplicate/membership-loss diagnosis and revocation handling; it does not demonstrate an authorization bypass.
Required action: Use a supported reliable wire code mapping, a justified dependency repair, or a compatible server error shape. Keep one translator and preserve rejection semantics. Do not arbitrarily trust arbitrary text as a membership-loss code.
Closure check: A realistic PostgREST JSON error reaches the typed ClubError and intended revocation behavior. Unknown errors remain unknown, and another account is never revoked by an old error.

F18 — Synopsis cache mixes Anime/Manga identity and input domains
Evidence: SOURCE-CONFIRMED; FM generation not run
Priority: P2
Owner: DeviceIntelligence
Sources: Kuro/Services/AppleFMService.swift:212,340,385
Problem: The same Int dictionary stores description.hashValue keys and bare mediaId keys. Anime 7 and Manga 7 share the explicit ID key; an updated description can reuse old content for the same ID. Sharing hash and ID namespaces is also unnecessary collision risk.
Required action: Use a typed key containing MediaKey plus relevant source revision/input digest and locale. Keep text-only calls in a distinct key case. Expose a small provider/cache seam without requiring live Foundation Models in tests.
Closure check: Equal numeric Anime/Manga IDs and changed input never return each other's cached text. Non-FM devices continue to show the existing fallback safely.

F19 — Notification delivery permission changes are not reflected in outcomes
Evidence: SOURCE-CONFIRMED scheduling contract gap; device behavior UNVERIFIED
Priority: P2
Owner: Releases / notifications
Sources: Kuro/Releases/ReminderScheduler.swift:30,43; docs/plans/2026-10-05-modular-architecture-test-matrix.md:750
Problem: Permission is requested only when notDetermined. Scheduling is void and failures are debug-only, so revocation is not represented to callers. The review does not claim an observed delivered notification after denial.
Required action: Make permission/delivery outcome explicit at the notification boundary and recheck authorization when relevant. Preserve approved UI; avoid new prompts on every schedule. Test the existing abstraction and qualify one live notification path separately.
Closure check: Denied/revoked permission cannot be reported as successful delivery or leave misleading state. Authorized scheduling and restored-own-account behavior remain intact.

F20 — Request timestamps omit a time-zone designator
Evidence: CHARACTERIZED wire shape; incorrect live instant NOT demonstrated
Priority: P2 compatibility qualification
Owner: Collection / transport serialization
Sources: KuroTests/CollectionContractTests.swift:37; SDK date encoder / RPC date payloads
Problem: The test helper appends Z to SDK timestamps lacking a zone and assumes UTC. This can conceal interpretation differences at PostgreSQL boundaries; no observed production time shift is claimed.
Required action: Define timestamp versus civil-date semantics at each affected API. Use explicit UTC instants where appropriate, or prove the server interpretation under a non-UTC database session. Do not alter display dates indiscriminately.
Closure check: Same instant survives SDK encode, database cast and decode across non-UTC session/device settings. Date-only fields retain their intended civil-date meaning.

F21 — Batch status updates fan out redundant Collection refreshes
Evidence: SOURCE-CONFIRMED request amplification
Priority: P2
Owner: Collection / Library change sinks
Sources: Kuro/Views/EditorialCollectionView.swift:755; Kuro/Collection/CollectionStore.swift:643
Problem: Each batch status mutation triggers the Collection sink, then the view performs an explicit feed fetch. The existing withCollectionRefreshDeferred helper is used by removal but not status updates. Cancelling successive requests still creates avoidable started work.
Required action: Use the existing deferral scope for the batch, retain per-item outcomes and perform one final refresh for the active filter. Do not add a global event framework.
Closure check: A representative batch produces bounded final refresh requests, preserves per-item success/failure reporting and leaves the visible filter correct.

F22 — Collection card pages are fetched without current view consumers
Evidence: SOURCE/DOCUMENTED unused data path; confirm final callers before removal
Priority: P2 maintainability / efficiency
Owner: Collection / session bootstrap
Sources: Kuro/Collection/CollectionStore.swift; Kuro/Identity/SessionController.swift; docs/plans/2026-10-05-modular-architecture-large-file-review.md:CollectionStore
Problem: collectionAnimeItems and collectionMangaItems are fetched and held but no current view reads them according to the caller map. Bootstraps and post-import refreshes can do work the feed-based UI does not use.
Required action: Revalidate callers including flags and prototype-linked production views. Remove unused live reads/state, or integrate them as a justified projection with an actual consumer. Keep card pages required by another approved flow.
Closure check: The remaining Collection state has named real consumers and cold/post-write request counts show no unused page loads. Removal does not break imports or exports.

F23 — Catalog keeps unwritten legacy paging state and an ineffective export fallback
Evidence: SOURCE-CONFIRMED
Priority: P2 maintainability
Owner: Catalog / Imports export
Sources: Kuro/Catalog/CatalogStore.swift:63; Kuro/Imports/ImportsService.swift:421; docs/plans/2026-10-05-modular-architecture-large-file-review.md
Problem: Legacy animeItems/currentAnimePage/loading fields have no current writer. Imports export reads the always-empty array as a title fallback. The fields suggest a second catalog/list projection that is not real.
Required action: Remove unwritten paging state after confirming callers. Resolve export titles through a typed Catalog reader or established hydrated Library entry path, with bounded batch fetching rather than per-title N+1 requests.
Closure check: Exports contain available real titles; unresolved IDs use an explicit truthful fallback. No stale unused paging state or replacement independent tracking authority remains.

F24 — Unreachable GenreHub keeps a large legacy rail family alive
Evidence: SOURCE/DOCUMENTED reachability gap
Priority: P2 maintainability
Owner: Discovery / secondary presentation
Sources: Kuro/Views/GenreHubView.swift; Kuro/Discovery/DiscoveryStore.swift; docs/plans/2026-10-05-modular-architecture-large-file-review.md:DiscoveryStore
Problem: GenreHubView has no current construction; roughly 300 lines of rail methods and two section types exist mainly for it. fetchTrendingAnime still has a real AuthView consumer and must not be swept away with the dead family.
Required action: Trace all route/flag/preview/operational callers. Locally retire unreachable source or assign an approved reachable consumer; do not add a new product route merely to justify keeping code. Preserve actually used trending behavior.
Closure check: Each retained Discovery API has a current consumer; removed code has no remaining compiled references and the existing Auth experience is preserved.

F25 — TasteDeck and its outbox UI are not mounted in production
Evidence: SOURCE-CONFIRMED reachability / qualification gap
Priority: P2
Owner: Taste / AppShell
Sources: Kuro/ContentView.swift; Kuro/Views/TasteDeckView.swift; Kuro/Views/TastePicksView.swift; docs/plans/2026-10-05-modular-architecture-test-matrix.md:492
Problem: ContentView mounts TastePicksView; TasteDeckView has no construction in Kuro. Tests of its model/outbox do not establish behavior of the actual mounted Taste surface. Historical inventory still describes a deck at pager index 0.
Required action: Map the current approved Taste capability and real signal writers. Remove obsolete unreachable code if confirmed, or integrate only if the product authority requires it. Ensure the actual mounted surface uses the one signal owner.
Closure check: A real mounted Taste journey verifies signal ownership, errors and navigation. The inventory accurately names the reachable UI and no second signal writer is introduced.

F26 — The declared non-FM stub is unused and fallback is untested
Evidence: SOURCE-CONFIRMED + test gap
Priority: P2 qualification
Owner: DeviceIntelligence / composition
Sources: Kuro/Services/AppleFMService.swift:69,693; Kuro/Composition/AppComposition.swift:573
Problem: StubFMProvider is never instantiated. The live AppleFMService availability guard returns nil, which is different from proving a functioning injected fallback. Existing documentation can imply more fallback coverage than exists.
Required action: Use the existing FMProvider seam where it makes caller behavior testable; test unavailable and failed-provider outcomes. Remove unused stub code if it serves no consumer, or wire it into tests. Preserve current nil/no-assist behavior.
Closure check: Classification, disambiguation, synopsis and collection-search consumers work without FM and without an extra loading trap or unintended server classifier.

F27 — Three parser defects are pinned as green characterization cases
Evidence: DOCUMENTED executed corpus defects
Priority: P2
Owner: Concierge parser
Sources: supabase/functions/concierge-parse/rules_corpus_test.ts; docs/modules/edge-functions.md; tests/concierge-corpora
Problem: parser_en_009 and parser_de_012 split Steins;Gate on semicolon; parser_de_022 drops the German perfect-tense progress phrase bis Kapitel 200. Current-output pins can keep the gate green while the intended input still fails.
Required action: Repair title-preserving segmentation and the progress extraction in production rules. Update the specific defect pins to intended outcomes, retaining protected supported inputs. Avoid another copied parser in tests.
Closure check: The three corpus cases pass the intended behavior through production rules and an import integration example targets the correct title and progress.

F28 — Two German mood cases route to fallback instead of intended modes
Evidence: DOCUMENTED executed router gaps
Priority: P2
Owner: Concierge routing
Sources: supabase/functions/concierge-recommend/router_corpus_test.ts; docs/modules/edge-functions.md
Problem: router_de_005 romantisches and router_de_029 schauriges route to premium_picks. They are pinned production outputs, not proof of the expected mood behavior.
Required action: Define the intended inflection matching in the deterministic router, keeping the closed mode vocabulary and narration-only server AI policy. Resolve the two cases without a broad heuristic rewrite.
Closure check: The exact German inputs reach the accepted modes; existing EN/DE corpus expectations remain valid or explicitly adjudicated.

F29 — Parser corpus disagreements have unresolved acceptance meaning
Evidence: DOCUMENTED questions / fixture maintenance gap
Priority: P2 acceptance
Owner: Imports / parser contract
Sources: docs/modules/edge-functions.md; supabase/functions/concierge-parse/rules_corpus_test.ts
Problem: Ten product-question cases are pinned and four corrected expectations exist only in the test while original corpus data differs. IDs: de_050,en_046,en_039,de_037,en_040,de_038,en_055,de_046,de_052,de_018; corrections de_013,en_011,en_025,de_004. Not all disagreement is a demonstrated parser bug.
Required action: Adjudicate each case against accepted import semantics, document the outcome and keep the canonical fixtures/test annotations consistent. Do not claim zero defects by re-expecting undesired output.
Closure check: Each listed case has an explicit intended outcome and rationale. A corpus gate distinguishes genuine defects from accepted semantic choices without silently modifying all expectations.

F30 — clarify_v2 off allows parser-ambiguous auto-Apply
Evidence: SOURCE/DOCUMENTED retained product decision
Priority: P1 decision for writes
Owner: Imports / Concierge
Sources: Kuro/Imports/ImportReconciler.swift:378,388,401; Kuro/Views/ConciergeView.swift; docs/plans/2026-10-05-modular-architecture-completion-report.md
Problem: Concierge can auto-apply parser-ambiguous lines when clarify_v2 is off; Profile uses a stricter entrypoint. Adaptation ambiguity still blocks, so these are different ambiguities. The divergence is intentional in the code but weakens a broad safe-import claim.
Required action: Use the active product contract to define write-safe ambiguity. Default to requiring review for material uncertainty about title/status/progress; preserve harmless wording ambiguity only with an explicit rule. Centralize named rules and document any intentional surface difference.
Closure check: An ambiguous title/adaptation or materially uncertain mutation cannot silently apply. Concierge and Profile each have an explicit tested acceptance policy for both flag states.

F31 — Parse and Apply normalize aliases differently
Evidence: SOURCE-CONFIRMED duplicated policy drift
Priority: P2
Owner: Imports shared server policy
Sources: supabase/functions/concierge-parse/rules.ts:122; supabase/functions/concierge-apply/apply_plan.ts:26
Problem: Parser normalization strips additional verbs and rating expressions; Apply normalization does not. An alias recorded at Apply can miss the lookup key used by Parse.
Required action: Extract one shared production alias-normalization rule used by both paths. Assess existing persisted aliases before changing matching; preserve valid provider/source identity and avoid name-only adaptation linkage.
Closure check: Record then look up representative EN/DE/rating-bearing aliases through actual consumers: keys agree. Existing aliases have a compatible read path or prepared migration strategy.

F32 — Rate-limit lookup errors fail open
Evidence: REPRODUCED for Apply; analogous paths SOURCE-CONFIRMED
Priority: P1
Owner: Concierge request boundary
Sources: supabase/functions/concierge-apply/handler.ts:114; supabase/functions/concierge-undo/handler.ts:62; concierge-parse/index.ts:78; concierge-resolve/index.ts:176; evidence/rate-limit-error-probe.json
Problem: A returned rate-limit RPC error with data=null is ignored. Apply continues and writes successfully in the added actual-handler probe. Undo/Parse/Resolve similarly test allowed=false without checking error. This is retained behavior.
Required action: Define the limiter as a required gate for protected work. A missing/error result must not permit a write or paid provider call. Return a retryable typed failure distinct from an actual 429 denial; keep legitimate anonymous/public endpoint contracts explicit.
Closure check: Limiter error produces no business write/provider charge, explicit denial remains 429 with Retry-After, and a valid allowed result proceeds.

F33 — Captured account context is not an SDK credential lease
Evidence: SOURCE-CONFIRMED design risk; cross-account server write NOT reproduced
Priority: P1 audit obligation
Owner: Identity / request adapters / Imports / Taste / Social
Sources: Kuro/Imports/ImportsService.swift:151,177; SDK SupabaseClient.swift:441; docs/plans/2026-10-05-modular-architecture-plan.md:G1
Problem: Private callers share one SDK client. The SDK obtains the current token during request adaptation, whereas app context was captured earlier. Unstructured/delayed work can reach dispatch after a transition. Result guards alone do not prove obsolete work cannot send or be attributed to a new account. Explicit list user filters offer extra RLS defense; JWT-derived RPC writers differ.
Required action: Trace token acquisition and dispatch for each private mutation family. Bind the dispatched credential identity to the initiating account, reject obsolete context before dispatch/retries, and cancel queued work. Do not fix this by trusting a client-supplied user_id. Use a supported request broker/scoped transport only if necessary.
Closure check: A controlled pre-dispatch account-switch test proves no A-originated queued mutation is sent as B. Do not mark a merely late response test as proof of credential binding.

F34 — Private club raw votes/reactions/member rows bypass aggregate privacy
Evidence: FIXTURE-REPRODUCED; live parity UNVERIFIED
Priority: P1
Owner: Clubs SQL authorization
Sources: supabase/tests/rls/20_clubs.sql; supabase/tests/rls/63_club_privacy_levels_and_open_items.sql; club_votes_select_member / club_reactions_select_member / club_members_select_member
Problem: Membership-only SELECT policies let members read raw per-user rows directly. Privacy gating and anonymous counts in RPC responses do not protect direct table reads.
Required action: Design a minimal privacy-preserving aggregate boundary with explicit caller membership checks and safe search_path/grants. Restrict raw personal rows while retaining necessary approved member metadata. A SECURITY DEFINER conversion must not accidentally reveal private individual tracking fields.
Closure check: Another member cannot read forbidden raw identities/votes/reactions/progress by direct SELECT, and intended aggregate totals still work for private/status/progress levels.

F35 — Removal is not sticky and departed votes/reactions remain in counts
Evidence: FIXTURE-REPRODUCED; policy/copy decision required
Priority: P1
Owner: Clubs membership policy / SQL
Sources: supabase/tests/rls/20_clubs.sql; supabase/tests/rls/63_club_privacy_levels_and_open_items.sql; join_club / leave_club
Problem: Owner/admin removal or leave deletes membership, but the shared invite code still permits rejoin. Departed votes/reactions remain in aggregates and raw rows. Leave dialog promises stronger finality than this implements.
Required action: Define removal separately from voluntary leave. Proposed safe default: owner-removed users require explicit restoration; voluntary leave can rejoin with a valid invite and accurate copy. Decide whether departed activity is deleted or excluded from current-member counts. Enforce the rule server-side.
Closure check: Removed user cannot immediately rejoin with the old code; a valid explicitly restored user can. Leave copy and retained/excluded activity match the chosen contract. No new removal UI is required just to enforce existing backend operations.

F36 — Current RLS makes cross-member bundle status counts incomplete
Evidence: FIXTURE-REPRODUCED
Priority: P2
Owner: Clubs aggregate RPCs
Sources: supabase/tests/rls/20_clubs.sql; supabase/tests/rls/63_club_privacy_levels_and_open_items.sql
Problem: Bundle runs SECURITY INVOKER and list RLS exposes only caller rows. In the fixture, three of four members track an item but member_status_counts reflects only the caller. Restricting SELECT further without changing aggregation also reduces polls/reactions/member count.
Required action: Implement authorized aggregate computation together with F34. Individual data remains subject to sharing level. Do not regard a blanket SECURITY DEFINER flip as a complete repair: it also enables previously hidden cross-member data.
Closure check: Expected counts are correct for multiple members while private individual tracking remains hidden. Test raw access and aggregate output together.

F37 — Account deletion bypasses club ownership-transfer and current-orphan cleanup
Evidence: FIXTURE-REPRODUCED; newest cleanup RPC qualification outstanding
Priority: P1/P2 lifecycle
Owner: Account deletion / Clubs SQL
Sources: supabase/tests/rls/50_account_deletion_fk_and_rpc.sql; supabase/functions/delete-account/deletion.ts:208,249
Problem: In the exercised fixture a shared club loses its owner and a solo club becomes an orphan after the sweep already ran. leave_club has lifecycle logic account deletion bypasses. The fixture uses an older cleanup RPC body, so the exact current hosted result remains unverified.
Required action: Inspect/qualify the effective cleanup RPC and establish one club lifecycle operation for deletion, ownership transfer and empty-club cleanup. Handle current victim clubs explicitly rather than relying on the next unrelated deletion sweep.
Closure check: Deleting an owner preserves a shared club with valid ownership or the explicitly approved ownerless policy, and a solo club is cleaned safely. Other members' content is preserved.

F38 — Account deletion has a concurrent-write cleanup gap
Evidence: REPRODUCED: PostgreSQL role/RLS fixture interleaving
Priority: P1
Owner: Account deletion / SQL write barrier
Sources: supabase/functions/delete-account/deletion.ts:216,249; evidence/90_review_deletion_interleaving.sql
Problem: After TEXT list cleanup, a still-authenticated concurrent request inserts a row; deleting auth.users does not cascade that list row. The probe confirms the survivor. Notes-only updates under simulated deleted-user claims also work; a normal new insert after deletion is indirectly blocked by a taste FK. Live acceptance of deleted-user JWTs was not proven.
Required action: Establish a database-enforced deletion/write barrier and compatible ownership/cascade strategy for all user-keyed relations, including legacy TEXT rows. Coordinate cleanup with concurrent mutations. Preserve retryability and never rely solely on local sign-out or a final best-effort sweep.
Closure check: Controlled competing write cannot leave private data after successful deletion. Interrupted deletion can retry safely. Qualified Auth/Storage behavior remains a separate gate.

F39 — Orphan sweep count/delete race can destroy a newly joined club
Evidence: REPRODUCED: PostgreSQL interleaving
Priority: P1
Owner: Account deletion / Clubs transaction
Sources: supabase/functions/delete-account/deletion.ts:150,159; evidence/90_review_deletion_interleaving.sql
Problem: Sweep sees zero members, another user joins, then the unconditional service-role DELETE removes the club and cascades the new membership. The global sweep can affect clubs unrelated to the currently deleting user. Retained pattern.
Required action: Use a database operation coordinated with joins and a revalidated deletion condition under the appropriate lock, or remove the global sweep from the request and use a safe separate cleanup owner. A stale pre-read is not authorization to delete.
Closure check: Join between observation and deletion preserves the joined club. Truly empty eligible clubs can still be cleaned. Exercise the concurrency boundary once with two database sessions.

F40 — Legacy user_lists view can expose another user's rows
Evidence: FIXTURE reconstruction demonstrates risk; live view existence/options UNVERIFIED
Priority: P1 qualification
Owner: Library SQL / schema inventory
Sources: supabase/tests/rls/10_user_lists.sql; legacy_sql/08_create_user_lists_view.sql; supabase/tests/README.md
Problem: The reconstructed legacy view without security_invoker allows user 2 to see user 1 rows. It is absent from the baseline capture and the hardening migration does not replay, so this is not a claim that the deployed view currently leaks.
Required action: Inspect effective view existence/options/grants in the qualified environment. Preserve invoker semantics or retire an unused view through an approved forward change. Include view access in the authorization contract, not just table policies.
Closure check: Other-user and anonymous view reads are denied/empty as intended, and owner access works through the exact effective view or its documented replacement.

F41 — Three authorization repairs are prepared only, not qualified deployed state
Evidence: FIXTURE red/green evidence; hosted status UNVERIFIED
Priority: P1 qualification
Owner: Clubs / Social SQL
Sources: supabase/prepared-migrations/20261005120000_club_members_role_column_guard.sql; 20261005120100_club_rails_insert_admin_only.sql; 20261005120200_toggle_comment_reaction_visibility.sql
Problem: Prepared fixes address role escalation via UPDATE, unauthorized direct rail INSERT, and comment reaction visibility. The green fixture includes these files by default. Effective live policies may differ and no deployment has been performed.
Required action: Recheck each precondition/grant and prepare cohesive forward migrations. Keep files outside the deploy path until authorized. Preserve intended sharing-level edits, admin actions and visible comment reactions. Account for all broad PUBLIC/table/column grants.
Closure check: Old qualified schema reproduces each denied action; fixed qualified schema rejects it and allows legitimate operations. Applied-state claims require explicit deployment and post-check evidence.

F42 — Membership revocation lacks a server event and subscriptions are broad
Evidence: SOURCE-CONFIRMED; live event delivery UNVERIFIED
Priority: P1/P2 privacy lifecycle
Owner: Clubs realtime / SQL
Sources: Kuro/Clubs/ClubRealtimeCoordinator.swift:74; docs/plans/2026-10-05-modular-architecture-execution-ledger.md
Problem: club_members is not in the reviewed Realtime publication; rail/vote/reaction subscriptions are unfiltered, with only polls filtered by club. Removed members may keep a cached bundle until a failing request or TTL. The in-memory invalidation method cannot react to a signal never received.
Required action: Provide a scoped authorized revocation/invalidation path and filter subscriptions where the real table schema permits. Restrict event payloads consistently with privacy policy and prevent stale channel callbacks from publishing. Use bounded refetch of aggregates where private raw events cannot be delivered.
Closure check: A member removed externally loses private state/subscription promptly according to an explicit contract. Rejoin/old teardown does not drop the current channel. Qualify actual Realtime delivery separately from fake channel tests.

F43 — Database fixture is an incomplete effective schema
Evidence: REPLAY MEASURED: 176 applied / 62 failed baseline-first, including prepared files
Priority: P1 qualification
Owner: Database verification / schema ownership
Sources: scripts/db/run_local_db_tests.sh; supabase/tests/README.md; evidence/kuro-deep-db-review-run.log
Problem: 321 passing assertions cover a partial audited fixture. taste_tag_stats is absent and the newest delete_user_concierge_data body does not replay. Strict replay measured 130 applied/108 failed including 3 prepared files; baseline-post measured 2/4. Do not confuse 235 historical files with 238 attempted files.
Required action: Prepare a qualified non-production schema strategy with required seed dependencies/effective view/function bodies. Preserve historical migrations/checksums. Add a setup completeness check for the objects the slice depends on, and report replay failure distinctly from RLS test success.
Closure check: Changed authorization/transaction tests execute against the required effective objects and roles, including the latest cleanup RPC and taste isolation. Missing objects keep their gates BLOCKED.

F44 — Storage, GoTrue and live PostgREST behavior are not established
Evidence: EXPLICIT qualification gap
Priority: P1 qualification
Owner: Identity / deletion / transport / verification
Sources: supabase/tests/rls/50_account_deletion_fk_and_rpc.sql; docs/plans/2026-10-05-modular-architecture-test-matrix.md
Problem: The fixture stubs auth/storage and simulates Auth deletion as superuser. In-process HTTP responses exercise the SDK but not a running PostgREST server. Real grants, HTTP error mapping, Storage ownership and GoTrue session/token semantics remain unqualified.
Required action: Use an approved disposable/local full stack or non-production target, never production as substitute. Keep unit/fixture/hosted labels distinct. Prepare recovery commands if prerequisites are unavailable; finish independent source work without declaring these gates passed.
Closure check: Representative real-stack auth, owner mutation, permission error and deletion paths match contracts. A missing stack is BLOCKED, not PASS and not a reason to deploy early.

F45 — Hardened deletion requires unverified deployed prerequisites
Evidence: DOCUMENTED compatibility/deployment prerequisite
Priority: P1 deployment blocker
Owner: Account deletion / release verification
Sources: supabase/functions/delete-account/deletion.ts; docs/plans/2026-10-05-modular-architecture-execution-ledger.md:Prepared
Problem: Required deletes now include anime_comments/manga_comments; service_role DELETE grants, table column types and the media bucket have not been verified against an effective deployed-equivalent schema. A mismatch would make deletion fail for every affected user.
Required action: Run approved read-only prerequisite checks and prepare any missing grants/schema changes explicitly. Keep required failures visible and Auth deletion last. Do not weaken cleanup to make a happy-path test pass.
Closure check: All required relations, grants and bucket exist with expected ownership semantics; missing prerequisites fail safely and are resolved before any deployment approval.

F46 — Several auth legs and outbound auth headers lack SDK-level qualification
Evidence: DOCUMENTED coverage gap
Priority: P2 qualification
Owner: Identity / HTTP contract tests
Sources: docs/plans/2026-10-05-modular-architecture-test-matrix.md:166,738
Problem: Launch restore, sign-up, Apple sign-in, same-user callback setSession and SDK event mapping have mainly funnel-entry evidence. Authorization/apikey headers are not asserted in current adapter tests. Existing email tests do not qualify every distinct credential path.
Required action: Test each distinct SDK credential/session mechanism once at the existing HTTP seam with controlled responses. Assert relevant identity/headers and stale-attempt behavior. Reuse shared funnel tests for common cleanup rather than multiplying provider permutations.
Closure check: Actual SDK mapping and persisted-session behavior are checked where supported. Tests use fixture credentials only and verify a nonzero executed count.

F47 — All sixteen integrated UI journeys remain unqualified
Evidence: DOCUMENTED; review probes were unit tests, not UI journeys
Priority: P2 acceptance
Owner: Navigation / presentation / test configuration
Sources: docs/modules/README.md:80; Kuro/Views/Routing/KuroRoutes.swift; KuroUITests
Problem: Pure RoutePolicy tests do not establish real sheet presenters, nested navigation, cold/warm deep links, swipe arbitration, filter selection or approved layouts. The review's four simulator SDK probes do not close these journeys.
Required action: Create a safe fixture-only app/launch configuration and perform the sixteen listed journey checks, grouping automation by distinct wiring pattern. Use deterministic waits and selective visual inspection; avoid a sprawling screenshot suite.
Closure check: Each documented journey has a result on the current source. Correct detail/editor/club appears, nested presenters and deep links work, swipe does not open a card, and approved composition is preserved.

F48 — Test host can initialize production configuration
Evidence: SOURCE-CONFIRMED possibility; no production request incident asserted
Priority: P1 test safety / reproducibility
Owner: Composition / test runner
Sources: Kuro/Composition/AppComposition.swift; Kuro/KuroApp.swift; Config/Shared.xcconfig; docs/plans/2026-10-05-modular-architecture-test-matrix.md:Test environment
Problem: The unit-test host constructs AppComposition.shared and starts launch restore with the ordinary production configuration. Per-test StubSupabase clients isolate test requests but do not necessarily isolate the host app. The review used an isolated copied app with invalid fixture host/key.
Required action: Add a supported test-only composition/configuration path selected before singleton creation, isolated SDK persistence and a network-deny guard. Keep production builds unable to enter it accidentally. Do not remove actual lifecycle behavior from the test path being qualified.
Closure check: Running unit/UI verification cannot contact production or inherit real-account tokens. A test intentionally attempting external production access is rejected locally before network dispatch.

F49 — Critical handler tests are not part of the normal gate path
Evidence: SOURCE-CONFIRMED gate omission
Priority: P2
Owner: Quality gates / backend
Sources: scripts/quality-gates/run_all.sh; docs/modules/edge-functions.md:Gate
Problem: run_all invokes parser/router tests but not Apply, Undo or delete-account handler/deletion suites. The DB fixture is also separate. A normal green gate can therefore miss the business-critical failures this review reproduced.
Required action: Wire the existing focused Deno suites into the standard local/CI verification path. Make DB qualification an explicit separately labeled gate if setup differs. Reuse existing tests; do not duplicate them as another test framework.
Closure check: A meaningful Apply/Undo/deletion regression fails the documented gate command. Missing prerequisites produce an explicit failure/BLOCKED report, and skipped gates cannot be summarized as complete.

F50 — Screen-level request and subscription baselines are missing
Evidence: DOCUMENTED limited coverage
Priority: P2 efficiency qualification
Owner: Composition / presentation / transport metrics
Sources: docs/plans/2026-10-05-modular-architecture-test-matrix.md:545; KuroTests/CollectionContractTests.swift
Problem: Counts are pinned for selected owner flows, not cold/warm/remount screen journeys. One SDK client is a static check. Post-import view refreshes can duplicate sink work, and repeated mount/subscription paths remain incompletely measured.
Required action: Instrument existing controlled transports for representative screen cold/warm/remount and mutation flows. Resolve unexplained increases and duplicate subscriptions. Keep a small counter-based assertion set, not a new analytics platform or large load benchmark.
Closure check: Each representative wiring pattern has a bounded justified request/channel count; batch/import paths do not multiply redundant refreshes.

F51 — Active backend handlers remain mixed orchestration boundaries
Evidence: SOURCE-CONFIRMED architecture work
Priority: P1/P2 required architecture
Owner: Backend capability owners
Sources: supabase/functions/concierge-recommend/index.ts; concierge-parse/index.ts; manga-chapter-enrich/index.ts; bulk-import-anime/index.ts; bulk-import-manga/index.ts
Problem: Recommend remains 1,806 lines with an approximately 1,300-line serve closure; parser search/alias/current-entry orchestration remains in index; manga enrichment remains 2,088 lines; bulk importers 747/770. Low churn or lack of an offline consumer does not close actual divergent policy/provider/repository/run seams.
Required action: Complete the function-specific extraction matrix below, preserving slugs and contracts. Entry adapters bind environment/request dependencies and call testable run handlers. Put pure matching/selection rules beside typed repositories/provider transports, without mandatory generic layers.
Closure check: Every active backend capability has a cohesive run entry, production policy tests and one controlled failure-path handler/run test. No required seam is deferred solely because the old file rarely changes.

F52 — Operational workers were indexed rather than semantically extracted/verified
Evidence: DOCUMENTED source scope / unexecuted workers
Priority: P2 required architecture
Owner: Synopsis / safety / providers / media relations / operations
Sources: docs/modules/operations.md; scripts/synopsis_enrichment_worker.swift; catalog_safety_worker.swift; provider_availability_worker.swift; media_relations_worker.js
Problem: The migration preserves and indexes worker paths but does not exercise lock, checkpoint, cursor, retry, report or worker orchestration boundaries. Stable wrapper paths do not require keeping all internals monolithic.
Required action: Keep wrapper/label/report compatibility and extract only real internal seams using existing language patterns. Update Swift compile commands to include actual supporting sources. Introduce a controlled offline run seam and ensure production wrappers invoke it.
Closure check: Each active worker has one success and one representative interrupted/provider-failure run proving cleanup/checkpoint/report behavior. No live provider or production write is used as a unit-test substitute.

F53 — Central models and RPC parameter collections retain cross-capability editing coupling
Evidence: SOURCE-CONFIRMED architecture work
Priority: P2
Owner: Catalog contracts / native capability APIs
Sources: Kuro/Models/SupabaseModels.swift; Kuro/Services/SupabaseRPCParams.swift; docs/plans/2026-10-05-modular-architecture-large-file-review.md:4.6
Problem: SupabaseModels is 1,297 lines and combines value vocabulary with legacy/projection/provider concerns. Roughly 30 RPC parameter types have single-owner consumers spread across capabilities, keeping multiple owners editing one file. Large size alone is not the defect.
Required action: Move owner-private request/response types beside their adapter; put truly shared catalog/media values in one neutral contract home. Move provider policy to Providers. Preserve a single canonical model definition and legacy decoding compatibility.
Closure check: A capability-specific RPC change edits its capability and tests, not unrelated parameter bundles. No duplicate Anime/Manga/MediaKey model or SDK type leaks into UI/domain APIs.

F54 — In-app feature boundaries are largely conventional, not enforced
Evidence: SOURCE-CONFIRMED gate scope
Priority: P2 required architecture
Owner: Composition / capability APIs / architecture gate
Sources: scripts/quality-gates/check_architecture.sh; Packages/KuroModules/Package.swift; Kuro/Composition/AppComposition.swift
Problem: The three package graph is compiler-checked. Other capability owners share the app module, and six regex rules cover selected forbidden patterns rather than arbitrary feature-internal access or all dependency edges. This does not demonstrate that actual cycles exist; it weakens the zero-forbidden-access claim.
Required action: Define a small explicit capability API/dependency manifest; hide implementations using existing access control and enforce cross-capability references with a focused check, or compile a boundary where useful. Permit composition and narrow neutral contracts, not blanket cross-feature access.
Closure check: A representative forbidden reference in a scratch copy fails the gate; valid API calls pass; all actual edges have an owner/rationale and no cycle. Avoid a custom general-purpose architecture compiler.

F55 — Private workflows remain in large rendering files
Evidence: SOURCE-CONFIRMED; some pure-rule extraction is already complete
Priority: P2 required where lifetime/ordering defects need it
Owner: Concierge / Discovery / Clubs / AppShell presentation
Sources: Kuro/Views/ConciergeView.swift; EditorialDiscoverView.swift; ClubDetailView.swift; AuthView.swift; docs/plans/2026-10-05-modular-architecture-large-file-review.md:10
Problem: Clarification/routing/preselection rules and shared detail chrome were extracted and should stay closed. Conversation Apply/Undo sequencing, draft state and multiple task handles remain private view logic. Discover and ClubDetail publish private snapshots in view state; Auth welcome artwork has a separate update/task lifetime.
Required action: Extract a session-local workflow model where necessary to make sequencing, cancellation and reset testable; keep SwiftUI rendering and established approved layouts. Isolate Auth welcome artwork as a presentation component. Do not mandate a view-model class for every simple screen.
Closure check: Actual views consume the new workflow APIs; private state/tasks have one lifecycle owner; rendering files contain no duplicated mutation/reconciliation policy. D1-D3 and existing route extractions are not redone needlessly.

F56 — Keep-cohesive waivers sometimes use weak evidence
Evidence: DOCUMENTED reviewer dissent / architecture acceptance issue
Priority: P2
Owner: Architecture lead
Sources: docs/modules/edge-functions.md; docs/plans/2026-10-05-modular-architecture-large-file-review.md:6,10
Problem: No offline consumer, no recent commits, or no existing test is used to waive backend seams. The Recommend remainder is explicitly called the weakest keep in the large-file review. These facts do not show shared authority, lifetime or failure policy.
Required action: Reassess large active files by owner, invariant, state lifetime, consumers, external boundaries and meaningful failures. Keep genuinely cohesive code regardless of length; split concrete divergent responsibilities now under the expanded whole-codebase scope.
Closure check: Each large active file has a short inspectable cohesion decision with source evidence. A required split cannot be relabeled optional to obtain completion.

F57 — Operational root assumptions disagree with this checkout
Evidence: SOURCE-CONFIRMED portability/compatibility gap
Priority: P2
Owner: Operations configuration
Sources: scripts/run_media_relations_refresh.sh:4; scripts/unified_local_dashboard_server.js:8; docs/modules/operations.md
Problem: Several installers/runners and the unified dashboard hardcode /Applications/Kuro. The canonical checkout here is /Users/max/Kuro-Anime-App; CI/CD derives its current repo root while the dashboard reads another report root. The review does not claim installed jobs on another host are broken.
Required action: Use one task-specific overridable project-root resolution mechanism, preserve legacy installed paths through compatible wrappers/configuration and verify report-root agreement. Do not reinstall launchd jobs or mutate installed credentials without authorization.
Closure check: Offline configuration checks in the canonical checkout and a relocated scratch copy resolve the same intended workers/reports; existing documented labels/ports/default overrides remain compatible.

F58 — Media-relations configuration depends on other pipelines' credential plists
Evidence: SOURCE-CONFIRMED hidden operational dependency
Priority: P2
Owner: Media relations / configuration
Sources: scripts/run_media_relations_refresh.sh:10,31; docs/modules/operations.md
Problem: The runner obtains SUPABASE variables from other pipelines' installed plists. Removing an unrelated pipeline/label can break credential discovery, undermining independent module removal.
Required action: Define explicit media-relations configuration with compatible fallback during migration. Document which settings are shared public config and which are credentials. Preserve values; do not print secrets or change installed credentials by inference.
Closure check: Media-relations configuration resolves without requiring another pipeline to be installed. Existing configured runs preserve credential precedence and fail clearly when required settings are absent.

F59 — Local CD deploys production by default
Evidence: SOURCE-CONFIRMED execution hazard
Priority: P1 execution boundary
Owner: Operations / release scripts
Sources: scripts/local_cd.sh:7,77,97; docs/modules/operations.md
Problem: DEPLOY_SUPABASE defaults to 1 and invokes linked db push/functions deploy. A modularity verification task must not accidentally run it as a generic local check.
Required action: Keep deployment separate from verification. Make non-deploy validation explicit/safe and require an intentional deployment entry/flag under project approval rules. Inspect installed scheduler invocation before changing default behavior; no deployment in this task.
Closure check: The documented verification path has no remote writes. Production deployment requires explicit authority and displays the exact target/actions; existing approved automation changes are reviewed separately.

F60 — Pre-commit checks are not active in this clone
Evidence: CURRENT local config check: core.hooksPath unset
Priority: P2 tooling
Owner: Repository quality gates
Sources:  .githooks/pre-commit; git config core.hooksPath; docs/modules/operations.md
Problem: The hooks directory exists but is not configured as active here. Documentation should not imply secrets/migration-name checks run automatically on commit. Explicit run_all checks still exist.
Required action: Document and provide the supported opt-in hook setup, or use the established CI gate as the enforced owner. Do not silently change the user's global Git configuration. Ensure the authoritative path runs without relying on local hooks.
Closure check: The selected enforcement path actually rejects a representative secret/migration-name violation in a scratch fixture; local hook status is reported accurately.

F61 — Authoritative docs and generated source blocks disagree
Evidence: SOURCE/DOCUMENTED handoff defect
Priority: P2
Owner: Documentation / inventory generator
Sources: AGENTS.md; CLAUDE.md; CURRENT_APP_STATE.md; CURRENT_APP_STATE_PLAIN.md; IMPLEMENTATION_PLAN_Variation1.md; scripts/generate_app_state_sources.js
Problem: AGENTS retains deleted service paths and stale counts; generated current-state blocks were deliberately left stale. The source generator may stamp HEAD while embedding dirty source, which is not a complete source identity. The deployment switch description also needs precise true-to-false semantics: it is currently true and should become false after compatible Apply deploy.
Required action: Reconcile the canonical current docs, distinguish historical snapshots, regenerate reviewed/redacted blocks or replace unnecessary source duplication with accurate references under project rules. Record dirty-source digest/source identity rather than HEAD alone. Update status after every actual initiative.
Closure check: No current authority points to deleted production files or presents old counts/behavior as current. Generated evidence matches the actual source and no credentials are embedded. Deployment switch is described accurately.

F62 — Completion verdict contradicts mandatory gates and reproduced defects
Evidence: REVIEW-CONFIRMED acceptance failure
Priority: P1 acceptance
Owner: Lead / independent reviewer
Sources: docs/plans/2026-10-05-modular-architecture-completion-report.md; execution-ledger.md; architecture-plan.md:G0-G7
Problem: COMPLETE-WITH-DISCLOSED-GAPS claims all code-level gates pass while G4/G5 are partial and G1 now has reproduced failures. Disclosure does not override a mandatory gate. Structural retirement is useful but is not lifecycle qualification.
Required action: Reopen gate statuses, resolve the required work, and apply binary PASS/FAIL/BLOCKED/NOT-APPLICABLE evidence. Report local architecture status independently from deployed/release status. Weights cannot compensate for failures.
Closure check: Final verdict follows the actual integrated evidence; all required source work and local gates pass, and unavailable external qualification remains explicitly BLOCKED. No completion headline masks it.

F63 — Offline/restart guarantees and durable outboxes are absent
Evidence: DOCUMENTED product qualification gap, not an automatic new-feature commission
Priority: P2 contract scope
Owner: Library / Taste / product master
Sources: Packages/KuroModules/Sources/KuroLibrary/LibraryStore.swift; Kuro/Taste/TasteStore.swift; docs/plans/2026-10-05-modular-architecture-test-matrix.md
Problem: Library projection and Taste outbox are in memory. No durable offline sync or restart proof exists. A modular extraction does not establish those product capabilities; implementing a whole sync platform is not justified solely by modularity.
Required action: Define honest restart/pending-operation semantics and preserve extension seams. Implement persistence only when required by the active approved product contract or to repair loss in an actually reachable existing flow; otherwise record the product gate separately, with no offline-complete claim.
Closure check: Architecture APIs do not promise durability they lack. If durability is required, a focused restart/lost-ack test proves it on the real persistence path.

F64 — Dormant Groq classifiers conflict with narration-only project policy
Evidence: SOURCE/DOCUMENTED policy and ownership decision
Priority: P2
Owner: Concierge resolve / Realm descriptors
Sources: supabase/functions/concierge-resolve/index.ts; supabase/functions/realm-describe/index.ts; docs/modules/edge-functions.md
Problem: Resolve chooses candidates with Groq; realm-describe classifies realm/tone/register/pacing. Current caller maps say Resolve has no app/script consumer and Realm drains are paused/manual. Documentation calling dormancy an exception does not authorize reactivating forbidden classification.
Required action: Confirm actual callers/config/cron and explicitly classify dormant paths. Keep them dormant or prepare local retirement with compatibility notes; do not reactivate them. Any actual classification consumer must follow the approved deterministic/on-device policy, and an exception needs explicit user authority.
Closure check: No active default flow uses server Groq for classification/routing. Dormant/manual paths and removal/deployment boundaries are truthful and owner-assigned.

F65 — Resolve leaks budget reservations on provider failure
Evidence: SOURCE-CONFIRMED; provider failure not separately executed
Priority: P2
Owner: Concierge resolve budget lifecycle
Sources: supabase/functions/concierge-resolve/index.ts:227,243,258,282
Problem: User/global reservations precede groqResolve; finalization happens only after it succeeds. A thrown provider call jumps to the outer catch without releasing those reservations. Reserve RPC errors also deserve fail-closed review. The function is currently documented dormant.
Required action: If retained as callable code, put reservation lifecycle in one run owner with finally-based compensation/actual-use accounting and checked required outcomes. Respect F64; do not enable the forbidden provider just to exercise a test.
Closure check: A controlled provider throw or denied second reservation leaves no leaked reservation. A successful call accounts for actual usage once, without contacting Groq in tests.

F66 — Image mirroring has unbounded fetch and payload-selected storage target
Evidence: SOURCE-CONFIRMED risk; no abuse incident demonstrated
Priority: P1/P2 backend hardening
Owner: Image mirror provider/storage boundary
Sources: supabase/functions/mirror-images/index.ts:359; docs/modules/edge-functions.md
Problem: fetch(url) has no explicit timeout/response-size cap/host allowlist; blob materialization can consume unbounded resources. Bucket comes from payload. A secret gate limits callers but does not define a safe resource/target contract.
Required action: Extract the mirror run and bounded provider/storage adapters. Define approved source hosts/redirect handling, content type/size limits, timeouts and allowed destination bucket/path. Preserve existing authorized sources and report failures without erasing valid prior URLs.
Closure check: Controlled oversized, timeout, redirect-to-unapproved-host and invalid-bucket cases fail safely; valid catalog images mirror once with bounded concurrency and consistent cursor/report behavior.

F67 — AniList import endpoint has a documented unresolved type error
Evidence: SOURCE-CONFIRMED type-shape mismatch; fresh deno check not run for this endpoint
Priority: P2
Owner: AniList import contract
Sources: supabase/functions/concierge-import-anilist/index.ts:262; docs/modules/edge-functions.md
Problem: The cached-text path accesses raw.truncated outside its declared request shape; the existing backend index records a deno check error. That endpoint was kept outside the checked extraction slice.
Required action: Fix the request model/validation to match supported fields and type-check the actual entrypoint. Extract provider pagination/line conversion/cached-text policy at the real seams and preserve publicListOnly, limits and truncation semantics.
Closure check: Endpoint type-checks with the available cached dependencies and a controlled cached/fresh import run returns the declared shape, including correct truncation.

F68 — Consolidated outbound URL validation intentionally changed edge behavior
Evidence: DOCUMENTED compatibility decision; normal builder tests exist
Priority: P2 compatibility qualification
Owner: Providers / detail links
Sources: Kuro/Providers/ProviderLinkBuilders.swift; KuroTests/DetailProviderLinksTests.swift:329; docs/plans/2026-10-05-modular-architecture-completion-report.md
Problem: Duplicate validators were successfully removed, but accepted/rejected edge URLs changed. The completion report lists this as a retained compatibility gap. Consolidation alone does not approve every behavior delta.
Required action: Compare the relevant pre-migration validators against the intended single contract; document deliberate fixes and preserve valid supported links, provider notes and locale identity. Retain HTTPS/http rules appropriate to existing supported providers.
Closure check: Representative previously valid catalog/provider links still open correctly, malformed/unsupported targets are rejected, and flag-off/catalog fallback works in an integrated detail journey.

F69 — Dead request/presentation types and misleading file names remain
Evidence: SOURCE/DOCUMENTED cleanup candidates; final reachability proof required
Priority: P3 maintainability
Owner: Native owners / presentation
Sources: Kuro/Services/SupabaseRPCParams.swift:498; Kuro/Views/EditorialDiscoverView.swift:1328; Kuro/Views/ConciergeView+AniListImport.swift
Problem: RPCGetMediaProviderAvailabilityDetailParams has no consumer; GenrePickerSheet is unreferenced; ConciergeView+AniListImport.swift is a standalone sheet rather than the implied extension. Unused StubFMProvider is tracked separately under F26. These are navigation/maintenance gaps, not production incidents.
Required action: Remove genuinely unused local types after complete caller verification; rename misleading local filenames when safe and update Xcode/docs. Do not delete user prototypes, deployed endpoints, historical SQL or required compatibility wrappers from one grep.
Closure check: Every retained production type/file has a truthful home and use; build/resources/docs resolve after cleanup, with unrelated work preserved.

F70 — Ownership inventory is split across stale partial surfaces
Evidence: DOCUMENTED architecture/evidence maintenance gap
Priority: P2
Owner: Architecture inventory / lead
Sources: docs/plans/2026-10-05-modular-architecture-ownership-manifest.csv; docs/modules/script-classification.csv; docs/modules/sql-function-index.csv; docs/documentation-surface-map.md
Problem: The 169-row manifest inventories Swift app/package/tests, while backend/SQL/scripts rely on separate indexes, many baseline-derived. A file owner alone does not name mutable state, caller/write path, interface or dependency. All production paths need a coherent current view for full-codebase completion.
Required action: Reuse/regenerate the existing inventories into one navigable scope index spanning native, all current edge entrypoints, effective SQL, workers, dashboards, scripts and CI. Classify active/dormant/legacy/generated/prototype assets explicitly; preserve prototypes. Link actual APIs/state/write owners rather than merely listing folders.
Closure check: Every current production path and mutable state has one owner and a verified caller/dependency classification; current inventory agrees with the source, with no unowned active path or unjustified duplicate authority.

12. HANDOFF COMPLETENESS CHECK

Every entry F01-F70 is present in this document. Appendix A embeds all the preserved native/handler/SQL reproduction sources and results, local test summaries, and dirty source status/digests. The findings, execution contract and evidence are in this one document; no separate register, archive or evidence attachment is required. No application source was changed to produce this handoff. No schedules or timing estimates are part of the execution contract. The local source is the implementation input; this review document is not deployed/production proof.

The next model must return the complete finding disposition table and module matrix, not another abbreviated narrative claiming the migration is finished. Completion means integrated narrow ownership plus corrected behavior and valid evidence, with external approval boundaries respected.


APPENDIX A — EMBEDDED REVIEW EVIDENCE

The evidence below records the review baseline and observed outcomes, not the intended implementation. The next model must use current production code, adapt imports and harness configuration to the active checkout, and convert reproductions into intended-behavior assertions. Passing a reproduction is evidence of the existing defect. The captured JSON summaries provide the actual selected test counts without needing the raw xcresult bundles. The original temporary paths in scripts/logs identify the review setup; recreate a bounded fixture when a scratch path no longer exists. No live or production equivalence is claimed.

Embedded entries:
- evidence/90_review_deletion_interleaving.sql
- evidence/90_review_deletion_interleaving.sql.log
- evidence/DeepReviewProbes.swift
- evidence/kuro-deep-db-review-run.log
- evidence/kuro-deep-handler-probes.jsonl
- evidence/kuro-deep-handler-probes.ts
- evidence/kuro-review-undo-repro.ts
- evidence/native-comment-probe-summary.json
- evidence/native-sdk-probes-summary.json
- evidence/rate-limit-error-probe.json
- evidence/rate-limit-error-probe.ts
- evidence/review-source-status.txt
- evidence/source-digests.json
- evidence/undo-reproductions.jsonl


BEGIN EMBEDDED FILE: evidence/90_review_deletion_interleaving.sql
SHA256: 3f02d72d6834659ca9cbd08d334ce03fb958bb1bceb031204621d6f210bc033d

\set ON_ERROR_STOP on
begin;
select tests.make_user(90),tests.make_user(91);
insert into public.anime(id) values(424290),(424291);
-- Request 1: service-role cleanup completes; request 2 can still insert before Auth deletion.
delete from public.anime_user_lists where user_id=tests.uid(90)::text;
select tests.as_user(tests.uid(90));
insert into public.anime_user_lists(user_id,anime_id,list_type) values(tests.uid(90)::text,424290,'WATCHING');
select tests.reset();
delete from auth.users where id=tests.uid(90);
select tests.eq('REPRO: concurrent post-cleanup insert survives auth deletion',
 (select count(*) from public.anime_user_lists where user_id=tests.uid(90)::text),1::bigint);
-- A normal insert after deletion is blocked indirectly by the taste-event FK.
-- A notes-only change does not emit a taste signal, so check the surviving row separately.
select tests.as_user(tests.uid(90));
update public.anime_user_lists set notes='post-deletion note' where user_id=tests.uid(90)::text;
select tests.reset();
select tests.eq('REPRO: surviving TEXT row accepts notes-only update under deleted-user claims',
 (select notes from public.anime_user_lists where user_id=tests.uid(90)::text),'post-deletion note');
-- An orphan is found empty, then a different user joins before the service-role DELETE.
select tests.as_user(tests.uid(91));
select (public.create_club('Review orphan',null,'status'))->>'club_id' as club \gset
select tests.reset();
delete from auth.users where id=tests.uid(91);
select tests.eq('orphan sweep observes zero members',(select count(*) from public.club_members where club_id=:'club'),0::bigint);
select tests.make_user(92);
select invite_code as invite from public.clubs where id=:'club' \gset
select tests.as_user(tests.uid(92));
select public.join_club(:'invite');
select tests.reset();
select tests.eq('different user joined between count and delete',(select count(*) from public.club_members where club_id=:'club'),1::bigint);
delete from public.clubs where id=:'club';
select tests.eq('REPRO: stale orphan decision deletes other user membership',(select count(*) from public.club_members where user_id=tests.uid(92)),0::bigint);
rollback;

END EMBEDDED FILE: evidence/90_review_deletion_interleaving.sql


BEGIN EMBEDDED FILE: evidence/90_review_deletion_interleaving.sql.log
SHA256: 762714d12a30682a459923d94ed297868bf4ea9d969292a4938e275f4d48034f

psql:/private/tmp/kuro-sql-deep-review/supabase/tests/rls/90_review_deletion_interleaving.sql:12: NOTICE:  TEST ok: REPRO: concurrent post-cleanup insert survives auth deletion
psql:/private/tmp/kuro-sql-deep-review/supabase/tests/rls/90_review_deletion_interleaving.sql:19: NOTICE:  TEST ok: REPRO: surviving TEXT row accepts notes-only update under deleted-user claims
psql:/private/tmp/kuro-sql-deep-review/supabase/tests/rls/90_review_deletion_interleaving.sql:25: NOTICE:  TEST ok: orphan sweep observes zero members
psql:/private/tmp/kuro-sql-deep-review/supabase/tests/rls/90_review_deletion_interleaving.sql:31: NOTICE:  TEST ok: different user joined between count and delete
psql:/private/tmp/kuro-sql-deep-review/supabase/tests/rls/90_review_deletion_interleaving.sql:33: NOTICE:  TEST ok: REPRO: stale orphan decision deletes other user membership

END EMBEDDED FILE: evidence/90_review_deletion_interleaving.sql.log


BEGIN EMBEDDED FILE: evidence/DeepReviewProbes.swift
SHA256: 79c28a7e2f28d8935e6f33b657f83351e3c8f109a0a125039de36d08cbf50e79

import Testing
import Foundation
@testable import Kuro

@MainActor
@Suite("Deep review failure reproductions", .timeLimit(.minutes(1)))
struct DeepReviewProbes {
 @Test("Revoked club's late friend response is still handed out")
 func lateRevokedFriendResponse() async throws {
  let slow=StubGate()
  let h=try PublicDataHarness { r in
   guard r.resource == "rpc/fetch_friend_activity_for_title" else {return .emptyArray}
   return StubResponse.json(#"{"friends_tracking":[{"user_id":"revoked-friend","display_name":"F","status":"CURRENT","progress":3,"rating":null,"updated_at":null}],"comments":[]}"#).held(by:slow)
  }
  await h.service.session.applySession(userId:LifecycleFixtures.userA,email:"a@example.com")
  let read=Task.immediate { @MainActor in try await h.service.social.fetchFriendActivityForTitle(mediaType:"ANIME",mediaId:101) }
  _=await h.server.waitForRequest {$0.resource == "rpc/fetch_friend_activity_for_title"}
  h.service.clubs.invalidateClub("revoked-club")
  slow.open()
  let result=try await read.value
  #expect(result.friends_tracking.first?.user_id == "revoked-friend", "Reproduces stale permission response, not desired behavior")
  await h.tearDown()
 }
 @Test("A's failed sign-in clears a later successful B sign-in")
 func lateFailedSignInEndsB() async throws {
  let slow=StubGate()
  let h=try SessionSDKHarness { r in
   if StubAuth.isAuth(r,"token") {
    if r.jsonObject?["email"] as? String == "a@example.com" {return StubResponse.json(#"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#,status:400).held(by:slow)}
    return .json(StubAuth.sessionJSON(StubAuth.userB,email:"b@example.com"))
   }
   if StubAuth.isAuth(r,"logout") {return .json("",status:204)}
   return .emptyArray
  }
  let old=Task.immediate { @MainActor in try? await h.session.signInWithEmail(email:"a@example.com",password:"bad") }
  _=await h.server.waitForRequest {StubAuth.isAuth($0,"token") && $0.jsonObject?["email"] as? String == "a@example.com"}
  try await h.session.signInWithEmail(email:"b@example.com",password:"good")
  #expect(h.identity.currentUserId == StubAuth.userB)
  slow.open();_=await old.value
  #expect(!h.identity.isAuthenticated, "Reproduces newer account being cleared by old failure")
  await h.tearDown()
 }
 @Test("Parse begun before a tracking change refills the cleared cache afterward")
 func staleParseRefillsCache() async throws {
  let slow=StubGate()
  let h=try PublicDataHarness { r in
   if r.path.contains("/functions/v1/concierge-parse") {return StubResponse.json(ImportsContractTests.parseJSON).held(by:slow)}
   return .emptyArray
  }
  await h.service.session.applySession(userId:LifecycleFixtures.userA,email:"a@example.com")
  let read=Task.immediate { @MainActor in try await h.service.imports.conciergeParse(text:"naruto") }
  _=await h.server.waitForRequest {$0.path.contains("/functions/v1/concierge-parse")}
  h.service.imports.dropTrackingCopies()
  #expect(h.service.imports.conciergeParseCache.isEmpty)
  slow.open();_=try await read.value
  #expect(h.service.imports.conciergeParseCache.count == 1,"Reproduces stale pre-change result restoring cache")
  await h.tearDown()
 }
 @Test("A's comment mutation result is handed out after B signs in")
 func staleCommentMutationReturns() async throws {
  let slow=StubGate()
  let h=try PublicDataHarness { r in
   guard r.resource == "rpc/upsert_title_comment" else {return .emptyArray}
   return StubResponse.json(#"{"id":"comment-a","user_id":"account-a","text":"A private draft","created_at":"2026-10-05","updated_at":"2026-10-05"}"#).held(by:slow)
  }
  await h.service.session.applySession(userId:LifecycleFixtures.userA,email:"a@example.com")
  let write=Task.immediate { @MainActor in try await h.service.social.upsertTitleComment(mediaType:"ANIME",mediaId:101,text:"A private draft") }
  _=await h.server.waitForRequest {$0.resource == "rpc/upsert_title_comment"}
  await h.service.session.applySession(userId:LifecycleFixtures.userB,email:"b@example.com")
  slow.open();let result=try await write.value
  #expect(result.user_id == "account-a", "Reproduces old-account success being handed out")
  #expect(h.service.identity.currentUserId == LifecycleFixtures.userB)
  await h.tearDown()
 }
}

END EMBEDDED FILE: evidence/DeepReviewProbes.swift


BEGIN EMBEDDED FILE: evidence/kuro-deep-db-review-run.log
SHA256: 77c77e7eec29a1b4994d5cd282681d65f9a6e788373d49bade13ae036eeb5329

guard: environment clean; guard unit check passed
pending: fixture INCLUDES 3 prepared-NOT-DEPLOYED migration(s) (supabase/tests/pending_migrations.txt); use --exclude-pending for the deployed-chain state:
           20261005120000_club_members_role_column_guard.sql
           20261005120100_club_rails_insert_admin_only.sql
           20261005120200_toggle_comment_reaction_visibility.sql
target: throwaway PostgreSQL 17.10 (Homebrew) on unix socket /tmp/kuro-db-test.QXV6mx (port label 54329), TCP disabled, data_directory=/private/tmp/kuro-db-test.QXV6mx/data

================ migration replay (supabase/migrations, 235 files) ================
replay[strict]: 130 files applied, 108 files failed (details: /tmp/kuro-db-test.QXV6mx/reports/replay-strict.tsv)
replay[baseline-post]: 2 files applied, 4 files failed (details: /tmp/kuro-db-test.QXV6mx/reports/replay-baseline-post.tsv)
replay[baseline-first]: 176 files applied, 62 files failed; baseline PRE-APPLY: PASS (details: /tmp/kuro-db-test.QXV6mx/reports/replay-baseline-first.tsv)

---- baseline-post (baseline, then only later files): object counts in kuro_baseline_post ----
public tables: 27
public matviews: 7
public policies: 24
public constraints (all types): 105
baseline declares 26 distinct policies; baseline-post has 24 of them.
not created in baseline-post (the baseline dependency-guards them on tables/functions that only the pre-baseline chain creates, e.g. club tables and is_club_member):
    club_rail_item_reactions|club_reactions_insert_member
    club_rail_item_reactions|club_reactions_select_member
expected here: README_baseline_capture.md's 106 constraints / 26 policies are reached only once club_rail_items and is_club_member exist.
In baseline-post they do not (pre-baseline chain files create them), so the baseline's own guards (to_regclass('public.club_rail_items'))
skip exactly 1 FK (club_rail_item_reactions_rail_item_id_fkey) and 2 policies (club_reactions_*): 105 constraints / 24 policies is the consistent result.

---- baseline-post per-file result ----
PASS 20260807000000_baseline_capture_v1.sql 
FAIL 20260807010000_leftover_repairs_v1.sql ERROR:  function public.delete_user_concierge_data(text) does not exist
FAIL 20260810120000_clubs_trust_flags_promote_100.sql ERROR:  relation "public.feature_flags" does not exist
FAIL 20261005120000_club_members_role_column_guard.sql ERROR:  relation "public.club_members" does not exist
FAIL 20261005120100_club_rails_insert_admin_only.sql ERROR:  relation "public.club_rails" does not exist
PASS 20261005120200_toggle_comment_reaction_visibility.sql 

---- strict (empty DB, filename order): failures grouped by first error ----
 104 ERROR:  relation "…" does not exist
   2 ERROR:  function public.current_season_name(timestamp with time zone) does not exist
   1 ERROR:  function public.rebuild_media_realm_tier() does not exist
   1 ERROR:  column "…" of relation "…" does not exist

---- baseline-first (FIXTURE build): failing files ----
FAIL  20260203183000_concierge_recommend_rpc.sql
        ERROR:  relation "public.user_lists" does not exist
FAIL  20260203190000_editorial_recommend_engine.sql
        ERROR:  insert or update on table "editorial_penalty_tags" violates foreign key constraint "editorial_penalty_tags_tag_id_fkey"
FAIL  20260203191500_recommend_focus_tags.sql
        ERROR:  relation "public.editorial_penalty_tags" does not exist
FAIL  20260203194500_recommend_focus_filter.sql
        ERROR:  relation "public.editorial_penalty_tags" does not exist
FAIL  20260203201000_editorial_story_boosts.sql
        ERROR:  insert or update on table "editorial_tag_boosts" violates foreign key constraint "editorial_tag_boosts_tag_id_fkey"
FAIL  20260203203000_recommend_seed_similarity.sql
        ERROR:  relation "public.editorial_penalty_tags" does not exist
FAIL  20260203223000_scale_perf_bundle_and_indexes.sql
        ERROR:  relation "public.user_lists" does not exist
FAIL  20260203235500_search_rpc_keyset.sql
        ERROR:  function similarity(text, text) does not exist
FAIL  20260204233000_recommend_seed_similarity_allow_anon.sql
        ERROR:  relation "public.editorial_penalty_tags" does not exist
FAIL  20260204234500_recommend_seed_similarity_ranked_tags.sql
        ERROR:  relation "public.editorial_penalty_tags" does not exist
FAIL  20260204235500_recommend_seed_similarity_genre_gate.sql
        ERROR:  relation "public.editorial_penalty_tags" does not exist
FAIL  20260205231000_curated_rails.sql
        ERROR:  relation "public.user_lists" does not exist
FAIL  20260205234000_curated_rails_seed.sql
        ERROR:  relation "public.curated_rails" does not exist
FAIL  20260205235000_discover_bundle_use_curated_rails.sql
        ERROR:  function public.current_season_name(timestamp with time zone) does not exist
FAIL  20260206120000_curated_rails_expansion.sql
        ERROR:  relation "public.curated_rail_items" does not exist
FAIL  20260206150000_security_hardening_rls_and_views.sql
        ERROR:  relation "public.editorial_boosts" does not exist
FAIL  20260206162329_curated_rails_expansion.sql
        ERROR:  relation "public.curated_rail_items" does not exist
FAIL  20260206164200_security_hardening_rls_and_views.sql
        ERROR:  relation "public.editorial_boosts" does not exist
FAIL  20260207011000_curated_rails_vibes_seed.sql
        ERROR:  relation "public.curated_rails" does not exist
FAIL  20260207020000_curated_rails_more_vibes_seed.sql
        ERROR:  relation "public.curated_rails" does not exist
FAIL  20260208022035_phase0_remove_sequels.sql
        ERROR:  relation "curated_rail_items" does not exist
FAIL  20260208022110_add_sports_mode.sql
        ERROR:  relation "curated_rails" does not exist
FAIL  20260208022136_phase0_remove_misclassified.sql
        ERROR:  relation "curated_rail_items" does not exist
FAIL  20260208022153_add_scifi_mode.sql
        ERROR:  relation "curated_rails" does not exist
FAIL  20260208022239_add_horror_supernatural_mode.sql
        ERROR:  relation "curated_rails" does not exist
FAIL  20260208022250_phase0_dedup_rails.sql
        ERROR:  relation "curated_rail_items" does not exist
FAIL  20260208022326_phase0_slim_and_rerank.sql
        ERROR:  relation "curated_rail_items" does not exist
FAIL  20260208022342_add_demographic_rails.sql
        ERROR:  relation "curated_rails" does not exist
FAIL  20260208022404_phase0_fix_classics.sql
        ERROR:  relation "curated_rail_items" does not exist
FAIL  20260208023052_phase0_backfill_underpopulated_rails.sql
        ERROR:  relation "curated_rail_items" does not exist
FAIL  20260208023221_phase0_dedup_backfilled_rails.sql
        ERROR:  relation "curated_rail_items" does not exist
FAIL  20260208023331_phase0_final_backfill.sql
        ERROR:  relation "curated_rail_items" does not exist
FAIL  20260208090000_refine_short_and_fantasy_rails.sql
        ERROR:  relation "public.curated_rails" does not exist
FAIL  20260208091500_curated_rails_premium_picks_seed.sql
        ERROR:  relation "public.curated_rails" does not exist
FAIL  20260209120000_new_vibe_rails.sql
        ERROR:  relation "public.curated_rails" does not exist
FAIL  20260211162000_reduce_school_shoujo_overlap.sql
        ERROR:  relation "public.curated_rail_items" does not exist
FAIL  20260324213000_discover_airing_today_berlin_day.sql
        ERROR:  function public.current_season_name(timestamp with time zone) does not exist
FAIL  20260731060000_taste_math_v2.sql
        ERROR:  relation "public.editorial_penalty_tags" does not exist
FAIL  20260731070000_taste_math_v2_hotfix.sql
        ERROR:  function public._taste_deck_apply_tag_stats(uuid, text, integer, text, integer) does not exist
FAIL  20260731100000_discover_p1.sql
        ERROR:  relation "public.editorial_boosts" does not exist
FAIL  20260731150000_realm_graph_v1.sql
        ERROR:  relation "public.media_tag_vectors" does not exist
FAIL  20260731160000_realm_gate_calibration.sql
        ERROR:  relation "public.media_tag_vectors" does not exist
FAIL  20260731170000_media_realm_llm_v1.sql
        ERROR:  relation "public.media_realm_tier" does not exist
FAIL  20260731180000_similarity_inclusion_fix.sql
        ERROR:  relation "public.media_tag_vectors" does not exist
FAIL  20260731194000_debug_sim_v42.sql
        ERROR:  relation "public.media_tag_vectors" does not exist
FAIL  20260731200000_penalty_clamp_and_debug_cleanup.sql
        ERROR:  relation "public.media_tag_vectors" does not exist
FAIL  20260802123000_media_realm_membership_delta_v1.sql
        ERROR:  relation "public.media_realm_membership" does not exist
FAIL  20260802125000_membership_delta_check_float4.sql
        ERROR:  relation "public.media_realm_membership_delta" does not exist
FAIL  20260802140000_spirited_away_gate_harden.sql
        ERROR:  relation "public.realm_affinity_overrides" does not exist
FAIL  20260802141000_canon_bless_and_discover_realm_rails.sql
        ERROR:  relation "public.media_tag_vectors" does not exist
FAIL  20260802150000_curation_sources_expand_v1.sql
        ERROR:  column "blessed" of relation "canon_seed" does not exist
FAIL  20260804100000_similarity_penalty_and_costs.sql
        ERROR:  relation "public.realm_affinity_overrides" does not exist
FAIL  20260804120000_tier_from_effective_and_cron.sql
        ERROR:  relation "public.media_realm_tier" does not exist
FAIL  20260804121000_rebuild_tier_execute_service_role_only.sql
        ERROR:  function public.rebuild_media_realm_tier() does not exist
FAIL  20260804130000_media_similar_titles_precompute.sql
        ERROR:  relation "public.media_tag_vectors" does not exist
FAIL  20260804150000_hygiene_ops_fn_and_view_advisors.sql
        ERROR:  relation "public.realm_affinity_effective" does not exist
FAIL  20260805110000_realm_audit_overrides.sql
        ERROR:  relation "public.media_realm_membership" does not exist
FAIL  20260805112000_realm_audit_override_conditional_swap.sql
        ERROR:  relation "public.media_realm_membership" does not exist
FAIL  20260805120000_edges_first_serving.sql
        ERROR:  relation "public.media_similar_titles" does not exist
FAIL  20260806000000_security_and_mirror_repair.sql
        ERROR:  relation "public.media_similar_seed_state" does not exist
FAIL  20260806020000_serving_hardening_v1.sql
        ERROR:  relation "public.media_similar_seed_state" does not exist
FAIL  20260807010000_leftover_repairs_v1.sql
        ERROR:  relation "public.media_similar_seed_state" does not exist
replay reports copied to /private/tmp/kuro-deep-db-review

================ RLS / authorization tests on kuro_baseline_first ================
FIXTURE: audited schema fixture (stubs + baseline-first application). NOT a complete migration replay.
         NOT Supabase Auth / Realtime / Storage / PostgREST / pg_cron / pg_net.
PASS  00_harness_and_preconditions.sql          14 assertions, 0 blocked, 0 findings
PASS  10_user_lists.sql                         34 assertions, 1 blocked, 1 findings
PASS  20_clubs.sql                              84 assertions, 0 blocked, 3 findings
PASS  30_social_comments.sql                    31 assertions, 0 blocked, 0 findings
PASS  40_streaming_and_taste.sql                31 assertions, 2 blocked, 0 findings
PASS  50_account_deletion_fk_and_rpc.sql        26 assertions, 2 blocked, 2 findings
PASS  60_club_role_guard.sql                    34 assertions, 0 blocked, 0 findings
PASS  61_club_rail_insert_policy.sql            13 assertions, 0 blocked, 0 findings
PASS  62_comment_reaction_visibility.sql        18 assertions, 0 blocked, 0 findings
PASS  63_club_privacy_levels_and_open_items.sql  36 assertions, 0 blocked, 3 findings

---- findings (observed behavior; NOT fixed here) ----
  * public.user_lists view without security_invoker (legacy_sql/08 as written) -- user 2 sees 2 of user 1's rows through the view
  * bundle cross-member statuses cannot work under RLS -- 3 of 4 members track the item; bundle member_status_counts={"COMPLETED": 1} (expected one entry per status if cross-member reads worked)
  * revocation is not sticky -- owner removal deletes the club_members row only; the club-wide invite_code still works, so a removed member can join_club() again unless the code is expired/exhausted/rotated
  * club raw per-user rows readable by any member -- policies club_votes_select_member / club_reactions_select_member / club_members_select_member use is_club_member() only; fetch_club_bundle's anonymous-aggregate and sharing_level gating are RPC-only and bypassable via direct table reads
  * anime_comments / manga_comments need an explicit delete -- user_id TEXT, no FK: neither delete_user_concierge_data (any repo version) nor the auth.users cascade removes them; the delete-account function now deletes both as REQUIRED steps (supabase/functions/delete-account/deletion.ts), emulated below
  * club lifecycle on account deletion -- edge function step 2 sweeps clubs with created_by IS NULL AND no members, but runs BEFORE auth deletion when created_by is still set, so it only ever cleans earlier victims; leave_club has ownership-transfer/cleanup logic that account deletion bypasses
  * R4 OPEN: tightening the SELECT policies alone breaks the app -- own-row SELECT on club_votes / club_rail_item_reactions / club_members makes the SECURITY INVOKER fetch_club_bundle and fetch_club_bundle_loading return own-only counts (polls 3->1, reactions, member_count 4->1); not applied
  * R4 OPEN: option D4-A is feasible in the fixture but privacy-visible -- fetch_club_bundle(_loading) SECURITY DEFINER + own-row SELECT policies keeps counts and private gating, hides raw rows, but ALSO makes cross-member list statuses/progress appear (resolves finding 3); Realtime INSERT events of other members' votes/reactions would stop reaching clients. Owner decision.
  * R5 OPEN: revocation is not sticky (leave path) -- leave_club / owner removal delete only the club_members row; the club-wide invite_code keeps working (contradicts the leave dialog copy), and the departed member's votes/reactions remain in counts and raw rows. No remove-member UI exists; removal today is a direct DELETE by owner/admin.

---- BLOCKED (not faked; reason + recovery) ----
  - production state of public.user_lists (security_invoker) -- view absent from baseline capture and 20260206150000 does not replay; verify with pg_class.reloptions on a production-equivalent DB
  - taste_tag_stats owner isolation (taste_tag_stats_select_own) -- table is created by 20260731060000_taste_math_v2.sql which does not replay here (FK-data dependency on editorial_penalty_tags); recovery: production-equivalent schema
  - latest delete_user_concierge_data (20260806020000 adds discover_rail_impressions) -- that migration does not replay; fixture holds the 20260305153000 body
  - storage objects owned by the user (bucket "media") -- Supabase Storage is not part of this fixture; storage.objects is a stub with no owner cascade. Covered only by the delete-account unit tests with a fake storage dependency.
  - auth.users deletion by GoTrue / supabase_auth_admin -- the fixture deletes from the stub auth.users as superuser; FK cascade behavior is real PostgreSQL, the Auth server is not.

RESULT: 10 test files, 321 assertions passed, 5 blocked markers, 9 finding markers -> PASS
PROVEN: RLS/RPC authorization on the tables listed in supabase/tests/README.md, for the schema this fixture contains.
NOT PROVEN: full migration replay; production schema equality; Supabase Auth/Realtime/Storage/PostgREST behavior; edge functions; any file listed as FAIL above.
teardown: throwaway cluster stopped and /tmp/kuro-db-test.QXV6mx removed

END EMBEDDED FILE: evidence/kuro-deep-db-review-run.log


BEGIN EMBEDDED FILE: evidence/kuro-deep-handler-probes.jsonl
SHA256: 74665f79e0a948ddaecb47963ca4f62f25a0be249b39ec9e9e535edeb3be9527

{"probe":"import_session_items:insert","apply":{"status":200,"body":{"success":true,"sessionId":"import_sessions-1","applied":[{"mediaType":"ANIME","mediaId":7,"status":"PLANNING","action":"add"}],"skipped":[],"conflicts":[],"errors":[]}},"undo":{"status":200,"body":{"success":true,"sessionId":"import_sessions-1","reverted":[],"warnings":[],"errors":[]}},"remainingRows":[{"rating":null,"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"PLANNING","progress":0}],"sessions":[{"created_at":"2026-10-05T00:00:00.000Z","user_id":"11111111-1111-4111-8111-111111111111","status":"cancelled","source":"chat","id":"import_sessions-1"}]}
{"probe":"import_sessions:update","apply":{"status":200,"body":{"success":true,"sessionId":"import_sessions-1","applied":[{"mediaType":"ANIME","mediaId":7,"status":"PLANNING","action":"add"}],"skipped":[],"conflicts":[],"errors":[]}},"undo":{"status":404,"body":{"error":"No applied session to undo"}},"remainingRows":[{"rating":null,"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"PLANNING","progress":0}],"sessions":[{"created_at":"2026-10-05T00:00:00.000Z","user_id":"11111111-1111-4111-8111-111111111111","status":"draft","source":"chat","id":"import_sessions-1"}]}
{"probe":"partial-import","apply":{"status":200,"body":{"success":false,"sessionId":"import_sessions-1","applied":[{"mediaType":"MANGA","mediaId":9,"status":"READING","action":"add"}],"skipped":[],"conflicts":[{"mediaType":"ANIME","mediaId":7,"error":"State changed since parse — review and retry"}],"errors":[]}},"undo":{"status":404,"body":{"error":"No applied session to undo"}},"remainingManga":[{"rating":null,"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","manga_id":9,"list_type":"READING","progress":0}],"sessions":[{"created_at":"2026-10-05T00:00:00.000Z","user_id":"11111111-1111-4111-8111-111111111111","status":"failed","source":"chat","id":"import_sessions-1"}]}
{"probe":"partial-undo-retry","first":{"status":200,"body":{"success":false,"sessionId":"import_sessions-1","reverted":[],"warnings":[],"errors":[{"id":"import_session_items-2","error":"transient delete failure"}]}},"retry":{"status":404,"body":{"error":"No applied session to undo"}},"remainingRows":[{"rating":null,"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"PLANNING","progress":0}],"sessions":[{"created_at":"2026-10-05T00:00:00.000Z","user_id":"11111111-1111-4111-8111-111111111111","status":"cancelled","source":"chat","id":"import_sessions-1"}]}
{"probe":"invalid-identifier","input":0,"apply":{"status":200,"body":{"success":true,"sessionId":"import_sessions-1","applied":[{"mediaType":"ANIME","mediaId":1,"status":"PLANNING","action":"add"}],"skipped":[],"conflicts":[],"errors":[]}},"remainingRows":[{"rating":null,"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","anime_id":1,"list_type":"PLANNING","progress":0}]}
{"probe":"invalid-identifier","input":-4,"apply":{"status":200,"body":{"success":true,"sessionId":"import_sessions-1","applied":[{"mediaType":"ANIME","mediaId":1,"status":"PLANNING","action":"add"}],"skipped":[],"conflicts":[],"errors":[]}},"remainingRows":[{"rating":null,"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","anime_id":1,"list_type":"PLANNING","progress":0}]}
{"probe":"invalid-identifier","input":null,"apply":{"status":200,"body":{"success":true,"sessionId":"import_sessions-1","applied":[{"mediaType":"ANIME","mediaId":1,"status":"PLANNING","action":"add"}],"skipped":[],"conflicts":[],"errors":[]}},"remainingRows":[{"rating":null,"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","anime_id":1,"list_type":"PLANNING","progress":0}]}

END EMBEDDED FILE: evidence/kuro-deep-handler-probes.jsonl


BEGIN EMBEDDED FILE: evidence/kuro-deep-handler-probes.ts
SHA256: 2560706f188e3cc1a1b482dc12c91e628802631af605f62d4bec67fe356eb150

import {handleApply} from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-apply/handler.ts";
import {handleUndo} from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-undo/handler.ts";
import {FakeSupabase,conciergeSchema} from "file:///Users/max/Kuro-Anime-App/supabase/functions/_shared/test_fake_supabase.ts";
const u="11111111-1111-4111-8111-111111111111";
const req=(body:unknown)=>new Request("https://fixture.invalid",{method:"POST",headers:{Authorization:"Bearer fixture","Content-Type":"application/json"},body:JSON.stringify(body)});
async function call(fn:typeof handleApply|typeof handleUndo,body:unknown,db:FakeSupabase){const r=await fn(req(body),{client:()=>db});return {status:r.status,body:await r.json()};}
for(const fault of ["import_session_items:insert","import_sessions:update"]){
 const db=new FakeSupabase(conciergeSchema(),u);db.faults.set(fault,"injected returned database error");
 const apply=await call(handleApply,{items:[{mediaType:"ANIME",mediaId:7,status:"PLANNING",action:"add"}]},db);
 db.faults.clear();const undo=await call(handleUndo,{sessionId:apply.body.sessionId},db);
 console.log(JSON.stringify({probe:fault,apply,undo,remainingRows:db.rows("anime_user_lists"),sessions:db.rows("import_sessions")}));
}
{
 const db=new FakeSupabase(conciergeSchema(),u);db.seed("anime_user_lists",[{user_id:u,anime_id:7,list_type:"WATCHING",progress:3}]);
 const apply=await call(handleApply,{items:[{mediaType:"ANIME",mediaId:7,status:"WATCHING",action:"update",progressEpisodes:5,expectedExisting:{status:"WATCHING",progress_episodes:1}},{mediaType:"MANGA",mediaId:9,status:"READING",action:"add"}]},db);
 const undo=await call(handleUndo,{sessionId:apply.body.sessionId},db);
 console.log(JSON.stringify({probe:"partial-import",apply,undo,remainingManga:db.rows("manga_user_lists"),sessions:db.rows("import_sessions")}));
}
{
 const db=new FakeSupabase(conciergeSchema(),u);const apply=await call(handleApply,{items:[{mediaType:"ANIME",mediaId:7,status:"PLANNING",action:"add"}]},db);
 db.faults.set("anime_user_lists:delete","transient delete failure");const first=await call(handleUndo,{sessionId:apply.body.sessionId},db);
 db.faults.clear();const retry=await call(handleUndo,{sessionId:apply.body.sessionId},db);
 console.log(JSON.stringify({probe:"partial-undo-retry",first,retry,remainingRows:db.rows("anime_user_lists"),sessions:db.rows("import_sessions")}));
}
for(const id of [0,-4,null]){
 const db=new FakeSupabase(conciergeSchema(),u);const apply=await call(handleApply,{items:[{mediaType:"ANIME",mediaId:id,status:"PLANNING",action:"add"}]},db);
 console.log(JSON.stringify({probe:"invalid-identifier",input:id,apply,remainingRows:db.rows("anime_user_lists")}));
}

END EMBEDDED FILE: evidence/kuro-deep-handler-probes.ts


BEGIN EMBEDDED FILE: evidence/kuro-review-undo-repro.ts
SHA256: c237b238a76770e6d587af07a34ffd071d91cb25e4462ffce2bb778c20f2811d

import { handleApply } from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-apply/handler.ts";
import { handleUndo } from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-undo/handler.ts";
import { conciergeSchema, FakeSupabase } from "file:///Users/max/Kuro-Anime-App/supabase/functions/_shared/test_fake_supabase.ts";
const user = "11111111-1111-4111-8111-111111111111";
function request(body: unknown) { return new Request("https://example.test", {method:"POST", headers:{Authorization:"Bearer jwt", "Content-Type":"application/json"},body:JSON.stringify(body)}); }
for (const scenario of ["later-rating", "conflicted-item", "deleted-after-import"]) {
  const db = new FakeSupabase(conciergeSchema(), user);
  db.seed("anime_user_lists", [{user_id:user,anime_id:7,list_type:"WATCHING",progress:3,rating:8,notes:"original",verdict:null}]);
  const items = scenario === "conflicted-item" ? [
    {mediaType:"ANIME",mediaId:7,status:"WATCHING",action:"update",progressEpisodes:5,expectedExisting:{status:"WATCHING",progress_episodes:1}},
    {mediaType:"MANGA",mediaId:9,status:"READING",action:"add"}
  ] : [{mediaType:"ANIME",mediaId:7,status:"WATCHING",action:"update",progressEpisodes:5,rating:9,expectedExisting:{status:"WATCHING",progress_episodes:3}}];
  const applied = await (await handleApply(request({items}), {client:()=>db})).json();
  if (scenario === "later-rating") db.tables.get("anime_user_lists")![0].rating = 10;
  if (scenario === "conflicted-item") db.tables.get("anime_user_lists")![0].progress = 6;
  if (scenario === "deleted-after-import") db.tables.set("anime_user_lists", []);
  const beforeUndo = structuredClone(db.rows("anime_user_lists"));
  const result = await (await handleUndo(request({sessionId:applied.sessionId}), {client:()=>db})).json();
  console.log(JSON.stringify({scenario,conflicts:applied.conflicts,beforeUndo,afterUndo:db.rows("anime_user_lists"),result}));
}

END EMBEDDED FILE: evidence/kuro-review-undo-repro.ts


BEGIN EMBEDDED FILE: evidence/native-comment-probe-summary.json
SHA256: 5f6081d3faf055c9d3a0be0d1b0913bea96e650bad7045d61d156b9c8efab842

{
  "devicesAndConfigurations" : [
    {
      "device" : {
        "architecture" : "arm64",
        "deviceId" : "8B41088B-36CF-4A22-BD66-C438918A8910",
        "deviceName" : "iPhone 17 Pro",
        "modelName" : "iPhone 17 Pro",
        "osBuildNumber" : "23C54",
        "osVersion" : "26.2",
        "platform" : "iOS Simulator"
      },
      "expectedFailures" : 0,
      "failedTests" : 0,
      "passedTests" : 1,
      "skippedTests" : 0,
      "testPlanConfiguration" : {
        "configurationId" : "1",
        "configurationName" : "Test Scheme Action"
      }
    }
  ],
  "environmentDescription" : "Kuro · Built with macOS 27.0.1",
  "expectedFailures" : 0,
  "failedTests" : 0,
  "finishTime" : 1791200976.374,
  "passedTests" : 1,
  "result" : "Passed",
  "skippedTests" : 0,
  "startTime" : 1791200946.237,
  "statistics" : [

  ],
  "testFailures" : [

  ],
  "title" : "Test - Kuro",
  "topInsights" : [

  ],
  "totalTestCount" : 1
}

END EMBEDDED FILE: evidence/native-comment-probe-summary.json


BEGIN EMBEDDED FILE: evidence/native-sdk-probes-summary.json
SHA256: f23b7f0ea40c06aa5f4deb42cae7a55df03aeb00041d6e3d1819c9cd423005f1

{
  "devicesAndConfigurations" : [
    {
      "device" : {
        "architecture" : "arm64",
        "deviceId" : "8B41088B-36CF-4A22-BD66-C438918A8910",
        "deviceName" : "iPhone 17 Pro",
        "modelName" : "iPhone 17 Pro",
        "osBuildNumber" : "23C54",
        "osVersion" : "26.2",
        "platform" : "iOS Simulator"
      },
      "expectedFailures" : 0,
      "failedTests" : 0,
      "passedTests" : 3,
      "skippedTests" : 0,
      "testPlanConfiguration" : {
        "configurationId" : "1",
        "configurationName" : "Test Scheme Action"
      }
    }
  ],
  "environmentDescription" : "Kuro · Built with macOS 27.0.1",
  "expectedFailures" : 0,
  "failedTests" : 0,
  "finishTime" : 1791200795.945,
  "passedTests" : 3,
  "result" : "Passed",
  "skippedTests" : 0,
  "startTime" : 1791200718.069,
  "statistics" : [

  ],
  "testFailures" : [

  ],
  "title" : "Test - Kuro",
  "topInsights" : [

  ],
  "totalTestCount" : 3
}

END EMBEDDED FILE: evidence/native-sdk-probes-summary.json


BEGIN EMBEDDED FILE: evidence/rate-limit-error-probe.json
SHA256: cf80f53a1e85f678bf4097d5f9ee14aabd47b2ab9ffb7cdfb48d43047ea635a4

{"status":200,"body":{"success":true,"sessionId":"import_sessions-1","applied":[{"mediaType":"ANIME","mediaId":7,"status":"PLANNING","action":"add"}],"skipped":[],"conflicts":[],"errors":[]},"rows":[{"rating":null,"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"PLANNING","progress":0}]}

END EMBEDDED FILE: evidence/rate-limit-error-probe.json


BEGIN EMBEDDED FILE: evidence/rate-limit-error-probe.ts
SHA256: d3ec1269f90ebb1052a498b7b744e7081226ca89a80f73d83c56043497d28ada

import {handleApply} from "file:///Users/max/Kuro-Anime-App/supabase/functions/concierge-apply/handler.ts";
import {FakeSupabase,conciergeSchema} from "file:///Users/max/Kuro-Anime-App/supabase/functions/_shared/test_fake_supabase.ts";
const u="11111111-1111-4111-8111-111111111111";
const db=new FakeSupabase(conciergeSchema(),u);
const rpc=db.rpc.bind(db);
db.rpc=(fn,args)=>fn==="check_concierge_rate_limit"?Promise.resolve({data:null,error:{message:"rate-limit database unavailable"}}):rpc(fn,args);
const req=new Request("https://fixture.invalid",{method:"POST",headers:{Authorization:"Bearer fixture","Content-Type":"application/json"},body:JSON.stringify({items:[{mediaType:"ANIME",mediaId:7,status:"PLANNING",action:"add"}]})});
const res=await handleApply(req,{client:()=>db});console.log(JSON.stringify({status:res.status,body:await res.json(),rows:db.rows("anime_user_lists")}));

END EMBEDDED FILE: evidence/rate-limit-error-probe.ts


BEGIN EMBEDDED FILE: evidence/review-source-status.txt
SHA256: 12b435d64c3dcd50692f5f5de643c32b86a82190e6c972c7ee2e191007b002bd

 M CLAUDE.md
 M CURRENT_APP_STATE.md
 M CURRENT_APP_STATE_PLAIN.md
 M IMPLEMENTATION_PLAN_Variation1.md
 M Kuro.xcodeproj/project.pbxproj
 M Kuro/ContentView.swift
 M Kuro/KuroApp.swift
 M Kuro/Models/SupabaseModels.swift
 M Kuro/Services/ConciergeAnalytics.swift
 M Kuro/Services/FeatureFlags.swift
 M Kuro/Services/KuroDiskDetailCache.swift
 M Kuro/Services/SupabaseRPCParams.swift
 D Kuro/Services/SupabaseService+Browse.swift
 D Kuro/Services/SupabaseService+ClubRealtime.swift
 D Kuro/Services/SupabaseService+Clubs.swift
 D Kuro/Services/SupabaseService+Collection.swift
 D Kuro/Services/SupabaseService+Concierge.swift
 D Kuro/Services/SupabaseService+Discover.swift
 D Kuro/Services/SupabaseService+Monetization.swift
 D Kuro/Services/SupabaseService+Recommendations.swift
 D Kuro/Services/SupabaseService+Social.swift
 D Kuro/Services/SupabaseService+Streaming.swift
 D Kuro/Services/SupabaseService+Taste.swift
 D Kuro/Services/SupabaseService+UserLists.swift
 D Kuro/Services/SupabaseService.swift
 M Kuro/Views/AddToListSheet.swift
 M Kuro/Views/AuthView.swift
 M Kuro/Views/BrowseComponents.swift
 M Kuro/Views/BrowseView.swift
 D Kuro/Views/Cards.swift
 M Kuro/Views/ClubCreateSheets.swift
 M Kuro/Views/ClubDetailSheets.swift
 M Kuro/Views/ClubDetailShellComponents.swift
 M Kuro/Views/ClubDetailTabComponents.swift
 M Kuro/Views/ClubDetailView.swift
 M Kuro/Views/ClubsView.swift
 D Kuro/Views/ConciergeActionFooter.swift
 M Kuro/Views/ConciergeAniListImportCoordinator.swift
 M Kuro/Views/ConciergeComponents.swift
 D Kuro/Views/ConciergeComposerDock.swift
 M Kuro/Views/ConciergeImportCards.swift
 M Kuro/Views/ConciergeInputField.swift
 D Kuro/Views/ConciergeIntentDeck.swift
 M Kuro/Views/ConciergeRecommendationRails.swift
 M Kuro/Views/ConciergeView+AniListImport.swift
 M Kuro/Views/ConciergeView.swift
 M Kuro/Views/DetailPages/AdaptationPathSection.swift
 M Kuro/Views/DetailPages/AnimeDetailView.swift
 M Kuro/Views/DetailPages/ClubActivitySection.swift
 M Kuro/Views/DetailPages/EntityDetailSheets.swift
 M Kuro/Views/DetailPages/ExternalLinksSection.swift
 M Kuro/Views/DetailPages/FriendsActivitySection.swift
 M Kuro/Views/DetailPages/MangaDetailView.swift
 M Kuro/Views/DetailPages/MediaDetailSheet.swift
 M Kuro/Views/DiscoverOneThingCard.swift
 D Kuro/Views/EditorialCards.swift
 M Kuro/Views/EditorialCollectionComponents.swift
 M Kuro/Views/EditorialCollectionView.swift
 M Kuro/Views/EditorialDiscoverView.swift
 M Kuro/Views/EditorialSearchView.swift
 M Kuro/Views/GenreHubView.swift
 M Kuro/Views/KuroConciergeMark.swift
 M Kuro/Views/KuroRefinedCard.swift
 M Kuro/Views/OnboardingView.swift
 D Kuro/Views/PosterView.swift
 M Kuro/Views/ProfileFreshnessCard.swift
 M Kuro/Views/ProfileView.swift
 M Kuro/Views/QuickVerdictActionCard.swift
 M Kuro/Views/TasteDeckView.swift
 D Kuro/Views/UIComponents.swift
 M KuroTests/KuroTests.swift
 M docs/documentation-surface-map.md
 M scripts/generate_app_state_sources.js
 M scripts/quality-gates/check_docs_current_state.py
 M scripts/quality-gates/router_test_cases.js
 M scripts/quality-gates/run_all.sh
 M scripts/quality-gates/test_concierge_corpora.sh
 M scripts/quality-gates/test_router_offline.sh
 M supabase/functions/concierge-apply/index.ts
 M supabase/functions/concierge-parse/index.ts
 M supabase/functions/concierge-recommend/index.ts
 M supabase/functions/concierge-resolve/index.ts
 M supabase/functions/concierge-undo/index.ts
 M supabase/functions/delete-account/index.ts
 M tools/design-directions/INSTRUMENT_README.md
 M tools/design-directions/instrument.css
 M tools/design-directions/instrument.html
 M tools/design-directions/instrument.js
?? AGENTS.md
?? Kuro/Catalog/
?? Kuro/Clubs/
?? Kuro/Collection/
?? Kuro/Composition/
?? Kuro/Concierge/
?? Kuro/Design/FlowLayout.swift
?? Kuro/Discovery/
?? Kuro/Identity/
?? Kuro/Imports/
?? Kuro/Infrastructure/
?? Kuro/Library/
?? Kuro/Providers/
?? Kuro/Releases/
?? Kuro/Search/
?? Kuro/Social/
?? Kuro/Taste/
?? Kuro/Telemetry/
?? Kuro/Views/ClubViewLifecycle.swift
?? Kuro/Views/DetailPages/DetailSharedComponents.swift
?? Kuro/Views/DetailPages/ProviderLinkViews.swift
?? Kuro/Views/LibraryViewActions.swift
?? Kuro/Views/Routing/
?? Kuro/Views/SharedCards/
?? Kuro/Views/TastePicksView.swift
?? Kuro/Views/TrackingDraft.swift
?? KuroTests/AccountLifecycleTests.swift
?? KuroTests/AssistantContractTests.swift
?? KuroTests/ClubErrorTests.swift
?? KuroTests/ClubsContractTests.swift
?? KuroTests/ClubsViewRulesTests.swift
?? KuroTests/CollectionContractTests.swift
?? KuroTests/ConciergeRoutingTests.swift
?? KuroTests/DetailProviderLinksTests.swift
?? KuroTests/IdentityCompositionTests.swift
?? KuroTests/ImportReconcilerTests.swift
?? KuroTests/LibraryFacadeTests.swift
?? KuroTests/LibraryHTTPContractTests.swift
?? KuroTests/LibraryTestSupport.swift
?? KuroTests/LibraryViewActionsTests.swift
?? KuroTests/PersonalDataHTTPContractTests.swift
?? KuroTests/PostgrestLibraryTransportTests.swift
?? KuroTests/PublicDataHTTPContractTests.swift
?? KuroTests/RoutingTests.swift
?? KuroTests/SharedInfrastructureTests.swift
?? KuroTests/StubPostgREST.swift
?? KuroTests/TasteDeckBannerTests.swift
?? KuroTests/TrackingDraftTests.swift
?? Packages/
?? canvases-canonical/kuro-map3-string-audit.canvas.tsx
?? docs/handoffs/
?? docs/modules/
?? docs/plans/
?? docs/research/
?? scripts/capture_screen_canvas.py
?? scripts/db/
?? scripts/export_screen_canvas.py
?? scripts/quality-gates/check_architecture.sh
?? scripts/quality-gates/test_packages.sh
?? scripts/serve_design_share.py
?? scripts/serve_live_preview.py
?? supabase/functions/_shared/test_fake_supabase.ts
?? supabase/functions/concierge-apply/apply_plan.ts
?? supabase/functions/concierge-apply/handler.ts
?? supabase/functions/concierge-apply/handler_test.ts
?? supabase/functions/concierge-parse/rules.ts
?? supabase/functions/concierge-parse/rules_corpus_test.ts
?? supabase/functions/concierge-recommend/router.ts
?? supabase/functions/concierge-recommend/router_corpus_test.ts
?? supabase/functions/concierge-recommend/router_modes.fixture.json
?? supabase/functions/concierge-recommend/router_test.ts
?? supabase/functions/concierge-recommend/router_test_support.ts
?? supabase/functions/concierge-undo/handler.ts
?? supabase/functions/concierge-undo/handler_test.ts
?? supabase/functions/concierge-undo/undo_plan.ts
?? supabase/functions/delete-account/adapters.ts
?? supabase/functions/delete-account/deletion.ts
?? supabase/functions/delete-account/deletion_test.ts
?? supabase/functions/delete-account/fake_backend.ts
?? supabase/functions/delete-account/handler.ts
?? supabase/functions/delete-account/handler_test.ts
?? supabase/functions/delete-account/real_client_shapes.ts
?? supabase/prepared-migrations/
?? supabase/tests/
?? tools/design-directions/README.md
?? tools/design-directions/aperture.css
?? tools/design-directions/aperture.html
?? tools/design-directions/aperture.js
?? tools/design-directions/archive/
?? tools/design-directions/art.js
?? tools/design-directions/art.json
?? tools/design-directions/assets/aperture-review.png
?? tools/design-directions/assets/detail-character-180.png
?? tools/design-directions/assets/detail-character-181.png
?? tools/design-directions/assets/detail-character-182.png
?? tools/design-directions/assets/detail-character-21.png
?? tools/design-directions/assets/detail-character-22.png
?? tools/design-directions/assets/detail-character-23.png
?? tools/design-directions/assets/detail-character-24.png
?? tools/design-directions/assets/fonts/
?? tools/design-directions/assets/medium-diptych-v43.jpg
?? tools/design-directions/assets/medium-diptych-v43.png
?? tools/design-directions/assets/medium-diptych-v43.prompt.txt
?? tools/design-directions/assets/medium-objects-v47.png
?? tools/design-directions/assets/medium-objects-v47.prompt.txt
?? tools/design-directions/assets/original-discover-review.png
?? tools/design-directions/assets/world-landscape.png
?? tools/design-directions/assets/world-paper.png
?? tools/design-directions/build_art_materials.py
?? tools/design-directions/composition-review.html
?? tools/design-directions/flow.html
?? tools/design-directions/folio.html
?? tools/design-directions/home-profile.js
?? tools/design-directions/index.html
?? tools/design-directions/instrument-art-materials.js
?? tools/design-directions/instrument-detail-data.js
?? tools/design-directions/interlude.html
?? tools/design-directions/journal.css
?? tools/design-directions/journal.html
?? tools/design-directions/journal.js
?? tools/design-directions/manga-crosscut.html
?? tools/design-directions/manga-directions.css
?? tools/design-directions/manga-directions.js
?? tools/design-directions/manga-four.html
?? tools/design-directions/manga-library.html
?? tools/design-directions/manga-options.html
?? tools/design-directions/manga-philosophies.css
?? tools/design-directions/manga-philosophies.js
?? tools/design-directions/manga-reference-study.html
?? tools/design-directions/modern.css
?? tools/design-directions/modern.html
?? tools/design-directions/modern.js
?? tools/design-directions/panels.html
?? tools/design-directions/reference-atlas.html
?? tools/design-directions/references.html
?? tools/design-directions/studies.html
?? tools/design-directions/switch-options.html
?? tools/design-directions/world-art.json
?? tools/design-directions/world.css
?? tools/design-directions/world.html
?? tools/design-directions/world.js
?? tools/live-preview/
?? tools/screen-canvas/

END EMBEDDED FILE: evidence/review-source-status.txt


BEGIN EMBEDDED FILE: evidence/source-digests.json
SHA256: 5943919bc44425a82e7bddfeecf97c6bc56ead73d994feef031a8aa3d840b835

{
  "head": "471c609943d2374c6dda940aebdfde2fcb077d50",
  "dirty": true,
  "files": {
    "Kuro/Catalog/CatalogStore.swift": "90070d0ac7a0ac8ce8e13cd56d33ae37f0ec935f8650f7e42fd7c2d8158e877d",
    "Kuro/Catalog/DiscoveryContentRules.swift": "320b15c8eacfdd6df6c487f8f2a9ef3271e34a125280db2520dde15f6a941c50",
    "Kuro/Catalog/MissingSupabaseConfiguration.swift": "c90909819edd082c49febb5042fcb3458b18e853e39cf35c9d56be332cda2142",
    "Kuro/Clubs/ClubModels.swift": "298f4a33ae8b85df710379a2328c9ea8a2a1088391ae2eb7966827139e457e38",
    "Kuro/Clubs/ClubRealtimeCoordinator.swift": "4bd9e25a243f98e6801b9afd7726cd4734cf4a9401460b85479e88ae24fe8076",
    "Kuro/Clubs/ClubsLibrarySink.swift": "195d2c03d60af52f9fda98a4ace10c4d673fe4079fe526b0372360072ddfcaeb",
    "Kuro/Clubs/ClubsStore.swift": "2579f4afa47ca9ee5c239247be442db739d46755e46c6e765d5769ff27182887",
    "Kuro/Collection/CollectionStore.swift": "7ea7d6a07c856c4462364b6397ff20fd3a806b0ce2d3ee89fcced01131efd867",
    "Kuro/Composition/AccountScopedState.swift": "1c689297a8bd400fa1092021f059aac030b4a2542d577e9220137f1b9f235376",
    "Kuro/Composition/AppComposition.swift": "b649f6da1e96b3c4d3ba46eed9a6f7dbf113e6952098ade7f6472be996ec492c",
    "Kuro/Composition/BannerCenter.swift": "9b628b08cbeb4cbde0c07401346d0d2bfa3e23ac27c105f2971592591bae94ff",
    "Kuro/Composition/LibraryChangeSinks.swift": "ac454ebbf7b6801c46b2004bb88e710167fa10e2c45ae67558cda26cbdfae33a",
    "Kuro/Composition/LibraryRefreshHook.swift": "cc85cab544f0660197973faf73b2361e1eca6edf5e0ae15703a603d178df8e79",
    "Kuro/Composition/PostgrestLibraryTransport.swift": "a2771b39a7f28da84727d72a1217ca3c322ff56e7ffca6afd6359a18f5813fe6",
    "Kuro/Concierge/ConciergeFunctions.swift": "1401d9de91892eea56aca855f46874a94ba77dec2067c4259b7b16e8057956b3",
    "Kuro/Concierge/ConciergeRecommendModels.swift": "a6545e355c361448d2c6c7a24db1b83f6e9f63fdb99c28dfdb9c5b0c62dbc75c",
    "Kuro/Concierge/ConciergeRouting.swift": "e533fad521cc6126d4a531a969ee7a74893c2785763b6a032aa30fa3d1145343",
    "Kuro/Concierge/ConciergeStore.swift": "6424000bfb20b0cd7ef4297c8fde6d34890ecc709d0b61cb0e82f1031e06df76",
    "Kuro/ContentView.swift": "a4e6b79f1e14a84b9c38e7a631d7f37016fc645793b7116d8cc3c53c9ace2145",
    "Kuro/Design/Color+Hex.swift": "7ebeb3f5b9f4f9c38daa3a96ffaee8f9b5730c80ae4c1305e76ed1fbce6fc531",
    "Kuro/Design/FlowLayout.swift": "533bf979a09fe3e68134c7d4d2a5e033809807a5f9bb6b9e6105211a31761a94",
    "Kuro/Design/KuroDesignSystem.swift": "6f7b89a19abcd37b7f70c3483f0fc4e925af46f9537f900a367c78a06760f232",
    "Kuro/Discovery/DiscoverCards.swift": "9689462aa4698a54e572b0895e9754569930fb042de8c0df894734f365c979bb",
    "Kuro/Discovery/DiscoveryStore.swift": "fac451b08859a9cc82c95949246c1a37849048ab34e33ec68f94c6fd8e29cc81",
    "Kuro/Discovery/RecommendationsReader.swift": "f77edd9ef18f41c2411b51a4c9ea3234d8c5f38b7e4e8da32aed7cee2377f898",
    "Kuro/Identity/AuthCallbackGuard.swift": "fe4c374a72684c3caf0af4a2850e1605ff08981c6e099dc48671e22cf26dd7f7",
    "Kuro/Identity/AuthService.swift": "c20608ae318f76d764caf5d01129087dcd9bbbff73af6c385a4ead556f175f6a",
    "Kuro/Identity/IdentityStore.swift": "c1ceb1d978ad50547660ffedac8514949dd5de5dbf3413bf8ffd641b974cd89c",
    "Kuro/Identity/SessionController.swift": "c610f7ab2fb936d2ad6f028087d49f574596866d971e4fcc3e8b947ba264953a",
    "Kuro/Imports/ImportModels.swift": "59c5808f21d8725a83cfe7b11ff1334f3a1505b8d765a863f956e6713f2d700f",
    "Kuro/Imports/ImportReconciler.swift": "516a205e333ffea17e17f48f6c652c972d6d398b9e7262cd4652cc9b59dc91fc",
    "Kuro/Imports/ImportsService.swift": "53404f277a633a1937daf2ae93f9c30b4dac2521d7a64c6a1588ff200bbd25f1",
    "Kuro/Infrastructure/MemoryPressure.swift": "32a17ff305f63e0618186fc6619e75e5a2a5cf43a045cd187f0735a452e4c6f8",
    "Kuro/Infrastructure/Retry.swift": "3358a4736c0431060a363543ddf9f5caa123cc836742b91407e4123840d28f22",
    "Kuro/Infrastructure/TimedCache.swift": "1266a76cca1429059e2985f6e5362265804c7818918c44605cf0b2804caed687",
    "Kuro/KuroApp.swift": "35818b8ada0f98cbb66f70bfcc20b8bd939269eeaf631cac459f2543acfaaa3f",
    "Kuro/Library/LibraryActions.swift": "76cef3906503e8d924639278d809f656ce637d50420c3b712ec0f7ab2661adea",
    "Kuro/Library/LibraryRealtime.swift": "cfbe7cf261c9d61fb3ecace728cef7416580746bbe503a91804634a0e89d953f",
    "Kuro/Models/DiscoverBundle.swift": "917f6c3c08c85e0440effc00d8f025f0b551635cfd8ca21e3401f585e08d4394",
    "Kuro/Models/SupabaseModels.swift": "71405441f0dbeb447e0d63d5787e65138e6581f6294636034084fb269848595f",
    "Kuro/Providers/ProviderAvailabilityStore+DetailLinks.swift": "166391ff038cfc66bdccc14c255ad71ba7fce197307c8a5947b163ed06327c1c",
    "Kuro/Providers/ProviderAvailabilityStore+LegalLinks.swift": "9de1931dba1ef7577a7cb2cc8472885aea902b7dc41ef1f546a467d46a93331c",
    "Kuro/Providers/ProviderAvailabilityStore.swift": "29a817a8da5a009ac7bd21945dcb866dd0cedb201c75a2baa71576b5c4c67f3e",
    "Kuro/Providers/ProviderLinkBuilders.swift": "f726c9efdfcafeb1080915154aa4112b8c4586df55bce7f15099a7b95d0ac37c",
    "Kuro/Releases/ReleasesStore.swift": "287870de0aab5475f88237a02e421a6e987eb9cf0d4e01e98b899569cc341a87",
    "Kuro/Releases/ReminderScheduler.swift": "4e9416db3d7ad039d910852bef36a4c6dfa7ccfa00a0b58112d887354230d48a",
    "Kuro/Search/SearchStore.swift": "57e4112a9e166f9c41c69bafee353314a8e785f19f7284cda0ceeb1a51280820",
    "Kuro/Services/AppConfig.swift": "b88fda8bb3c78ce3cf427ba5d9cd7b4baabf55e2a2182b18aa059c3ac2144f77",
    "Kuro/Services/AppleFMService.swift": "8e0e2819ef4478af256dbf45e07e371c612a1ce2b1743ed77a2e5310b79d3e7e",
    "Kuro/Services/ConciergeAnalytics.swift": "eebd7213bec5f5f338552c26880ad72261cabc415ece2f17ede177705bedc70a",
    "Kuro/Services/DeepLinkRouter.swift": "ff50f6522bd13e1981b633987e4b320ee02bf6c5e91c3114ca31594d69eeb451",
    "Kuro/Services/FeatureFlags.swift": "09d7fde3b59b4ac0341870a448b159e62d25f0863ca3aee348926074e9ca9a46",
    "Kuro/Services/ImagePipeline.swift": "a796cf187cee8ff22e888aca1d43c9ba52e957a5e005f6787c988ce9e00d5e05",
    "Kuro/Services/KuroDiskDetailCache.swift": "2abff13641ab49824688fb949b884019032ecd4e8a3d3fc759e7c5d4f05ce2a4",
    "Kuro/Services/KuroPerf.swift": "c8ec439a3dc031d12012a0f8e24aaa54be544f2cbf76afa426252fb9954df056",
    "Kuro/Services/NetworkMonitor.swift": "8c6693a947a0782a05253cfd1bc3bc5d3b572656f3ff9dcdd490d6531d94ca5b",
    "Kuro/Services/SupabaseRPCParams.swift": "bcbb5638802d80674c289154cb2ba11e2d6f250a3a2dfad31b1a3f7371d10a53",
    "Kuro/Services/TextNormalization.swift": "9b092a6ea3f8e9b48a89f0c9a786e9b81f793e59a6bcfeca31e402e6bdfcfa95",
    "Kuro/Social/SocialActivityStore.swift": "88b91cf18923dd638e02506ef057b5bb643ba0ff3b19667a5fff708eb12b83c4",
    "Kuro/Taste/TasteModels.swift": "ff45171749c73a326579954f74067de6dc5366423b7204eec1f26da911f62a18",
    "Kuro/Taste/TasteStore.swift": "b658653aab482a09781c3c48c7743defbdfbdce068953ab8d6c1e027d431f106",
    "Kuro/Telemetry/InteractionTelemetry.swift": "686da794b07250f70c05ca0cdfa6317eaccb7690f10b86ab28f59baecf60d75e",
    "Kuro/Telemetry/OutboundLinkTelemetry.swift": "ef954ae535266b1c82a7e2d31acfd552548cd7b3e7f44531e695675a94a0c3b5",
    "Kuro/Views/AddToListSheet.swift": "f5eabe6b1f1baa0b38326f60f9a5688516e6ec4a837ff72dddd346621bf93568",
    "Kuro/Views/AuthView.swift": "5860c79d21b9069eb85b0800ad95327e92962d79b4e1ea13d50a18a3c6a970d2",
    "Kuro/Views/BrowseComponents.swift": "1903c22b6e2439be5d4d7c7d1487edacfc6bc87ae73188f5b834cb0860ad8228",
    "Kuro/Views/BrowseView.swift": "2551f1f55f579f1e2c3f8095617d4cb24bbb4ad2658a90223be059477b8b3102",
    "Kuro/Views/ClubCreateSheets.swift": "405d222e87f972263360db92b896b31013246f72a27f4d7c777f5647ca11ed3d",
    "Kuro/Views/ClubDetailSheets.swift": "b41422e580a5bb4ab097e390d373113ae13f872d6d27d6e33077c2e6a1df9a07",
    "Kuro/Views/ClubDetailShellComponents.swift": "4946b2b30eb897f156671c0fa50e440054d01d2cc5aacd4ab67e87792cd83d10",
    "Kuro/Views/ClubDetailTabComponents.swift": "743c3c0ce043d3d768fc621f9b8bb7f6583174477f7a85b5b8bef96571126fd3",
    "Kuro/Views/ClubDetailView.swift": "24a7b8490e9fc428c6159af8b14485b76612d1cff36f01f30b224eb9939b102e",
    "Kuro/Views/ClubViewLifecycle.swift": "442c35f2356e57391b3ece530985bf8e91bd760cf44c26431b2c330616cfa821",
    "Kuro/Views/ClubsView.swift": "38859bdb76a581ae0515415bf75f7a73ee414d0d075b0d565360a1bcca247703",
    "Kuro/Views/ConciergeAniListImportCoordinator.swift": "44465a739cf93e902cf493b9852b3b01b76005dba9f4c64798786e1415021fbd",
    "Kuro/Views/ConciergeComponents.swift": "08791d5e9f05f5d9da0fd3b875cc6177621e7129c3dc0d18ac969c3d37affe90",
    "Kuro/Views/ConciergeEditorialShell.swift": "c826a848eeb9b84503862f836d86cd3718889134f85bdb1175ba9c07d44afd20",
    "Kuro/Views/ConciergeImportCards.swift": "041b74e7aaef19dfce77ac33830cc53d58b14255b0ed25e27821696eb5aa00dd",
    "Kuro/Views/ConciergeInputField.swift": "936a3b864017c5483a5d43029ec8a7692f1b39b4ad9e4c8f12767686c94ea7b1",
    "Kuro/Views/ConciergeRecommendationRails.swift": "c0618d4f869ff72892e92776e73f796ec20d9044871344cdf878ecffc2b59625",
    "Kuro/Views/ConciergeResponseStage.swift": "1711a66d0ff71657cbe9230c0e5dbe098bdf56bd03794418d819045568630042",
    "Kuro/Views/ConciergeView+AniListImport.swift": "f6ac760e25e481f533d457b7949c6f225997f2a318829a06e415e13bceeb9121",
    "Kuro/Views/ConciergeView.swift": "5e72a020870c7b8762bbe3102ccb94579f31648cc197f5c94edba637cfa7eaa7",
    "Kuro/Views/CountdownTimer.swift": "cd854c8883e9d3d33144dcbbdaf7a411ef73319bf842f0f85d2aa4e0252f0fa4",
    "Kuro/Views/DetailPages/AdaptationPathSection.swift": "189cc1cef2246fb0ed5683a78cc960b70ca4a36ef4f5bc9975b04448b9100ce5",
    "Kuro/Views/DetailPages/AnimeDetailView.swift": "7b1fb133e467f5106b4d2aeab5446e005d9365e70d79bcd5d31ca0bd4784111e",
    "Kuro/Views/DetailPages/CastSection.swift": "9ed4d1c80ae90f0711888aef3936706eac68658adb783a454cce26c8834024bb",
    "Kuro/Views/DetailPages/ClubActivitySection.swift": "4af8d5299302659c4c3521833d0dfcbd816259ce1c000fc93860955eb6172ef5",
    "Kuro/Views/DetailPages/CreditsSection.swift": "4da41dc420455e1e351624501f4c9a2ffdff583679bca53819a24fbc904c8774",
    "Kuro/Views/DetailPages/DetailSharedComponents.swift": "2b95949cac316a976a646be36791fb78562d4c374ed9feabedc353fe264765b0",
    "Kuro/Views/DetailPages/EntityDetailSheets.swift": "33f99acdc29d9f4cebabf4b926b2650ebc3d5bdf84d028188b3abdd948e42d09",
    "Kuro/Views/DetailPages/ExternalLinksSection.swift": "87665ae4a050f569ddb5daad69022cd2f69cc290a203367469ceb0a99fc905dc",
    "Kuro/Views/DetailPages/FriendsActivitySection.swift": "2ab1a4a1d81fc23059c11036f0bebaec6710feb4677cb9aa3a4b97a4c5cfe070",
    "Kuro/Views/DetailPages/MangaDetailView.swift": "eb5221ce42f1ae7e89a9bac876792e73a2cffa769bf9ac49b4acc7aba12d3801",
    "Kuro/Views/DetailPages/MediaDetailSheet.swift": "e0f9be2fa61d32f6ea49fade594a0a1c371f357aeb729344779ea71b1d9f182e",
    "Kuro/Views/DetailPages/ProviderLinkViews.swift": "d7a32ddd6b9f9ec6f05c83d6ebec51afe84023bd72dd79708c0115ec9894e77f",
    "Kuro/Views/DiscoverOneThingCard.swift": "1b87b1e028a80191fccbd459880d788573b2b44dafc3c3b84e3b7845be5382f2",
    "Kuro/Views/DiscoverViewModel.swift": "e54df130efec328725af80035a86dd3f926000259d9da693f02dbc29993fef1d",
    "Kuro/Views/EditorialCollectionComponents.swift": "b753f09dee6ca9919b4d469a000ac20aae98883ac3782e08db29adc802c6a4aa",
    "Kuro/Views/EditorialCollectionView.swift": "c303047d76f42a341a895c612cb40b6381e89940c737da31e791c8868c1a7d1c",
    "Kuro/Views/EditorialDiscoverRouting.swift": "f0f216efcdbbf3b52453f6ae9a334a5bfe72d7780f7666a1f480553c38cce3fa",
    "Kuro/Views/EditorialDiscoverView.swift": "a9660d241a469ceff266ead314e1de52190a0bb30c5e731cd7bcfd0d418c4ab4",
    "Kuro/Views/EditorialSearchView.swift": "f70e2df86415914f8cf494ce9f05290d54256c873520f70f8bc0d96b61dc5e5b",
    "Kuro/Views/GenreHubView.swift": "6f7ab9dd68a4252029bfbb0db9b42be82a8a0ccb1dbe5fd35d369c412b9288b6",
    "Kuro/Views/KuroCachedAsyncImage.swift": "5eef08d45394621b661ccf20f9a0cde572d9682ab0bba00d308f3f56e7b5cb4a",
    "Kuro/Views/KuroCardText.swift": "7ef15b7832e98f52ad3b6097c49244d6601a9f12282687900d7a7d5e1ecc464f",
    "Kuro/Views/KuroConciergeMark.swift": "43ce9b6a94113089fdb8683e3966fce5e7b692d8bf25b734efde1a5fffe0c7e8",
    "Kuro/Views/KuroDeliberateTap.swift": "cd26d3133cda097791911755dad0d3d074c070238242f20ccd4515618ced7c5b",
    "Kuro/Views/KuroGestureCoordinator.swift": "922023644bfd75709e4f23c1e463b627b4c5b587e30afa2ef570ebc49195a65a",
    "Kuro/Views/KuroGesturePolicy.swift": "865bef0167f78d800a321ed5c936f794d22e1fd853379188f89dd944c30811bc",
    "Kuro/Views/KuroGlass.swift": "90df69e46c578979b00e5f1d9a17a21dc3661724b49b7facab640f6b489aebf5",
    "Kuro/Views/KuroInteractionEnvironment.swift": "ac5126a97fd3c023a560b8d07b2bc2dc9f6b9291cded3d35ec2ab165582802e7",
    "Kuro/Views/KuroLoadMoreSentinel.swift": "09e3c8cf3139b5fa13c79b23c5ba08d2bc4eb681ff6c700385c4c60e91e26468",
    "Kuro/Views/KuroPagingGesture.swift": "8198cc17ac8bd1b61e17d1138adacf6770f906e9add977dfc9f1056dc8dc5774",
    "Kuro/Views/KuroRefinedCard.swift": "ecf9c5f15a2c66c822b916b9c7efb14d805b0c749798c114ebacd1c0a69d9c80",
    "Kuro/Views/KuroToast.swift": "de1ae5cfd213e36182a9ffc8f4adda4b4332b5b1ebc0a519d58c38e9a753a4df",
    "Kuro/Views/KuroTransientBanner.swift": "136aff540d0ac235d3a958c63395cb1df362254a8520d0278c368eda675c8f70",
    "Kuro/Views/LibraryViewActions.swift": "b496ffe1e2b944033a53ed8246681df6e99aa11bf0947080e73d055f8b8f8511",
    "Kuro/Views/OnboardingView.swift": "27dfc21f7965c5b5bf684d9c1b8405754d92dba99370a7e946edf8ed66aea2be",
    "Kuro/Views/ProfileFreshnessCard.swift": "f2aab9f6164addc092c7522982a5e66b1043430bedf95436bae6f44065220fca",
    "Kuro/Views/ProfileView.swift": "162e4295bea320c52a1d35cc393c812db64205dc160adea9c0e652214cc5dfab",
    "Kuro/Views/QuickVerdictActionCard.swift": "becc5a918cd081c7cb105ca544ee50e878d17ebe481f1b29937319d60b2c2058",
    "Kuro/Views/Routing/KuroRoutes.swift": "d4250004c6f5c353409eb4bc2a68aa65439a07aec60b8b96e3ce343eca0f6b47",
    "Kuro/Views/SharedCards/AddToClubRailSheet.swift": "adf5a31597cc46c69c9dc0a4d8cfb32c6ebece824d8f888d312179c26d4cd3f8",
    "Kuro/Views/SharedCards/CompactAnimeCard.swift": "2e7f8c5324d7b685bdf6f9b5edc015257a40b889eb4513322809df5c498271aa",
    "Kuro/Views/SharedCards/GridAnimeCard.swift": "6d81830862987d3ca94bb48ced37f12e3e6f2acdeeff31cc0ef13ba88559262a",
    "Kuro/Views/TasteDeckView.swift": "4da7d72f42e9e9c625eb17c0fbb7f17092661e7ce79b4e2393436a930c610151",
    "Kuro/Views/TastePicksView.swift": "a7882f2d5f5b85b099dd6a62f8df3246c198a3952863640a894018c9efbe867a",
    "Kuro/Views/TrackingDraft.swift": "d46164693a00e2427b24704fa2a29c7afa074c80d28c7806924846d1ca3b9017",
    "Packages/KuroModules/Sources/KuroCore/AccountScopedLoads.swift": "7927b989ff46debc183e63f66d3d609331255358fb026cfc559cd439c6914196",
    "Packages/KuroModules/Sources/KuroCore/AccountSession.swift": "19844b6b73dc612fb3c15e77ec0fa7a992ae4cd0172ebbcff0daf261ca0d4c17",
    "Packages/KuroModules/Sources/KuroCore/MediaKey.swift": "3cf12d6871c8ca0b4b8a688012d5cdc1b9dd59db2d369b29eb67e8f2987dc388",
    "Packages/KuroModules/Sources/KuroLibrary/LibraryContracts.swift": "6e39de0e244b3bc72ea2af4143ea660a4744f1b486362d4a1f195709b8c4b3a3",
    "Packages/KuroModules/Sources/KuroLibrary/LibraryStore.swift": "a0aaa025d8df1db856c3faaf6398ec50e19e4b76a5bfabe9bb21e3afbb737d53",
    "Packages/KuroModules/Sources/KuroLibrary/LibraryValues.swift": "6e8f76c138fbc290775ce792e08535eba0122724d1d6e175f4a3d6107ac1e901",
    "Packages/KuroModules/Sources/KuroSupabase/LibraryRowTransport.swift": "335556aea52d70661166f41ff38d168ac852e220076925d58dc38f9e7b7db4e3",
    "Packages/KuroModules/Sources/KuroSupabase/SupabaseLibraryBackend.swift": "b68d886a7cc5cb4eacac4bf7d7d61f1faf014a4cebcb0d80f9afaff0771ef2f8",
    "Packages/KuroModules/Sources/KuroSupabase/UserIdText.swift": "5cb5aca852624a3cf47a566fd69a3c749bc7f23e36e674ac6c3aba5f3c6c7ca3",
    "supabase/functions/_shared/normalization.ts": "4551526eacbf7eb1a1abb5bbb21012c35b6d0fcf2f0689b9263b2712bf6a9398",
    "supabase/functions/_shared/test_fake_supabase.ts": "9085a04567cefb61b554422ca707930c63d8ebf17c88ec0d8ab8cd1bf6271e7f",
    "supabase/functions/auth-callback/index.ts": "bc718486267943a763e1753266d9fd4061de73f32146d29530e8ab220bf0fa4f",
    "supabase/functions/bulk-import-anime/index.ts": "31f2703c2fc0f46c3cc753872a0883281d9e9402d0a628d5bda4ee07bb8571ba",
    "supabase/functions/bulk-import-manga/index.ts": "43b01aadad8a744bff1bed8b337836578aad538453b38fcd2c9bc991c4dd3e4f",
    "supabase/functions/concierge-apply/apply_plan.ts": "67c7d6caa56fc66e2c2f3423fbe125c841c2260c5813752c3c6f2a8d65270f32",
    "supabase/functions/concierge-apply/handler.ts": "68546bec1791976b41f000b3ff58f06ed6a13c87871d86caa2bf8dc70970b463",
    "supabase/functions/concierge-apply/handler_test.ts": "136e8a82f8ab6173513df736e12fdbdaa28c1b4e8d334fbc5a44c65e3a6c1d85",
    "supabase/functions/concierge-apply/index.ts": "8c902283f4d471291edbc76bc811786a77c68e2870084b897c296c25e6f96bec",
    "supabase/functions/concierge-import-anilist/index.ts": "aebf8b0281a85c144f4da234fe8ba7f28e9cb9c0ad667662e584f68d8e5f4f35",
    "supabase/functions/concierge-parse/index.ts": "fa40a78fb7fba3b7b739e8331c1bf9e549bbb54b9e507d2eac385111c4d9381d",
    "supabase/functions/concierge-parse/rules.ts": "243e24d7563a075be415b0f611ed36ec6ac45d2ee7912710a26389dd3dff9458",
    "supabase/functions/concierge-parse/rules_corpus_test.ts": "4a7b87c23902fd57e2e3433738b7facc25817683a58cbcf71421bf32d6ed5215",
    "supabase/functions/concierge-recommend/index.ts": "321bebc2458f7e1a71e496ef1e9132b82b27626b8998948129bc4b3ab051865f",
    "supabase/functions/concierge-recommend/router.ts": "94270ebe646c1ff5ed6334871e123e03330219344ea72acb9724b10e95d0e261",
    "supabase/functions/concierge-recommend/router_corpus_test.ts": "3b5ef6a96fad2abf46097d6e5a4765967af002315620342c1d425a2c9ba4857a",
    "supabase/functions/concierge-recommend/router_test.ts": "9e0bde4e4e227920133d5b19ba5da6350596a3f28ae8088c55d0370a6ee69e41",
    "supabase/functions/concierge-recommend/router_test_support.ts": "c3c1f0941c871a87352ccae69b6552005386064067ba9c7e5b6495c1274cf80a",
    "supabase/functions/concierge-resolve/index.ts": "8d5856b03680a1aade85cf7151d18bc7f1ea7d86f7dcb8667d2e4c9c2e56c035",
    "supabase/functions/concierge-retrieve-assist/index.ts": "5d1b270212cf82ecddd7cf41da52514bc0bbf9d5b98007ea4cb2557b130438a1",
    "supabase/functions/concierge-retrieve-feedback/index.ts": "af977aa6edb86a669b7b6fdef0b39c441f68d753ca6c26e8ef1470640b3d6729",
    "supabase/functions/concierge-undo/handler.ts": "41a5e60f9fdb3740b53c3c6049d7e27a8565e713f7b0b5159f264b13295e52d1",
    "supabase/functions/concierge-undo/handler_test.ts": "97208cc456d8e29a35fd808c6aaf898fde20977aae0d24f12c07a26f8bcf092a",
    "supabase/functions/concierge-undo/index.ts": "7dfe2be911aaf3582d4a1e8a5654333b4eea1766c352d4a02182a6efa2db6bd0",
    "supabase/functions/concierge-undo/undo_plan.ts": "a1a2e84510ddec5b5489564e11179e641253735f0c29937f0ef1dd5e17db7f17",
    "supabase/functions/delete-account/adapters.ts": "3ef7184b761a0e67b322855cca8e131ac3b61fa6f907ffc30f371e847682bdf2",
    "supabase/functions/delete-account/deletion.ts": "bf6c0836bb0bb395972b2c805707d96d16d42106d2681cd435cedf0a40e55cce",
    "supabase/functions/delete-account/deletion_test.ts": "1c1127b65d5496fe7a83bcd1db8d4fbd5c0b9d93605e882f6568014ceeded215",
    "supabase/functions/delete-account/fake_backend.ts": "0acee652d1a0c3ec746f3f515c9df460d0b3451c10e02b1ce03c64c660fd9854",
    "supabase/functions/delete-account/handler.ts": "cc4a0c800b302efb38e3eb8c69eecef39e2bec12ec958f4abee809c59c9d791f",
    "supabase/functions/delete-account/handler_test.ts": "b9cd80038dfd143c2332d2eae5fe0de5f1ab335fefa53ce856290303bf0bcaa9",
    "supabase/functions/delete-account/index.ts": "b96437247b724f89347f4209c8fbbcb78fa05f39d2069c3116bdde6313c09659",
    "supabase/functions/delete-account/real_client_shapes.ts": "e8f7bb8d34e300ab9ab3aa78c4880a70be50e672d828c136a21e37310d30b3c9",
    "supabase/functions/manga-chapter-enrich/index.ts": "fc1c94f9cb7cbbbf918036d7b1f4ffae3e3da874ebb9369a3d3fdae1d400e7cf",
    "supabase/functions/manga-source-review-action/index.ts": "f53bff131c510a6aadeaaae0f01e0f99654ae808d9524f6136dbdc33a6e62d0f",
    "supabase/functions/mirror-images/index.ts": "2d8a20619ecaa66ddb95e0c6d2afc644f2f0cb0daaf3f2055dbec12f8e882b6b",
    "supabase/functions/realm-describe/index.ts": "1891ea64bce984ba0e3ac37b3eb0445d3c22a44cbcf16cb5fe91bab007b98f5e"
  }
}

END EMBEDDED FILE: evidence/source-digests.json


BEGIN EMBEDDED FILE: evidence/undo-reproductions.jsonl
SHA256: 9e905568e10d8e6c9769d3236aa5c8233a4283b1e5dde213d8ffc492373c17dd

{"scenario":"later-rating","conflicts":[],"beforeUndo":[{"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"WATCHING","progress":5,"rating":10,"notes":"original","verdict":null}],"afterUndo":[{"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"WATCHING","progress":3,"rating":8,"notes":"original","verdict":null}],"result":{"success":true,"sessionId":"import_sessions-1","reverted":[{"mediaType":"ANIME","mediaId":7,"undoType":"restored"}],"warnings":[],"errors":[]}}
{"scenario":"conflicted-item","conflicts":[{"mediaType":"ANIME","mediaId":7,"error":"State changed since parse — review and retry"}],"beforeUndo":[{"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"WATCHING","progress":6,"rating":8,"notes":"original","verdict":null}],"afterUndo":[{"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"WATCHING","progress":6,"rating":8,"notes":"original","verdict":null}],"result":{"error":"No applied session to undo"}}
{"scenario":"deleted-after-import","conflicts":[],"beforeUndo":[],"afterUndo":[{"notes":null,"verdict":null,"user_id":"11111111-1111-4111-8111-111111111111","anime_id":7,"list_type":"WATCHING","progress":3,"rating":8}],"result":{"success":true,"sessionId":"import_sessions-1","reverted":[{"mediaType":"ANIME","mediaId":7,"undoType":"restored"}],"warnings":[],"errors":[]}}

END EMBEDDED FILE: evidence/undo-reproductions.jsonl

END OF COMPLETE COPY-AND-PASTE HANDOFF
