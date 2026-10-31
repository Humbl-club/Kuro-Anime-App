# Kuro modular architecture — Claude Code execution brief

## 1. Starting prompt

Copy the following prompt into Claude Code in the Kuro repository. The remaining sections are its execution contract.

```text
Fully execute docs/plans/2026-10-05-modular-architecture-plan.md in this checkout. Implement the modular architecture, integrate the real consumers, fix the specified account-lifecycle defects, and satisfy its success gates. Do not stop at an audit, a suggested plan, scaffolding, or the first successful extraction.

You have autonomy for the local code, contract, package, test, and documentation changes required by this brief. This explicitly authorizes the architectural pattern changes and related refactors described here. Preserve SwiftUI, @Observable, Supabase, the selected visual designs, existing supported behavior, provider identity, feature-flag semantics, and operational compatibility. Read AGENTS.md, CLAUDE.md, the current-state documents, and the active Home/detail master specification before changing their related areas. Preserve unrelated dirty and untracked work. Treat historical logs and older plan appendices as history, not current instructions.

Use multiple specialist sub-agents with distinct responsibilities. The lead owns sequencing, contracts, shared-file edits, integration, documentation, and final acceptance. Keep at most five agents active including the lead; use fewer when work is dependent. At least one reviewer must be independent of the production implementation being reviewed. Assign exclusive file ownership before parallel edits. Agents must return changed paths, contract changes, actual checks, unresolved findings, and handoff dependencies. Their claims are leads until the lead checks the integrated source and evidence.

Start by establishing the exact source snapshot and a safe verification path. Reproduce and repair account-transition failures in place before distributing state across modules. Then establish the complete ownership and caller map, define the required contracts, extract Library through a real journey, and complete the remaining native, backend, and active operational boundaries. Decide target count from demonstrated ownership and isolation needs; do not instantiate a target for every folder or screen.

Use the priority weights in section 2 for trade-offs. Mandatory gates cannot be traded away or overridden by a score. Apply the test matrix in section 3: reuse meaningful tests, add the smallest tests that expose important failures, test production rules rather than copied implementations, and run affected checks as a slice changes. Run the integrated verification set once on the final source. Repeat checks only when a change or unresolved failure invalidates their evidence. Do not add exhaustive coverage targets, redundant test layers, arbitrary sleeps, generic frameworks, or layout-only rewrites.

Complete every required stage in section 6. Keep a concise execution ledger with source identity, state ownership, interface decisions, integrated consumers, exact gate results, and genuine blockers. A moved file is not an integrated module. No dual writes or second authoritative state copies are allowed. Retire SupabaseService only after its final consumer migrates.

Continue autonomously through routine implementation choices, reversible repairs, and local verification. Production deployment, production data mutation, new paid infrastructure, credential changes, external communication, and destruction of unrelated work remain approval boundaries under project rules. Prepare reviewable changes and concrete commands before requesting such approval. Never substitute production for a missing test environment. If a prerequisite is unavailable, complete independent work, record the precise blocker and prepared recovery path, and keep its gate open.

This brief executes the architecture of current application capabilities. The Home/detail master remains authoritative for its separately authorized product work. Shape Library for its durable-sync contract, but do not silently commission the entire Home redesign or report its offline/product/capacity gates passed by architectural extraction. Required architecture work cannot be deferred solely to finish early; low-value proposed splits may be rejected with evidence while their capability still meets every ownership and behavior gate.

Finish with the completed ownership map, integrated changes, independent review results, exact test results, remaining environment or release gaps, and a concise developer guide for adding or removing a capability. Claim complete only when all applicable gates pass on the integrated source. Otherwise state precisely what remains incomplete. Do not include effort estimates, schedules, or delivery deadlines.
```

**Status:** Executed locally (2026-10-05; uncommitted, nothing deployed); see the [execution ledger](2026-10-05-modular-architecture-execution-ledger.md) for gate status and open items. This brief does not record any gate as passed; only the ledger records gate results. Deployment, device, hosted and capacity results are not established by this execution.

**Authority:** This replaces the earlier architecture execution order and effort assessment. The [Home/detail master specification](2026-10-02-series-and-home-rebuild-DRAFT.md), active v1.1 at preparation, retains its two product delivery waves and its own acceptance requirements. Revalidate the active version at execution. This brief does not replace product decisions or authorize a release.

## 2. Priority weights and success parameters

### Decision weights

The weights govern which problem to solve first and which implementation to choose. They are not staffing percentages, self-awarded acceptance points, or a way to compensate for failed tests. Follow prerequisite order even when a dependent task has a higher weight.

| Priority | Weight | What earns priority | What does not |
| --- | ---: | --- | --- |
| Correctness, account isolation and privacy | 35% | Eliminate stale-account publication, conflicting authority, unsafe deletion, broken permission lifecycle and mutation errors | Moving the same defects into new files; relying on client checks instead of RLS |
| Maintainability and ownership | 25% | One clear capability owner, narrow interfaces, understandable state lifetime, independently changeable implementations | More directories, a compulsory target count, or an equally broad replacement service |
| Behavior and contract compatibility | 20% | Preserve tracking fields, navigation, selected appearance, import safeguards, provider identity, flags and active jobs | Unrequested redesign or changed behavior disguised as structural extraction |
| Verification quality | 10% | Deterministic tests that catch real failures and integrated checks of the actual production path | Coverage percentages, duplicated router logic, always-true assertions or repeated green suites |
| Simplicity and execution efficiency | 10% | Direct composition, reusable existing seams, small diffs, safe parallel work and removal of redundant indirection | Generic registries, service locators, global event buses, empty targets or speculative frameworks |
| Total | 100% | Correct behavior with clear ownership and proportionate machinery | A numerical architecture grade |

