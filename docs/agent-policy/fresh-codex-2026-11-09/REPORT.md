# Fresh Codex acceptance — 9 November 2026

The sampled shared-policy workflow works in a fresh native Codex process after two portability fixes. Codex received root `AGENTS.md` through normal instruction loading, found the mounted progress owners and later SQL writer, and executed the three requested policy/documentation checks successfully. Claude-specific model/tool/environment configuration remains isolated and unchanged in behavior. This is coding-agent workflow evidence, not application tests, hosted parity, or a guarantee against future source-selection mistakes.

Machine-readable runtime, command-exit, isolation and preservation receipts: [evidence.json](evidence.json). Earlier Claude acceptance remains separately preserved in [its original report](../fresh-session-2026-11-09/REPORT.md); this initiative did not rerun fresh Claude model selection.

## Runtime and isolation

Used the desktop-bundled binary at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`, version `0.166.0-alpha.5.1`. The `codex` on PATH was the older `0.29.0` binary and was not used. Each acceptance phase started a new `codex exec` process/thread, without resume or conversation history. Runtime `turn_context` records identify **OpenAI / gpt-6.1-sol / high effort**. Model selection was explicit for these invocations; no persistent default or automatic model switching was changed or proved.

The process used existing authentication with `--ignore-user-config`, disabled apps/multi-agent/web/MCP configuration, and a network-restricted permission profile extending `:read-only`. Only the dedicated scratch directory had write access. Native runtime metadata confirms filesystem root-read plus scratch-write. A separate sandbox canary successfully wrote a scratch fixture and received `PermissionError` for its attempted repository canary. It left no repository canary. The legacy runtime field calls this `workspace-write`; the effective managed permission entries, rather than that label, establish the actual boundary.

Codex's recorded instruction input includes `# AGENTS.md instructions for /Users/max/Kuro-Anime-App` and the shared-policy body. It does not include the Claude adapter body as instructions. File references in shared guidance are not adapter loading. Presence-only probes returned `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=False`; no values or environment dumps were taken. There were no Claude/helper/model-worker, MCP, web or file-change event types in the captured Codex item streams. The docs gate's explicit adapter check reads repository data; it does not execute the Claude startup hook or apply its environment, tools or models.

## Failures retained and repairs

| Fresh phase | Observed result |
|---|---|
| `baseline` — `01a1c06c-382c-73a1-a9c5-fdbb037dff54` | Shared check passed. All 30 tests errored during fixture setup because pure read-only permissions denied temporary storage; no assertions ran. Docs gate failed on stale inventory. A separate no-Claude fixture reproduced an unconditional shared-loader dependency on `CLAUDE.md`. |
| `retest` — `01a1c072-2298-7582-b8f6-384328c18a1e` | Scratch-only profile allowed execution. Shared check, 35 tests and docs gate passed. Codex still identified that test fixture setup depended on installed Claude files. |
| `final` — `01a1c077-e3b3-7801-afef-637e365b89a0` | Split fixtures: all 36 tests and shared check passed. Docs gate correctly failed as concurrent package additions changed inventory from 36 to 39. Source-routing acceptance was retained; the session honestly reported partial acceptance. |
| `acceptance` — `01a1c07a-0d93-7653-b7b9-816b77741244` | With current inventory reconciled, shared check, all 36 tests and docs gate passed. Count during acceptance: 293 app Swift /39 package Swift /250 canonical SQL. |

All process exits were 0: a model's successful completion can report failed checks. Command-level numeric exits, actual outputs and executed counts are the acceptance evidence; process success alone is not.

The changes are restricted to coding-agent tooling and its documentation:

- Shared `agents/routes.yaml` schema v2 contains provider-neutral routing, capability and verification contracts. Claude's existing model/tool mapping moved unchanged into `.claude/adapter.json` schema v1. A precise `.gitignore` exception shares that file.
- Shared `load`, routing, and ordinary `--check` never read `CLAUDE.md` or `.claude/` configuration. Optional `--check-claude` and Claude startup explicitly validate the adapter as data. The complete checkout's docs gate performs this separate validation when either adapter entry point exists; a half-installed adapter intentionally fails. No-Claude exports with neither entry point avoid it.
- Test fixtures are split into 28 shared tests and eight optional adapter tests. Core regressions reject Claude reads, reject provider settings in the shared schema, verify no-Claude routing and read-only resolution. Adapter regressions cover drift, imports, startup context and validation without hook execution or environment changes.
- A separate minimal source-reference fixture, physically without `.claude/` or `CLAUDE.md`, ran core routing and validation with exit 0, then unit discovery with exit 0: 36 discovered, eight explicitly skipped, **28 shared tests executed**. This fixture is not a complete app checkout or a docs/app test export.
- Documentation explains writable disposable test storage without widening repository/network access. Current inventory markers were reconciled; historical counts were retained.

## Source-selection evidence

The native sessions used the shared route/RPC resolver and inspected code, rather than accepting an old service map:

