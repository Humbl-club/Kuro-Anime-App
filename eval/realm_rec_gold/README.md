# Realm Graph — rec-edges gold set (Stage 3)

Spec: `docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md` §7.

## Files

| File | Role |
|---|---|
| `seeds.jsonl` | 100 seeds stratified across realms (Kuro + AniList ids) |
| `judgments.jsonl` | Relevant neighbors per seed |

## Harness

```bash
node scripts/eval_realm_rec_gold.js --bootstrap-seeds
node scripts/eval_realm_rec_gold.js --bootstrap-judgments   # heuristic only
node scripts/eval_realm_rec_gold.js                         # score → reports/realm-rec-gold/
```

Arms: (a) raw AniList edges · (b) realm-gated similarity · (c) edges ∩ gate.

**Ship rule:** mean P@10(c) − mean P@10(b) ≥ 0.05 on **owner** judgments. Heuristic bootstrap is for scaffolding only — do not wire edges into `recommend_ids_similar_to_seeds` until an owner pass clears the gate.

## Judgment rubric (owner)

For each seed, mark titles that a Kuro editor would accept as “similar taste neighbors” (same experience family, craft-compatible). Reject LN seasonal TV next to auteur cinema, gag titles next to tragedy, etc. Prefer ~8–20 relevant neighbors; unordered is fine for P@10.

## Owner pass (required before ship)

```bash
# Build A-tier + gated-similarity shortlists for each seed
node scripts/realm_gold_owner_shortlist.js

# Copy template → working judgments file
cp eval/realm_rec_gold/owner_judgments.template.jsonl \
   eval/realm_rec_gold/owner_judgments.jsonl

# Fill relevant[] / rejected[] per seed (use owner_shortlists.jsonl as the menu)
# Then score against owner judgments:
node scripts/eval_realm_rec_gold.js \
  --judgments eval/realm_rec_gold/owner_judgments.jsonl
```

Shortlists prefer titles already in blessed `canon_seed` (Tier A) plus gated similarity neighbors — not raw popularity.