When alternatives both satisfy the hard gates, prefer the one that requires less unrelated knowledge, fewer independent state copies, fewer dependency hops, and less maintenance. Add an abstraction only when it protects a real invariant, isolates an external dependency, serves actual consumers, or enables a necessary failure test. The reviewer must be able to name that benefit.

### Mandatory success gates

All applicable gates must pass. These are binary evidence requirements, not weighted scores. Missing environment evidence is BLOCKED, not a pass or an excluded test. Each stage lists the gates it advances; final completion requires all gates.

| Gate | Required result | Evidence |
| --- | --- | --- |
| G0 — Source preservation and reproducibility | Exact commit plus dirty/untracked snapshot recorded; unrelated work preserved; test setup targets a disposable local or approved non-production environment | Scoped diff, file digests, target identity and runnable commands without logged credentials |
| G1 — Account and permission lifecycle | Every private store, task, cache, subscription and persisted preference has a lifecycle owner; obsolete account/permission work cannot publish, send or resurrect private state | Controlled delayed-response tests, account A/B transitions, cleanup assertions and applicable database authorization tests |
| G2 — One write and projection authority | One execution owner per mutation; one authoritative local tracking projection; no dual writes or independent legacy copy | Caller/write map, consumer migration, mutation tests and independent inspection |
| G3 — Complete architectural ownership | 100% of current production paths, service methods and mutable state mapped; zero unowned paths; zero dependency cycles or forbidden feature-internal access; capability boundaries expose no SDK payloads | Ownership manifest, compiler checks, targeted source checks and reviewed exceptions for deliberate infrastructure access |
| G4 — Compatibility and actual integration | All migrated consumers use the new owners; typed identity, supported fields, routes, flags, visual tokens, import semantics and operational entrypoints preserved or explicitly corrected | Contract examples, real adapter checks, focused native journeys and operational compatibility checks |
| G5 — Meaningful verification | Required checks pass against the integrated source; each new test covers a named failure; no known blocking defect in scope; independent reviewer resolves findings | Test-to-risk matrix, command results, final source identity and findings disposition |
| G6 — Proportionate design | Every compiled target and new major abstraction has a demonstrated purpose; large files receive semantic review; no mechanical split or speculative framework needed for acceptance | Short keep/split decisions and reviewer walkthrough of representative workflows |
| G7 — Retirement and handoff | No live SupabaseService facade, feature references to that service, feature-owned raw queries, or competing state copies; canonical docs and developer instructions match the code | Final reference search, capability map, relevant project gates and documented add/remove procedure |

An out-of-scope pre-existing issue may remain explicitly listed; it cannot excuse a failure of an applicable gate or a regression caused by this migration. A safety defect discovered in a migrated capability is in scope. A substantial unrelated product change needs separate authority. Architecture completion, product completion and production release remain separate statements.

## 3. Correct tests without over-testing

### Test selection rule

For each change, identify the invariant that could break, choose its cheapest faithful test, and reuse existing coverage. Add a higher-level test only when a lower-level test cannot establish the result. Do not write tests for private helper layout, plain getters, constants, trivial delegation or unchanged low-risk presentation extraction.

A new regression test should fail for the original defect where reproducible, and pass for the repair. Tests for newly introduced contracts should reject the relevant malformed or conflicting case. Use controlled response completion, injected clocks and explicit synchronization instead of arbitrary sleeps. Parameterize genuine variants rather than copying tests.

Fakes model external outcomes; they do not reimplement the policy under test. Extract/import the production router and parser rules instead of maintaining a second test-only copy. Corpus validation and corpus execution are different checks. Reuse existing corpora as parameterized production-rule cases; report intentional behavior changes explicitly.

### Required risk-to-test matrix

The entries describe scenarios, not a quota of test functions. Several can share a focused parameterized test. Reuse existing valid tests rather than writing replacements merely to obtain new filenames.

