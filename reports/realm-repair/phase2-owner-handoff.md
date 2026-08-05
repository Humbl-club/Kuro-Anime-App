# Phase 2 — Scoreboard: owner handoff (2026-08-05)

Phase 1 (repair) is done and pushed; the graph you'd be judging is the REPAIRED one
(penalty restored, gates→costs, tier from effective membership, precomputed serving —
`reports/realm-repair/phase1-acceptance.md`). The shortlists below were regenerated
AFTER the repair, so they reflect current neighbors.

**Nothing in Phase 2 can proceed without you.** No automated verdict is trusted until
your judgments exist — the heuristic numbers are circular by construction (labels
partly sourced from the AniList edges they score) and say so themselves.

## What you do (~1 hour, ≥50 seeds is enough)

1. **Use the interactive judging tool** (easiest path):
   https://claude.ai/code/artifact/f026a849-76ef-41e0-ada7-9d25db31b0db
   All 100 seeds × 40 candidates embedded; tap ✓/✗ per candidate, arrow keys between
   seeds, progress autosaves in the browser, skip freely. **≥50 judged seeds** makes
   the eval decision-grade.
2. Press **Export** — it downloads two files:
   - `owner_judgments.jsonl` → save to `eval/realm_rec_gold/owner_judgments.jsonl`
     (the human-readable record, includes your rejections + notes)
   - `judgments.jsonl` → save to `eval/realm_rec_gold/judgments.jsonl` — this
     **replaces the heuristic file; the eval reads exactly this path** (note: the
     script has no `--judgments` flag — earlier drafts of this doc said otherwise).
3. Run the eval:

   ```bash
   node scripts/eval_realm_rec_gold.js
   ```

   Output: `reports/realm-rec-gold/latest.{json,md}` — mean P@10 for
   (a) raw AniList edges, (b) the realm-gated graph, (c) edges∩gate.
   (Manual alternative: edit the template by hand per the old flow — the tool is
   strictly the same data, just faster.)

## What the numbers decide

- **Ship rule** (pre-registered, `eval/realm_rec_gold/README.md`): edges go into
  ranking only if P@10(c) − P@10(b) ≥ **+0.05 on YOUR judgments**. The heuristic
  run's verdict (ship=false) is scaffolding and gets discarded either way.
- The same baseline measures every later change: penalty-magnitude tuning (the
  −3…−37 integers currently act as bans — collateral: AoT off Berserk's list,
  Boy and the Heron off SA's), the critique layer (Phase 3+), and the LLM regrade
  (Phase 5) all must move this number or they don't ship.

## Current heuristic baseline (context only, NOT decision-grade)

100/100 seeds scored, zero timeouts (that part is real and was the S2 gate):
raw 0.817 / gated 0.199 / intersect 0.145 — inflated toward (a) by label circularity.

## Also waiting on you (from the security sweep)

- **Rotate IMPORT_SECRET** and move it out of the bulk-import cron-command literal
  (Supabase Vault or a properly-set GUC). The scraping tooling is gone; the literal
  isn't. Rotation is prudent regardless.
- Weekly vs nightly similar-store re-stale on the Micro instance (nightly full
  rebuild = ~1–6h of background driver fires; weekly halves the load, staleness
  grows to ≤7 days for changed titles).
