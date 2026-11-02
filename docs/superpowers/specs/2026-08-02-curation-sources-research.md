# Curation sources research — anime & manga (EN + JP)

**Date:** 2026-08-02  
**Purpose:** Honest audit of which real-world curation signals Kuro should trust for `canon_seed`, Hidden Gem, and Stage 3 gold judgments — after a multilingual web pass (English + Japanese).  
**Honest precondition:** The Stage A–C implementation work did **not** previously do this research. It reused sources already named in the Realm Graph master plan §5 and the 435-row `canon_seed` migration. This document is the catch-up research pass.

---

## 0. How to read trust tiers

| Tier | Meaning for Kuro |
|---|---|
| **A — Canon anchors** | Multi-year, jury/pro-voted, citeable. Safe to force `tier=canon` when blessed. |
| **B — Desk discovery** | Strong for “what’s rising / what editors recommend this year.” Use for Shelf / Hidden Gem / leanings copy — not automatic canon. |
| **C — Community consensus** | Large-N fan signal. Useful for gold-set judgments and popularity floors; **never** sole canon authority (recency/hype bias). |
| **D — Craft / lens specialists** | Trusted by niches (sakuga, feminist critique, gekiga). Inform realm signatures & affinity vetoes; sparse title lists. |
| **E — Avoid as canon** | Awards/lists that optimize for streaming marketing, pure popularity, or single-season hype. |

---

## 1. What Kuro already has in `canon_seed` (live counts)

| Source | Rows | Language / nature | Tier |
|---|---:|---|---|
| Japan Media Arts Festival | 118 | JP government / jury (文化庁メディア芸術祭) | **A** |
| r/anime Classics | 50 | EN community decade-scale consensus | **C→A*** |
| Shogakukan Manga Award | 47 | JP publisher award (小学館漫画賞) | **A** |
| Kodansha Manga Award | 46 | JP publisher award (講談社漫画賞) | **A** |
| Kono Manga ga Sugoi! | 39 | JP industry survey mook (宝島社) | **A/B** |
| Tokyo Anime Award | 39 | JP industry + fan hybrid (TAAF) | **A/B** |
| Tezuka Cultural Prize | 27 | JP Asahi / cultural (手塚治虫文化賞) | **A** |
| Critic Consensus | 25 | EN longform critic agglomeration (swarm-compiled) | **B** |
| Eisner Award | 22 | US comics industry (manga category) | **A** |
| Manga Taishō | 19 | JP bookstore-recommender prize (マンガ大賞) | **A** |
| Annecy Cristal | 3 | FR international animation festival | **A** (under-filled) |

\*r/anime classics is community, but decade-scale sticky lists behave more like soft canon than seasonal Reddit threads.

**Coverage verdict:** Manga awards are solid. Anime film/TV “desk” is thinner than it looks — Annecy is almost empty (3 rows), and JP seasonal critic/user surfaces (Filmarks, TAAF fan 100) are not ingested as ongoing pipelines.

---

## 2. Japanese sources (depth)

### A-tier (industry / cultural)

1. **文化庁メディア芸術祭 (Japan Media Arts Festival)** — Animation + Manga divisions. Jury of artists/critics; Grand Prize / Excellence. Historical winners include もののけ姫, 千と千尋, 千年女優, マインド・ゲーム, まどか☆マギカ, 君の名は。, この世界の片隅に. Festival form changed after ~2022; still the strongest JP public cultural signal.  
   - Official: https://www.j-mediaarts.jp/  
   - Already primary Kuro source (118 rows).

2. **東京アニメアワードフェスティバル / TAAF「アニメ オブ ザ イヤー」** — Fan Best-100 → industry pro vote for 作品賞; separate アニメファン賞. 2026: film 鬼滅・無限城編, TV Gundam GQuuuuuuX.  
   - Official: https://animefestival.jp/  
   - In Kuro as Tokyo Anime Award (39). Keep **作品賞** as A; treat fan award as C.

3. **手塚治虫文化賞** (Asahi) — Cultural manga prize; マンガ大賞 winners include ドラえもん, MONSTER, バガボンド, PLUTO, ゴールデンカムイ, チ。, etc.  
   - Official: https://www.asahi.com/special/tezukaosamu-culturalprize/  
   - In Kuro (27).

