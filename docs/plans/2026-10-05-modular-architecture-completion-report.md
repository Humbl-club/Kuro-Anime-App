# Modular architecture: completion report

> **Superseded historical report.** The COMPLETE-WITH-DISCLOSED-GAPS verdict below is not current acceptance. The [completion register](2026-10-05-modularity-completion-register.csv), [continuation ledger](2026-10-05-modularity-completion-ledger.md) and [active execution note](2026-10-07-modularity-production-execution.md) govern current status. Remaining source, hosted and native qualification prevents a full completion claim.

Brief: [2026-10-05-modular-architecture-plan.md](2026-10-05-modular-architecture-plan.md). Evidence, rulings and per-stage logs: [execution ledger](2026-10-05-modular-architecture-execution-ledger.md). Nothing is committed, deployed or applied to any remote.

**Verdict: COMPLETE-WITH-DISCLOSED-GAPS.** Every code-level gate passes on the final frozen source (G0, G2, G3, G6, G7 PASS; G1 PASS in code and tests with environment legs BLOCKED). G4 and G5 are PARTIAL. This is not claimed complete for release or product purposes: no UI/device journey was ever run, nothing was deployed, and hosted/capacity proof does not exist. See "Remaining environment and release gaps".

Source identity: HEAD `471c609`, branch `kuro/taste-overhaul`, 20 deleted / 68 modified / 143 untracked paths, index empty. 129 Swift files in `Kuro/`, 14 in `Packages/`, 23 in `KuroTests/`, 235 migrations in `supabase/migrations/` (unchanged vs HEAD, checksums unchanged), 3 prepared migrations outside the deploy path.

## 1. Ownership map

Pointers: [ownership map](2026-10-05-modular-architecture-ownership-map.md), [manifest CSV](2026-10-05-modular-architecture-ownership-manifest.csv) (169 rows = 129 app + 14 package + 23 unit-test + 3 UI-test files, each with owner, line count and git state), [contracts](2026-10-05-modular-architecture-contracts.md), [large-file review](2026-10-05-modular-architecture-large-file-review.md), [test matrix](2026-10-05-modular-architecture-test-matrix.md). The E0 baselines are kept beside the final versions.

Decision on target count (from demonstrated need): three compiled targets, in the local package `Packages/KuroModules`: `KuroCore` (MediaKind/MediaKey, AccountContext, session coordinator, scoped loads), `KuroLibrary` (the tracking domain), `KuroSupabase` (Library backend over a transport seam). Every other capability is an in-app owner folder by recorded decision (R-E2-1); the brief's 34-target proposal was not adopted.

## 2. Integrated changes

- **Account lifecycle (first, repaired in place).** One funnel, `Kuro/Identity/SessionController.swift`; account-scoped owners implement `AccountScopedState`; every async completion captures an `AccountContext` and guards `isCurrent` before any private write; fail-closed auth-callback guard; deletion clears local state only after confirmed success.
- **Library as the single tracking authority.** `LibraryStore` (package) is the only projection; `LibraryActions` is the only write mapping; list tables are named only in `PostgrestLibraryTransport` and `LibraryRealtime`; field-masked absolute edits; rating scale repaired to the database's 1-10 (three writers had sent 10-100).
- **SupabaseService retired.** 13 files / 7,154 lines deleted, zero references. Each capability has an owner in `Kuro/<Capability>/` (Identity, Library, Catalog, Discovery, Search, Collection, Releases, Providers, Social, Clubs, Imports, Concierge, Taste, Telemetry, Infrastructure, Composition), built once in `AppComposition.makeGraph` over one Supabase client and read via `@Environment`.
- **Typed routes.** `EnvironmentValues.kuroRoutes` (`openMedia`, `openClub`, `presentTrackingEditor`, `presentAddToClub`) replaces 26 cross-feature constructions; pure `RoutePolicy`.
- **Large-file splits (G6).** Four required splits found open at the first pass and closed: detail pages, Concierge/Profile decision rules to pure code, shared cards placed under `Views/SharedCards/`, Concierge rules lanes. 7 dead view files and 45 dead declarations deleted.
- **Backend (local only).** Pure-rule extraction with injected dependencies in `delete-account`, `concierge-apply`, `concierge-undo`, `concierge-recommend` (router), `concierge-parse` (rules); three prepared migrations in `supabase/prepared-migrations/`; local DB harness (`scripts/db/*`, `supabase/tests/**`) that refuses non-local targets.
- **Gates and docs.** `scripts/quality-gates/check_architecture.sh` (blocking in `run_all.sh`), package-aware docs gate, router/corpora gates repaired to execute production rules, `test_packages.sh`; `docs/modules/*`, CLAUDE.md file map, `CURRENT_APP_STATE*.md`, `IMPLEMENTATION_PLAN_Variation1.md`.
- **User-dirty files** were edited only mechanically (R-E6-1, R-E8-1, R-E8-2). `AGENTS.md` and `tools/design-directions/*` were not touched.

