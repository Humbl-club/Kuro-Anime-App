# Discovery-first routing — 9 November 2026

Implemented and retested the discovery-first workflow in fresh Claude and Codex sessions. Both ran `--discover` before choosing routes, obtained exact filenames before scoped reads, and used advertised route IDs. Review of the captured tool inputs/results found **no unknown route IDs, nonexistent concrete source-path operands, or source reads lacking a prior catalog/file-search result**. This is sampled evidence; sequencing is an instruction verified in these traces, not a universal runtime guarantee.

The final Codex session ran all **46 policy tests** and the policy/docs checks successfully. The fresh Claude confirmation also ran all **46 tests**; its docs check detected concurrent package-count drift, then passed when that same test session reran only the docs check after reconciliation. [Machine-readable receipts](evidence.json) retain the failures and chronology. Neither app tests nor hosted behavior were qualified.

## Changes

- `policy.py --discover` publishes the valid route IDs and existing owner paths, without inferring task intent. Agents must copy IDs rather than invent aliases.
- `--files '<glob>'` discovers exact active-tree filenames and candidate route IDs. It reports unmatched patterns, total matches and truncation; repeated flags retain every pattern. It reads no contents and excludes hidden, archived, dependency/build/cache and symlink paths plus retired service names. Native Glob/`rg --files` remain alternatives; a scoped lookup is not proof of whole-repository absence.
- `--paths` now returns `missing_paths` and exit 2 for nonexistent inputs **even when a route pattern matches**. Such a route is a suggestion, never proof the input file exists. Planned new paths still require discovery of existing owners.
- Unknown route diagnostics include the catalog command and valid IDs; no fuzzy fallback silently chooses an owner.
- Shared `AGENTS.md` requires catalog discovery first, then filename discovery before reads/searches outside known sources. Claude's adapter/routing rule/Explore instructions follow that rule. Shell-less Explore uses the lead's catalog plus Glob. The existing Claude startup hook now emits the discovery-first reminder; its settings were not modified.
- The discovered package manifest now maps to `infrastructure` and is an explicit source there. It had been a valid existing file with no route; this was a coverage gap, not a nonexistent-path guess.
- Added ten regressions to the prior 36: catalog validity, exact package filename discovery, route-matching missing paths, mixed misses, exclusions/no-content reads, truncation, input boundaries, CLI action ambiguity, manifest coverage and repeated filename flags. Existing diagnostics/startup tests were strengthened. The complete suite is **38 shared +8 optional Claude tests**.

`agents/routes.yaml` remains provider-neutral schema v2. `.claude/adapter.json` and `.claude/settings.json` retain their prior hashes: no model/tool mapping, environment value, main model or global configuration changed. Explore/routing text changed only to teach discovery. Core routing still needs no Claude files.

## Fresh-session evidence

| Phase | Runtime/session | Outcome |
|---|---|---|
| Claude initial | `claude-opus-5-5`; `5d167a27-ed46-44c5-9489-2a7c83ca5b85` | Catalog first; valid routes/source paths; 44 tests and docs PASS. A formatting pipe was denied by the test's shell allowlist; direct lookup succeeded. |
| Codex initial | `gpt-6.1-sol`; `01a1c08f-8f85-73e2-a029-e767a912ce00` | Catalog and filename discovery first. Existing `Package.swift` returned unmapped; that route gap was fixed. 45 tests and docs PASS. |
| Claude full retest | `claude-opus-5-5`; `73618027-499b-4b10-b8f0-5ceec4e7b39d` | Copied routes, looked up Home/Collection/shell filenames before UI reads, checked mounted views and the later SQL body. 45 tests/docs PASS. A repeated-`--files` call exposed argparse dropping earlier groups and a harmless `*RootView*` filename-query miss. Repeated flags were fixed and regression-tested. No nonexistent path was read. |
| Codex full retest | `gpt-6.1-sol`; `01a1c091-f8d0-7f83-8c2d-80fd13e39dd6` | Catalog → copied routes → `rg --files` → exact `--paths` → reads → wrapper/internal SQL lookup. No missing/unmapped/unresolved sources. **46 tests, policy and docs PASS.** One heredoc read failed to create a temporary file; `python3 -c` succeeded without wider permissions. |
| Claude confirmation | `claude-opus-5-5`; `5c238290-d952-4817-8853-c52813454644` | Fresh shorter discovery/action/sender confirmation after code was frozen at 46 tests. Catalog → filename inventory → combined valid routes/paths → reads. **46 tests and policy PASS.** Docs first failed as package files grew 43→44; docs-only follow-up in this same session passed after reconciliation. Full SQL/account/mount evidence remains in the earlier full retest. |

