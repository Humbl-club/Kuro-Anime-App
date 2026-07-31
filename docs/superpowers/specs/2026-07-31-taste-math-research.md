# Taste Mathematics — Literature Review → Kuro Design (2026-07-31)

> **Superseded in part:** §3 (the Kuro design) is replaced by `2026-07-31-taste-math-v2-critical-review.md` — critical review, unified vector model, worked user arithmetic. §1–2 (literature + mapping) still stand.

How Netflix / the recommender-systems literature actually implements "a continuous game that learns what you love", mapped onto Kuro's existing schema. Every mechanism below cites its source; every Kuro parameter is numeric.

---

## 1. What the literature actually says

### 1.1 Implicit feedback with confidence weights (the base model)
**Hu, Koren & Volinsky, "Collaborative Filtering for Implicit Feedback Datasets" (ICDM 2008)** ([paper](https://yifanhu.net/PUB/cf.pdf), ~4,900 citations): separate *preference* (binary: likes or not) from *confidence* (how much evidence): `c_ui = 1 + α·r_ui` where `r_ui` is accumulated behavior. Watching 80% of a series is worth more than opening it once. **This is exactly what `taste_signal_events.event_strength` already is** — Kuro's Sprint 01 is HKV-shaped, just content-based instead of matrix-factorized.

### 1.2 Pairwise ranking (what swipe data is best for)
**Rendle et al., "BPR: Bayesian Personalized Ranking from Implicit Feedback" (UAI 2009)** ([arXiv](https://arxiv.org/abs/1205.2618), ~9,900 citations): don't predict ratings; directly optimize that observed-positive items outrank unobserved/negative ones per user. A swipe deck is a *pairwise-judgment generator*: each `deck_love` vs each `deck_skip` in the same session is a training pair. BPR is the field-standard objective for exactly this data shape.

### 1.3 Exploration/exploitation (when to show what you're unsure about)
**Li, Chu, Langford & Schapire, "A Contextual-Bandit Approach to Personalized News Article Recommendation" (WWW 2010, LinUCB)** (Yahoo! front page, production-proven): model expected reward per candidate as a linear function of features, and pick by **upper confidence bound** — predicted reward *plus* an uncertainty bonus. Uncertain-but-promising candidates get dealt; as evidence accumulates the uncertainty bonus shrinks. **Thompson Sampling** (Agrawal & Goyal, 2013) is the simpler Bayesian equivalent: maintain a posterior per arm (here: per tag/genre), sample from it, deal the sampled best. TS ≈ LinUCB quality with far less machinery — right for Kuro's scale.

### 1.4 Diversity re-ranking (anti-echo-chamber)
**Carbonell & Goldstein, "The Use of MMR, Diversity-Based Reranking" (SIGIR 1998)**: `MMR(i) = λ·relevance(i) − (1−λ)·max similarity(i, already_selected)`. Greedily pick items that are both relevant *and* different from what's already in the batch. This is the canonical answer to "12 cards that aren't all the same show."

### 1.5 Cold start (when should choices kick in)
The literature's answer is **never a hard gate — it's continuous Bayesian shrinkage**: blend the user estimate with the population prior by evidence mass, `influence = n / (n + k)`. With n = 0 events the user is 100% prior (editorial); the blend grows smoothly. Netflix operationalizes the same idea with an explicit picker onboarding (their "select a few you like" screen) to jump-start n. Hard "do nothing for the first N swipes" rules are *not* what production systems do — instead, early swipes change **what gets dealt next** (calibration/exploration) long before they're allowed to change **ranking** (exploitation).

### 1.6 What the big services actually run (evidence quality noted)
- **Netflix** — published: candidate generation → learned ranking → row-level re-ranking, driven overwhelmingly by *implicit* signals (play time, completions); exploration is continuous (their artwork personalization is literally a bandit per image); evaluation by interleaving A/B. Sources: [Amatriain, "Big & Personal"](https://amatria.in/pubs/BigAndPersonal.pdf), [Netflix TechBlog](https://netflixtechblog.com/foundation-model-for-personalized-recommendation-1a0bd8e02d39).
- **Crunchyroll** — not published. Observable behavior: watch-time velocity + continuation-driven ranking; "not interested" feeds a *global* model, weakly personalized.
- **AniList / MyAnimeList** — not published. Community evidence: hybrid content+CF (tag vectors + rating-graph matrix factorization), MAL with popularity floors on candidates, AniList with fast per-user vector updates on explicit feedback. Treat specific claims from SEO content mills as unverified.
- **Takeaway:** nobody serious uses one model. It's always: **candidates from several generators → ranker → diversity/exploration re-ranker → feedback loop.** Kuro already has the bones of every stage.

---

## 2. Kuro mapping — what exists vs what the math needs

| Stage | Literature | Kuro today | Gap |
|---|---|---|---|
| Signal capture | HKV confidence weights | `taste_signal_events` with signed strengths ✓ | no time decay (a 2023 love = a today love) |
| Profile | content-based vector / MF | `user_taste_profiles` tag/genre vector, caps, confidence tiers ✓ | tiers are a step function; should be smooth shrinkage |
| Pairwise signal | BPR | love/skip pairs accumulate ✓ | not yet exploited as pairs (fine — content vector approximates) |
| Candidate generation | multi-generator | quality-floored catalog + popularity ✓ | no stratification, no exploration generator |
| Dealing policy | bandit (TS/LinUCB) | mirrored-first + popularity ✗ | **the real gap: dealing is pure popularity** |
| Diversity | MMR | none ✗ | batches can echo-chamber |
| Exploit consumer | ranker with prior | `fetch_personalized_new_to_you` (0.8 editorial + 0.2 fit cap) ✓ | good — keep |
| Evaluation | interleaving/A-B | `taste_pipeline_status` + click ledger ✓ | add deal→love rate by stratum |

**The honest conclusion:** Kuro's *storage and representation* are already literature-shaped. The weak link is the **dealing policy** (popularity, not a bandit) and **no diversity mechanism**. That is also the cheapest thing to fix — pure SQL.

---

## 3. The Kuro design (numeric, implementable)

### 3.1 The ramp — shrinkage, not gates
Replace the 4-tier confidence step function with smooth shrinkage (keep tiers only as display copy):

```
influence(n) = n / (n + k)        k = 20 strong events (|strength| ≥ 0.3)
personalized_weight = 0.20 × influence(n)     // 0.20 = contract's max_user_influence
```
n = 5 → 4% influence. n = 20 → 10%. n = 60 → 15%. n = 150 → 17.6%. Never exceeds 20% — editorial prior always dominates, per the frozen contract.

**The user's instinct ("first 50–100 swipes shouldn't skew rankings") is honored through the dealing phases below, not by discarding early data:** early swipes steer exploration immediately, steer ranking only as shrinkage allows.

### 3.2 Dealing phases (bandit schedule on the deck)
Dealing splits every batch of 12 into **exploit slots** (likely loves, from profile) and **explore slots** (information gain). Explore ratio decays but never dies:

```
explore_ratio(n) = max(0.25, 0.75 × exp(−n / 50))
```
| Phase | n (strong events) | Explore | Dealing behavior |
|---|---|---|---|
| Calibration | 0–20 | ~75% | **Stratified quotas**: genre clusters (6 editorial buckets) × era (pre-2000 / 2000s / 2010s / 2020s) × format (TV / film / manga), popularity-stratified (canon head 40% / acclaimed mid 40% / hidden gems 20%). Guarantees the catalog is *sampled*, not chart-read. |
| Blend | 20–80 | ~50–35% | exploit = titles scoring high on profile fit via existing tag-IDF machinery; explore = Thompson sampling (3.3) |
| Living | 80+ | ≤25%, never 0 | exploit-dominant; explore keeps probing drift + negative space |

### 3.3 Thompson sampling per tag (the exploration math)
New table `taste_tag_stats (user_id, tag, alpha, beta, updated_at)` — a Beta posterior per user per tag:
- `deck_love` on a title → `alpha += 1` for each of its top tags (rank ≥ 40)
- `deck_known` → `alpha += 0.3`
- `deck_skip` → `beta += 1`
- weekly decay: `alpha, beta ← 0.95 ×` each (taste drifts; posterior re-widens → exploration naturally returns)
Explore slot score for a title = `mean over its tags of sample(Beta(alpha, beta))`. Sampling in SQL: `ln(-ln(u1)) / ln(-ln(u2))`-style gamma-ratio approximation, or simpler: **expected value + uncertainty bonus** `(alpha/(alpha+beta)) + 0.5/sqrt(alpha+beta+1)` — a deterministic UCB1-flavored variant if true sampling proves ugly in PL/pgSQL. Both are defensible; pick at implementation time.

### 3.4 Diversity — MMR within each batch
After scoring, greedy MMR selection with λ = 0.7:
```
MMR(i) = 0.7 × slot_score(i) − 0.3 × max_tag_overlap(i, already_selected)
```
Hard caps as guardrails: ≤ 4/12 per genre cluster, ≤ 2/12 per franchise (via the media_relations walk already built for the franchise cap), ≥ 2/12 manga if the user has any manga signals.
Negative-space probe: with p = 0.10 per batch, deal one title from a *skipped* tag to confirm or release the exile (feeds `beta` more evidence; the avoidance floors already prevent one-skip exile).

### 3.5 Time decay on all events (HKV extension)
In `recompute_user_taste_profile`: `strength_effective = strength × 0.5^(age_days / 180)` — a 6-month-old signal counts half, a year-old a quarter. Your taste from 2023 informs but doesn't rule. (Events stay stored raw; decay applies at aggregation.)

### 3.6 Metrics that prove it works (extend `taste_pipeline_status`)
- **deal→love rate** by phase and by genre stratum (should rise over time but never hit 1.0 — that means echo chamber)
- **catalog coverage**: % of quality-floored catalog dealt at least once, per user and globally
- **avoidance reversal rate**: how often probed negative space converts (validates the probe)
- **profile churn**: mean |Δweight| per recompute (should decay as n grows)

### 3.7 Later (multi-user, when density justifies)
- Item-item co-occurrence from `taste_signal_events` across users ("loved-by-same-user" counts, nightly matview) → a collaborative generator alongside content fit. This is the CF half of MAL/AniList hybrids. Premature today: single-user events are too sparse.
- Embeddings via pgvector on synopsis/tags — only if the tag vector demonstrably plateaus.

---

## 4. What changes vs what shipped this morning

1. `fetch_taste_deck_batch` v2: stratified/explore-aware dealing (3.2, 3.3, 3.4) — pure SQL, same RPC signature.
2. New table `taste_tag_stats` + updates from `record_taste_deck_signal` (same transaction).
3. `recompute_user_taste_profile` v2: smooth shrinkage (3.1) + time decay (3.5) replacing tier lookups in the *weight* path; tiers kept for display copy.
4. `taste_pipeline_status` v2: metrics in 3.6.
5. No iOS changes required for 1–4. All behind existing flags; ranking influence still capped at 0.20 by the frozen contract.

**Phasing:** 1+2+3 are one migration and the entire "feel" upgrade. 4 is the morning-report extension. 3.7 is a separate sprint with a data-density gate.

## 5. References
1. Hu, Koren, Volinsky — *Collaborative Filtering for Implicit Feedback Datasets*, ICDM 2008 — https://yifanhu.net/PUB/cf.pdf
2. Rendle et al. — *BPR: Bayesian Personalized Ranking from Implicit Feedback*, UAI 2009 — https://arxiv.org/abs/1205.2618
3. Li et al. — *A Contextual-Bandit Approach to Personalized News Article Recommendation (LinUCB)*, WWW 2010 — Yahoo! production system
4. Agrawal & Goyal — *Thompson Sampling for Contextual Bandits with Linear Payoffs*, 2013
5. Carbonell & Goldstein — *The Use of MMR, Diversity-Based Reranking*, SIGIR 1998
6. Amatriain — *Big & Personal: data and models behind Netflix recommendations* — https://amatria.in/pubs/BigAndPersonal.pdf
7. Netflix TechBlog — *Foundation Model for Personalized Recommendation*, 2025 — https://netflixtechblog.com/foundation-model-for-personalized-recommendation-1a0bd8e02d39
