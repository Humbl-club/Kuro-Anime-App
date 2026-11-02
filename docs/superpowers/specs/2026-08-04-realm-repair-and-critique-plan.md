# Realm repair + critique ingestion — THE plan (2026-08-04)

Status: **direction locked by owner 2026-08-04. This is the single canonical document** for
what to do next and how. Supersedes the open A/B/C axes question (answer: fixed axes + one
proving quote). Extends `2026-07-31-realm-graph-master-plan.md` and
`2026-08-02-curation-sources-research.md`. Visual summary:
claude.ai/code/artifact/43c1f297-477b-4100-9cf9-d3aa7983d333

How to read: §1 what's true today · §2 what we decided · §3–§7 the five phases in
execution order, each with concrete steps and a definition of done · §8 model assignment ·
§9 legal posture · §10 owner decision checklist.

---

## 1. Verified state (audited live, 2026-08-04)

Architecture is sound (two axes: realm membership + tier; projection over clustering; SQL
weight class; one space for titles and users). Faults, all verified against production:

1. **Tags are the only measurement.** They say what a title is *about*, never what it *is*.
   Spirited Away: `supernatural-yokai` 0.608 vs `auteur-cinema` 0.603 — 0.005 picks the
   whole neighborhood. Totoro gated out at 0.287 < 0.35. Kon absent from top 25.
2. **Fuzzy membership feeding hard cliffs** (≥0.35, top-realm-in-S, affinity ≥0.9) —
   brittle; the SA "harden" added seed-specific vetoes (whack-a-mole).
3. **Serving shape wrong**: live gated-cosine RPC times out (53/100 gold seeds; anon too).
4. **No measurement layer**: `owner_judgments.jsonl` empty; heuristic eval circular
   (labels partly sourced from the AniList edges it scores); acceptance = 1 self-tuned seed.
5. **Penalty term inert**: live function computes `- greatest(0, penalty)` over
   all-negative rows → total penalty applied across the catalog = 0.
6. **`realm-tier-refresh` cron 0/4 runs** (statement timeouts). Tier data still matches
   (populated at CREATE) but nothing propagates from here on.
7. **Split-brain membership**: similarity reads `media_realm_membership_effective`
   (LLM deltas applied); tier is built from the raw matview (deltas ignored).
8. **~600 visible titles have membership but no tier row** → NULL tier gate silently
   drops them from all recommendations.
9. **Leftovers**: `_ops_import_secret_from_cron()` still in prod; 3 ERROR-level security
   advisors (SECURITY DEFINER views `realm_affinity_effective`, `media_realm_llm_pending`,
   `media_realm_profile`, the last granted to `anon`).
10. **Nothing realm-facing reaches users**: `discover_realm_rails_v1` and
    `personalized_new_to_you_v1` at 0%. Taste pipeline has 53 signals / 2 profiles ever.

---

## 2. Locked decisions

- **Three measurement layers, one graph.** Tags = subject only (demoted). Craft lineage =
  first-class (not an `ilike` multiplier). Critic ingestion = quality + warnings layer.
- **Critic ingestion**: hand-picked **niche** critic sites only, trust-tiered registry
  (A–E, same pattern as canon awards). Agents **parse, don't hoard**: fixed axes +
  verdict (0–4) + one verbatim proving quote + source. Full prose never stored in DB.
- **Axes v1**: story · visuals · characters · pacing · sound · legacy.
  (Sound may be dropped from v1 if pilot parse quality is thin — owner call at the gate.)
- **Content notes are separate and deadpan** (`media_content_notes`: type · severity ·
  evidence quote · source). Example class: Made in Abyss → sexualized minors · high.
  Fun voice never applies to safety. Ever.
- **Verdict voice**: DB stores 0–4; display voice in one `verdict_voice` copy table
  (swappable, DE-translatable, no migrations). Locked v1 vocabulary:
  - Story: peak fiction · cooking · mid · plot optional · dumpster fire
  - Visuals: sakuga feast · clean · serviceable · budget ran out · slideshow
  - Characters: unforgettable · alive · fine · cardboard · who?
  - Pacing: no filler · tight · breathes · drags · filler hell
  - Legacy: changed the game · aged like wine · of its time · aged like milk · footnote
  - Compound flags (parser-detected): carried by animation · three-episode rule ·
    fumbled the ending · read the manga · sleeper · slow burn, worth it
- **Beautiful trash is a shelf, not an insult**: joy ≠ acclaim, computed from score vs
  favourites divergence (formula = owner decision, §10). Low tier + high joy = dealable
  and printable ("a documented weakness for beautiful trash").