Both Codex sessions used the desktop-bundled `0.166.0-alpha.5.1` CLI, explicit `gpt-6.1-sol` with high effort, ignored personal config, disabled apps/multi-agent/MCP/web, and had effective root-read/scratch-write/network-restricted permissions. The older PATH CLI was not used. Native instruction records show normal root `AGENTS.md` injection and no Claude adapter body injected as Codex instructions. Claude `2.1.319` used normal project/global loading, audited instruction hooks, no per-call model override, read/search tools and narrowly allowed policy/check commands; no helpers were invoked. Runtime message/model records, not agent self-report, establish the models. Claude traces contain no advisor calls.

Claude instruction-hook evidence shows root `CLAUDE.md`, its shared `AGENTS.md` import and project rule loading. Each fresh session's **first repository command** was `python3 scripts/agents/policy.py --discover`. Source provenance was checked chronologically against prior catalog/resolver outputs, RPC candidates, filename inventory and content-search results. The extractor is lexical and was manually reviewed; it is not an AST, complete security audit, or proof of behavioral correctness. Codex CLI events omit a failed nested tool call, so native public tool-call/output records also preserve that failure. Hidden reasoning and authentication material are not copied into the report.

## Source conclusions

The full retests confirmed the actual app shell mounts Home/Collection, then traced:

1. `Kuro/Views/Home/HomeView.swift` → `Kuro/Home/HomeStore.swift` → `LibraryStore.storeProgress` in `Packages/KuroModules/Sources/KuroLibrary/LibraryProgress.swift`.
2. `Kuro/Views/EditorialCollectionView.swift` → `Kuro/Collection/CollectionStore+Lists.swift` → `LibraryStore.advanceProgress`, with its guarded direct-edit fallback.
3. Composition supplies the shared Library owner. `HomeStore.configureProgress` installs the outbox sender through `withCredentialLease(for: account)` and `SupabaseHomeProgressSender`. Merely finding the general Library transport would miss this sender.
4. Credential admission/cancellation, account generations, binding epochs, account-scoped outbox state and registered private-state clearing are relevant. Actual flag arguments matter; construction does not establish enablement.
5. The public `apply_progress_mutations_v1` wrapper is at `supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql:797`. Its internal writer has the later definition at `supabase/prepared-migrations/20261008100000_import_status_fence_preserves_units.sql:7`, not just the older foundation body. Folder placement does not prove deployment state.

Exact application-test candidate identified, **not executed**:

```sh
swift test --package-path Packages/KuroModules --filter LibraryProgressOwnerTests
```

## Verification receipts and limits

The test wrapper runs only one inspected, fixed command per invocation, sets a disposable scratch TMPDIR and disables bytecode writes. It captures the real subprocess numeric exit/stdout/stderr; a model's successful completion or a shell summary is not substituted for those receipts.

| Command executed by wrapper | Codex full retest | Claude confirmation |
|---|---|---|
| `python3 scripts/agents/policy.py --check` | Exit 0; 16 routes | Exit 0; 16 routes |
| `python3 -m unittest discover -s scripts/agents -p 'test_*.py'` | Exit 0; **46 tests**, no skips | Exit 0; **46 tests**, no skips |
| `bash scripts/quality-gates/check_docs_current_state.sh` | Exit 0 | Exit 1 on count drift; **exit 0** in docs-only follow-up |

A minimal source-reference fixture with no `.claude/` or `CLAUDE.md` also passes catalog/filename discovery and unit discovery: **46 discovered, 38 shared executed, eight explicitly skipped**. It is not a full application export. Adapter validation remains an explicit inert data check; it does not launch Claude or apply its hooks/environment/models to Codex.

Concurrent work changed package/export files, moved a prepared migration into canonical history and updated other evidence. Fresh runtime receipts observed inventory 293 app Swift /43 then44 package Swift /250 canonical SQL. After those receipts, canonical SQL inventory reached251. Current markers and the final host docs check are reconciled separately; the earlier receipts are not rewritten. No application/backend/load code was written or reverted by this initiative. Global instruction/config files, Claude settings and model mapping match turn-start hashes. A concurrent task staged the cold-catalogue migration during finalization, so the index diff no longer matches baseline; this initiative made no index writes and preserved that staged change. Changed protected hashes and index drift are recorded rather than falsely claimed identical.

No app build/test, simulator, database execution, hosted write, deployment, staging or commit was performed by this initiative. A filename-query miss is legitimate discovery; the fix prevents treating an invented concrete path or route as verified. Instruction-following across arbitrary future models/tasks is not guaranteed, and these tests do not measure general task accuracy, speed or cost.

Prior reports remain unchanged: [Claude acceptance](../fresh-session-2026-11-09/REPORT.md), [first Codex acceptance](../fresh-codex-2026-11-09/REPORT.md). Normal Codex project loading is described in the official [AGENTS instructions documentation](https://learn.chatgpt.com/docs/agent-configuration/agents-md); the native runtime records establish what actually loaded here. Raw local evidence locations and hashes are in `evidence.json`; public summaries, discovered paths, tool inputs and numeric receipts are durable there.