| Risk / change | Smallest sufficient check | Success parameter |
| --- | --- | --- |
| Stale account fetch | Controlled A request, end A session, begin B, then complete A; parameterize successful and failed completions | A cannot change B data, lookups, error/loading state or active handles; B starts its own work |
| Derived state and private caches | Seed each inventoried private category, transition session, inspect reset/scoping; test one integration route using the inventory | No prior-account entry, badge, club projection, preference or private cache is read as B state |
| Obsolete task cleanup | Replace an in-flight handle, complete its predecessor, then inspect and complete its successor | Old completion cannot clear or cancel the new handle |
| Session entry points | Table-driven restore/sign-in/callback/sign-out/deletion transition tests | All paths use the same lifecycle policy; same-account token refresh does not unnecessarily erase state |
| Subscriptions and local reminders | Controlled subscription/notification delivery seam plus teardown/remount scenario | Private listeners stop; late events are rejected; prior-account reminders are removed or explicitly scoped |
| Deletion cleanup | Handler tests with returned cleanup errors, followed by safe database integration for relevant relations/roles | Required cleanup failure cannot return success; retries are safe; local SDK session cleanup is verified |
| Library fields and identity | Existing mapping/decoding tests plus targeted mutation cases for anime/manga with equal numeric IDs, status, rating, progress, notes and verdict | Correct target and scale; progress intent does not overwrite unrelated fields; remove/Undo semantics stay explicit |
| Mutation sequencing | Controlled overlapping writes and refreshes through the real coordinator | One writer; stale refresh cannot replace newer accepted state; errors retain actionable state |
| Adapter compatibility | Execute the real adapter against controlled transport responses or a local service boundary | Request fields, auth ownership, null/optional values, errors and responses match the declared contract |
| RLS and revocation | Real PostgreSQL/Supabase tests under authenticated owner, another member, outsider and revoked member; include pending response/event scenario | Allowed operations succeed; denied access remains denied after revocation; private cached presentation is invalidated |
| Imports and assistant rules | Production rules executed against relevant existing corpus/fixtures; focused preview/apply/Undo integration | No wrong adaptation, duplicate authoritative write, changed auto-apply threshold, lost field or unsafe Undo |
| Catalog and paging | Existing tests plus boundary/cursor/medium cases where mappings or paging move | No target confusion, duplicate/missing pages, ancillary-format regression or guessed relation identity |
| Shared UI and navigation | One representative integrated save/detail/club route per distinct wiring pattern; selective visual check of affected layouts | Correct target, preserved controls/focus/selection and unchanged approved composition |
| Taste and device intelligence | Relevant decoding/rule tests; controlled cancellation/retry if ownership changes; existing FM stub | Signals are not duplicated or assigned to a new account; non-FM fallback remains usable |
| Packages and build settings | Compile/test first real extraction and final integrated app; inspect explicit imports, isolation, resources and access control | No accidental isolation change, duplicate compilation, broken app resources or SDK leakage |
| Edge/worker extraction | Production pure-rule tests and one representative handler/run through controlled provider/storage boundaries | Stable response/entrypoint, auth, idempotency, cursor/checkpoint, lock and report behavior |
| Request/subscription regression | Count actual calls for representative cold/warm load, mutation and remount using transport instrumentation | No unexplained increase over the pinned baseline; no duplicate client, unbounded refetch or repeated subscription |

Tests using fake permissions do not prove RLS. Tests using in-memory stores do not prove durable restart behavior. Package unit tests do not prove native gesture behavior. Maintain these distinctions in the evidence ledger.

### Run policy

1. Establish the relevant baseline once before changing that capability. Separate existing failures from new ones.
2. During a slice, run its focused tests and affected target build. Sharing a test result requires the same tested source and configuration.
3. After integration, run the affected integration check. Agent-local results alone cannot qualify the merged source.
4. On the final integrated tree, run the existing unit suite, selected meaningful UI journeys and all required applicable repository gates. A build-and-test invocation can supply build evidence; avoid a redundant identical build. Use the project-supported iPhone 17 Pro destination or documented generic fallback.
5. Run the qualified database/handler checks for changed backend and privacy boundaries. Run structural checks once on the final tree, then only for invalidated evidence after repairs.
6. Repeat a broader suite only for a new shared-contract change, failure, cross-capability concern or invalidated final source. A new production change after final checks requires the corresponding checks again.

The lead schedules checks; agents do not each run the entire app suite. An independent reviewer inspects evidence and reproduces disputed or high-risk results, not every already-settled command. One review cycle per integrated slice is sufficient unless its fixes introduce new relevant changes.

Inspect gate scripts before running them. Preserve mandatory repository checks; make the docs inventory package-aware before moving source. Repair misleading router/corpus checks so their names accurately state what they verify. Select relevant UI tests rather than the entire historical sleep-based collection. Do not silently disable failing checks or use a production-backed UI run as the safe test baseline.

### Verification environment

Use an available disposable local Supabase stack where practical; otherwise use an already approved non-production equivalent that supplies the required database roles, auth behavior and extensions. Check in minimal configuration, fixtures and reset/run commands, with no credentials. Validate project identity before any migration, seed, deletion or test write. Test entrypoints must reject the production project and unrecognized targets, including production overrides through environment variables.

Rehearse required schema changes against the disposable schema. If historical replay is broken, report that result; use a documented audited schema fixture only for the bounded tests it honestly supports. Never rewrite applied migrations to obtain a green test environment, and do not describe fixture execution as complete migration replay. Production migration rehearsal remains a separate unsatisfied gate when replay is not established.

Use the actual database authorization path, not a service-role client for tests of user access. Provider access, storage and SDK behavior may have controlled seams; label those checks accordingly. New paid services, global tooling changes or provisioning are not automatic workarounds for unavailable local prerequisites.

## 4. Scope, source evidence and ownership

### Scope of full execution

Complete the architectural ownership, interface and integration work for every current production capability: Identity, Catalog/discovery/search, Library, Releases/reminders, Clubs, SocialActivity, provider availability/preferences, Recommendations/Taste, Concierge/Imports, runtime flags/configuration, telemetry/device intelligence, edge functions, and active operational workers. Review all production paths; deeply change the ones whose actual ownership or behavior fails the gates.

