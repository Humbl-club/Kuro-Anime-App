# Realm assignment audit — 3,000 most-served titles (2026-08-05)

Six independent critic-agents audited the assigned top realm of every canon-tier title
plus everything served at rank ≤5 in similarity rails (popularity-ordered cap 3,000).
Verdicts from work knowledge; honest unknowns; suggestions constrained to the taxonomy.

## Headline
- **396 / 2,961 judged = 13.4% wrong** (2,565 ok, 39 unknown)
- Error rate grows with depth: 7.0% (pop 1–500) → 11.4% → 16.2% → 15.4% → 13.2% → 16.0%
- **47% of errors are r1/r2 swaps** — the correct realm already sits in second place
- **w1 tripwire confirmed: 20% wrong below w1 0.55 vs 3% at w1 ≥ 0.70**

## Absorbing realms (%% of their assignments judged wrong, ≥20 assigned)
classic-serial-canon **67%** · food-craft 42%% · quiet-melancholy 31%% · sci-fi-space 30%% ·
cyberpunk-dystopia 30%% · sword-samurai 28%% · moe-cgdct 28%% · seinen-drama 27%% · family-generations 23%%

## Robbed realms (titles that should have landed there)
sports-competition **+50** · comedy-parody +45 · battle-shounen +39 · romantic-comedy +21 ·
dark-fantasy +18 · romance-slow-burn +17 · grand-adventure +14 · supernatural-yokai +12

## The six systematic failure classes (cross-confirmed by ≥2 auditors each)
1. **Setting keywords beat experience** — ARIA→sci-fi-space, Carole & Tuesday→cyberpunk, DBZ Kai→sci-fi-space, Gintama→sword-samurai ×5. The core tags-can't-see-register thesis, measured.
2. **Sports erasure** — ~50 sports titles scattered into moe/romance/family/melancholy realms. sports-competition is the single most-robbed realm.
3. **Sequel/franchise drift** — base entries file sanely, sequels/specials/manga land elsewhere (4 Sailor Moon seasons in 4 realms; Initial D across 3). Needs franchise-level reconciliation with entry-point anchoring.
4. **classic-serial-canon = misc bucket** — 67%% wrong; low-w1 titles with no clean realm default into the prestige realm.
5. **Register inversions** — moe-cgdct fires on male-cast ensembles (Free!, Backflip!!); bl-yuri fires on subtext, misses real yuri; kids-family catches elegies (Night on the Galactic Railroad).
6. **Taxonomy hole: no magical-girl realm** — mahou-shoujo scatters by construction; dark-magical-girl doubly so. First evidenced case for a realm addition.

## Fix plan (staged, none applied yet)
- **F1 (mechanical, high-confidence): r1/r2 swap class** — 187 titles where the auditor's suggestion equals the existing r2. Apply as membership deltas through the existing media_realm_llm → delta plumbing (model tag 'fable5-realm-audit'), then rebuild tier + re-stale affected seeds' similarity stores.
- **F2 (audited corrections beyond r2):** remaining 209, applied same path where the ±0.2 delta clamp suffices; the rest queue for the signature-level regrade.
- **F3 (systemic):** low-w1 (<0.55) re-review queue as a permanent QA loop; franchise reconciliation pass (majority realm, entry-point anchored); signature repairs for the six failure classes; mahou-shoujo realm proposal for the owner's taxonomy fight.
- All of F1–F3 land under Phase 5 (regrade) discipline: measured against the gold scoreboard before/after.

Evidence: audit_out_1..6.jsonl (3,000 verdicts) · misassignments.jsonl (396, popularity-ordered) · input.jsonl · taxonomy.json