## 3. Independent review results

- Per-lane independent reviewers (never the implementer) ran for every lane. Real defects they found and that were fixed: a forged-token bypass of the callback `sub` check (E1, fixed twice: fail-closed plus `exp` >= 60 s plus a post-`setSession` re-check); an auto-apply regression where the reconciler ignored the server's "already tracked" (union rule plus load-state gate); a wrong reminders ruling (R-E3-3); prepared migrations sitting in the deploy path (R-E7-1).
- **Final whole-branch reviewer, first verdict: NOT COMPLETE.** Its evidence predated later edits, the ledger was stale, and 4 required splits were open. Closed by typed routes, shared-card placement, detail decomposition, Concierge rules lanes, a frozen-tree re-run, a rewritten ledger and a regenerated manifest.
- **Final whole-branch reviewer, re-check: COMPLETE-WITH-DISCLOSED-GAPS, no blocking items.** Its gate statuses agree with the ledger. It required wording corrections only (R-E8-2, contracts deviations, memory wording, CLAUDE.md date). Those corrections, the Rule-2 memory append, and a later correction of R-E8-2's own wording (it first called the edit "additive"; the diff shows it also removes three deep-link state variables and three sheet blocks) were made after that verdict and were **not re-reviewed**.

## 4. Test results (frozen tree, run once, evidence in the session scratchpad `final/`)

| Check | Result |
| --- | --- |
| Package `swift test` | 39 tests, 8 suites, passed |
| App `KuroTests` (iPhone 17 Pro, iOS 26.2 simulator) | `totalTestCount 310, passed 310, failed 0, skipped 0` (baseline before any change: 85) |
| Release generic build (`CODE_SIGNING_ALLOWED=NO`) | BUILD SUCCEEDED; only 4 pre-existing warnings, all in the user's untracked `TastePicksView.swift` |
| `run_all.sh` (rails audit, ios-build, ios-test skipped) | 7 passed, 0 failed |
| Local DB harness (throwaway Postgres 17, audited-schema fixture, guard cases 50/50) | 10 files, 321 assertions passed; 5 BLOCKED and 9 finding markers are the documented open items |
| deno | delete-account 33, concierge-recommend 9, concierge-parse 2, concierge-apply 10, concierge-undo 7: all passed |
| Docs gate | PASS (129 app / 14 package / 235 migrations) |

Superseded and not evidence: the earlier 10:43 run (predates later changes; kept under `final/prev/`) and the 10:47 re-run, which used a wrong `-only-testing:` suite name and executed **0 tests**. The local DB fixture is an audited schema, not a full migration replay (strict replay applies 127/235; baseline-first 173). Checks run after the freeze: docs gate PASS, `rg MUTATION Kuro KuroTests Packages` clean, index empty.

## 5. Remaining environment and release gaps (ranked)

1. **Prepared edge/SQL changes are undeployed.** Until `concierge-apply` is deployed, the app's `ImportReconciler.sendsStoredRatingAndNotes` stays in its pre-deploy state; it flips with the apply deploy. Apply/undo/delete-account behavior changes are listed in the ledger ("Prepared, NOT deployed").
2. **`user_id` casing (F1, R-E3-4).** The app sends the upper-case `uuidString`; the captured RLS compares lower-case text. Needs a read-only production check, then one flip at a single decision point.
3. **Club RLS decisions R4/R5 undecided;** RLS was exercised only on the fixture schema.
4. **supabase-swift 2.54.1 decodes PostgREST `detail`, the server sends `details`,** so DETAIL error codes never reach the app.
5. **16 device smoke journeys never run** ([docs/modules/README.md](../modules/README.md)). UI, gestures, routes, detail pages are untested at runtime. G4 and G5 stay PARTIAL for this reason.
6. Realtime after permission revocation, unfiltered club subscriptions, no `club_members` realtime signal, no durable offline sync.
7. Detail link validator accept/reject edge cases changed.
8. Also recorded: `delete-account` pre-deploy read-only checks (service_role DELETE privileges, the two comment tables, `media` bucket); with `clarify_v2` off Concierge auto-applies parser-ambiguous lines (owner decision); `AppleFMService` synopsis cache keyed by bare media id; revoked notification permission goes unnoticed; request dates sent without a time zone; `AGENTS.md` diverges from CLAUDE.md; auto-generated blocks in `CURRENT_APP_STATE.md` not regenerated.

Home/detail master-spec offline, product and capacity gates are not claimed.

## 6. Developer guide

Full guide with the navigation map and the 16 smoke journeys: [docs/modules/README.md](../modules/README.md).