Full execution does not mean rewriting every file. A cohesive implementation can remain after an evidence-backed keep decision, provided it has a named owner, legal dependencies, a real entrypoint and the required tests. An unresolved required ownership split stays open. Historical scripts, unused experiments, archived designs and applied migrations receive classification and navigation, not automatic rewrites.

Library must expose a contract compatible with the master specification's revisions, receipts, field ownership, durable projection/outbox, absolute intent, Undo and conflict outcomes. RPC names in that specification are proposed; those behaviors are requirements for its product delivery. Do not invent a competing sync design or freeze unsafe full-row upserts as the final progress contract. Implement related correctness repairs here; track unimplemented new product behaviors in the product ledger. Do not claim durable offline support until its actual persistence and server requirements pass.

Current Home is a future product consumer, not an existing pager screen to fabricate during this migration. Integrate existing Collection, detail, save, import and reminder consumers. If authorized product work runs alongside the migration, reuse the same Library and identity contracts and evidence; retain the product master’s existing two-wave sequence.

### Preparation snapshot — revalidate at execution

Recorded HEAD: `471c609943d2374c6dda940aebdfde2fcb077d50`. The source baseline includes dirty and nonignored untracked files. The [baseline JSON](2026-10-05-modularity-baseline.json) is historical local evidence, not a claim that HEAD alone contains those files.

| Group | Files | Physical lines |
| --- | ---: | ---: |
| Native Swift, current working tree | 94 | 46,537 |
| Native Swift, HEAD | 93 | 46,331 |
| Native test Swift | 4 | 1,785 |
| Edge TypeScript, including shared code | 17 | 11,659 |
| SQL migration history | 235 | 62,863 |
| Operational scripts, including legacy | 90 | 20,753 |
| Browser prototype source, including archive | 47 | 3,089 |

The SupabaseService family totals 7,154 lines across 13 files. Textual service references occur in 50 Swift files/259 occurrences; environment declarations occur in 30 files/61 occurrences; FeatureFlags.shared occurs in 18 files/69 occurrences. These are different source metrics, not runtime request counts. Existing source compiles into one production application target without local internal packages.

Known source concerns to reproduce: unchecked account-context publication in user-list fetches; derived/private state left by reset; user-dependent Discover cache without account key; separate club realtime teardown; callback/session transition divergence; unchecked deletion results. Runtime and deployed incidents have not been demonstrated by this planning initiative.

Reuse the existing call registers under `docs/research/2026-09-26-kuro-plan/evidence/` and the product master's inventory when helpful, validating against current source. Do not recreate a second disconnected database/call audit. The ownership map must also cover stored state and lifetimes, which a call register alone cannot establish.

### Ownership inventory fields

One compact JSON/CSV manifest and one human-readable map are sufficient. Record capability, source paths/entrypoint, concrete state/write owner, exported reader/writer contracts, current callers, dependencies, relevant tables/RPCs/edge functions/jobs, private/public cache scope, tasks/subscriptions/persistence, account/permission invalidation, focused checks, and integration status. Track SQL functions by schema plus signature and latest effective definition, not name alone; include permissions and dependencies. Preserve one chronological migration history.

| Current responsibility | Intended capability owner | Key separation |
| --- | --- | --- |
| Auth and bootstrap in main service | Identity/session coordinator + auth adapter | SDK credentials versus observable identity/lifecycle |
| List models, mutations and lookup caches | Library + list adapter | One tracking projection/writer; typed field intents |
| Collection card paging | Collection query/composition + Catalog contracts and Library projection | Public catalog presentation versus user tracking authority |
| Detail models, credits, relations and ladder | Catalog + catalog adapter | Public cache, stable provider IDs and sourced relation evidence |
| Discover/+Discover, Browse, Search | Discovery/catalog query owners + their screen models | Editorial/personalized queries, cursors, cancellation and private result caching |
| Upcoming reads and notifications in +UserLists | Releases + notification delivery | Schedule truth/reminder intent versus device scheduling |
| +Clubs and +ClubRealtime | Clubs + private subscription adapter | Move credits/ladder methods out of club ownership |
| +Social | SocialActivity, sharing narrow club-authorization contracts | Comments/reactions/friend counts and permission-scoped caches |
| +Streaming | ProviderAvailability + preference owner/adapter | Public provider registry versus private user and club preferences |
| +Recommendations and +Taste | Recommendations/Taste + adapters and screen coordinator | Ranking/profile/realm contracts versus deck gestures and signal delivery |
| +Concierge and import UI | Imports/Concierge + adapters | Preview/reconcile/apply/Undo decisions versus rendering and SDK responses |
| +Monetization | Outbound-link telemetry | Existing logging does not imply a new StoreKit/paywall capability |
| FeatureFlags, AppConfig, network and clock | Runtime configuration interfaces + live implementations | Injected access; retain rollout and debug override behavior |
| Images, public disk detail cache, visual tokens | Image/cache infrastructure and DesignSystem | Resource scope, actor isolation and public-data lifetimes |
| AppleFMService | DeviceIntelligence through existing FMProvider seam | Existing availability guards and graceful fallback |
| Edge handlers, provider jobs, active workers | Their named backend capability owners | Auth/transport versus policies, storage/provider access and run coordination |

