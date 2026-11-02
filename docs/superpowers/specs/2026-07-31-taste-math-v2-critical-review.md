# Taste Math v2 — Critical Review, a Real User's Arithmetic, and the Taste-Map (2026-07-31)

Supersedes §3 of `2026-07-31-taste-math-research.md`. Verified against the live schema: tag categories are `Genre / Theme / Demographic / Content` with per-title `rank` 0–100 (`legacy_sql/02:401`); `media_relations` edges are franchise-only (`SOURCE/ADAPTATION/PREQUEL/SEQUEL/SIDE_STORY/SPIN_OFF` — **no similarity edge exists**); `recommend_ids_similar_to_seeds` scores `overlap × (1 + rank/100) × ln(1 + N/(1+df))` — rank-weighted IDF, i.e. an unnormalized cosine cousin (`20260204234500:81-98`).

---

## 1. Critical review of my own v1 proposal — where it breaks

1. **`deck_known` stalls the ramp.** v1 counted "strong events" as |strength| ≥ 0.3; `deck_known` is 0.25, so it doesn't count — but in real sessions *known* is the most frequent action. n grows at half the honest rate and personalization never wakes up. **Fix: evidence mass, not thresholds.** `n = Σ evidence` with love = 1.0, skip = 1.0, known = 0.5.
2. **Thompson sampling in PL/pgSQL is romantic.** Gamma-ratio sampling in SQL is fragile and undebuggable at 2am. **Kill it; use deterministic UCB**: `explore_score(tag) = mean + 0.5/√(1+α+β)` with a `Beta(1,1)` prior. Same explore-then-exploit behavior, fully explainable, no RNG.
3. **The stratification matrix is over-engineered.** genre × era × format × popularity = 72 quota cells against a score-≥70 pool — quota starvation everywhere. **Collapse to 2 axes**: 6 genre clusters × 3 popularity strata (canon / acclaimed / hidden gems); era becomes an MMR diversity term, not a quota.
4. **PASS records nothing → selection bias.** The system can't distinguish "never heard of it" from "seen it, neutral". Accepted deliberately (PASS = no judgment), but documented: `deck_known` is the user's tool for that, and dealing must not infer negativity from passes.
5. **The score ≥ 70 floor is a deliberate blind spot.** The deck will never learn taste inside low-rated niches. For an editorial decision product that's a feature, not a bug — but it must be *stated*: Kuro maps taste over the acclaimed catalog, not the whole swamp.
6. **One skip must never exile a genre — verified the floors hold** (worked example §4.3). But negative-space probing (p = 0.10) needs the *avoided* list, not raw skips, or it re-deals junk the user only skipped once.
7. **Popularity contaminates similarity.** v1 reused the seed-similarity RPC, which adds `log(favourites)` and score terms. For *ranking* that's fine; for *similarity* it makes every title "similar to" whatever is popular. **Similarity must be content-pure** (§3); popularity lives in the editorial prior only.
8. **The ad-hoc fit sum should be a proper cosine.** Summing profile weights over a title's tags double-counts correlated tags and scales with tag count. Putting users and titles in the **same IDF-weighted vector space** fixes this and unifies fit, similarity, and explainability (§3). This is the biggest mathematical upgrade over v1.

## 2. The taste-map — what a title *is*, in layers

AniList has no subgenre field and no "inspired by" edge. The map must be synthesized from five layers, richest first:

- **L2 — Tags with rank + category (the workhorse).** Hundreds of tags, each with a per-title relevance rank 0–100. Categories do different jobs: `Genre`-category tags refine the 18 coarse genres ("Isekai", "Cyberpunk"); **`Theme`-category tags ARE the storyline layer** ("Coming of Age", "Time Manipulation", "Ensemble Cast", "Slow Burn", "Survival"); `Demographic` tags (Shounen/Seinen/Shoujo/Josei/Kids) encode audience register; `Content` tags encode tone (violence, fanservice). Rank lets us say "Melancholy is *central* to Frieren (85), incidental to another show (30)".
- **L3 — Craft DNA (the "feels like" layer).** Studio, director/creator, original author. "Ufotable fight choreography", "Makoto Shinkai skies", "same mangaka" — the strongest human-intuitive similarity signal, and it exists in our join tables (`anime_studios`, `anime_staff`, `manga_authors`) with roles.
- **L1 — Coarse frame:** 18 genres + format (TV/film/OVA) + demographic. Useful as guardrails and MMR clusters, useless as the main map (everything is "Action, Adventure, Fantasy").
- **L4 — Continuity, NOT similarity:** `media_relations` (SEQUEL/ADAPTATION/SIDE_STORY…) answers "what else is in this franchise", never "what feels like this". Don't abuse it for similarity.
- **L5 — Behavior (future):** cross-user co-occurrence ("users who loved X also loved Y") once multi-user event density justifies it; synopsis embeddings (pgvector) for storyline semantics tags can't express.