- **Tier = earned**: AniList score + critic consensus + awards/canon. "Classic" stops
  being tag-guessed.
- **Gates → costs**: distance demotes, doesn't kill. Hard exclusion only at family/tier.
- **Precompute serving**: nightly `media_similar_titles` (top-30 per title).
- **Taste stays strictly per-user** (verified in place): JWT-derived user id, RLS, 20%
  cap. Shared layer = title facts only. Deck co-occurrence = future explicit opt-in.
- **Deck unchanged**; critic axes upgrade what swipes teach (visuals-driven vs
  story-driven). Optional later: post-love one-tap "WHAT GOT YOU? — art / story / vibes".
- **Flags stay at 0%** until Phases 1–2 are done; preview only via `--ff-on=` demo build.
  0%→100% is a product call by the owner.

---

## 3. PHASE 1 — Repair (~1 day, one migration + one cron change)

All in one migration where possible; each item independently verifiable.

1. **Penalty operator**: in `recommend_ids_similar_to_seeds`, replace
   `- greatest(0, coalesce(p.penalty,0))` with `+ coalesce(p.penalty, 0)` (both anime and
   manga branches). Values stay negative — that is the Feb convention
   (`20260203190000/201000`), and other functions still use it. Do NOT flip stored signs.
   *Verify*: Berserk seed no longer surfaces low-canon isekai (Highserk/Overlord class);
   isekai-tagged candidates drop, never rise.
2. **Gates → costs**: keep hard exclusion ONLY for (a) tier distance > 1, (b) no shared
   family and affinity < 0.6. Convert the rest to multipliers on the cosine score:
   shared top realm ×1.0 · adjacent realm (affinity ≥ 0.6) ×0.85 · same family only ×0.65.
   Membership ≥0.35 cliff becomes a weight term, not an entry test. Remove the two
   seed-specific affinity vetoes once costs land (they were tuned on one seed).
   *Verify*: SA top-12 keeps Ghibli-class; Totoro re-enters; Hanako-kun S2 drops below
   Wolf Children; vending machine still absent (tier gate holds it out).
3. **Missing tiers**: rebuild `media_realm_tier` FROM `media_realm_membership_effective`
   (ends split-brain, item 7) and backfill the ~600 visible titles with membership but no
   tier row. *Verify*: `SELECT count(*)` of visible titles without tier = 0.
4. **Tier refresh cron**: staged rebuild (build into temp table, swap) or raised
   `statement_timeout` inside the job; must succeed on schedule.
   *Verify*: next 2 cron runs green in `cron.job_run_details`.
5. **Precompute**: nightly `media_similar_titles` matview — top-30 neighbors per
   (media_type, media_id) from the repaired scorer; `recommend_ids_similar_to_seeds`
   becomes a cheap read over it (seed-blend at read time for multi-seed calls).
   *Verify*: p95 of the RPC under `authenticated` < 200ms; gold eval runs 100/100 seeds
   with zero timeouts.
6. **Hygiene**: drop `_ops_import_secret_from_cron()`; fix the 3 SECURITY DEFINER view
   advisors (convert to `security_invoker` or restrict grants; `media_realm_profile`
   loses `anon`). *Verify*: `get_advisors(security)` ERROR count back to 0.

**Definition of done**: all six *Verify* checks pass; migration committed AND pushed;
docs triad + MEMORY updated.

---

## 4. PHASE 2 — Scoreboard (~1 hour of owner time)

1. Owner fills `eval/realm_rec_gold/owner_judgments.jsonl` from
   `owner_shortlists.jsonl` (4,000 candidates, 40 per seed, already built). Mark
   `relevant[]` / `rejected[]` per seed; partial coverage is fine — judged seeds only.
2. Re-run `scripts/eval_realm_rec_gold.js --judgments eval/realm_rec_gold/owner_judgments.jsonl`
   AFTER Phase 1 (so it measures the repaired, precomputed graph, 100/100 seeds).
3. Record baseline P@10 in this doc. Every later change (critique layer, regrade) gets
   measured against it. **No automated verdict is trusted until this exists.**

**Definition of done**: ≥50 seeds owner-judged; baseline table appended below; the
AniList-edges ship/no-ship question re-decided on owner data (heuristic verdict discarded).

---

## 5. PHASE 3 — Critique ingestion pilot (the detailed process)

Deliberately staged: **a couple of sites first → owner blesses sites → owner blesses
titles → parse → gate.** No swarm until the gate passes.