Extension filenames are not ownership evidence. Read full implementations and callers; +Clubs and +UserLists contain responsibilities from other capabilities.

## 5. Modules, interfaces and maintainability rules

### Start small, finish complete

Establish logical ownership inside the existing application first where it avoids needless risk. Once lifecycle and the first real Library contracts are stable, introduce one local Swift package with a small set of meaningful targets. Expand or consolidate only for an independently owned lifecycle, real consumers, platform separation, test isolation or useful compiler enforcement. Every target needs that rationale; there is no target-count quota.

A possible initial set is shared identity/value contracts, Library, designated Supabase adapters, platform implementations, and pure design primitives. This is an example, not a final manifest. Do not collect all business state into a new KuroCore or place the entire old service into an unbounded KuroSupabase target. If several related adapters share a target, keep their owners and interfaces distinct; split compilation when consumers or isolation justify it.

Domains use Foundation/Observation and approved nonpresentation dependencies; they do not import SwiftUI, UIKit, Supabase or feature implementations. The application creates the shared SDK client once, constructs live adapters and coordinators, and injects only the capabilities consumers need. Feature models own loading/selection/presentation snapshots, not a second authoritative Library. Public caches may outlive an account; private projections must not.

Features depend on domain contracts and presentation primitives. Adapters depend on contracts and transport. App composition connects them. Cross-capability dependencies are acyclic and narrow. No service locator, DI framework, generic global refresh bus or protocol that republishes the old service is needed.

### Shared cards, sheets and routes

DesignSystem owns visual tokens and pure components. A connected card is not a design primitive just because it is reused. Presentational cards receive immutable summaries and actions; account/business state is supplied by a feature or reusable domain-aware presentation owner. Keep a connected component in the app during transition until its interface is ready.

Give AddToListSheet a Library-facing presentation owner and narrow reader/writer dependencies, plus a typed catalog summary and connectivity hint. Other consumers present it through an injected action/router or that explicitly reusable UI boundary; they do not import Collection's private implementation. Club actions and provider/friend projections use their own narrow interfaces rather than access to the global service.

Enumerate direct detail/sheet constructors. Convert sibling-feature navigation into typed outputs such as openMedia, openClub and presentTrackingEditor handled by app composition. Local detail sections may remain private to their feature. Extracting a view does not require a compiled module for each row. Route migration is actual stage work, not an assumption.

### Swift build compatibility

Revalidate the toolchain and deployment/platform settings before the first package move. The current app uses MainActor default isolation, Swift language mode 5 and MemberImportVisibility. Package targets do not automatically inherit app settings.

Declare an intentional isolation/language policy for each target. Preserve existing isolation for migrated observable state; use explicit actors or nonisolated Sendable values where the actual work requires them. Review Task.detached captures, shared mutable statics and protocol isolation at the changed boundary. Do not introduce a whole-app Swift-language upgrade as part of extraction.

Use explicit imports for the modules whose declarations/extensions a source file uses. Choose internal/package/public access narrowly: package is for targets in the same package; the Xcode app needs genuinely public entrypoints. Do not make every declaration public to force compilation. Keep supabase-swift resolution compatible; remove direct app product dependencies only as actual consumers migrate.

App metadata remains in the root Info.plist and may correctly use Bundle.main. Package-owned resources need their own explicit bundle lookup. Inject test configuration instead of loading production configuration through a standalone test executable. Check image/assets/localization, target membership and duplicate symbols. Folder-synchronized groups reduce project bookkeeping; they do not establish resource correctness.

### Size and complexity

There are no mandatory source-line caps. File/type/module length, independent lifetimes, branch complexity, dependency breadth and change coupling are review signals. Inspect ordinary handwritten files around 400–600 lines, stateful types around 350–500 aggregated across extensions, and modules around 2,000–3,000 lines, adjusting judgment to the capability. These are prompts, not pass/fail thresholds.

Keep a large cohesive implementation when a reviewer can follow its entrypoint, contracts, state and tests. Split when independent responsibilities, cancellation policies or consumers actually diverge. Do not minify, scatter one owner into extensions, create meaningless wrappers or remove helpful comments to improve counts. Do not add a complexity-analysis framework merely to produce a score.

Record keep or split briefly in the ownership map. Required unresolved splits remain open; low-value proposals may be rejected with rationale. A deferred required split is not completion. Reviewers focus on whether a change is easier to understand and make safely, rather than the number of files created.

### Adding and removing capabilities

The developer guide must show where an entrypoint, contract, implementation, adapter and test live. Adding a feature should require its owned code, necessary contracts and a composition/route registration, without edits across unrelated features. Removing one should require removing its consumers/registration and stopping its owned work, while retaining shared contracts used elsewhere. Removing a feature never authorizes deletion of user data or historical migrations.

Use one root navigation map and concise package/module notes only where setup or ownership needs explanation. Avoid repeating current-state history in every README.

## 6. Full execution order and stage gates

Each stage performs implementation, consumer integration, focused verification, independent review and required documentation. Start the next independent lane when its contracts are stable; do not treat parallel work as permission to skip a dependency. The lead can keep preparatory read-only work moving while a dependent mutation waits.

### E0 — Pin source, partition work and establish verification