To **add a capability**: create `Kuro/<Capability>/` with an `@Observable @MainActor` owner store; if it holds account data, implement `AccountScopedState` (`cancelAccountWork()`, `clearPrivateState()`), capture an `AccountContext` before every suspension and guard `isCurrent` before every private write; build it once in `AppComposition.makeGraph` from the shared client and add it to the single `AccountScopedState` list (an exact-membership test fails if you forget); inject it with `@Environment`, never a singleton; reach other features through typed routes, not constructors; add tests against production rules (the `StubPostgREST` harness for SDK paths) and a row in the ownership manifest; run `scripts/quality-gates/check_architecture.sh`. Promote it to a package target only when a second consumer or a compile-time boundary justifies it.

To **remove a capability**: delete its folder, its composition line and its `AccountScopedState` entry, migrate or delete the last consumer first (nothing may reference it; the architecture gate enforces the retired facade pattern), remove its routes, then update the manifest, ownership map and the three state docs.

## 7. Rulings made (each with its cost if wrong)

From the ledger (`docs/plans/2026-10-05-modular-architecture-execution-ledger.md`, lines 21-35):

| Ruling | Decision | Cost if wrong |
| --- | --- | --- |
| R-E0-1 | Execute in this checkout, no worktree, no commits | Harder to revert selectively; mitigated by the E0 patch snapshot and per-stage path lists |
| R-E1-1 | Same-user session events keep the account context | Unnecessary reloads, or stale data if lax |
| R-E1-2 (amended twice) | Callback decided before `setSession`, fail-closed while signed in (`sub` match, `exp` >= 60 s, post-`setSession` re-check) | A user switching accounts via an emailed link must sign out first; residual recorded in the ledger |
| R-E1-3 | Sign-out and deletion invalidate the context before the first suspension | None recorded in the ledger |
| R-E2-1 | Three initial compiled targets; no SDK dependency inside the package | Later extraction churn; contracts are target-agnostic |
| R-E2-2 | `SupabaseService` a forwarding facade until its last consumer migrates | Temporary indirection |
| R-E3-1 | Database rating 1-10 is authoritative; legacy 0-100 score is display only | If production lacks the CHECK, previously accepted 10-100 values are now rejected client-side |
| R-E3-2 | Field-masked absolute edits; `save` never overwrites | Behavior change for flows that relied on `addToList` resetting status/progress |
| R-E3-3 | Reminders re-armed on every applied anime change that leaves the title tracked | One extra `anime` GET per anime write |
| R-E3-4 | F1 `user_id` casing not resolved; single decision point | Stays open until the owner's read-only production check |
| R-E6-1 | Mechanical API-swap edits to the user's `TastePicksView.swift` | Merge conflict with concurrent edits |
| R-E8-1 | Mechanical edits to `KuroApp.swift` and `ContentView.swift` | Merge conflict with concurrent edits |
| R-E8-2 | `ContentView.swift` also edited for typed routes: 6 hunks (911 to 886 lines), presenter installs, three deep-link state variables and sheets replaced by route calls; pager/header/gestures untouched. Supersedes R-E8-1's wording | Larger merge surface in `ContentView.swift` if the user has concurrent edits to those lines |
| R-E7-1 | Prepared migrations live in `supabase/prepared-migrations/` | An extra `git mv` at approved deployment |
| R-E7-2 | `delete-account` treats `anime_comments`/`manga_comments` as required deletes | If either table or column type differs in production, deletion fails for every user: verify read-only before deploying |

Deviations from the contracts document, now recorded there: the `FeatureFlags` instance is injected (no separate `RuntimeFlags` type); `presentTrackingEditor` takes a `TrackingEditorRequest` wrapping `any MediaDisplayable`; `presentAddToClub` was added; `ListStatus.repeating` is stored as WATCHING (anime) / READING (manga).

## 8. Owner actions (not performed; each needs approval)

1. **Pre-checks, read-only, before any deploy:** `user_id` casing query on the list tables and `pg_policies` (F1); `delete-account` checks (service_role DELETE privileges, `anime_comments`/`manga_comments` existence and types, `media` bucket).
2. **Deploy order:** `delete-account` and `concierge-undo`, then `concierge-apply` (its deploy flips `sendsStoredRatingAndNotes`). Command per the project: `supabase functions deploy <name> --project-ref bkdifromsqxkndnllmdj`.
3. **Prepared migrations:** after approval of each, `git mv supabase/prepared-migrations/<file> supabase/migrations/`, then `supabase db push --linked --include-all`, `get_advisors(security)`, and refresh checksums.
4. **Decide club RLS R4/R5.**
5. **Fix `detail` vs `details`** in the SDK or server so structured error codes reach the app.
6. **Run the 16 device smoke journeys** on a simulator or device.
7. **Reconcile `AGENTS.md`** with CLAUDE.md.
8. **Commit decision.** Nothing is committed; the work sits in the working tree on `kuro/taste-overhaul` alongside the user's other uncommitted work.
