# M1 Verify — Phase 1 Fixes 1+2 acceptance (live production)

- **Date:** 2026-08-04 (evening run)
- **Verifier:** Senior QA Engineer (independent of implementer)
- **Migration under test:** `supabase/migrations/20260804100000_similarity_penalty_and_costs.sql` (applied)
- **Pre-fix snapshot:** `reports/realm-repair/penalty-before.json` (captured 2026-08-04T17:46:55Z)
- **Access:** Supabase Management API `POST /v1/projects/bkdifromsqxkndnllmdj/database/query` (`read_only:false` needed only to EXECUTE the STABLE RPC; every statement issued was a SELECT — zero DDL/DML)

## Summary

| Check | Verdict |
|---|---|
| Deploy sanity | PASS — live def has `+ coalesce(penalty,0)`, no `greatest(0,·)`, cost ladder + mem_term present, 4 veto rows deleted |
| P1 | **PASS** — zero isekai/LN junk in Berserk top-25 |
| P2 | **PASS** — all 16 penalized snapshot candidates decreased (none rose) |
| G1 | **PASS** (caveat: Boy and the Heron nuked by its own Isekai penalty tag) |
| G2 | **FAIL** — Totoro re-enters the pool but ranks #48, not top-25 |
| G3 | **FAIL** — Hanako S2 #8 ABOVE Wolf Children #22 |
| G4 | **PASS** — vending-machine class absent from top-50 |
| G5 | **PASS** on the realm-gate letter (caveat: genre cliff still structurally blocks both Kon films) |

---

## Deploy sanity (precondition)

```sql
select pg_get_functiondef(p.oid) from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname='recommend_ids_similar_to_seeds';

select realm_a, realm_b, affinity from public.realm_affinity_overrides
where (realm_a,realm_b) in (('battle-shounen','supernatural-yokai'),
  ('supernatural-yokai','battle-shounen'),
  ('isekai-reincarnation','auteur-cinema'),('auteur-cinema','isekai-reincarnation'));
```

- Live definition contains `+ case when … else coalesce(ap.penalty, 0) …` (anime) and `+ … coalesce(mp.penalty, 0)` (manga); no occurrence of `greatest(0`; cost ladder (`1.0 / 0.85 / 0.65`) and `mem_term` present. Matches the migration body.
- Veto query returns `[]` — the 4 directed Spirited Away override rows are gone.

**PASS.**

---

## P1 — Berserk (MANGA seed 5) top-25 contains zero low-canon isekai junk

```sql
select o.ord as rank, o.media_id, coalesce(m.title_english,m.title_romaji) as title,
       m.average_score, o.overlap_count, round(o.score::numeric,4) as score
from public.recommend_ids_similar_to_seeds('MANGA', array[5]::int[], 25, false)
     with ordinality as o(media_id, overlap_count, score, ord)
join public.manga m on m.id = o.media_id order by o.ord;
```

Result (rank · id · title · avg · score):

| # | id | title | avg | score |
|---|---|---|---|---|
| 1 | 16 | Vinland Saga | 90 | 0.5329 |
| 2 | 9 | Tokyo Ghoul | 84 | 0.5161 |
| 3 | 115 | Claymore | 81 | 0.5101 |
| 4 | 332 | Devilman | 80 | 0.4962 |
| 5 | 86 | Dorohedoro | 86 | 0.4919 |
| 6 | 78 | Fire Punch | 79 | 0.4624 |
| 7 | 15 | The Promised Neverland | 79 | 0.4239 |
| 8 | 7 | One Piece | 91 | 0.4217 |
| 9 | 108 | Witch Hat Atelier | 87 | 0.4209 |
| 10 | 132 | Made in Abyss | 85 | 0.4096 |
| 11 | 414 | Bibliomania | 78 | 0.4057 |
| 12 | 524 | Leviathan | 82 | 0.4039 |
| 13 | 90 | Fullmetal Alchemist | 89 | 0.3918 |
| 14 | 97 | Kingdom | 89 | 0.3911 |
| 15 | 85 | Uzumaki: Spiral into Horror | 79 | 0.3811 |
| 16 | 175 | The Girl From the Other Side | 82 | 0.3698 |
| 17 | 2 | Chainsaw Man | 85 | 0.3697 |
| 18 | 1238 | Historie | 81 | 0.3477 |
| 19 | 1669 | The Bugle Call: Song of War | 82 | 0.3399 |
| 20 | 742 | PIGPEN | 79 | 0.3377 |
| 21 | 1186 | Basara | 83 | 0.3288 |
| 22 | 977 | Shigurui | 78 | 0.3279 |
| 23 | 494 | Helck | 80 | 0.3249 |
| 24 | 409 | Your Throne | 78 | 0.3196 |
| 25 | 18205 | Fate/Zero | 75 | 0.3166 |