**"Inspired by" / "similar to" = cosine over the IDF-weighted L2 vector, with an L3 multiplier** (§3.3). That's the honest version: content-pure, explainable, and built from tables we already have.

## 3. The unified vector model (the real upgrade)

### 3.1 One space for titles and users
Nightly matview `media_tag_vectors`: per (media_type, media_id, tag), `w = (rank/100) × IDF(tag)`, `IDF = ln(1 + N/(1+df))`, N ≈ 63k titles. Genres fold in as pseudo-tags at weight 0.6 × IDF. Rare tags (Rakugo, df ≈ 300) weigh ~8× more than common ones (Action, df ≈ 15k) — **IDF is what makes a profile distinctive instead of generic**.

User vector = Σ over signaled titles of `strength × decay(age) × title_vector`, per-tag negative floor −1.0, title cap 8%, franchise cap 15% (all already implemented), then L2-normalize.

### 3.2 Three consumers, one math
- **personalized_fit(title)** = `cos(user, title)` ∈ [−1, 1] — replaces the v1 sum.
- **similar(a, b)** = `cos(title_a, title_b)` — content-pure "more like this"; upgrades the seed RPC from unnormalized overlap to true cosine.
- **explanation(title)** = top shared tags by `u_i × t_i` — every recommendation can say *why* in one sentence ("because you loved Frieren → Melancholy, Journey, Fantasy"). Honesty brand intact.

