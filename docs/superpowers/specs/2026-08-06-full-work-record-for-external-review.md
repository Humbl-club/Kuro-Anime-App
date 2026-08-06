# Kuro taste overhaul — complete work record for external review (2026-08-06)

**Audience: an external reviewer (Kimi K3) with full repo access.** This is the
complete, honest record of everything on branch `kuro/taste-overhaul` — 31 commits,
215 files, +54,463 lines, ~35 production migrations, spanning 2026-07-30 → 2026-08-06.
Every claim points at a committed artifact or a live-DB check you can re-run.

**Suggested reviewer instruction:** *"Read this document, then adversarially review
the branch: verify the headline metrics against live prod, attack the judge-provenance
and architecture decisions in §7, and report anything overstated, fragile, or wrong."*

---

## 1. Era 1 — Overnight swarm epic (2026-07-30/31, commit `0b4f499`)

Built by the Kimi K3 swarm per `2026-07-31-kimi-k3-agent-swarm-overnight-epic` (Phase 0
audit → ideation deck → 6 ADRs → implementation → morning brief, all under
`docs/superpowers/specs/2026-07-31-*`):

- **Taste Deck** at pager index 0 (flag `taste_deck_v1`, now 100%): full-page card,
  NOT FOR ME / I KNOW THIS / CALLS TO ME, flick gestures with pager exclusion zones,
  endless dealing, meta chips (ANIME/MANGA · EP · SEASONS · SUB/DUB), loves → Collection
  as PLANNING (server-side), leanings sheet reading the server profile only.
- **Concierge archived** out of the pager (Profile row + `kuro://concierge`; backend intact).
- **Taste math v2** (migrations `20260731060000`–`095000`): IDF tag-vector space
  (`media_tag_vectors`), per-user profiles with 180-day half-life + shrinkage
  w = 0.20·n/(n+20), stratified deck dealing with UCB exploration + MMR, pass memory.
  Live-tested with throwaway accounts; 3 real bugs found+fixed that night (P0 deck-down
  via pg_safeupdate, P2 privilege escalation on 12 functions, P3 inverted profile vectors).
- **Clubs trust pack, image-convergence triggers, outbound-click monetization ledger**
  (flag OFF), 5 dark feature flags.
- **Discover P1** (`81f7fa3`, `99ffb26`): The One Thing hero (daily editorial rotation),
  Because-You rail (flag 0%), monochrome score chips, larger rail cards.

## 2. Era 2 — Realm Graph Stages 1–2b (2026-07-31 → 08-02, commits `90a8659`…`51c013e`)

Per `2026-07-31-realm-graph-master-plan.md` (the two-axis model: graded membership in
~40 hand-designed realms × acclaim tier within realm):

- **Stage 1**: `realm_signatures` (842 rows, 40 realms, 12 families), membership/affinity/
  tier matviews, realm-gated similarity, canon_seed (512 rows, 14 award/critic sources),
  `media_rec_edges` import (103k AniList recommendation edges).
- **Stage 2b**: LLM descriptor pass — 7,166 titles (`media_realm_llm`), ±0.2 membership
  delta overlay (`media_realm_membership_delta` + `_effective` view), Spirited Away gate
  harden, `discover_realm_rails_v1` RPCs (`fetch_tonight_shelf`, `fetch_realm_hidden_gem`)
  + iOS (flag 0%), curation sources expansion (`curation_seasonal_signal`),
  YOUR REALMS in the leanings sheet.
- Known-flawed at the time and later fixed: heuristic gold eval was circular; descriptor
  deltas were 95.7% flat +0.2 stamps; the Groq writer was abandoned mid-drain.

## 3. Era 3 — Verification audit + decision lock (2026-08-04, `b18acc5`…`6c2aed9`)

Four independent audit agents (docs / repo+git / live DB / iOS) verified the swarm's
claims. Headline true state at audit time: penalty term inert (double sign accident →
clamp zeroed it), tier-refresh cron 0/4 (un-re-armable timeout), similarity RPC timing
out (53/100 gold seeds), tier built from raw membership while similarity read effective
(split-brain), ~600 visible titles tier-less, owner gold judgments nonexistent, both
realm flags dark, 7 prod-applied migrations uncommitted. Full evidence in the audit
messages + `reports/realm-repair/m1-verify.md` §1.