- Pre-fix offenders now gone: Overlord (517, was #12), Clevatess (4178, was #13), Highserk Senki (2236, was #9), God of High School (142, was #18), Tower of God (77, was #21), Index NT (2556, was #22), Magi (159, was #24), So I'm a Spider So What (291, was #25).
- Penalty scan of all 25 new IDs against `manga_tags x editorial_penalty_tags` returns **zero rows** — no title in the list carries any penalty tag.
- Title-level judgment: Helck / Your Throne / Fate/Zero are not the low-canon LN-isekai class; no slime, no "reborn" seasonal entries.

**PASS — zero offenders.**

Observation (not gated): Attack on Titan (was #1, 0.6838, tag "Reincarnation" −10), Land of the Lustrous (was #7, "Reincarnation" −10) and Fata Morgana (2221, −10) also vanished. With raw integer penalties (−6…−37) added to a 0–2.5 score scale, any penalty tag is an effective hard ban, not a demotion. Flagged for the tuning phase.

---

## P2 — No penalty-tagged snapshot candidate's score increased

```sql
-- which snapshot rows carry penalty tags
select mt.manga_id, sum(p.penalty), array_agg(t.name)
from public.manga_tags mt
join public.editorial_penalty_tags p on p.tag_id = mt.tag_id
join public.tags t on t.id = mt.tag_id
where mt.manga_id in (<berserk snapshot top-25 ids>) group by mt.manga_id;
-- same for anime_tags over the SA snapshot ids
-- after-scores: recommend_ids_similar_to_seeds('MANGA', array[5], 50, false)
--               recommend_ids_similar_to_seeds('ANIME', array[111], 50, false)
```

Penalty-tagged candidates in the snapshot (16 of 50 rows) — before score → after:

| Seed | id | title | tags (penalty) | before | after |
|---|---|---|---|---|---|
| Berserk | 6 | Attack on Titan | Reincarnation (−10) | 0.6838 | absent from top-50 |
| Berserk | 77 | Tower of God | Dungeon, Female Harem (−9) | 0.3821 | absent |
| Berserk | 91 | Land of the Lustrous | Reincarnation (−10) | 0.4596 | absent |
| Berserk | 142 | The God of High School | Isekai (−12) | 0.4030 | absent |
| Berserk | 159 | Magi | Dungeon, Reincarnation (−13) | 0.3800 | absent |
| Berserk | 291 | So I'm a Spider, So What? | Dungeon, Isekai, Reinc., Video Games (−28) | 0.3745 | absent |
| Berserk | 517 | Overlord | Dungeon, F.Harem, Isekai, Video Games (−24) | 0.4192 | absent |
| Berserk | 2221 | Fata Morgana no Yakata | Reincarnation (−10) | 0.4102 | absent |
| Berserk | 2236 | Highserk Senki | Isekai, Reincarnation (−22) | 0.4244 | absent |
| Berserk | 2556 | A Certain Magical Index NT | F.Harem, Reincarnation (−16) | 0.3814 | absent |
| Berserk | 4178 | Clevatess | Isekai (−12) | 0.4129 | absent |
| SA | 168 | Bakemonogatari | Female Harem (−6) | 0.3102 | absent |
| SA | 182 | Noragami Aragoto | Reincarnation (−10) | 0.4271 | absent |
| SA | 435 | Kamisama Kiss | Male Harem (−6) | 0.3663 | absent |
| SA | 1413 | The Boy and the Heron | Isekai (−12) | 0.5056 | absent |
| SA | 2768 | InuYasha Movie 2 | Isekai (−12) | 0.3963 | absent |

Non-increase proof, two independent ways:

1. **Empirical:** all 16 are absent from the new top-50 of their seed. 50th-place score is 0.2710 (Berserk) / 0.2059 (SA); every penalized before-score is above that, so every one of them decreased.
2. **Analytical bound:** new score = sim(≤1) × craft·rail(≤2.5) × realm_mult(≤1) × mem_term(≤1) + penalty_sum(≤−6) ≤ **−3.5**, i.e. strictly below every positive before-value.

**PASS — zero increases; all 16 decreased.** (Overall-score reshuffles for non-penalized rows are expected from the new multipliers and are out of scope for P2.)

---

## G1 — Spirited Away (ANIME 111) top-12 Ghibli-class heavy

```sql
select … from public.recommend_ids_similar_to_seeds('ANIME', array[111]::int[], 12, false)
with ordinality … join public.anime …;
```

| # | id | title | avg | score |
|---|---|---|---|---|
| 1 | 200 | Princess Mononoke | 85 | 0.6802 |
| 2 | 161 | Howl's Moving Castle | 85 | 0.6298 |
| 3 | 374 | Ponyo | 79 | 0.4383 |
| 4 | 1259 | xxxHOLiC | 76 | 0.4283 |
| 5 | 92 | Noragami | 78 | 0.4251 |
| 6 | 2759 | Natsume's Book of Friends Movie: Ephemeral Bond | 82 | 0.4041 |
| 7 | 1630 | The Eccentric Family | 77 | 0.3849 |
| 8 | 2142 | Toilet-bound Hanako-kun Season 2 | 79 | 0.3511 |
| 9 | 376 | Suzume | 81 | 0.3509 |
| 10 | 4466 | Okko's Inn | 75 | 0.3359 |
| 11 | 15673 | MUSHI-SHI The Next Passage Special | 82 | 0.3319 |
| 12 | 858 | The Secret World of Arrietty | 77 | 0.3298 |

- 4 Ghibli titles in the 12 (Mononoke #1, Howl's #2, Ponyo #3, Arrietty #12); Kiki's #20 and Porco Rosso #43 in the wider list. Required anchors (Mononoke / Howl's) present.

**PASS.** Caveat: The Boy and the Heron (1413, was #3 pre-fix) is now absent from the entire top-50 — not because of realm gates (its tier is canon) but because it carries an AniList "Isekai" penalty tag (−12), which under the restored operator is a hard kill. Same penalty-magnitude issue flagged under P1.

---

## G2 — Totoro (221) re-enters the SA top-25

```sql
-- top-50 run (same RPC, p_limit 50) + membership/cosine trace queries below
```

- Totoro appears at **rank 48, score 0.2096** in the top-50. It re-enters the candidate pool (pre-fix it was hard-excluded entirely) but is **NOT in the top-25**.

**FAIL** against the check as defined (top-25 re-entry).

Root cause, fully traced (exact decomposition reproduces the observed score):

| Component | Value | Evidence |
|---|---|---|
| cosine vs SA | 0.1843 | only **3** overlapping tag_keys in `media_tag_vectors` |
| craft mult | **1.0** | Totoro has **ZERO rows** in `anime_staff` AND `anime_studios` (SA has 4 studio/4 director rows, Mononoke 4/6, Howl's 5/5) — shared-director (+0.5) and shared-studio (+0.15) can never fire |
| rail mult | 1.25 | shared curated rail with SA |
| realm_mult | 1.0 | top realm kids-family (0.4399) is in SA's realm set |
| mem_term | 0.9099 | shared_w 0.2869 (supernatural-yokai) → 0.5 + 0.5·(0.2869/0.35) |
| **score** | 0.1843 × 1.25 × 0.9099 = **0.2096** | matches RPC output exactly |

**What the implementer must change:** this is a DATA gap, not an RPC logic gap. Backfill Totoro's credits (`anime_staff`: Hayao Miyazaki director; `anime_studios`: Studio Ghibli). With credits present: 0.1843 × min(2.5, 1.65 × 1.25) × 0.9099 = **0.346 → would rank ~#9**, comfortably inside top-25. Secondary lever (M2/Fix 3 descriptor pass): enrich Totoro's tag vector — 3 overlapping keys vs SA is starvation for a sibling film. No change to `recommend_ids_similar_to_seeds` itself is needed for G2.

---

## G3 — Hanako-kun S2 below Wolf Children in the SA list

- Toilet-bound Hanako-kun S2 (2142): **rank 8**, score 0.3511
- Wolf Children (334): **rank 22**, score 0.2980
- Both present; Hanako is ABOVE Wolf Children.

**FAIL.**

Trace (both titles, same seed):

| | Hanako S2 (2142) | Wolf Children (334) |
|---|---|---|
| cosine vs SA | 0.3053 (overlap 8) | 0.2384 (overlap 7) |
| top realm | supernatural-yokai 0.7459 (in S) | auteur-cinema 0.6974 (in S) |
| shared_w / mem_term | 0.6077 / 1.0 | 0.6028 / 1.0 |
| realm_mult | 1.0 | 1.0 |
| extra factor | ×1.15 — **shared studio** with SA: Studio Hibari (id 2132) is credited on BOTH Spirited Away (cooperation credit) and Hanako S2 (Lerche is a Hibari label) | ×1.25 rail |
| tier | canon | canon |
| score | 0.3053 × 1.15 = 0.3511 | 0.2384 × 1.25 = 0.2980 |

Notably both scores are bit-identical to the pre-fix snapshot (0.351125 / 0.298021): the cost conversion is a no-op for titles whose top realm is already in S with strong shared weight, so Fix 2's machinery cannot separate this pair by construction.

**What the implementer must change (two independent levers, either/both):**
1. **Craft-signal precision:** `anime_studios`-based shared_studio treats animation-cooperation credits as creative kinship — Studio Hibari's cooperation credit on Spirited Away hands Hanako a +15% boost against SA. Restrict the shared-studio EXISTS to main-studio rows (if `anime_studios` has a role/is_main column, filter on it; if not, that column is the missing data). Removing the bogus 1.15 drops Hanako to 0.3053 (still above WC's 0.2980 — necessary but not sufficient).
2. **Vector/tone separation (the actual fix):** Hanako's cosine to SA (0.3053, 8 shared tag keys) exceeds Wolf Children's (0.2384) — a school-gag-supernatural show reads closer to SA than a Hosoda family drama in the current tag space. This is Fix 4 (tone/demographic axes) / descriptor-pass territory, not something Fix 1/2 mechanics can express. G3 should be re-run as an acceptance check of that fix.

---

## G4 — Vending-machine / gag-isekai class absent from SA top-25

- 1381 ("Reborn as a Vending Machine…" S1) and 13287 (S2): **absent** from the entire SA top-50.
- Title scan of the SA top-25: no vending-machine, gag-isekai, or "reborn" seasonal peers present.

Defense-in-depth trace:

| id | avg | tier | penalty_sum | blocking layers |
|---|---|---|---|---|
| 1381 | 63 | **acclaimed** | −31 | canon-seed merit floor (63 < 75, not blessed) + penalty −31 |
| 13287 | 64 | solid | −37 | tier distance 2 (solid vs canon) + merit floor + penalty −37 |

**PASS.** Data-quality flag for Fix 3: 1381's tier is 'acclaimed' — tier distance alone (|3−4| = 1) would NOT block it; only the merit floor and penalty do. The tier rebuild should demote it, otherwise G4 rests on the merit floor for canon seeds and on nothing tier-side for acclaimed-tier seeds.

---

## G5 — Perfect Blue / Paprika not structurally excluded by the realm cliff

Resolved IDs: Perfect Blue = **286** (avg 85). Paprika = **486** (avg 79, genres Fantasy/Mystery/Psychological/Sci-Fi/Thriller — the Kon film; the second row titled Paprika, id 8904, avg 64 with empty genres, is a junk/duplicate row and was excluded).

```sql
-- memberships + tier + affinity + cosine/shared_w trace queries (see scratchpad)
select m.media_id, m.realm, m.family, m.weight from media_realm_membership_effective m
 where m.media_type='ANIME' and m.media_id in (286,486);
select media_id, tier from media_realm_tier where media_type='ANIME' and media_id in (286,486);
select realm_a, max(affinity) from realm_affinity_effective
 where realm_b in (<SA realm set>) group by realm_a;
```

SA seed realm set S: supernatural-yokai 0.6077 (intense), auteur-cinema 0.6028 (craft-art), grand-adventure 0.2827 (epic-adventure), kids-family 0.2492 (young), coming-of-age 0.2000 (emotional-core). Seed tier: canon (rank 4).

| | Perfect Blue 286 | Paprika 486 |
|---|---|---|
| tier | canon → distance 0 ≤ 1 ✓ | canon → distance 0 ≤ 1 ✓ |
| top realm | idol-showbiz 0.4500 (aff to S: 0.123 < 0.6) | psychological-thriller 0.5500 (aff to S: 0.241 < 0.6) |
| family bridge | holds auteur-cinema 0.2000 (craft-art = seed family) → hard exclusion (b) does NOT fire | holds auteur-cinema 0.2000 + arthouse-experimental 0.2000 (craft-art) → survives |
| realm_mult | **0.65** (same family only) | **0.65** (same family only) |
| mem_term | 0.5 + 0.5·(0.20/0.35) = **0.7857** | **0.7857** |
| merit floor | avg 85 ≥ 75 ✓ | avg 79 ≥ 75 ✓ |
| cosine vs SA | 0.0693 (overlap 3) | 0.0883 (overlap 3) |
| in top-50? | no (gated score ≈ 0.069 × 0.65 × 0.786 ≈ 0.035 vs 50th = 0.2059) | no (≈ 0.045) |

The traced hard exclusion — tier distance ≤ 1 AND (shared family OR affinity ≥ 0.6) — **passes for both films**; each has a finite cost path (0.65 × 0.7857). The old top-realm-in-S cliff no longer structurally excludes them.

**PASS on the check's letter.** Two caveats the planner should own:
1. **The genre-overlap hard gate still structurally excludes both** before any scoring: SA has 4 genres {Adventure, Drama, Fantasy, Supernatural} → threshold 2 shared; Perfect Blue overlaps only {Drama} (1), Paprika only {Fantasy} (1). At any p_limit these titles cannot appear for seed 111. If "Kon reachable from SA" is a real product goal, the genre cliff needs the same gates-to-costs treatment.
2. Even without the genre gate, their cosines (0.069/0.088, 3 shared tag keys each) put them nowhere near the neighborhood — descriptor/vector enrichment is the practical path.

---

## Latency baseline (context for Fix 5 — NOT pass/fail)

Method: wall-clock (`curl -w %{time_total}`) around Management API calls executing the RPC with `p_limit 12`; 1 untimed warmup + 5 timed calls per seed. Includes HTTPS + Management API overhead from a local Mac — treat as an upper bound / relative baseline only.

| Seed | 5 warm samples (s) | p50 | max |
|---|---|---|---|
| ANIME 111 (SA) | 1.541 · 2.326 · 1.331 · 1.532 · 1.678 | 1.541 | 2.326 |
| MANGA 5 (Berserk) | 2.038 · 2.409 · 2.036 · 1.933 · 2.487 | 2.038 | 2.487 |
| ANIME 5329 (random) | 1.937 · 1.754 · 1.404 · 1.654 · 3.283 | 1.754 | 3.283 |
| ANIME 1970 (random) | 2.122 · 1.907 · 1.488 · 2.821 · 1.424 | 1.907 | 2.821 |
| ANIME 20074 (random) | 1.673 · 1.302 · 3.607 · 4.796 · 1.689 | 1.689 | 4.796 |

**Overall (25 samples): p50 = 1.907 s · p95 (nearest-rank) = 3.607 s.** Random seeds are not cheaper than curated ones; the tail (3.6–4.8 s) is real and is Fix 5's problem.

---

## Files / provenance

- Live RPC output captures: scratchpad `p1_berserk25.json`, `g1_sa12.json`, `sa50.json`, `p2_berserk50.json` (session scratchpad, ephemeral)
- Snapshot: `reports/realm-repair/penalty-before.json`
- Nothing was modified in the database or the repo besides this report file.

---

# Loop 2 re-verify (2026-08-04, after 20260804110000_totoro_credits_and_studio_main.sql)

Fix applied by implementer: Totoro (221) credits backfilled — `anime_staff` row (staff 3169 Hayao Miyazaki, role "Original Creator") + `anime_studios` row (1179 Studio Ghibli). The shared-studio main-restriction was a **documented skip**: 29,830/30,005 `anime_studios` rows have NULL role and the importer never captured AniList's studio-edge `isMain`, so G3's mechanical component is out of Fix-1/2 scope.

Re-run method identical to loop 1 (same RPC calls, live production, SELECT-only).

## Precondition — backfill present

```sql
select 'staff', staff_id, role from anime_staff where anime_id = 221
union all select 'studio', studio_id, null from anime_studios where anime_id = 221;
```
Returns exactly the 2 backfilled rows: staff 3169 "Original Creator", studio 1179. Confirmed.

## G2 (re-run) — Totoro in SA top-25

- **Totoro rank 10, score 0.3458** — inside top-25 (implementer smoke #10 @ 0.3458 confirmed independently, exact match).
- Decomposition check: 0.1843 (cosine) × min(2.5, 1.65 × 1.25) × 0.9099 (mem_term) = 0.3458 ✓. The 1.65 craft factor fires via shared_author — "Original Creator" matches the `%creator%` role test on both the Totoro row and SA's existing Miyazaki row — plus shared_studio (+0.15). Note: the backfilled role does NOT match the `%director%` test; the boost lands through the author path, same +0.5 magnitude, so the outcome is equivalent.

**G2: PASS.**

## G1 (regression) — SA top-12 still Ghibli-class heavy

New top-12: Mononoke #1 (0.6802) · Howl's #2 (0.6298) · Ponyo #3 (0.4383) · xxxHOLiC #4 · Noragami #5 · Natsume Movie #6 · Eccentric Family #7 · Hanako S2 #8 · Suzume #9 · **Totoro #10 (0.3458)** · Okko's Inn #11 · MUSHI-SHI Special #12.

4 Ghibli titles in the top-12 (Arrietty slid 12→13; Kiki's #21 in top-25). Mononoke/Howl's anchors unchanged. **G1: PASS.**

## G3 (re-run) — recorded as SOFT-FAIL

- Hanako S2 (2142): rank **8**, score 0.3511 (unchanged).
- Wolf Children (334): rank **23**, score 0.2980 (unchanged score; slid 22→23 purely because Totoro entered above it — every rank from old #10 down shifted +1).
- Hanako still ABOVE Wolf Children. Two causes, both out of Fix-1/2 scope:
  1. **Bogus shared-studio boost (×1.15):** Studio Hibari cooperation credit on Spirited Away matches Hanako's Hibari/Lerche credit. Unfixable without importer capture of AniList's studio-edge `isMain` (29,830/30,005 rows role-NULL today) — importer change + backfill required before the shared_studio EXISTS can be restricted to main studios.
  2. **Tag-space proximity:** Hanako's cosine to SA (0.3053, 8 shared keys) exceeds Wolf Children's (0.2384, 7) — requires the Phase 5 descriptor/vector regrade, not scoring mechanics.

**G3: SOFT-FAIL** (documented, deferred: importer isMain capture + Phase 5 regrade).

## P1 (regression) — Berserk top-25 still junk-free

Re-ran `recommend_ids_similar_to_seeds('MANGA', array[5], 25, false)`: the 25 rows are **bit-identical** to the loop-1 run (Vinland Saga 0.5329 #1 … Fate/Zero 0.3166 #25). The anime credits backfill touched nothing on the manga path, as expected. Zero isekai/LN junk. **P1: PASS.**

## G4 (regression) — vending class still absent

SA top-25 scan: 1381 and 13287 absent; no vending-machine / gag-isekai peers present. **G4: PASS.**

## Loop-close verdict table

| Check | Verdict | One-line evidence |
|---|---|---|
| P1 | **PASS** | Berserk top-25 junk-free, penalty scan zero rows, bit-identical across loops |
| P2 | **PASS** | All 16 penalized snapshot candidates decreased (absent from top-50; bound ≤ −3.5) |
| G1 | **PASS** | Mononoke #1, Howl's #2, Ponyo #3, Totoro #10 — 4 Ghibli in top-12 |
| G2 | **PASS** | Totoro rank 10 @ 0.3458 after credits backfill (decomposition verified) |
| G3 | **SOFT-FAIL** | Hanako #8 > WC #23; causes: no isMain data (importer gap) + tag-space proximity (Phase 5) |
| G4 | **PASS** | 1381/13287 and peers absent from SA top-25 (merit floor + penalty + tier) |
| G5 | **PASS** | PB 286 / Paprika 486: canon tier, craft-art family bridge, cost path 0.65 × 0.7857 — realm cliff no longer structural; genre cliff caveat stands |

---

# M2 verify (2026-08-04, Fixes 3+4 — tier from effective + cron)

- **Migrations under test:** `20260804120000_tier_from_effective_and_cron.sql`, `20260804121000_rebuild_tier_execute_service_role_only.sql` (both applied)
- **Method:** identical to M1 — Management API, SELECT-only; all numbers re-derived independently, none taken from the implementer.

## T1 — no visible member missing a tier row — PASS

```sql
with vis as (score>=70, non-adult, has-cover anime UNION manga),
     memb as (select media_type, media_id, max(weight) w
              from media_realm_membership_effective group by 1,2)
select count(*) filter (where mb.w >= 0.25 and t.media_id is null),
       count(*) filter (where mb.w >= 0.35 and t.media_id is null),
       count(*) filter (where mb.w >= 0.25)
from vis v join memb mb using(...) left join media_realm_tier t using(...);
```

Result: **missing at >= 0.25 = 0 · missing at >= 0.35 = 0** · visible members at >= 0.25 = 7,457. Expected 0; got 0 at both thresholds — nothing to explain. The pre-fix gap (~2,200 / 429 claimed) is closed.

## T2 — tier rows present and sane — PASS

- Spirited Away 111 → `supernatural-yokai / canon`; Totoro 221 → `kids-family / canon`.
- Previously-tier-less cohort spot-check. The exact pre-rebuild set is not reconstructible live (the old matview was dropped and both membership sources have since moved), so the cohort was derived by its mechanism: raw top weight below `_realm_membership_threshold()` (= 0.25, so the OLD build's percentile-basis join produced no row) while effective weight clears it. 5 such titles, all now tiered:

| type | id | title | avg | realm | tier | eff_w | raw_w |
|---|---|---|---|---|---|---|---|
| ANIME | 13236 | Gabriel Dropout OVA | 75 | moe-cgdct | acclaimed | 0.450 | 0.250− |
| ANIME | 16090 | Nadia: The Secret of Blue Water | 73 | grand-adventure | acclaimed | 0.450 | 0.250− |
| MANGA | 12205 | Yuunagi ni Mae, Boku no Ribbon | 71 | sports-competition | solid | 0.450 | 0.250− |
| MANGA | 8044 | Nademonogatari | 84 | seinen-drama | canon | 0.449 | 0.249 |
| MANGA | 7039 | My Beloved Oppressor | 73 | seinen-drama | acclaimed | 0.449 | 0.249 |

(An alternative derivation — tiered titles with zero raw membership rows — returns empty: the raw matview has itself refreshed past the old tier build, confirming the split-brain was threshold/staleness-shaped, not missing-row-shaped.)

## C1 — cron job — PASS

`cron.job`: **jobid 51 · jobname `realm-tier-refresh` · schedule `50 4 * * *` · active `true` · command exactly** `set statement_timeout = '600s'; select public.rebuild_media_realm_tier();` (session-level SET as its own first statement — the load-bearing part).

`realm-tier-rebuild-once`: **absent from `cron.job`** — properly unscheduled, not lingering. (Its historical run persists in `job_run_details` as jobid 52, which is expected — run history survives unschedule.)

## C2 — rebuild run — PASS

Latest `cron.job_run_details` for the rebuild command (jobid 52, the one-off): **status `succeeded`, return "1 row", 2026-08-04 18:52:00 → 18:54:16 UTC = 136.3 s** — well inside the 600 s ceiling and above the old 120 s killer, i.e. the old cron could never have completed it. Corroborating history: 4/4 runs of the old jobid 48 (`refresh materialized view concurrently…`) failed 2026-08-01…04, each at exactly 120.0 s with "canceling statement due to statement timeout" — matches the migration's diagnosis verbatim.

## STRUCT — table shape + ACLs — PASS

- `pg_class`: `media_realm_tier` **relkind `r`** (plain table), **relrowsecurity `true`**.
- `pg_policies`: exactly one policy — `media_realm_tier_select_all`, **cmd SELECT, USING (true)**, roles {public}; **no write policies** (default-deny for client-role DML).
- Indexes: **`media_realm_tier_uidx` UNIQUE (media_type, media_id)** + `media_realm_tier_realm_idx` (realm).
- `rebuild_media_realm_tier()` **proacl = `{postgres=X/postgres,service_role=X/postgres}`** — EXECUTE is postgres + service_role ONLY; the ACL is non-NULL and contains neither anon, authenticated, nor PUBLIC, so those roles get permission denied by definition (JWT probe skipped per instruction; the deny path for unprivileged roles was incidentally demonstrated live when the Management API read-only role got `42501 permission denied` invoking `_realm_membership_threshold()`).

## REG — no behavior regression — PASS

- `recommend_ids_similar_to_seeds('ANIME', array[111], 12, false)`: **identical to the M1 loop-2 list** — same 12 ids, same order, same scores (Mononoke 0.6802 #1 … Totoro **#10 @ 0.3458** … MUSHI-SHI #12).
- `media_realm_profile` resolves: row for ANIME 111 (Spirited Away · supernatural-yokai · canon) returned.
- Tier distribution (rebuilt table, 57,310 rows):

| type | canon | acclaimed | solid | tail |
|---|---|---|---|---|
| ANIME | 2,296 | 2,870 | 3,559 | 8,689 |
| MANGA | 933 | 4,433 | 10,580 | 23,950 |

## SEM — tier semantics preserved — PASS

- Before-tiers ARE derivable for 9 ids: the M1 loop-1 evidence in this file recorded pre-rebuild tiers. Before → after: 111, 221, 334, 1413, 2142, 286, 486 all `canon → canon`; **1381 `acclaimed → acclaimed`**; 13287 `solid → solid`. 9/9 unchanged — consistent with a semantics-preserving rebuild where only the membership universe moved.
- Canon plausibility: old 56,874 rows with canon 2,463 + 1,050 = 3,513 → new 57,310 rows with canon **2,296 + 933 = 3,229** (−8%). Canon contracted slightly; no explosion. Total rows +436 net (new tier-less entrants offset by titles whose effective membership dropped out).
- Standing flag (pre-existing, NOT a Fix-3 regression): 1381 "Reborn as a Vending Machine" keeps `acclaimed` — a within-realm percentile artifact of isekai-reincarnation (tier measures good-for-its-kind). Fix-3's brief was semantics preservation, which this confirms; the artifact belongs to the tuning phase.

## M2 verdict table

| Check | Verdict | Evidence |
|---|---|---|
| T1 | **PASS** | 0 missing tier rows at >= 0.25 and >= 0.35 (7,457 visible members) |
| T2 | **PASS** | 111 supernatural-yokai/canon, 221 kids-family/canon; 5 cohort spot-checks tiered sanely |
| C1 | **PASS** | jobid 51, `50 4 * * *`, active, command begins `set statement_timeout = '600s';`; one-off job absent |
| C2 | **PASS** | rebuild succeeded in 136.3 s (vs 4/4 prior 120.0 s timeouts of the old refresh) |
| STRUCT | **PASS** | relkind r, RLS on, select-only policy, unique (media_type,media_id), proacl postgres+service_role only |
| REG | **PASS** | SA top-12 bit-identical incl. Totoro #10 @ 0.3458; profile view resolves; distribution sane |
| SEM | **PASS** | 9/9 recorded before-tiers unchanged; canon 3,513 → 3,229 (no explosion) |
