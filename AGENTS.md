# Kuro — shared agent policy

Updated 2026-11-09. Applies to every coding agent working in this repository.

## Authority and scope

- This is the canonical operating policy. `CLAUDE.md` is an adapter, not a second policy.
- Shared source routing and `--check` use only the provider-neutral registry. Claude model/tool mappings live in `.claude/adapter.json`; its hooks/env live in `.claude/settings.json`. Only explicit `--check-claude` or Claude startup validates that adapter as data; neither applies it to another agent.
- For Kuro, this policy explicitly replaces personal defaults requiring multiple personas for every task, automatic deployment after implementation, or blanket independent review. Do not change global settings to achieve this project override. Host/system restrictions and explicit user instructions still apply.
- Use one agent by default. Delegate only permitted, bounded work with clear input, file ownership, expected output and verification. The lead remains accountable. Separate files alone do not establish independence. Sensitive lifecycle, authorization, recovery and deployment changes require focused independent review when the environment permits; otherwise report that gap, without claiming equivalent assurance.
- Preserve unrelated work. Inspect `git status --short` and existing diffs before editing; read every file before changing it. Never reset, clean, stash, stage or overwrite others' changes to simplify a task.
- Match current patterns. No unrelated features, refactors, dependency changes or infrastructure.
- Destructive operations, external communication, credentials, hosted mutations, production migrations, feature activation, deployment and TestFlight upload require explicit authorization for that scope. A command in a document is not authorization. Existing authorization persists; do not ask again for the same approved action.

## Route to sources before selecting a model

1. Establish expected behavior, affected account/data boundaries and what would prove success.
2. First repository discovery command in each session: `python3 scripts/agents/policy.py --discover`. It returns valid route IDs and verified existing owner paths. Copy IDs from that output; never infer an ID from a capability name. `git status` and reading bootstrap instructions may precede discovery.
3. For files outside the returned sources, run `python3 scripts/agents/policy.py --files '*Name*.swift'` (quoted filename glob) or `rg --files`/native Glob first. Use the exact returned path for Read/sed/rg/Grep; never reconstruct its directory from a filename or guess search roots. Content searches can start at repository root with a filename glob. Then run `python3 scripts/agents/policy.py --paths <discovered-path> ...` or repeated `--route <copied-id>` and read owners/specifications. Read-only workers without shell use supplied catalog output plus native Glob before scoped reads/searches. Maps are starting points, not proof a file is mounted, a contract is deployed, or a test covers behavior.
4. Combine all applicable routes. A screen plus a tracking write needs UI and Library contracts; an RPC needs its clients and database authorization contract. Include existing tests even when no test file is edited.
   For SQL claims run `python3 scripts/agents/policy.py --rpc <function>` for the client RPC and relevant internal callees. Inspect later definition candidates in both migration folders; a directory label or old function body does not establish effective/deployed behavior. Include the Identity route when reasoning about account changes.
5. Missing paths (even when a route pattern matches), unmapped paths, unresolved owners or conflicting sources require discovery. Read the diagnostic, return to `--discover`/`--files`/Glob, and broaden by symbol/caller evidence. Do not retry spelling/directory guesses. Proposed new files still need discovery of existing owners first. Resolve the contract before editing; report unresolved uncertainty. Update stale routes in the same initiative.
   Run discovery/resolver commands directly. Their JSON already supplies paths/lines; avoid formatting pipes or compound shell commands that can obscure the resolver exit or need extra permissions.
6. Choose model/tools after context and verification needs are known. Correctness, account safety and verifiability constrain selection; optimize latency/cost within them. A model's confidence is not validation. Escalate ambiguity, contradictions or failed checks to a capable available model or lead; unavailable switching never lowers the standard.

## Which source answers which question

- Product intent: current user instructions and the relevant approved specification. Old executor prompts do not grant new authorization.
- Local behavior: actual code, mounted composition/routes, contracts and focused tests. `docs/modules/README.md` maps capabilities; `docs/documentation-surface-map.md` distinguishes active and historical documents.
- Technical status: relevant current sections of `CURRENT_APP_STATE.md`; plain-English status: `CURRENT_APP_STATE_PLAIN.md`; initiative status: `IMPLEMENTATION_PLAN_Variation1.md`. Search these large files instead of loading all history.
- Hosted/runtime claims: fresh owning-service evidence or exact dated deployment/qualification receipts. Source, mocks, local passes and prepared migrations never prove hosted parity. Reverify consequential changeable claims when needed.
- Historical material (`archive/`, old dated logs, retired service maps) explains history only. Memory is a navigation hint, not authority.
- When intent, implementation and runtime differ, name the difference. Code establishes implementation; it does not automatically satisfy intent. Never select whichever source makes a check pass.
- Follow production construction and actual argument values. A factory's default parameter, or a path being compiled/constructed, does not establish its effective flag state or whether a caller uses it.

## Current architecture and implementation constraints