- Inspect current HEAD, dirty/untracked paths and active documents; capture digests for touched existing source. Never reset, stash, overwrite or clean unrelated work to obtain a convenient baseline.
- Identify production versus archived/prototype/unused paths, current root composition and all service/flag dependencies. Use the existing registers as a starting point.
- Assign files and interface ownership to agents. Select relevant baseline checks and record pre-existing failures. Inspect test/deployment scripts for effects before execution.
- Establish the smallest safe test configuration and the disposable database path required for backend work. Repair package-aware inventory/test gates before source relocation. Do not run the linked deployment script as setup.
- Start a compact manifest/ledger. At this point only classify changes; do not start wholesale package moves.

**Exit:** G0 passes for the next slice. Controlled lifecycle tests are runnable. Required database setup is runnable or explicitly blocked with a prepared recovery path; the corresponding backend qualification remains open. Agents have disjoint ownership and agreed interface contracts.

### E1 — Repair lifecycle before extracting ownership

- Add a single account-transition coordinator in the current architecture, with an account context carrying user identity and generation. Invalidate previous work before transition suspension points. Compare context before all private publication, including errors, loading state and cleanup.
- Route restore, sign-in, SDK auth events, callbacks, sign-out, failed bootstrap and deletion through that policy. Keep same-user token refresh semantics deliberate. Do not disable legitimate recovery callbacks or claim nonce/PKCE security from an untested assumption.
- Inventory all private arrays and lookup caches, pagination generations/snapshots, Discover personalization, club/friend projections, user/club provider preferences, stored selections, task handles and subscriptions. Clear or scope them explicitly. A small typed list of owned invalidations is sufficient; no generic cache-registration framework is required.
- Cancel account-owned handles and prevent obsolete completions from clearing successors. Include club realtime cleanup and late-event guards; scope or remove account-owned pending notifications.
- Ensure successful deletion clears the SDK's locally persisted session through the supported path, not only visible auth flags. Inspect actual SDK behavior. Check required backend cleanup results; keep deletion retryable/idempotent and auth-user deletion ordered safely. Confirm applicable FK/RLS behavior in the safe database.

**Exit:** G1 passes for lifecycle repairs, supported by the corresponding tests in section 3. Unavailable SDK/database evidence remains an explicit open gate. Lifecycle state ownership can remain in the current service temporarily; it need not move into packages to be tested.

### E2 — Complete ownership and freeze narrow contracts

- Finish the inventory for every current service method, stored property, task, cache, query, mutation and live caller, including SocialActivity, ProviderAvailability and outbound-link telemetry.
- Separate typed MediaKey/provider identity and minimal catalog summaries before extracting Library. Catalog presentation objects are not Library's tracking authority.
- Define LibraryReader/LibraryWriter or equivalently narrow interfaces, typed outcomes and affected-entry invalidation. Specify field ownership, mutation ordering, revisions/receipts where supported, errors, removal and Undo. Align the interface with the active product sync requirements; record which behavior actually exists.
- Assign auth/session, catalog, discovery, releases, clubs, social, provider preferences, imports, recommendations and runtime interfaces. Shared errors may reuse primitives without erasing capability-specific outcomes.
- Enumerate shared save/card dependencies and direct detail-route construction. Confirm every proposed compiled target has actual consumers and a reason.
- Record local request/response examples for changed HTTP/RPC adapters. Reuse contract fixtures for models and tests; use OpenAPI where useful for HTTP and typed SQL/RPC fixtures where appropriate. Postman is optional, not required infrastructure.

**Exit:** G2/G3 have a complete reviewed destination map; no required method or state lacks an owner. Contract examples cover the affected success/failure cases. An independent reviewer confirms the proposed graph, shared UI home and product compatibility before broad consumer changes.

### E3 — Integrate Library through existing consumers

- Create the @Observable Library state owner using established project patterns. Move tracking rules, typed mapping, sequencing and derived lookups with it. Keep backend payloads in the list adapter.
- Migrate Collection, shared save sheets and detail tracking controls through the same writer. Then migrate import apply/Undo reconciliation and other tracking consumers. Cover all inventoried writers, including indirect RPC/import paths; a table-name grep alone is insufficient.
- Replace global list/feed/upcoming refresh coupling with explicit affected-entry/query invalidation. Separate Releases/notification delivery from list persistence. Keep retries and cancellation finite and owned.
- Correct unsafe progress/full-row field coupling deliberately, with contract and regression evidence. Keep source extraction and intentional behavior correction distinguishable in the diff/ledger.
- A temporary legacy facade may forward to the new owner; it may not retain another mutable tracking copy or execute another write. Implement durable product behavior only under its separately authorized scope and existing contract, without a second writer.

**Exit:** G1/G2/G4 pass for tracking. All existing tracking consumers are integrated; no feature writes directly to list tables or bypasses the authoritative mutation interface. Tests verify fields, medium identity, failure and overlapping mutations. Product offline behavior is not claimed without its persistence/server evidence.

### E4 — Introduce useful compilation boundaries and composition

- Move the stable contracts/Library implementation and designated adapters into the justified local package targets. Move low-dependency tokens/platform implementations when their real interfaces are ready.
- Make actor isolation, imports, access control, supported platforms and resources explicit. Repair packaging at this first real extraction before propagating the pattern.
- Centralize live composition and SDK client creation in the app. Inject narrow readers/writers, flags, connectivity and required platform actions into migrated consumers.
- Update package-aware source/docs checks and allowed-import rules. Use SwiftPM/compiler cycle detection; add a custom rule only for a architectural constraint the compiler cannot establish.

