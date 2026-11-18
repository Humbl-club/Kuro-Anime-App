# Fresh Claude acceptance — 9 November 2026

**Result: the sampled policy-loading, source-navigation, model-default and local
policy-check requirements are verified after corrections.** This is bounded
runtime evidence, not a guarantee of future agent decisions or application quality.
The initial failures are retained in [evidence.json](evidence.json).

## Actual runs

Claude Code `2.1.319`, existing authenticated installation, Kuro working directory.
Each session used a new UUID, without resume/continue or a CLI model override.
Temporary audit hooks recorded instruction loads and worker lifecycle metadata.
The ordinary project settings/startup hook stayed enabled. A read-only acceptance
tool/command allowlist denied edits; MCP, browser and skills were disabled for the
test. These restrictions are part of the test conditions, not a new global setup.

| Fresh session | Purpose | Outcome |
| --- | --- | --- |
| `6bef0b5b-41ec-41e5-81d5-15e10e778602` | Natural small progress-source lookup | Imported shared policy; no helpers; current Home/Collection/Library paths found; overstrict policy statement flagged |
| `3ac38222-ac1e-4cf1-9d55-43a6b90c0e91` | Four explicitly requested workers | Expected models and 24 passing checks; stale SQL citations, package-command omission and implicit advisor found |
| `e7c70fea-d64d-4d44-a524-de1ec06255d9` | Four-worker corrected retest | Expected models; latest SQL body; exact package command; 30 passing checks; no advisor or denied calls |
| `d1d03597-fe50-4cea-859b-79bc40715c19` | Final sender/composition source confirmation | Shared policy; no helpers; actual outbox sender and explicit production fence argument distinguished; policy check passed |

Every session recorded `AGENTS.md` loading with reason `include`, parent
`CLAUDE.md`, and a successful real project SessionStart policy response. The
personal global CLAUDE file also loaded: both small probes nevertheless used the
project's one-agent default. This is observed behavior on two tasks, not a universal
instruction-adherence guarantee.

## Models observed in assistant message records

No worker call supplied a `model` or `effort` override. Both worker cohorts used:

| Role | Actual returned model ID | Corrected-retest agent ID |
| --- | --- | --- |
| Main session | `claude-opus-5-5` | session ID above |
| Explore | `claude-haiku-5-5` | `a8034b7aa83693207` |
| kuro-implementer | `claude-sonnet-5-5` | `afeee8c5e1c2c6b25` |
| kuro-runner | `claude-haiku-5-5` | `ad7229027d6ed3366` |
| kuro-reviewer | `claude-opus-5-5` | `a391979826c3e9c1c` |

Evidence uses runtime message fields and SubagentStart/Stop IDs, not workers'
self-reported identities. Effort frontmatter matches statically; effective effort
was not independently measured. Read-only workers executed only Read/Grep/Glob.
The implementer performed a read-only preflight, not an implementation-quality test.

## Failures found and corrections

1. **Overgeneralized ownership.** Mounted Home and Collection owners call the same
   Library store/outbox through capability APIs; they do not always pass through
   LibraryActions. Shared guidance and route entry points now include
   `LibraryProgress.swift`, HomeStore, CollectionStore+Lists, widgets and composition.
2. **Old SQL body cited as current.** The public progress wrapper's internal writer
   is replaced by `supabase/prepared-migrations/20261008100000_import_status_fence_preserves_units.sql:7`.
   Added read-only `--rpc` candidate lookup across both SQL folders and regressions
   for later/internal definitions and missing functions. It is a lexical lookup,
   not a schema parser or deployment detector. The retest read/cited the later body.
3. **Incomplete proposed package command.** The preflight now copies
   `swift test --package-path Packages/KuroModules --filter LibraryProgressOwnerTests`
   from the registry. This command was identified, **not executed**.
4. **Implicit additional model.** The first review transcript contains a real
   `server_tool_use` named `advisor`, despite the native-tool allowlist. Its opaque
   result does not establish the advisor model ID. Project settings now set
   `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`, validated by the policy checker. Corrected
   worker hook events recorded the effective environment value `1`; corrected
   retest/final transcripts contain zero server-tool calls. Global settings were
   not changed. The [official advisor documentation](https://code.claude.com/docs/en/advisor#turn-the-advisor-off)
   documents this separate disable control.
5. **Constructed/default versus effective caller.** The final probe traced the
   outbox's `HomeStore.configureProgress` credential-lease/send closure and
   `SupabaseHomeProgressSender`. It also found production composition explicitly
   passes `flags.seriesFoundationFenceEnabled()` to the general Library backend;
   the factory's default `false` does not establish production flag state.
6. **Evidence handoff/reporting limits.** The bounded reviewer did not receive all
   raw runner output, and the runner had a command-count typo and inferred numeric
   statuses. Worker guidance now requires distinguishing observed statuses from
   uncaptured ones. The outer harness independently checked actual tool-call lists,
   tool-success records and test output, and captured separate numeric process
   receipts. Those are labeled separately in the JSON.

One initial compound routing command was denied by the acceptance allowlist and
retried as a permitted direct routing command. The corrected retest/final had no
denials. The initial missing local `__pycache__` was explained by Apple's Python
cache prefix under `~/Library/Caches/com.apple.python`, not a missing test execution.

## Verification actually executed

The fresh Haiku runner executed the three local policy commands separately:

| Command | Corrected-run evidence |
| --- | --- |
| `python3 scripts/agents/policy.py --check` | Tool success; 16 routes/references/adapter PASS |
| `python3 -m unittest discover -s scripts/agents -p 'test_*.py'` | Tool success; **30 tests executed**, `OK` |
| `bash scripts/quality-gates/check_docs_current_state.sh` | Tool success; docs PASS; 293 app Swift /33 package Swift /250 migrations |

The outer harness also ran these commands directly and captured numeric exit code
**0** for each; stdout/stderr/argv are retained as `host_check_receipts` in the JSON.
This independent repeat is distinct from the Claude runner's own status summary.
No Swift/native/package app tests, database harness, app build, load test or hosted
probe was run by this initiative.

## Preservation and limits

Before/after hashes match for **850 tracked app/backend files** in the pre-test
snapshot. The staged binary diff SHA-256 is unchanged, preserving the five staged
SQL additions. Global Claude instructions/settings are unchanged. Intentional
changes are policy/adapter guidance, source routing/lookup tests, the scoped advisor
disable setting, these records and the required state/plan/project-memory notes.

Raw local CLI/transcript locations and hashes are recorded in `evidence.json`;
encrypted advisor content and private prompt/thinking streams were not copied into
the report. JSON includes public session results, exact source/command metadata and
the initial failures. Some runtime files reside in the local temporary directory
and may be cleaned later; the sanitized evidence here is the durable review record.

The bounded workers reported incomplete areas and the lead performed additional
targeted reads. This sample does not establish full progress/replay correctness,
every mounted route, flag values, hosted migration parity, device acceptance,
future autonomous model selection, model quality or a speed improvement.