### 3.3 "Inspired by" boost
`similar' = similar × (1 + 0.5·shared_creator + 0.15·shared_studio + 0.5·shared_author)` — craft DNA multiplier, capped at ×2. This is the "different title, same soul" case (e.g. a director's other film).

## 4. The arithmetic of one actual user

**Mina, brand new, session 1 (calibration batch, stratified 2-axis):**

| Action | Title | Strength | Illustrative top tags (rank) |
|---|---|---|---|
| LOVE | Frieren | +0.55 | Magic 90, Elves 85, Female Protagonist 75, Journey 70, Melancholy 65 + Fantasy/Adventure |
| LOVE | Violet Evergarden | +0.55 | Female Protagonist 75, Melancholy 70, War 60, Episodic 55 + Drama |
| KNOWN | Naruto | +0.25 | Ninja 85, Action |
| KNOWN | Death Note | +0.25 | Psychological 90, Thriller |
| KNOWN | Attack on Titan | +0.25 | Survival 80, Action |
| SKIP | Rent-a-Girlfriend | −0.45 | Harem 85, Ecchi 80, Romantic Comedy |
| SKIP | My Hero Academia | −0.45 | Superhero 88, Action |
| PASS | ×5 | — | no event (selection bias accepted, §1.4) |

### 4.1 The ramp, numerically
Weighted evidence: `n = 2(1.0) + 3(0.5) + 2(1.0) = 5.5` (v1's broken count gave 4).
`influence = n/(n+20) = 0.216` → ranking weight `w = 0.20 × 0.216 = 0.043` — **after a full first session, personalization holds 4.3% of the vote. Editorial holds 95.7%.** The "first 50–100 swipes" instinct is honored: at n = 50, w = 14.3%; at n = 100, w = 16.7%; asymptote 20%.

### 4.2 Her profile vector (raw strength → IDF-weighted)
Female Protagonist 0.826 · Melancholy 0.743 · Magic 0.495 · Elves 0.468 · Journey 0.385 · War 0.33 · Fantasy 0.33 · Adventure 0.33 · Drama 0.33 · Psychological 0.225 · Ninja 0.21 · Survival 0.20 · **Action 0.15 + 0.15 − 0.27 = 0.03** (two knows, one skip → nearly neutral — correct: MHA alone didn't exile shounen) · Superhero −0.396 · Harem −0.383 · Ecchi −0.36 · RomCom −0.27.

IDF transform (N = 63k): `df(Action) ≈ 15k → IDF 1.65`; `df(Melancholy) ≈ 800 → 4.38`. So **Action 0.05 vs Melancholy 3.25** in the final vector — the profile becomes *her*, not the average anime fan.

### 4.3 Avoidance floors, checked
Ecchi: 1 negative event, cumulative −0.36 → **not avoided** (needs ≥2 events or ≤ −0.8). If she skips one more ecchi title → ≥2 events → avoided, and NTY candidates with Ecchi rank ≥ 60 take the −0.5 penalty. One bad mood can't exile a genre; a pattern can.

### 4.4 Cosine fit, computed (toy subspace, shared dims only)
IDFs: Fantasy 2.18, Adventure 2.18, Drama 2.30, Melancholy 4.38, Survival 3.27, Coming of Age 3.98, Dark Fantasy 3.76, RomCom 2.82, Iyashikei 4.26.
|u| = 3.63 (dims: Fantasy 0.72, Adventure 0.72, Drama 0.76, Melancholy 3.25, Survival 0.65, RomCom −0.76).

| Candidate | dot(u,·) | |·| | **cos fit** |
|---|---|---|---|
| Ranking of Kings (Fantasy 95, Adventure 90, CoA 85, Drama 70, Melancholy 40, Survival 30) | 10.45 | 5.11 | **+0.563** |
| Made in Abyss (Adventure 95, Fantasy 90, DarkFantasy 85, Survival 75, Drama 65) | 5.63 | 5.16 | **+0.301** |
| Takagi-san (RomCom 90, Iyashikei 75, Slice of Life, Comedy) | −1.93 | 4.68 | **−0.114** |

The melancholy-fantasy lover gets *Ranking of Kings* first and the RomCom is actively buried. Sanity holds.

### 4.5 The blend — why early swipes don't hijack ranking
Editorial priors (popularity-normalized): Takagi 0.85, Abyss 0.80, RoK 0.75. Final = `(1−w)×prior + w×fit`:

| | n = 5.5 (w = 0.043) | n = 60 (w = 0.15) |
|---|---|---|
| Takagi-san | **0.808** | 0.705 |
| Made in Abyss | 0.779 | **0.725** |
| Ranking of Kings | 0.742 | **0.722** |

At n = 5.5 popularity still rules (correct — 12 swipes shouldn't rewire the app). By n = 60 the same profile flips Takagi below both fits. **Same signals, different evidence mass — the ramp doing exactly what you asked for.**

### 4.6 Exploration UCB, computed
Unseen tag (Sports): α=1, β=1 prior → `0.5 + 0.5/√3 = 0.79` — high explore score → sports titles get dealt early *despite zero signals* (that's information gain). After 3 skips: α=1, β=4 → `0.2 + 0.5/√6 = 0.40` → quietly stops appearing. Weekly ×0.95 decay re-widens old posteriors → drift comes back as exploration automatically.

### 4.7 Time decay
Her Frieren love at day 180: `0.55 × 0.5^(180/180) = 0.275`. At day 360: 0.14. Stored raw, decayed at aggregation — history is never deleted, just allowed to fade.

## 5. Revised implementation deltas (v2)

1. `media_tag_vectors` matview (tag weights × IDF, genres folded at 0.6) + nightly refresh alongside the existing matview cron.
2. `recompute_user_taste_profile` v3: build the user vector in the same space (decay 180-day half-life, weighted-n shrinkage k = 20, caps unchanged, negative floors) — store the normalized vector, not ad-hoc sums.
3. `fetch_taste_deck_batch` v3: 2-axis stratification (6 clusters × 3 popularity strata), UCB explore slots via `taste_tag_stats` cache (α/β from deck events, prior (1,1), weekly ×0.95), MMR λ = 0.7 with ≤ 4/12 per cluster, ≤ 2/12 per franchise, negative-space probe p = 0.10 from the *avoided* list only.
4. `fetch_personalized_new_to_you` v2: fit = cosine; blend `final = (1−w)×prior + w×fit`, `w = 0.20 × n/(n+20)` (replaces the tier-lookup weight).
5. Similarity upgrade (seed RPC v2): full cosine + L3 craft multiplier, popularity terms removed from *similarity* (kept in ranking).
6. Metrics: deal→love by stratum, catalog coverage, avoidance-reversal rate, profile churn.
7. Later, density-gated: cross-user co-occurrence (CF) + pgvector synopsis embeddings for the storyline semantics tags can't express.

All pure SQL except none — no iOS changes needed; flags and the 0.20 contract cap stay as the brake.

---

## Errata & live verification (2026-07-31 evening)

Implemented and pushed the same day (`20260731060000_taste_math_v2.sql` + hotfixes `…070000…` / `…080000…`, pass-memory `…090000…`). Production immediately corrected several spec details — this section is the errata; the sections above remain the design record.

**Spec errata (what actually shipped):**

- **Avoidance requires net-negative sentiment.** §4.3's floor (≥ 2 negative events or cumulative ≤ −0.8) shipped with an added guard: a tag is avoided only if it is *also* net-negative overall. Without it, a heavily loved genre with two incidental skips (live artifact: Drama) got "avoided" while the user clearly loved it.
- **Stored vector = top-60 tag keys by abs mass + ALL `genre:` keys with abs(w) > 0.001** (was top-80 in §5.2). The top-80 cut was truncating genres out of the stored profile entirely.
- **Genre weight = 1.2 × √IDF** (was 0.6 × IDF in §3.1). IDF-drowned genres plus §5.2's positive-only caps produced **inverted personas**: a Fantasy lover's vector came out 87% negative with `genre:fantasy` itself negative. The fix paired the genre re-weight with **symmetric absolute-mass caps** (caps now bound positive and negative mass alike), and the negative-mass ratio dropped 87% → 14% on the live reproduction.
- **NTY avoided-tag penalty narrowed** to `genre:` keys and Genre-category tags only — per-tag avoidance was over-penalizing candidates.
- **`deck_pass` added** (strength 0.00, memory-only): §1.4 accepted that PASS records nothing, but live data showed the cost — passed titles stayed eligible and were re-dealt (2/12 of one user's batch 2 were batch-1 passes). A pass now writes a durable neutral event: no α/β movement, no evidence, no recompute enqueue (unless it replaces a scored action), excluded from future deals, counts toward the 300/day budget.
- **PASS label retired → NOT FOR ME.** The iOS left action went back to DISLIKE semantics (`deck_skip` −0.45) per the "continuous liking/disliking" product decision; `.pass` remains supported server-side for a future neutral-pass UI.
- Thompson sampling was killed for deterministic UCB (already covered in §1.2 — shipped as designed).

**Production findings (things the spec couldn't know):**

1. **Prod data breaks naive uniqueness.** The initial push failed on tag/genre duplicate keys: the live tag tables contain case-variant tag rows and `genres` arrays contain duplicates. Fixed with uniqueness-by-construction (max-rank collapse for tags, distinct unnest for genres) and re-pushed clean.
2. **`pg_safeupdate` is a P0 class.** The deck went 100% down twice: first a bare DELETE on a temp table (hotfix 070000), then two bare UPDATEs without WHERE that had survived review (fix2 080000). Every data-touching statement in these functions now carries a WHERE — verified live with the deck back up.
3. **Postgres grants EXECUTE to PUBLIC by default.** `drain_taste_recompute_queue` (and 11 other internal/definer functions) were callable by any authenticated user. Fixed with explicit revokes from public/anon/authenticated; tier-2 helpers stay authenticated-callable because SECURITY INVOKER RPCs invoke them as the caller. Any future internal function needs an explicit revoke line in its migration.
4. **Live verification methodology.** 3 runs, 4 throwaway users created and deleted via the public auth API (signup autoconfirm is ON), exercised via curl against REST/RPC (not the iOS UI). Verified exact: signal contract; α/β stats 141/141 and 118/118; evidence/event_count; avoidance sets incl. the guard; ramp w at n = 0 / 5.5 / 6.5 (§4.1's 4.3% holds); NTY replicated 20/20 positionally × 3; deck verified live — 12 cards 6/6 anime-manga, stratified (head/mid/gems, not the popularity chart), 12/12 mirrored covers, zero repeats vs signaled titles, meta fields populated; drain cron fired on two */15 boundaries; delete-account cascades clean.

**Still open:** run-2 phantom `discover_rail_impressions` anomaly (20 foreign rows hid one fresh user's top-20; did not recur; one service-role SQL query closes it — prime suspect deploy-window activity 15:55–16:10 UTC); `taste_pipeline_status` contents + `cron.job` registration unverifiable without service-role access (403 correctly enforced); positive-mass caps vs small profiles — watch as data grows; KuroTests has zero deck-action coverage; `deck_known` false-positive watch continues; `personalized_new_to_you_v1` still 0% (ramp criteria: drain telemetry sane + staff rail check).