### Round 0 — Site scouting (output: dossiers; owner picks 3–4)

1. Candidate pool: Tier A–C names from `2026-08-02-curation-sources-research.md` plus a
   fresh scout of the niche-critique space. Candidate *classes* (examples, not blessed):
   craft/animation desks (Sakuga Blog type) · long-form review sites with named critics
   (THEM Anime type) · content-aware desks (useful for `media_content_notes`) · manga-first
   critics (Mangasplaining / Manga Bookshelf type) · JP critic/seasonal desks (Filmarks
   essays type). Mainstream aggregators and user-review farms are OUT by definition.
2. One **dossier per candidate** (8–12 sites scouted), one page each:
   name · URL · anime/manga/both · language · named critics? · review depth (word count,
   does it argue?) · archive size (est. titles covered) · robots.txt + TOS posture ·
   archive accessibility (index pages? RSS?) · lens/voice · proposed trust tier ·
   one example review link.
3. Fable 5 reads the dossiers, recommends tiers and a pilot slate; **owner blesses 3–4
   sites** (this is the "couple of sites" round — small on purpose).

*Definition of done*: dossiers in `reports/critique-pilot/dossiers/`; owner-blessed list
of 3–4 sites with tiers recorded in `critic_sources` seed data.

### Round 1 — Title shortlist (output: pilot titles; owner blesses)

Selection rules, in priority order:
1. **Overlap first**: titles reviewed by ≥2 blessed sites (consensus becomes testable).
2. **Dual-use**: every gold-set seed (§4) covered by any blessed site is IN — critic data
   then directly improves the eval we already run.
3. **Anchor set**: the named test cases — Spirited Away, Totoro, Kon films, Hosoda,
   Made in Abyss (warnings), 2–3 beautiful-trash candidates (joy-divergence picks).
4. **≥25% manga.**
5. **Cap ~150–200 titles** for the pilot.

Output: `scripts/data/critique_pilot_titles.json` — catalog id, title, inclusion reason,
covering sites. **Owner blesses the list** (quick pass, veto-only).

### Round 2 — Parse pilot (output: filled tables + QA report)

Schema first (one migration, Fable 5 designs, standard rules: RLS on, write =
service_role, read = authenticated, `SET search_path = public, extensions`):

- `critic_sources` — registry: name, url, tier (A–E), lens, language, blessed_at
- `critic_reviews` — one row per parsed review: source, url, url_hash, media ref,
  critic name (if bylined), fetched_at. **No prose column.**
- `media_critic_claims` — review ref × axis × verdict 0–4 × quote (≤40 words, verbatim) ×
  confidence; compound flags as boolean columns or a flags array
- `media_craft_scores` — aggregate per title × axis: consensus 0–1, n_reviews,
  tier-weighted (A×1.0 · B×0.8 · C×0.6)
- `media_content_notes` — media ref × type × severity (low/med/high) × evidence quote ×
  source ref. Types v1: sexual content · sexualized minors · graphic violence ·
  self-harm · abuse. Deadpan always.
- `verdict_voice` — axis × verdict 0–4 × lang (EN/DE) × label

Pipeline per review (stages, each resumable/checkpointed like `realm_descriptor_worker`):
1. **Fetch** (script + Haiku): robots.txt respected, rate-limited, per-site budget.
   Source text cached **locally only** for validation; never committed, never in DB;
   deleted after the pilot QA closes.
2. **Parse** (Sonnet): one review → claims JSON. Only axes the review actually addresses —
   never force all six. Verdict 0–4 + quote + confidence; compound flags; content notes
   extracted separately with their own evidence quote.
3. **Validate** (script): JSON schema; **quote must be a verbatim substring of the fetched
   source — hard fail otherwise** (makes hallucination mechanically detectable regardless
   of model); title resolves to exactly one catalog id (NFKC fuzzy match, unresolved →
   report, never guess).
4. **Upsert** (service-role script, same pattern as `realm_llm_pass_submit.js`).
5. **Aggregate** (SQL): `media_craft_scores` consensus, tier-weighted.
6. **QA** (Fable 5): 30 random claims re-read against their sources; verdict agreement
   and quote-context check. Plus the **Haiku calibration** (§8).

### The gate (pass all → Phase 4; fail any → fix parser, re-run pilot)

