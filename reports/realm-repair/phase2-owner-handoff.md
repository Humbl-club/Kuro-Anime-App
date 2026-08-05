# Phase 2 — Scoreboard: owner handoff (2026-08-05)

Phase 1 (repair) is done and pushed; the graph you'd be judging is the REPAIRED one
(penalty restored, gates→costs, tier from effective membership, precomputed serving —
`reports/realm-repair/phase1-acceptance.md`). The shortlists below were regenerated
AFTER the repair, so they reflect current neighbors.

**Nothing in Phase 2 can proceed without you.** No automated verdict is trusted until
your judgments exist — the heuristic numbers are circular by construction (labels
partly sourced from the AniList edges they score) and say so themselves.

## What you do (~1 hour, ≥50 seeds is enough)

1. Open `eval/realm_rec_gold/owner_shortlists.jsonl` — 100 seeds, 40 candidates each
   (canon-neighbor + heuristic pools, each candidate labeled with title + realm + tier).
2. Copy `eval/realm_rec_gold/owner_judgments.template.jsonl` →
   `eval/realm_rec_gold/owner_judgments.jsonl` (same directory).
3. For each seed you judge: fill `relevant` with the candidate ids that genuinely
   belong next to the seed, `rejected` with the ones that don't. Skip seeds freely —
   judged seeds only are scored; **≥50 judged seeds** makes the eval decision-grade.
   `notes` is optional but valuable ("right realm, wrong register" etc).
4. Run the eval against your judgments:

   ```bash
   node scripts/eval_realm_rec_gold.js --judgments eval/realm_rec_gold/owner_judgments.jsonl
   ```

   Output: `reports/realm-rec-gold/latest.{json,md}` — mean P@10 for
   (a) raw AniList edges, (b) the realm-gated graph, (c) edges∩gate.

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