**Exit:** G3/G6 pass for the migrated targets; the integrated app and focused tests compile/run with real consumers. No empty target, duplicate model implementation, copied writer or accidental app-setting change remains. This is a demonstrated boundary, not a package of tokens alone.

### E5 — Integrate Catalog, discovery, detail, releases and shared UI

- Extract public Catalog models, provider IDs, sourced relations, credits and cache/query adapters. Move Catalog behavior currently residing in +Clubs/+UserLists to that owner.
- Separate Discover, Browse and Search state, query parameters/cursors and personalized-cache scope. Preserve existing server-backed refinements and ancillary-format behavior.
- Split detail screen composition/state/sections at useful seams while retaining distinct Anime/Manga designs. Keep one documented loading coordinator and bounded section requests.
- Place connected cards and tracking sheets in their reviewed presentation owners; inject projections/actions and convert cross-feature detail constructors to typed routing outputs.
- Extract Releases and notification delivery using existing schedule truth and freshness semantics. Separate public provider availability from private preference/shared-club state.
- Integrate every affected consumer; do not create an unused Home model as proof of wiring.

**Exit:** G1/G3/G4/G6 pass for these capabilities. Catalog identity, paging, save/detail routes, availability notes and reminders are preserved or explicitly corrected. Focused journeys show current approved layout and controls remain usable without extra whole-screen reloads.

### E6 — Integrate Clubs, social, Taste, Concierge and imports

- Give club membership, polls/reactions, bundles and realtime channels explicit owners. Keep permission revocation and account transition connected to private caches and presentation.
- Give comments/friend counts and provider preferences narrow interfaces; avoid hiding their separate lifetimes in a broad club store. Exercise real RLS and revocation under the roles in section 3.
- Separate recommendation/profile/realm transport from Taste's screen/gesture/signal state. Audit realm-describe as an active capability rather than omitting it because other files are longer.
- Move import reconciliation, clarification, preview/apply/Undo decisions out of rendering. Preserve field fidelity, auto-apply safeguards, ambiguity handling and session-local Concierge behavior.
- Reuse FMProvider and non-FM fallback. Keep server narration and classification/routing policy exactly as required by project rules.
- Migrate Profile/auth/settings consumers through the owned interfaces while preserving their approved composition. Fix dependencies without commissioning a visual redesign.

**Exit:** G1–G4 pass for all these consumers. Permissions, pending operations, subscriptions and signal ownership are verified. Assistant tests exercise actual production rules; existing server apply/Undo contracts remain coherent with Library's local projection authority.

### E7 — Complete backend and active operational boundaries

- Build the current SQL function/signature/ownership index once, sharing it with the existing product inventory. Preserve migration order/checksums and record effective grants/RLS/helpers/dependencies.
- Review every current edge capability, including realm-describe. Prioritize behavior needed for safety, real tests and active consumers rather than sorting by file length or treating old code as automatically safe.
- Extract request/auth/validation, pure policy, provider transport, repositories and run orchestration where responsibilities diverge. Keep deployed slugs and external contracts stable. Export testable production rules instead of duplicating them into tests.
- Preserve JWT-derived user identity, rate limits, narration-only server AI, sanitized inputs, idempotency, finite provider concurrency/retries, source-ID matching, unresolved relation evidence, locks/checkpoints and failure results.
- Classify operational wrappers, active workers and archived scripts. Index stable paths by default; move only when a semantic extraction has clear benefit. Preserve launchd labels, report roots, environment lookup, relative paths, locks, dashboard identities and active callers. Keep separate pipelines isolated.
- Add new SQL migrations only for intentional correctness/contract changes; include required RLS and search_path rules. Rehearse in the qualified non-production environment. Keep deployment as a separate approval boundary.

**Exit:** G3/G4/G5/G6 pass for backend/active operations. Handler and worker tests use actual implementations with controlled external boundaries; database tests qualify changed authorization/transactions. All current production paths have either a completed semantic extraction or an evidence-backed cohesive owner. Historical/deployment gaps are accurately listed.

### E8 — Retire legacy authority, qualify and hand off

- Migrate the final consumers and remove the live SupabaseService facade/state owner. Remove obsolete product dependencies and compilation entries only after consumer evidence. Do not delete unrelated untracked work or infer dead code from one grep.
- Verify zero feature references to the retired service, zero feature-owned raw SDK/table queries, no FeatureFlags.shared business dependency in features, no independent tracking store, and no sibling feature-internal imports. Explicitly owned public image/cache/telemetry primitives are not prohibited merely for using static utilities.
- Run the final integrated test set from section 3 and applicable repository gates. Check representative request/subscription counts and actual screen/adapter integration. Record the source identity tested.
- Assign an independent reviewer who did not implement the production changes. Review all changed contracts, lifecycle, consumer integration and test realism; sample cohesive keep decisions. Resolve blockers and recheck only invalidated evidence.
- Finish the ownership/navigation guide and required current-state/implementation/memory updates. Preserve the product master and its separately pending proof; prepare any deployment actions for human approval without executing them by inference.

