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
| `KNOWLEDGE/INDEX.md` + `KNOWLEDGE/PART-*.md` | Self-contained LLM reference surface | Intentionally overlaps with current-state docs so it can be loaded independently. |
| `docs/production-blockers.md` | Focused audit/reference doc | Narrow-scope operational reference, not a whole-repo authority. |
| `docs/filter-wiring-audit.md` | Focused audit/reference doc | Targeted verification output. |
| `docs/clubs-spec.md` | Product spec | Historical design intent plus still-relevant implementation context. |
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