- Quote fidelity: **100%** verbatim (validator-enforced; QA confirms context isn't twisted)
- Fable 5 QA verdict agreement: **≥90%** within ±0
- Content-note recall: every known-warning anchor title (Made in Abyss et al.) caught
- Axis coverage: ≥60% of pilot titles have ≥2 axes scored from ≥2 reviews
- Consensus sanity: inter-site verdict spread ≤1 step on 80% of shared titles
- Title resolution: 0 wrong-title upserts in QA sample

**Definition of done**: gate report in `reports/critique-pilot/gate.md` with every number;
owner reads it and calls go/no-go on the swarm.

---

## 6. PHASE 4 — Swarm (scale, only after the gate)

- Owner blesses sites in batches (registry grows tier by tier; every site gets a dossier
  first — same Round 0 template, faster cadence).
- Bulk parse model per §8 (Haiku if calibrated, else Sonnet). Checkpointed workers,
  per-site rate budgets, resumable progress files (gitignored).
- Aggregates refresh nightly next to the other realm crons.
- Coverage report per batch: titles touched, axes filled, notes added, cost.

## 7. PHASE 5 — Regrade (close the loop)

- Rerun the LLM membership pass WITH critic evidence in the prompt — graded memberships
  and demotions this time, not +0.2 confirmation stamps (v1 delivered 95.7% flat +0.2).
- Tier recompute includes craft consensus + legacy axis.
- Re-run the gold eval (§4 baseline) — the number must move or the layer isn't earning
  its keep. Then, and only then, the flag-ramp conversation.

---

## 8. Model assignment (owner-proposed, analyzed, locked)

| Work | Model | Why |
|---|---|---|
| Schema, parser prompts, taxonomy calls, gate design | **Fable 5** | low-volume, high-judgment, expensive to get wrong |
| Site scouting dossiers, research files | **Sonnet** | real reading + synthesis, moderate volume |
| Tier recommendations on dossiers | **Fable 5** (owner decides) | judgment call with brand consequences |
| Fetch, robots checks, title resolution, dedupe, JSONL validation | **Haiku** + scripts | mechanical, well-specified, high volume |
| Review parsing — pilot | **Sonnet** | comprehension: irony, mixed verdicts, "gorgeous but hollow" |
| Review parsing — swarm bulk | **Haiku IF calibrated, else Sonnet** | cost matters at volume, but only after proof |
| QA sample, final implementation review | **Fable 5** | strongest model checks the others' plausible-but-wrong |
| Gold judgments (§4) | **Owner only** | that's the whole point of the gate |

**Haiku calibration gate** (runs inside the pilot): Haiku re-parses 50 reviews Sonnet
already parsed. Bulk promotion requires ≥90% verdict agreement (±0) AND 100% quote
fidelity. Below that, Haiku stays mechanical and Sonnet keeps parsing — measured, not
assumed, same philosophy as pilot-before-swarm.

## 9. Legal / consent posture

Quotes ≤40 words with attribution + link · robots.txt and site TOS respected before any
fetch (recorded in the dossier) · no full-text storage in DB, local fetch cache deleted
after pilot QA · per-site takedown honored immediately (delete claims by source ref —
schema supports it by construction) · JP sites under identical rules.

## 10. Owner decision checklist (everything blocked on you)

- [ ] Bless 3–4 pilot sites (after Round 0 dossiers)
- [ ] Bless the pilot title list (Round 1, veto pass)
- [ ] Confirm axes v1 (keep or drop `sound`)
- [ ] Define the joy formula for beautiful trash (proposal will come with Phase 1)
- [ ] Fill `owner_judgments.jsonl` (§4, ~1 hour)
- [ ] Go/no-go on swarm at the pilot gate
- [ ] Flag ramp decision (after Phase 5, not before)

## §4 baseline — recorded 2026-08-05 (Fable 5 pooled judge, owner veto pending)

100/100 seeds, zero timeouts, 1,839 pooled judgments (judge the arms' actual top-10s):
P@10 raw edges **0.847** · gated graph **0.512** · intersect 0.234 (÷10 artifact on short
lists) · Δ(c−b) −0.278 → pre-registered ship rule: no. Underlying finding: edges are the
strong retrieval signal (86.8% judged relevant), tag-projection cosine is weak (51.2%).
Strategic fork for owner: edges-first-realm-checked serving. Caveats: LLM/AniList
correlated priors; unknowns 4.8% (gated-skewed 6.3% vs 2.7%). Evidence:
eval/realm_rec_gold/judgments.fable5.audit.jsonl + reports/realm-rec-gold/latest.md.
Judge-confirmed realm misassignments (Food Wars→romantic-comedy ×2 judges, Fate UBW→
sword-samurai, HxH→crime-underworld, Mushoku→ecchi-fanservice) are named Phase-5 targets.
