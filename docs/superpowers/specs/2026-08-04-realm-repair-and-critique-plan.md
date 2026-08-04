# Realm repair + critique ingestion — decision lock (2026-08-04)

Status: direction locked by owner 2026-08-04. Supersedes the open A/B/C axes question
(answer: fixed axes + one proving quote). Extends `2026-07-31-realm-graph-master-plan.md`
and `2026-08-02-curation-sources-research.md`. Visual: claude.ai/code/artifact/43c1f297-477b-4100-9cf9-d3aa7983d333

## The verdict on the graph (verified 2026-08-04)

Architecture is sound (two axes, projection over clustering, SQL weight class, one space
for titles + users). Four structural faults, all fixable inside it:
1. Tags are the only measurement — they say what a title is *about*, never what it *is*.
   (Spirited Away: `supernatural-yokai` 0.608 vs `auteur-cinema` 0.603 — 0.005 picks the
   neighborhood; Totoro gated out at 0.287 < 0.35; Kon absent.)
2. Fuzzy membership feeding hard cliffs (≥0.35, top-realm-in-S, affinity ≥0.9) — brittle,
   whack-a-mole vetoes.
3. Serving shape wrong: live gated-cosine RPC times out (53/100 gold seeds; anon too).
4. No measurement layer: owner gold set empty, heuristic eval circular, acceptance = 1 seed.

Known-broken details: penalty term inert (`- greatest(0, penalty)` over all-negative rows;
correct fix restores Feb's `+ coalesce(penalty, 0)` operator — see 20260203201000, do NOT
flip stored signs); `realm-tier-refresh` cron 0/4 (timeouts); tier built from raw membership
while similarity reads `_effective` (split-brain); ~600 visible titles have membership but
no tier row (NULL gate drops them silently); `_ops_import_secret_from_cron()` still in prod.

## Locked decisions

- **Three measurement layers, one graph.** Tags = subject only (demoted). Craft lineage =
  first-class axis (not an `ilike` multiplier). Critic ingestion = the quality/warning layer.
- **Critic ingestion design** (the owner's plan, structured):
  - Hand-picked **niche** critic sites only, in a trust-tiered registry (A–E, same pattern
    as canon awards). No general aggregators, no "anybody's opinion".
  - Agents read reviews → **parse, don't hoard**: fixed axes + verdict (0–4) + one proving
    quote + source. Never store full prose (also the legal posture: quote + attribution +
    robots.txt respect).
  - Axes: **story · visuals · characters · pacing · sound · legacy**.
  - Tables: `critic_sources` (registry) · `media_critic_claims` (title × axis × verdict ×
    quote × source) · `media_craft_scores` (consensus per axis, 0–1) ·
    `media_content_notes` (type × severity × evidence quote × source).
  - **Content notes are separate and deadpan** (e.g. Made in Abyss: sexualized minors ·
    high). Fun is for quality, never for safety.
- **Verdict voice**: DB stores 0–4; display voice lives in one `verdict_voice` copy table
  (swappable, DE-translatable, no migrations). Locked vocabulary v1:
  - Story: peak fiction · cooking · mid · plot optional · dumpster fire
  - Visuals: sakuga feast · clean · serviceable · budget ran out · slideshow
  - Characters: unforgettable · alive · fine · cardboard · who?
  - Pacing: no filler · tight · breathes · drags · filler hell
  - Legacy: changed the game · aged like wine · of its time · aged like milk · footnote
  - Compound verdicts (parser-detected patterns): carried by animation · three-episode
    rule · fumbled the ending · read the manga · sleeper · slow burn, worth it
- **Beautiful trash is a shelf, not an insult**: joy ≠ acclaim, computable (score vs
  favourites divergence). Low tier + high joy = dealable, recommendable, and printable in
  leanings ("a documented weakness for beautiful trash"). Kills the elitism failure mode.
- **Tier = earned**: AniList score + critic consensus + awards/canon. "Classic" stops being
  tag-guessed.
- **Gates → costs**: distance demotes, doesn't kill. Hard cliffs only at family/tier level.
- **Precompute serving**: nightly `media_similar_titles` (top-30 neighbors per title).
  Kills the timeout class, makes eval reproducible.
- **Taste stays strictly per-user** (verified in place): signals → own profile only, JWT-
  derived user id, RLS, 20% cap. Shared layer = title facts only, never user behavior.
  Future deck co-occurrence = explicit opt-in decision, aggregates title-side only.
- **Deck integration**: interaction unchanged; critic axes let the same swipes learn *why*
  (visuals-driven vs story-driven). Optional later: post-love one-tap "WHAT GOT YOU? —
  the art / the story / the vibes". Trash dealing requires the joy metric first.

## Order of work

1. **Repair** (~1 day): restore `+ coalesce(penalty, 0)` operator · gates→costs pass ·
   `media_similar_titles` nightly matview · fix tier refresh timeout · build tier from
   `_effective` membership (end split-brain) · backfill ~600 missing-tier titles ·
   drop `_ops_import_secret_from_cron()` · measure similarity p95 under `authenticated`.
2. **Scoreboard** (~1 hr owner time): fill `eval/realm_rec_gold/owner_judgments.jsonl`
   from the 4,000-candidate shortlists. No automated verdict trusted until this exists.
3. **Pilot**: 10 sites (EN+JP mix from curation-sources research Tier A–C), ~200 titles,
   the 4 tables + `verdict_voice`. Gate: parser provably turns reviews into correct rows
   (spot-check sample vs source). No swarm before this passes.
4. **Swarm**: scale agents across the registry.
5. **Regrade**: rerun LLM membership pass with critic evidence — graded memberships and
   demotions, not +0.2 confirmation stamps.

Preview rule: realm/personalization flags stay at 0%; preview via `--ff-on=` on a demo
build. 0%→100% is a product call, made after Repair + Scoreboard.

## Open before Pilot

- Final site list (owner blesses the 10; candidates in 2026-08-02 research doc).
- Axis set confirmation (sound axis optional in v1 if parse quality is thin).
- Joy metric definition for the trash shelf (score vs favourites divergence formula).
