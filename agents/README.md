# Kuro agent routing

Root `AGENTS.md` is the provider-neutral policy. `routes.yaml` is its source and
verification registry; `.claude/` and root `CLAUDE.md` adapt it to Claude Code.
No runtime application/backend code or global agent configuration is changed.

Shared registry schema v2 contains no provider model/tool/environment settings.
Claude's schema-v1 registry is `.claude/adapter.json`; its existing settings and
worker files remain under `.claude/`. Source routing and ordinary `--check` never
read those files and work when both `.claude/` and `CLAUDE.md` are absent.
`--check-claude` explicitly validates that adapter as repository data, without
executing hooks, launching Claude or applying environment variables. The full
checkout's docs gate performs this separate check when the adapter is installed.
Shared unit fixtures do not read provider settings. Optional Claude tests have a
separate fixture/class and are explicitly skipped when that adapter is absent;
missing Claude files never break the shared test suite.

## Use

From the repository root:

```sh
python3 scripts/agents/policy.py --discover  # first discovery command each session
python3 scripts/agents/policy.py --files '*HomeView.swift' '*LibraryProgress.swift'
# Copy exact IDs/paths from discovery output before using --route/--paths:
python3 scripts/agents/policy.py --route library_progress --route identity
python3 scripts/agents/policy.py --check
python3 scripts/agents/policy.py --check-claude  # only for installed Claude adapter
python3 scripts/agents/policy.py --list
python3 scripts/agents/policy.py --route library_progress
python3 scripts/agents/policy.py --route library_progress --route identity --rpc apply_progress_mutations_v1 --rpc _apply_progress_mutations_for_user
python3 scripts/agents/policy.py --paths Kuro/Library/LibraryActions.swift Kuro/Views/Routing/KuroRoutes.swift
python3 -m unittest discover -s scripts/agents -p 'test_*.py'
bash scripts/quality-gates/check_docs_current_state.sh
```

The resolver returns JSON: applicable routes, current owner entry points, behavior
contracts, check candidates and required handoff fields. It returns **all** path
matches and any explicitly selected routes. A nonexistent path is reported in
`missing_paths` and returns `discovery_required`/exit 2 even when a route pattern
matches it. Suggested routes never certify that a guessed input file exists.
An unmapped path (including one mixed with known paths) also returns exit 2; unknown route IDs or
invalid configuration return exit 1. Retired `SupabaseService` and archive paths
cannot become current owners merely by matching a pattern.

There is no natural-language classifier pretending to understand the task. For a
question without filenames, start with `--discover`, copy a valid ID and confirm
with current symbols/callers. For a new/unmapped area, use bounded discovery,
confirm its owner and update the route before dependent edits. An explicit route
does not clear an unmapped path. Cross-cutting tasks must include every affected
capability even if only one route's filenames happen to match.

`--discover` publishes validated route IDs and existing owner paths, with no
provider configuration or task classifier. Before a scoped read/search outside
those owners, use `--files '<glob>'`, `rg --files`, or native Glob to find exact
paths. Filename lookup scans the active non-hidden tree, excluding archive,
dependency/build/cache directories, symlinks and retired service filenames. It
reads no contents. Repeated `--files` flags retain every pattern. It preserves unmatched patterns (exit 2), reports truncation
and total matches, and returns candidate route IDs per file. Narrow a truncated
query (`--limit` defaults to 80, maximum 500); absence within this scope is not
proof of repository-wide absence. Do not infer a directory from a basename.
Shell-less workers use lead-supplied catalog output and native Glob. Unknown
routes fail with valid IDs and the discovery command; no fuzzy auto-selection.

For RPC/server claims, `--rpc <unqualified-function-name>` lists CREATE FUNCTION
declaration candidates from both canonical and prepared SQL, ordered by filename
and line, with source hashes. Repeat for internal callees; inspecting only the
public wrapper can miss a later replacement of its writer. Missing functions
return discovery-required/exit 2. This is a lexical lookup, not a SQL parser,
overload resolver or effective schema reconstruction. Inspect candidate bodies,
dependencies and deployment receipts. A prepared-directory file may already have
been applied in an approved transaction; its location proves neither deployment
nor non-deployment. Never present an older matching body as the latest contract.

## What is enforced and what still needs judgment

`routes.yaml` uses the **JSON-compatible subset of YAML 1.2**, intentionally parsed
with Python's standard `json` library. No YAML dependency/install is required.
Keep this subset (no YAML comments/anchors/tags). The reader rejects duplicate
keys, unknown schema fields, invalid/missing references and checks, absolute or
escaping/symlink paths and historical/catch-all authorities. Explicit adapter
validation additionally checks model/tool/settings drift.
All commands in the registry are **templates/candidates, never executed**. Resolve
placeholders, inspect permissions and choose the smallest affected checks. Tests
of the resolver never invoke Swift, Deno, databases, providers or an LLM.

The source map is deliberately selective. It does not prove a symbol is still
mounted, an index is used, tests cover intent, RLS is correct or hosted code matches
local code. Follow composition/callers and actual RPC definitions; inspect dated
evidence and measure changed behavior. A successful path lookup alone is not
permission to edit, deploy, or declare a result correct.

