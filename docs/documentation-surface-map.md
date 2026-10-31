# Documentation Surface Map

This file defines which Markdown surfaces are current, which are reference-only, and which are historical.

## Current authoritative docs

| Surface | Role | Notes |
|---|---|---|
| `CURRENT_APP_STATE.md` | Technical current-state authority | Full engineering snapshot; may include historical changelog entries, but current inventory markers at the top are the source of truth. |
| `CURRENT_APP_STATE_PLAIN.md` | Plain-English current-state authority | Non-technical companion to `CURRENT_APP_STATE.md`. |
| `CLAUDE.md` | Rules + operating context | Policy, workflow rules, and high-value runtime context. Not the full system inventory. |
| `IMPLEMENTATION_PLAN_Variation1.md` | Ongoing implementation ledger | Tracks shipped work and plan status; historical by nature, but still maintained. |

## Live reference docs

| Surface | Role | Notes |
|---|---|---|
| `docs/handoffs/2026-10-07-integrated-testflight-execution.md` + `2026-10-07-integrated-release-checklist.csv` | Current integrated executor, all114finding reconciliation and lasting implementation rules | User-approved modularity/Home scope, two waves, bounded launch envelope and five release gates. NOT COMPLETE; source/local evidence never implies hosted or installed acceptance. |
| `docs/handoffs/2026-10-07-integrated-release-evidence/` | Current integrated local/source evidence and source checkpoint | Actual-owner, syntax and offline checks are labelled separately; no frozen artifact or hosted/installed acceptance. |
| `fastlane/RELEASE_PIPELINE.md` + `scripts/live/README.md` | Exact candidate release and bounded live qualification runbooks | Prepared procedures, not deployed or installed qualification. |
| `docs/app-store-metadata.md` | Current draft copy, privacy reconciliation and reviewer inputs | NOT SUBMITTED; effective vendor retention, archive privacy report, policy URL and Connect answers remain required. |
| `docs/handoffs/2026-10-07-home-series-evidence/INDEPENDENT_REVIEW.md` + `independent-review/` | Independent Home/series dirty-tree review and reproducible evidence | R01–R16; requests changes and supersedes earlier approval-only/readiness and visual-pass claims. Source/local review, not a deployment or full capacity/device qualification. |
| `docs/handoffs/2026-10-07-home-series-evidence/REPAIR_LEDGER.md` + `repairs/` | Active R01–R16 source repair and verification record | Current checks, historical failures, reviewed hashes, reproduction commands and unrun/blocking proof. Dirty-tree local evidence; not deployment or a frozen release candidate. |
| `KNOWLEDGE/INDEX.md` + `KNOWLEDGE/PART-*.md` | Self-contained LLM reference surface | Intentionally overlaps with current-state docs so it can be loaded independently. |
| `docs/plans/2026-10-05-modular-architecture-plan.md` | Claude Code modular architecture execution brief | Prompt first; autonomous coordinated sub-agents, weighted priorities, mandatory success gates, focused test matrix and lifecycle-first E0–E8 integration. No effort estimates. Executed locally 2026-10-05 (uncommitted, not deployed); gate status and open items live in the execution ledger. Historical modularity-only scope is superseded by the integrated executor; the Home master retains product/design requirements. |
| `docs/plans/2026-10-05-modular-architecture-execution-ledger.md` | Modular architecture execution ledger | Append-only history with current status tables: rulings, per-stage evidence, gate status (G0–G7), exact test results, prepared-NOT-deployed changes, blockers and open owner decisions. Historical migration gate results; current integrated release verdict lives in the integrated checklist. Keep. |
| `docs/plans/2026-10-05-modular-architecture-contracts.md` | Frozen architecture contracts (E2) | Architecture shape, account-lifecycle contract and Library reader/writer/adapter contract with examples. Changes after a consumer migrates are recorded in the ledger; keep. |
| `docs/plans/2026-10-05-modular-architecture-ownership-map.md` | Final capability ownership map | Owners, folders, consumers, state lifetimes, keep/split decisions and where each part of the retired `SupabaseService` went. Keep current when an owner is added or removed. |
| `docs/plans/2026-10-05-modular-architecture-ownership-manifest.csv` | Final machine-readable ownership manifest | Generated snapshot of every Swift file in `Kuro/`, `Packages/` and the test targets with its final capability owner; companion to the ownership map. Regenerate on demand when owners change. |
| `docs/plans/2026-10-05-modular-architecture-ownership-manifest-e0-baseline.csv`, `docs/plans/2026-10-05-modular-architecture-service-member-map.csv` | E0 baseline manifests | Generated at E0/E2 against the pre-migration tree (line numbers and owners as proposed then). History only; superseded by the ownership map and final manifest. Archive when no longer useful. |
| `docs/plans/2026-10-05-modular-architecture-large-file-review.md` | Large-file keep/split review (G6) | Keep/split decisions for large files and owners at the end of the migration. Point-in-time; keep while the owners it reviews are unchanged. |
| `docs/plans/2026-10-05-modular-architecture-test-matrix.md` | Migration risk-to-test matrix (G5) | Which test covers which named risk; exact results live in the ledger. Keep. |
| `docs/plans/2026-10-05-modular-architecture-completion-report.md` | Modular architecture completion report | Verdict, integrated changes, review results, exact frozen-tree test results, remaining gaps, rulings list and owner actions. Snapshot of 2026-10-05; the ledger stays the live record. Keep. |
| `docs/modules/README.md` | Module navigation map + developer guide | Where each capability lives (incl. typed routes), enforced rules, verify commands, add/remove-a-capability procedure and the device smoke journeys that were NOT run. Current with the code; keep. |
| `docs/modules/edge-functions.md` | Edge-function ownership and keep/split decisions (E7) | Point-in-time line numbers (2026-10-05); records corpus disagreements and dormant/unused functions. Nothing deployed by it. |
| `docs/modules/detail-pages.md` | Detail-page map (Anime/Manga) | Files, load tables (also in each page header) and the provider-link snapshot after the D1–D3 decomposition. Keep current with the detail pages. |
| `docs/modules/operations.md` | Operational scripts index (E7) | Launchd families, paths that must stay stable, hazards. Index only; nothing moved. |
| `docs/modules/sql-function-index.md` + `.csv` | Effective SQL function/signature index (E7) | Generated from a snapshot of the 235-file migration chain; regenerate on demand when migrations change (its generator scripts are not checked in). |
| `docs/modules/script-classification.csv` | Classification of every script under `scripts/` | Generated snapshot (active/manual/legacy, references); regenerate on demand or archive. |
| `Packages/KuroModules/README.md` | Local package notes | Targets, isolation policy, how to test, what is not claimed. Keep. |
| `supabase/tests/README.md` + `supabase/tests/pending_migrations.txt` | Disposable local database test harness | Run modes, replay results, coverage, findings and BLOCKED items. Audited-schema fixture, not a migration replay or production parity. `pending_migrations.txt` lists prepared-NOT-deployed migrations. Keep. |
| `supabase/prepared-migrations/` | Prepared, NOT deployed migrations (club RLS R1–R3) | Deliberately outside `supabase/migrations/` so no push/deploy script applies them. On approval: `git mv` into `supabase/migrations/` and drop the line from `pending_migrations.txt`. |
| `docs/plans/2026-10-05-modularity-baseline.json` | Local source inventory for modularity assessment | Paths, line counts, digests and textual coupling signals at the recorded working tree. Not an AST/runtime graph, deployed inventory or capacity proof. |
| `docs/plans/2026-10-02-series-and-home-rebuild-DRAFT.md` | Home/detail master execution specification v1.1 | Product/design master retained; approved integrated release override supersedes old capacity and separate-scope requirements. Execution is in progress, not qualified. Older NOT STARTED statements are historical. |
| `docs/handoffs/2026-10-05-claude-code-production-handoff.md` | Portable Claude Code executor edition of the singular v1.1 master plan | Prompt first, active specification plus production gates and visual dependency manifest. Snapshot: reconcile/regenerate when the canonical plan changes. Not a second plan or implementation/release proof. |
| `docs/production-blockers.md` | Focused audit/reference doc | Narrow-scope operational reference, not a whole-repo authority. |
| `docs/filter-wiring-audit.md` | Focused audit/reference doc | Targeted verification output. |
| `docs/clubs-spec.md` | Product spec | Historical design intent plus still-relevant implementation context. |
| `docs/personalization_execution_contract.md` | Execution contract | Strict sprint/specification surface for personalization work, including glossary, rules, gates, and rollback policy. |
| `MASTER_PLAN.md`, `REPRODUCE.md`, `SCHEDULES.md` | Operational/reference docs | Keep only while they remain actively useful. |

## Historical / archived docs

Historical snapshots live in `archive/`.

Use them when you need:
- old design iteration context
- previous generated source bundles
- prior one-off rollout notes
- superseded knowledge docs

Do not treat archived docs as current truth unless they are explicitly re-verified.

## Keep / trim / archive policy

| Condition | Action |
|---|---|
| Current, authoritative, and actively maintained | Keep in repo root or `docs/` |
| Useful reference, but not authoritative | Keep in `docs/` or `KNOWLEDGE/` and label scope clearly |
| Historical rollout/design snapshot | Move to `archive/` |
| Generated snapshot larger than its maintenance value | Regenerate on demand or archive |

## Current practical rule

When a doc and the code disagree:
1. Code and live backend win
2. `CURRENT_APP_STATE.md` should be corrected next
3. Other docs should then be aligned or marked historical