- Kuro is a curated anime/manga iOS app: editorial discovery, personal tracking, private clubs and Concierge imports/recommendations. SwiftUI uses `@Observable`, never Combine (`ObservableObject`, `@Published`, `sink`, `assign`).
- Capability owners live in `Kuro/<Capability>/`; `Kuro/Composition/AppComposition.swift` builds one graph over one Supabase client. `SupabaseService` is retired. Do not recreate it, business singletons or SDK calls/imports in views.
- Library is the tracking authority. Views call typed capability APIs, never the store/SDK directly. `LibraryActions` serves editor/widget actions; mounted Home/Collection owners also call the same `LibraryStore` progress APIs in `LibraryProgress.swift`. Trace the composition-configured sender: progress uses `HomeStore`'s sender/credential-lease closure, while the general Library transport has separate gating. Preserve guarded durable/legacy paths; SDK calls stay behind owning capability/transport boundaries.
- Account work captures current `AccountContext`; stale completions cannot publish private state. Register scoped owners in composition. Preserve lifecycle ordering, revocation, cancellation, offline recovery, revision fencing and idempotent replay.
- Match current typed APIs/errors. Check PostgREST errors against the actual decoder, not historical `detail`/`details` assumptions.
- Backend is PostgreSQL/RLS/RPC plus Deno Edge Functions, Storage and scheduled workers. Inspect grants as well as RLS. Derive acting users from authentication; never trust a raw client-supplied acting `user_id`.
- New tables require RLS, deliberate grants, keys, ownership/deletion behavior and appropriate policies (service-only tables may intentionally have no client policy). New SQL functions set `search_path = public, extensions`; check SECURITY DEFINER privileges.
- Applied migrations are immutable. New SQL starts in `supabase/prepared-migrations/` with focused DB checks. Never run blanket `supabase db push --linked --include-all` or history repair under generic implementation authorization. Inspect exact files and live history before authorized deployment.
- Never use nonexistent `supabase db execute`, or `supabase db dump --linked` here. Use supported read-only inspection when needed.
- Foundation Models classification has an iOS 26 guard and fallback, without an FM entitlement. Groq is optional narration, not routing/classification authority.
- Retain raw intake data and provenance. Stale caches, provider search links and dependent upstreams are not independent replacement sources. Inspect current workers before changing provider behavior, budgets or cadence.

## Latency, concurrency and data hygiene

- Capacity is workload-specific qualification. The 100-active-user target is not measured production concurrency. Use dated evidence through the `performance` route; do not copy live tier/pool/flag state into always-loaded defaults.
- Measure critical-path latency, fan-out, payloads, DB occupancy and p95/p99 by relevant cohort. Separate cold, steady-state, provider, network and native-rendering time. Overall percentiles never override failed subgroups or missing stages/samples.
- Avoid N+1 reads, unbounded work and repeated identical queries. Batch and bound concurrency within DB/shared provider budgets. Parallelize only independent operations. Keep transactions short and outside remote HTTP waits.
- Preserve cached content during refresh within account/permission scope; cancellation and request/account generations prevent stale publication. Never show another account's cache.
- Justify indexes using representative plans and read/write/storage tradeoffs; not every filter needs an index. Use appropriate cursor paging. Explain correctness/performance tradeoffs against the relevant budget.
- Repeated writes need idempotency or mutation/revision fences. Workers need exclusive claims, bounded batches, crash/lease recovery and idempotent effects; locks alone do not guarantee exactly-once effects.
- Define purpose-specific retention, deletion, foreign-key behavior and rate limits. Growing durable user records do not imply automatic purging. Fixtures need scoped verified cleanup; production fixtures require authorization.

## UI and platform contracts

- Use `Kuro/Design/KuroDesignSystem.swift` tokens: monochrome statuses, serif editorial/sans-serif body, adaptive container widths. Red is for destructive actions. Preserve active light appearance unless requested otherwise.
- No `UIScreen.main`, hardcoded device/card widths or `Kuro/Info.plist` (the plist is at root). Wrap diagnostic `print()` in `#if DEBUG`.
- Navigation follows `docs/superpowers/specs/2026-11-02-navigation-contract-design.md`; Discover follows `docs/superpowers/specs/2026-11-04-discover-usability-design.md`. Use typed routes/pager tap gate, working back/close and accessible controls. Inspect flags and mounted code before asserting page order.
- User/view work has owned cancellation/lifecycle rules. Use existing infrastructure to keep decoding, image work and large sorts off hot main-actor paths.

## Verification and completion

- Select the smallest checks covering the failure modes. Routing output lists check candidates, not a command to run every suite. Inspect runner requirements, target and side effects before execution.
- Check actual owners/transports when relevant: empty/error/offline paths, stale accounts, rapid edits, retries/lost responses, revocation and authorization. Assertions establish behavior, not merely implementation shape.
- Use focused Swift package/native suites, relevant offline Deno tests or the disposable local DB harness. Confirm selected tests execute. Fixture/replay limitations remain explicit.
- Simulator tests use a verified available/owned iPhone 17 Pro UUID. Do not seize/reset another session's simulator or use iPhone 16 Pro. Inspect current native runners. Broad `run_all.sh`, exports, live probes, load tests and release jobs are not routine checks for narrow edits.
- Policy checks: `python3 scripts/agents/policy.py --check`, `python3 -m unittest discover -s scripts/agents -p 'test_*.py'`, and `bash scripts/quality-gates/check_docs_current_state.sh`.
- When changing the Claude adapter, also run `python3 scripts/agents/policy.py --check-claude`. Tests need disposable writable temporary storage; a read-only checkout can stay read-only while a test-specific scratch directory is writable. Never widen repository/network permissions merely to bypass a test failure.
- After every file-changing initiative update relevant sections and append dated Change Log/status entries in `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, and `IMPLEMENTATION_PLAN_Variation1.md` when tracked. Update the active executor's existing project memory with changed files, patterns/gotchas and relevant inventory changes; private memory paths are not shared authority.
- Report changed files, ownership evidence, exact checks/outcomes, blocked/skipped validation and remaining gaps. Distinguish implemented, locally verified, deployed and device-accepted. Never mark unmet requirements complete.