Owner then locked THE plan: `2026-08-04-realm-repair-and-critique-plan.md` — repair →
scoreboard → critique pilot (sites-then-titles-then-parse) → swarm → regrade; fixed
critique axes (story/visuals/characters/pacing/sound/legacy) + verdict-voice copy
table + deadpan content notes; model assignment (Fable 5 structure/QA, Sonnet parsing,
Haiku mechanical-with-calibration).

## 4. Era 4 — Phase 1 repair (2026-08-04/05, `c40bd6e`…`4e3c683`)

Executed per the owner's autonomous run prompt (`docs/superpowers/plans/
2026-08-04-claude-code-autonomous-phase123-prompt.md`), every fix through
implement → independent live verify → defect-first review (all APPROVE):

- **Fix 1+2** (`20260804100000`, `110000`): penalty operator restored to the Feb
  `+ negative` convention; hard gates → cost ladder (×1.0/0.85/0.65, smooth mem_term);
  SA-specific vetoes deleted; NULL tier no longer drops candidates; Totoro credits
  backfilled (it had ZERO staff/studio rows; 60 canon titles share the hole).
- **Fix 3+4** (`120000`, `121000`): `media_realm_tier` matview → RLS table built FROM
  effective membership (split-brain closed), staged rebuild fn; dead cron root-caused
  (postgres role's 2-min statement_timeout cannot be re-armed in-function; SET-first
  multi-statement cron fixes it) — first green run 136s.
- **Fix 5** (`130000`–`132000`, `140000`): precomputed `media_similar_titles`
  (top-30/seed, 225,541 rows), advisory-lock chunked builder, self-healing 5-min driver
  + nightly re-stale; RPC → indexed read + multi-seed blend + per-user exclusion at
  read; verbatim live scorer kept as fallback; `media_franchise_components` as the
  single franchise-label source. **p95 1.9–3.6s → 42–105ms; gold eval 53/100 timeouts → 100/100.**
- **Fix 6** (`150000`): secret-scraper function family dropped; 3 SECURITY DEFINER view
  advisors cleared via security_invoker (advisor ERRORs 3 → 0).
- **Incidents on record**: builder work_mem OOM → **~25-min production outage**
  (19:20–19:45 UTC 08-04, fixed `131000`); manga batch timeouts (fixed `132000`);
  pg_cron silent-no-op trap documented (a 16ms "succeeded"/"SET" run did nothing).
- Acceptance harness `scripts/realm_repair/run_phase1_acceptance.js`: 13 PASS / 0 FAIL /
  1 documented SOFT-FAIL (G3: importer never captured studio isMain + tag-space).
- Full QA sweep afterwards found 2 pre-existing Aug-1 breaks (stale doc counts; 8
  never-green deck tests) — fixed (`75f23cb`); simulator smoke vs repaired backend:
  nothing broken, one live user-facing bug found+fixed (One Thing lowercase argument,
  `20260805100000`).

## 5. Era 5 — Measurement, corrections, the fork, the pilot (2026-08-05, `32d5567`…`754d21c`)

- **Gold scoreboard v1** (owner redirected judging to Fable 5): pooled-arms design
  (judge the arms' actual top-10s), 4 parallel judges, 1,839 verdicts with reasons +
  honest unknowns. Result: **raw AniList edges P@10 0.847 vs realm-gated cosine 0.512**
  — the first non-circular measurement. Veto-review tool for the owner:
  claude.ai/code/artifact/f026a849-76ef-41e0-ada7-9d25db31b0db.
- **Realm assignment audit**: 6 agents × 500 titles (canon ∪ rank≤5 served, 3,000):
  **13.4% misfiled**, six cross-confirmed failure classes (setting-keywords-beat-register,
  sports erasure, sequel drift, canon-as-misc-bucket, register inversions, missing
  magical-girl realm), w1<0.55 tripwire (20% vs 3% error). All 396 second-judged →
  **393 applied** (`20260805110000`+`112000`) via `realm_audit_overrides` +
  conditional-ordering weight swap (absorption-tracked, reversible); 84 fiat memberships
  on record; non-overridden titles byte-identical. Gold delta: metric-neutral (0.512),
  composition improved — located the ceiling in the retrieval, not the labels.
- **Edges-first serving fork** (owner-decided, `20260805120000`): builder ranks
  community edges first (per-seed min-max rating → 3.0–4.0; penalties clamp to 2.6),
  safety gates demote, cosine backfills. 91.9% of top-10 slots edge-sourced. After
  delta-judging 302 new candidates (85.5% relevant): **gated P@10 0.512 → 0.823**
  (raw ceiling 0.850). Harness P1/P2 re-scoped to junk-class intent (penalized AND
  sub-merit; demotion-below-clean-band). SA's rail is now the Miyazaki list; Totoro #2.
- **Entry-point canonicalization** (`140000`+`150000`): 2,946 franchise entry points;
  rails recommend franchises via entry points (TR → MHA S1 / WIND BREAKER S1; Death
  Parade → Danganronpa: The Animation via a documented editorial relations bridge);
  SA/Berserk control seeds byte-identical; 380 rows remapped.
- **Critique ingestion pilot** (`20260805130000` + parses): 6-table schema (no-prose-by-
  construction, atomic validated ingest RPC), blessed slate seeded; 3 Sonnet parsers →
  **25 reviews / 55 claims / 5 content notes / 25 titles scored, 6 named critics,
  100% mechanically-enforced quote fidelity, 0 misattributions** (edition/season
  mismatches skipped, never guessed). Gate verdict (`reports/critique-pilot/gate.md`):
  parser PROVEN; coverage structural (21%) — levers: ANN re-admission (Wrong Every
  Time's real reviews live there), Medium owner-session lane, Kincaid permission
  (email draft ready), (url, media_id) key widening for multi-title essays.
- **Round 0 dossiers** (12 sites EN+JP with robots/TOS forensics), Phase 2 owner
  handoff, 117-title pilot list, magical-girl realm proposal, close-out docs.

## 6. Live state (re-verifiable)

Similar rails: p95 ≤105ms, gold gated P@10 0.823 (raw 0.850), franchise-entry-canonical.
Realms: 393 corrections live, tier from effective, nightly chain green unattended
(04:30 membership → 04:40 affinity → 04:50 tier → 05:10 re-stale → driver drains).
Critique layer: schema + 25 pilot reviews live. Security advisors: 0 ERRORs.
Acceptance: `node scripts/realm_repair/run_phase1_acceptance.js` → 13 PASS / 0 FAIL /
1 SOFT-FAIL. Gold eval: `node scripts/eval_realm_rec_gold.js`. All flags for realm
surfaces still 0% (owner ramp decision).

## 7. What the reviewer should attack (known soft spots, stated by the author)

1. **Judge provenance**: the gold judgments and realm audit were produced by the same
   model family that built the system (Fable 5 agents), mitigated by reasons+confidence
   audit trails, second-judge passes, and a pending owner veto — but the scoreboard's
   independence is a fair target. The 0.823 rests on those labels.
2. **AniList dependency**: edges-first makes serving quality dependent on AniList's
   community graph (coverage: 7,220 seeds, ~14 edges each; 2/100 gold seeds have zero
   surviving edges). Kuro's "not just AniList" identity vs this dependency is a real
   tension the owner accepted knowingly.
3. **Correction-layer sunset**: `realm_audit_overrides` is temporary-by-contract
   (conditional swap = absorption metric), but the Phase-5 signature regrade that
   absorbs it doesn't exist yet. Bridges become permanent.
4. **Pilot scale**: 25 reviews proves the parser, not the layer. Craft scores feed
   nothing user-visible yet; tier does not yet consume critic consensus.
5. **Unaudited majority**: realm audit covered 3,000 of 11,629 served titles; the
   low-w1 re-review queue is designed, not built.
6. **Un-reviewed final stretch**: eras 1–4 had per-fix defect-first reviews; the
   entry-point canonicalization and critique schema (era 5 tail) were implementer-
   verified (acceptance green) but got no independent reviewer pass — session-limit
   economics. Fair game for the harshest look.
7. **Owner walls honored but pending**: veto pass, IMPORT_SECRET rotation (still a
   literal in import cron commands — scraping tooling removed, literal remains),
   flag ramps, slate v3, magical-girl realm.

## 8. Key evidence index

`reports/realm-repair/` (m1-verify.md, phase1-acceptance.*, phase2-owner-handoff.md,
smoke/) · `reports/realm-audit/` (summary.md, misassignments.jsonl, apply_set.jsonl,
verify_f1/f2.jsonl, mahou-shoujo proposal) · `reports/realm-rec-gold/latest.*` ·
`eval/realm_rec_gold/` (seeds, pools, judge_out_*, judgments + fable5 audit trail) ·
`reports/critique-pilot/` (12 dossiers, parse_*.md, gate.md, Kincaid draft) ·
`docs/superpowers/specs/2026-08-04-realm-repair-and-critique-plan.md` (THE plan) ·
migration headers `20260804100000`–`20260805150000` (each carries its own rationale,
incidents, and revert path).