4. **マンガ大賞 (Manga Taishō)** — Explicitly “manga you’d recommend to someone,” ≤8 volumes, bookstore/committee scoring. Discovery-leaning but highly regarded.  
   - Official: https://mangataisho.com/  
   - In Kuro (19) — underweight vs influence; expand winners **and** high-score nominees.

5. **このマンガがすごい！** (Takarajimasha) — ~70–200 識者 (bookstore staff, editors, critics) each nominate top 5; オトコ編 / オンナ編. Industry’s annual “desk shortlist.”  
   - In Kuro (39). Prefer **#1–#3** for canon pressure; #4–#10 for discovery.

6. **講談社漫画賞 / 小学館漫画賞** — Long-running publisher awards; demographic departments. Already in Kuro. Cite department + year in `source_detail`.

7. **日本漫画家協会賞** — Peer award from 日本漫画家協会 (e.g. SPY×FAMILY, ゴールデンカムイ, 鬼滅). **Missing from Kuro.** Should be added as A-tier manga.

### B-tier (JP discovery / satisfaction)

8. **次にくるマンガ大賞** (KADOKAWA; user entry + vote; comics + web manga). Excellent for “what’s next,” bad as timeless canon.  
   - https://tsugimanga.jp/

9. **Filmarks アニメランキング** — Largest JP consumer ★ scores for broadcast/streaming seasons (e.g. 2026 H1: SBR, Dorohedoro S2, Frieren S2…). Use for seasonal Hidden Gem / “high satisfaction, not yet popular internationally,” **not** canon_seed.

10. **全国書店員が選んだおすすめコミック** / **このマンガを読め！** — Bookstore-staff picks (parallel culture to Kono Manga). Worth a future ingest; not yet in Kuro.

### JP niches worth knowing (D)

- **Anime!Anime! / Natalie Comic / Animate Times** — trade news, not canon lists.  
- **個人批評・同人誌的批評圏** — useful for gekiga/arthouse realms; too sparse for automated seed.

---

## 3. English / international sources (depth)

### A-tier

11. **Annecy** (Cristal + Jury / Contrechamp for features; TV series prizes). International animation desk. Japanese winners historically rare but high signal (Pom Poko, Lu Over the Wall, In This Corner of the World; 2026: A New Dawn Jury Contrechamp, Takopi TV Jury).  
   - Kuro has only **3** Annecy rows → expand to Cristal + Jury Feature + Contrechamp + TV Jury for JP-relevant titles.

12. **Eisner Awards (Best Manga / related)** — US comics industry recognition of manga. In Kuro (22).

13. **Anime News Network Encyclopedia ratings (Bayesian)** — Not an award, but the longest-running EN aggregator with methodology. Treat as C with high weight for gold-set “relevant neighbor” priors, not auto-canon.  
   - https://www.animenewsnetwork.com/encyclopedia/ratings-anime.php

### B-tier (EN annual critic desks)

14. **IndieWire / Polygon / Comics Beat / The Mary Sue** — Staff year-end anime lists. Good for seasonal Shelf arguments; high churn. Do **not** dump whole lists into canon_seed.

15. **Crunchyroll Anime Awards** — Industry-adjacent but heavily popularity/fan-vote. Tier **E** for canon; optional C for “global hype.”

### C-tier (community)

16. **MyAnimeList / AniList** — Score + popularity. Substrate for filters, not taste authority.  
17. **r/anime “classics” / decade threads** — Already in Kuro (50). Keep; prefer sticky/decade lists over seasonal karma.  
18. **MAL Interest Stacks / AniList custom lists** — Great for gold-set human judgment scaffolding; never auto-import.

### D-tier (specialist voices community actually respects)

19. **Sakuga Blog** (sakugabooru) — Production/craft criticism; Animation Awards by industry-aware writers. Inform **craft lineage** and auteur-cinema / arthouse signatures — not bulk canon.  
20. **THEM Anime Reviews** — Long-running independent EN review desk (since ~90s community lineage). Sparse but honest “would Kuro put this on a shelf?” signal.  
21. **Mangasplaining / MSX** — Podcast + publishing taste for underrepresented manga; good for gekiga/alt realms.  
22. **Anime Feminist** — Lens-specific critique; use for avoidance/register mapping, not canon lists.  
23. **Manga Deep Dive / Tokyo Manga Shelf** — JP-based EN writers adding cultural context English subs miss; qualitative, not list engines.