**Exit:** All G0–G7 pass for the architecture. No required split, caller migration, test or blocker remains disguised as complete. The result is reviewable integrated code and truthful evidence, not a deployment claim.

## 7. Multi-agent execution and change control

| Role | Responsibility | Exclusive ownership |
| --- | --- | --- |
| Lead/integrator | Scope, contracts, dependency order, shared-file integration, actual gate acceptance and progress | Root composition, package/project manifests, canonical docs/ledger; assigns temporary ownership of other shared files |
| Native capability agent | Account/Library/Catalog or another bounded native slice | Only the explicitly assigned service/model/feature files and their agreed interfaces |
| Backend/operations agent | Handler/SQL/provider/worker ownership and safe qualification | Assigned edge/migration/worker paths; no production writes |
| Verification/review agent | Failure scenarios, focused seams/tests, independent production review | Assigned tests/checks and findings; does not rewrite production implementation while acting as its independent reviewer |
| Optional presentation agent | Independent shared UI/navigation or screen slice after interfaces stabilize | Disjoint view paths; root routing/project edits requested through the lead |

Use a role only while it has useful independent work. Sequentially reuse agents when their ownership changes. Do not spawn one agent per file, commission overlapping whole-repo audits, or maintain several competing architecture documents. An independent production reviewer may author tests, but cannot approve production code they wrote; reassign review for that slice if they participated in implementation.

Before a parallel assignment, provide objective, paths, required inputs, frozen interfaces, dependencies, tests and expected handoff. No two agents edit a shared file concurrently. A file outside an assignment requires a coordination request to the lead, not an unsolicited rewrite. The lead integrates one contract-changing slice at a time; unrelated files can progress concurrently once dependencies are stable.

Integrate in bounded diffs. Keep the last qualified source and the agent-owned patch identifiable so a failed extraction can be reversed without restoring over unrelated changes. If rollback is needed, revert only the owned changes and preserve one active writer throughout; read-only result comparisons are acceptable, dual writes are not. Leave database history intact and treat any deployed rollback as a separately approved migration operation.

Agents hand off a small record: changed paths, public-contract changes, owner/lifecycle changes, actual command outcomes, remaining risks, and next dependency. The lead reads the diff and verifies integrated source instead of accepting an agent's summary as proof. Do not run a broad suite while other agents are mutating the source it is supposed to qualify. Freeze edits for final qualification; subsequent changes invalidate relevant evidence.

## 8. Ledger, documentation and completion report

Keep a single execution ledger alongside this brief, created at execution, and a compact ownership map/manifest. Use: NOT STARTED, IN PROGRESS, IMPLEMENTED, INTEGRATED, VERIFIED, or BLOCKED. IMPLEMENTED requires owned implementation; INTEGRATED requires all relevant actual callers; VERIFIED requires the stated gates on recorded source. Agent completion is not stage completion.

| Stage | Initial status | Evidence required |
| --- | --- | --- |
| E0 source/setup | NOT STARTED | Preserved snapshot, safe check targets, assigned files and runnable baseline |
| E1 lifecycle | NOT STARTED | Account/permission context, complete reset/cancellation map and failure tests |
| E2 contracts/map | NOT STARTED | Every method/state/caller assigned; shared UI, routing and sync-compatible contracts reviewed |
| E3 Library | NOT STARTED | One writer/projection and all current tracking consumers integrated |
| E4 packages/composition | NOT STARTED | Useful compiled boundaries, explicit isolation/import/access/resource policy and real integration |
| E5 catalog/UI/releases | NOT STARTED | Owned query/cache/loading/navigation/provider/reminder behavior |
| E6 private/assistant/Taste | NOT STARTED | Consumer migration, real privacy checks and actual production-rule tests |
| E7 backend/operations | NOT STARTED | Current SQL index, owned handlers/workers and compatibility evidence |
| E8 retirement/qualification | NOT STARTED | Legacy authority removed; G0–G7 verified; independent findings resolved |

Record gate ID, exact source/configuration/environment, command or inspected evidence, PASS/FAIL/BLOCKED, reviewer and unresolved issue. Each test result should reference the risk it establishes. Never equate an empty findings list with a test pass.

The lead updates CURRENT_APP_STATE.md, CURRENT_APP_STATE_PLAIN.md and relevant IMPLEMENTATION_PLAN_Variation1.md status/change log after each coherent completed initiative, with matching file inventories. Agents supply facts; they do not concurrently edit those documents. Use the approved memory extension-note workflow, rather than writing competing legacy memory paths. Update docs/documentation-surface-map.md for changed document roles. Keep historical logs append-only; do not rewrite old proof into current success.

If blocked, state the affected gate, exact unavailable prerequisite, prepared artifacts/commands and independent work completed. Do not repeatedly ask the user about routine choices, hide a failing check, or report global completion with missing mandatory evidence. Approval requests concern concrete external/destructive actions under project rules, not ordinary architecture decisions inside this brief.

The final report contains: architecture completion status; owners/compiled targets and reasons; integrated consumers and retired paths; safety/compatibility corrections; tests and independent review results; unresolved product/environment/device/release proof; and the short add/remove guide. Include no schedule or effort estimate. Release, hosted parity and the Home/detail master's capacity gates remain separately verified obligations when that product delivery is executed.