Read-only Claude workers allow only Read/Grep/Glob. Implementer/runner workers
can execute shell commands and therefore are not security sandboxes. Caller
permissions, inspected commands and existing authorization boundaries still apply.
Every worker receives the shared policy; the old `omitClaudeMd` shortcut is gone.
The Claude adapter sets `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`: Claude's server-side
advisor is an additional model call, not governed by the ordinary worker tool
allowlist. This keeps Kuro's model routing explicit without altering other
projects or coding agents. The explicit adapter validator checks this setting, and fresh-session evidence must
inspect `server_tool_use`/`advisor_tool_result` blocks as well as normal tool calls.

The Claude SessionStart command validates the shared core plus its adapter and emits a short policy
reminder; it follows the hook's working-directory ancestry when in a worktree.
Failure emits diagnostic context and a nonzero exit. SessionStart is not a write
barrier. Hooks may be disabled by runtime settings; the docs quality gate also
runs validation. Restart an existing Claude session to load changed definitions,
check `/memory`/`/agents`, and inspect `/tasks` when using a worker to confirm the
actual model. No fresh model invocation or agent evaluation is implied by local
configuration tests. Model aliases remain runtime defaults subject to overrides.

## Correctness-first selection

Profiles define required capability, not a universal vendor ranking. The Claude
adapter maps bounded discovery/command execution to Haiku, specified implementation
to Sonnet, and independent review to Opus. High-assurance judgment stays with a
capable lead. A written plan alone does not make risky code suitable for a smaller
model. Failures, ambiguous ownership, conflicting contracts or unverifiable output
require investigation/escalation, not repeated optimistic handoffs.

Evaluate actual tasks using source-selection accuracy, behavioral/contract results,
missed authorization/account boundaries, escalation quality and rework. Measure
accepted completion time/cost as secondary results. No model-quality or speed
improvement has been established by this configuration change.

## Maintenance and evidence

Local unit tests create disposable fixtures. Strict read-only sandboxes that deny
all temporary writes cannot execute those assertions. Give the test process an
isolated scratch directory while keeping the repository read-only; record that
permission boundary and actual executed counts. Do not treat fixture setup errors
as a passing suite or as evidence of broken application behavior.

Fresh runtime acceptance is recorded in
[`docs/agent-policy/fresh-session-2026-11-09/REPORT.md`](../docs/agent-policy/fresh-session-2026-11-09/REPORT.md)
with sanitized transcript/model/check evidence. Four fresh sessions exercised policy
imports, bounded discovery, worker defaults and actual local policy checks. Initial
failures and corrections remain recorded; this does not certify arbitrary future
tasks or application/hosted behavior.

Fresh Codex acceptance and the shared/Claude isolation regression are recorded in
[`docs/agent-policy/fresh-codex-2026-11-09/REPORT.md`](../docs/agent-policy/fresh-codex-2026-11-09/REPORT.md).
That initial acceptance ran 36 tests. Current shared test fixtures have no Claude
dependency. When the optional adapter is absent, its eight tests explicitly skip
while all 38 shared tests still execute. The complete checkout executes all 46 tests and explicitly validates its
installed adapter without applying Claude environment variables or hooks.

The subsequent [discovery-first Claude/Codex retest](../docs/agent-policy/discovery-first-2026-11-09/REPORT.md)
records catalog-first route selection, filename provenance before scoped reads,
missing-path enforcement and the current 46-test suite. It preserves benign
discovery misses, permission/temporary-file recovery and concurrent inventory
failures rather than claiming every tool call was successful.

Update route/check references in the same change when files move or ownership
changes. Keep live pool sizes, user counts, feature flags, upstream quotas and test
outcomes in their dated owning evidence. Search current-state docs for the latest
capacity report; a target is not measured concurrency, and a passing aggregate
does not override failed cohorts, cold misses or uncompleted burst/recovery.
For intake, trace actual worker/cron -> source identifiers -> writer RPC and raw
provenance. Cached data, search links and a source discovered via another provider
must not be described as an independent replacement.

The original dirty-tree `CLAUDE.md`, old `AGENTS.md` and eight local agent/rule
definitions are preserved byte-for-byte inside fenced sections of
`archive/agent-policy-2026-11-09.md`, each with its original SHA-256. They are
historical evidence only, never auto-imported. Other source edits and the index
were preserved. The personal global multi-persona file is unchanged; the Kuro
policy/adapter explicitly overrides that convention here.

Design basis: [Google DeepMind's Intelligent AI Delegation](https://arxiv.org/html/2602.11865v1)
(capability/authority/verification contracts; proposed framework, not a correctness
guarantee), [Google's context engineering in ADK](https://developers.googleblog.com/en/architecting-efficient-context-aware-multi-agent-framework-for-production/)
(scoped context and explicit transformations), and
[ADK Agent Config](https://adk.dev/agents/config/) (runtime-specific configuration,
not a universal format). Native adapter mechanics follow
[Claude memory/imports](https://code.claude.com/docs/en/memory),
[subagents](https://code.claude.com/docs/en/sub-agents) and
[hooks](https://code.claude.com/docs/en/hooks). This registry is a small local
implementation of those principles, not Google's ADK schema or a trained router.
Advisor behavior/disable control: [official Claude advisor documentation](https://code.claude.com/docs/en/advisor#turn-the-advisor-off).