| Question | Observed source conclusion |
|---|---|
| Mounted Home/Collection progress | `ContentView.swift` mounts Home/Collection. `Kuro/Views/Home/HomeView.swift` calls `HomeStore.advance`; Collection's owner also calls the shared Library progress APIs, with a guarded fallback. `LibraryProgress.swift` and `ProgressOutbox.swift` own durable progress. `SupabaseService` is retired. |
| Actual progress sender | `HomeStore.configureProgress` installs the outbox sender and credential-lease closure, ending in `SupabaseHomeProgressSender`. Merely finding `PostgrestLibraryTransport` would miss this path. |
| Effective production arguments | `AppComposition` supplies `seriesFoundationV1Enabled` to Home progress and `seriesFoundationFenceEnabled()` to the general Library backend. A factory default or constructor's existence does not establish effective enablement or hosted flag values. |
| Account isolation | Identity/account-session generation, credential leases, and registered cancellation/private-state clearing are relevant; screen-only routing is insufficient. |
| SQL definition selection | Public `apply_progress_mutations_v1` is at line 797 in `20261007040000_series_home_foundation_v1.sql`; `_apply_progress_mutations_for_user` has an initial body at line 558 and a later replacement starting line 7 of `20261008100000_import_status_fence_preserves_units.sql`. Both are under `supabase/prepared-migrations/`. Codex inspected the later body and kept source/deployment claims separate. |
| Relevant application check | Exact candidate: `swift test --package-path Packages/KuroModules --filter LibraryProgressOwnerTests`. Identified, **not executed** for this tooling-only initiative. |

These are dated observations, not frozen application source qualification. The report's source paths and line numbers reflect the observed tree; concurrent application work can move them.

The runs were not flawless. Baseline supplied an invalid route-argument form and recovered. A source probe guessed a nonexistent Collection directory. Final acceptance initially requested unknown route `library` and guessed a nonexistent app-level `LibraryProgress.swift`; the resolver failed with exit 2 and the session recovered using actual `library_progress`/Identity/Home routes and package sources. Searches also included nonexistent Features/Configuration directories. One here-document probe failed because the shell's temporary directory was not writable; the session exported the authorized scratch TMPDIR for subsequent child commands and the actual checks passed. Some compound discovery commands ended with exit 0 despite an earlier diagnostic; those exits are not treated as proof that each subcommand succeeded. The final phase stayed within its eight-shell-invocation budget. Shared guidance improves recovery and evidence discipline; it does not mechanically prevent guessed paths or replace behavioral validation.

## Final fresh command results

The three checks ran as separate shell-command items, each with process-local scratch/bytecode settings:

| Command | Exit | Evidence |
|---|---:|---|
| `python3 scripts/agents/policy.py --check` | 0 | PASS; 16 shared routes/references; no provider adapter load |
| `python3 -m unittest discover -s scripts/agents -p 'test_*.py'` | 0 | 36 tests in 2.214s; OK, no skips/errors |
| `bash scripts/quality-gates/check_docs_current_state.sh` | 0 | Shared validation PASS; explicit Claude adapter validation PASS; inventory 293/39/250; current-state docs PASS |

The shared-check item also contained a presence-only environment probe before the check. The unit and docs checks each had their own numeric receipt. No package/native tests, app build, broad suite, simulator, load test, hosted query, deployment or release was performed by this acceptance.

## Preservation and limits

Global Codex config/instructions and global Claude settings/instructions match turn-start hashes. Existing project Claude settings, all four worker definitions and all four rule adapters match their turn-start hashes. The moved mapping equals the original shared payload. Staged diff hash is unchanged. No reset/stash/clean/stage/commit was used.

Other work in this shared checkout concurrently committed/added Library package features and changed backend load/cold evidence. Five protected existing source files differ from baseline; the evidence lists them instead of falsely claiming the entire application tree stayed byte-identical. This initiative did not write or revert those sources. Inventory corrections account for concurrent files; they are not agent-policy app additions. After fresh acceptance, concurrent work continued adding package sources; current-state markers and the final host docs check are reconciled separately, with the final observed count in `evidence.json`. The fresh session's 39-file receipt remains unchanged.

This verifies a sampled fresh **CLI** session using the desktop-bundled runtime. It does not prove the behavior of every desktop UI launch, old CLI version, personal/MCP configuration, task, model, or organization override. The isolation run intentionally ignored user config; existing global instructions still applied through normal instruction loading. No new Codex-specific persistent settings were needed. No improvement in general model quality, task correctness rate, speed or cost is measured here.

Method references: official [AGENTS configuration](https://learn.chatgpt.com/docs/agent-configuration/agents-md), [non-interactive execution](https://learn.chatgpt.com/docs/non-interactive-mode), and [permissions](https://learn.chatgpt.com/docs/permissions). Runtime receipts, rather than documentation or model self-report, establish what this run loaded and executed. Raw JSONL remains in the local temporary evidence directory identified in `evidence.json`; sanitized public summaries, command receipts, hashes and runtime metadata are durable here. Hidden reasoning and authentication material are not copied into this report.
