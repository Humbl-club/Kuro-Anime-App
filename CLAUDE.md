# Claude adapter for Kuro

@AGENTS.md

`AGENTS.md` is the shared policy. This file supplies Claude-specific mechanics only.
For Kuro it explicitly supersedes the personal `~/.claude/CLAUDE.md` requirement
to spawn multiple personas for every task. Global settings remain unchanged.

## Routing

- Start discovery with `python3 scripts/agents/policy.py --discover`; copy valid
  IDs and owner paths. Use `--files '<glob>'`/Glob for other filenames before
  scoped reads/searches. Then resolve copied routes/paths before choosing workers.
- `.claude/agents/` supplies optional workers, not mandatory stages. Small tasks
  stay in the main session. Model/tool defaults are checked against
  `.claude/adapter.json`; invocation/organization overrides may still apply.
- `Explore` (Haiku): bounded discovery returning paths/lines and search limits.
- `kuro-implementer` (Sonnet): confirmed owner, explicit scope and verification.
- `kuro-reviewer` (Opus): sensitive/complex review using diff, expected behavior
  and evidence, without the lead's conclusion.
- `kuro-runner` (Haiku): exact caller-selected local check commands and logs.
  Shell execution means this worker is not a read-only security boundary.
- Keep ambiguous architecture, authorization, lifecycle/recovery decisions and
  authorized hosted actions with the lead at an appropriately capable model.
  Do not assume the main session is Opus; inspect the actual model when needed.
- Workers receive task/route context, dirty-tree boundaries, account/permission
  constraints and required evidence. All load shared policy; none omit it for speed.
- Explore/reviewer allow only Read/Grep/Glob, with no shell or MCP tool access.
  The lead runs commands and provides exact output when review needs it.
- Kuro disables the server-side advisor through project `env` settings. It is an
  additional model inference outside ordinary tool allowlists, so explicit worker
  routing must not silently gain an untracked advisor. Global defaults are unchanged.

## Startup and verification

The project SessionStart hook validates policy references and emits a reminder.
It runs no builds, tests, provider calls or mutations. Feedback is diagnostic;
it is not a sandbox or proof of model routing. With project hooks disabled, run
`python3 scripts/agents/policy.py --check-claude` manually. Ordinary source routing
and `--check` validate only the shared core and do not load this adapter registry.

The docs gate checks shared policy and adapter together. Confirm actual worker
selection/model using Claude's `/agents` and `/tasks` when workers are used;
static validation does not establish a fresh Claude session's runtime behavior.

Pre-consolidation instructions, including existing uncommitted edits, are preserved
in `archive/agent-policy-2026-11-09.md` as historical reference only.