---

## 4. Gaps vs Kuro today (actionable)

| Gap | Why it matters | Proposed action |
|---|---|---|
| **日本漫画家協会賞** missing | Peer cultural manga prize | Migration: ingest Grand Prize comic winners → `canon_seed` |
| **Annecy under-filled (3)** | International film desk almost unused | Expand Cristal + Jury + Contrechamp + TV Jury (JP + JP co-pro) |
| **Manga Taishō thin (19)** | Best “recommend to a friend” prize | Add all winners + ≥80-point nominees |
| **Kono Manga only partial** | Desk shortlist is yearly | Ensure #1–#3 both demographics each year since 2006 |
| No **Filmarks / 次にくる** pipeline | JP seasonal satisfaction & rising titles | Separate table or `source='filmarks-seasonal'` for Hidden Gem only |
| No **sakuga / THEM** channel | Craft truth for auteur realm | Manual editorial list → affinity overrides + signature tags |
| **Critic Consensus (25)** opaque | Swarm blob; hard to bless | Split into named sources (ANN yearlists, IndieWire, etc.) or unbless until cited |
| Gold judgments are heuristic | Stage 3 ship gate invalid until owner pass | Owner judges using A+B sources as candidate pools |

---

## 5. Recommended Kuro policy (lock this)

1. **`canon_seed` only accepts Tier A** (and r/anime decade classics as soft-A). Blessed by default; you unbless.  
2. **Tier B** feeds Discover Shelf blurbs + Hidden Gem candidate pools, never auto-canon.  
3. **Tier C** feeds gold-set *candidates* and popularity floors.  
4. **Tier D** edits signatures / affinity / register — human-sized lists.  
5. **Never** promote Crunchyroll Awards or raw MAL top-100 into canon.  
6. Multilingual rule: for every EN community list we keep, prefer a JP industry counterpart (already mostly true for manga; anime film needs Annecy + JMAF + TAAF 作品賞 balance).

---

## 6. Sources consulted this pass (non-exhaustive)

- Japan Media Arts Festival / 文化庁メディア芸術祭 (j-mediaarts.jp, Wikipedia JA)  
- TAAF 2026 アニメ オブ ザ イヤー (animefestival.jp, Animate Times)  
- 手塚治虫文化賞 (Asahi)  
- マンガ大賞 / Manga Taishō (mangataisho.com, Wikipedia EN)  
- このマンガがすごい！ (Wikipedia EN + award-books.com 歴代)  
- 講談社漫画賞 / 小学館漫画賞 / 日本漫画家協会賞 (official award pages)  
- 次にくるマンガ大賞 (tsugimanga.jp)  
- Filmarks 2026上半期アニメランキング (PR / Magmix)  
- Annecy 2017 & 2026 winners (ANN, Cartoon Brew, Branc JP)  
- Anime News Network Bayesian ratings  
- Sakuga Blog Animation Awards  
- THEM Anime Reviews  
- IndieWire / Polygon / Comics Beat / Mary Sue year lists  
- Mangasplaining, Anime Feminist, Manga Deep Dive  

---

## 7. Implementation status (2026-08-02)

1. ✅ Migration `20260802150000_curation_sources_expand_v1` — 日本漫画家協会賞 + Annecy expansion + Manga Taishō ≥80 nominees + Kono Manga #2/#3.  
2. ✅ Opaque `Critic Consensus` split into Paste / Time Out / A.V. Club, then deleted.  
3. ✅ `curation_seasonal_signal` (Filmarks + 次にくる + EN yearlists) + Hidden Gem boost.  
4. 🟡 Owner gold-set scaffolding shipped (`scripts/realm_gold_owner_shortlist.js`); **owner still fills** `eval/realm_rec_gold/owner_judgments.jsonl`.  
5. 🟡 Catalog gaps (not inserted): 風雲児たち, ヘルプマン！, 鎌倉ものがたり, ダンミツ — re-run compile after import.
