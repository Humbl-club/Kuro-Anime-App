# The Realm Graph — Kuro's Curation Knowledge Graph (master plan, 2026-07-31)

Status: Stage 1 live in prod (signatures/matviews/gated similarity + penalty clamp). Stage 2b descriptor pipeline live (Groq `realm-describe` + salvage); drain in progress. Stage 3 edges imported (gold-set eval still open). Stage 4 not started. Taxonomy treated as blessed for v1.
Supersedes nothing; extends `2026-07-31-taste-math-v2-critical-review.md` (tag space stays the substrate) and the Discover/Browse proposal.

## 0. The model in one paragraph

Two orthogonal axes. **Realm membership**: every title holds graded (0–1) membership in ~40 hand-designed realms (fuzzy, multi-membership, computed by projecting its IDF tag vector onto editorial realm signatures). **Tier**: acclaim percentile *within* each realm — "objectively good of its kind" (subjective across realms, objective within them). Users are mixtures in the same realm space; the taste profile, deck exploration, similarity, Because-You and The One Thing all consume this one graph. Everything is SQL-computable matrices with editorial control at exactly two points (realm signatures, affinity overrides) and data doing everything else.

## 1. Why a hierarchy (~10 families × ~40 realms)

18–24 flat realms felt tight because it *is*: gates want loose coupling (families), taste wants texture (realms). Families: coarse buckets used for avoidance, deck stratification, and family-level gates. Realms: the vocabulary of "what kind of experience", used for membership, affinity, leanings, and the LLM pass. Realms can split (when internal coherence measurably breaks) or merge (when two never differentiate) — the taxonomy is data-maintained, not carved in stone.

## 2. The taxonomy (draft v1 — this is the part to fight about)

Format: realm — one-line "what it feels like". (M) = manga-weighted. All realms exist for both media unless marked.

**Family: EPIC ADVENTURE**
1. Grand Adventure — journeys and quests with mythic scope (Frieren, One Piece)
2. Battle Shounen — power systems, tournaments, rivals (Naruto, JJK, MHA)
3. Dark Fantasy — beautiful and brutal at once (Berserk, Claymore, AoT)
4. Isekai & Reincarnation — other worlds, all tiers from Re:Zero to vending machines
5. Sword & Samurai — blade craft, honor, history-adjacent (Vagabond, Rurouni Kenshin)
6. Historical Epic — real eras, grand scale (Vinland Saga, Kingdom, Golden Kamuy)

**Family: EMOTIONAL CORE**
7. Quiet Melancholy — gentle sadness, time and loss (Mushishi, Violet Evergarden)
8. Romance & Slow Burn — longing done seriously (Your Lie in April, Fruits Basket)
9. Slice of Life & Iyashikei — healing, ordinary days (Yuru Camp, Barakamon, Aria)
10. Coming of Age — growing up as the subject (Spirited Away, March Comes in Like a Lion)
11. Tragedy & Tearjerker — engineered devastation (Grave of the Fireflies, Clannad AS)

**Family: MIND & THRILL**
12. Psychological Thriller — cat-and-mouse minds (Death Note, Monster, Psycho-Pass)
13. Mystery & Detective — puzzles and procedures (Erased, Hyouka, Conan)
14. Horror & Dread — fear as craft (Another, Higurashi, Junji Ito)
15. Mind Game & Strategy — rules, gambits, debts (Kaiji, Akagi, Death Parade)

**Family: SPECULATIVE WORLDS**
16. Sci-Fi & Space — futures, frontiers, engineering (Bebop, LoGH, Planetes)
17. Mecha — machines and their pilots (Gundam, Evangelion, Code Geass)
18. Cyberpunk & Dystopia — systems eating people (Akira, Ghost in the Shell, Psycho-Pass)
19. Time & Parallel Worlds — loops, leaps, branches (Steins;Gate, Re:Zero, Summertime)

**Family: CRAFT & ART**
20. Auteur Cinema — the legendary film realm (Ghibli, Kon, Shinkai, Hosoda, Yuasa)
21. Arthouse & Experimental — form as content (Kaiba, Tatami Galaxy, Ping Pong)
22. Classic Serial Canon — the long-form legends (FMA:B, Legend of the Galactic Heroes)

**Family: LAUGHTER**
23. Comedy & Parody — jokes as the engine (Gintama, Konosuba, Nichijou)
24. Romantic Comedy — love as farce and charm (Kaguya, Toradora, Takagi-san)

**Family: LIFE & WORLD**
25. Sports & Competition — bodies and brackets (Haikyuu, Chihayafuru, Blue Lock)
26. Music & Performance — stages and practice rooms (Nodame, Bocchi, Your Lie in April)
27. Food & Craft — cuisine and artisans (Food Wars, Delicious in Dungeon, Bartender)
28. Workplace & Adult Life — jobs, rent, small victories (Shirobako, Aggretsuko, Wotakoi)

**Family: INTENSE**
29. War & Military — campaigns and command (86, Youjo Senki, LoGH)
30. Crime & Underworld — gangs, heists, vengeance (Black Lagoon, 91 Days, Banana Fish)
31. Supernatural & Yokai — spirits among us (Natsume, Mononoke, Noragami)

**Family: RELATIONSHIPS & IDENTITY**
32. BL & Yuri — queer romance as the subject (Given, Bloom Into You)
33. Family & Generations — parents, children, time (Wolf Children, Sweetness & Lightning)
34. Idol & Showbiz — fame's machinery (Oshi no Ko, Idolmaster)

**Family: OTAKU REGISTER** (needed for accurate mapping; surfaced selectively, never editorially promoted)
35. Moe & CGDCT — cute girls, cute things (K-On, Bocchi)
36. Ecchi & Fanservice — self-describing; primarily an avoidance-mapping realm
37. Gag & Short-Form — quick-hit comedy

**Family: SEINEN & ALTERNATIVE (M)**
38. Seinen Drama — adult interiority, no genre net (Punpun, Solanin, March)
39. Gekiga & Alternative — the manga-as-art lineage (Tezuka legacy, alternative press)

**Family: YOUNG**
40. Kids & Family — all-ages wonder (Anpanman, Yokai Watch, Ghibli-adjacent kids' works)

Manga note: realms 38–39 are manga-native; most others span both media. Adaptation edges (`media_relations`) let a manga's realm membership inform its anime and vice versa.

## 3. The graph as four matrices (all SQL)

- `realm_signatures` (editorial): realm → {tag_key: weight} + genre/demo/source/era/craft hints. ~15–30 weighted tags per realm, hand-drafted, swarm-refined, owner-vetoed.
- `media_realm_membership` (matview): title × realm → 0–1 (dot of title IDF vector with signature, normalized; keep top-4 per title + anything ≥ 0.35). LLM pass (§6) may adjust ±0.2 with reasons logged.
- `realm_affinity` (matview): realm × realm → correlation of co-membership across catalog + `realm_affinity_overrides` (editorial). This is the measured knowledge-graph edge set.
- `media_realm_tier` (matview): title × its top realm → tier from acclaim percentile *within that realm* (canon ≥ p97, acclaimed ≥ p85, solid ≥ p60, tail) + canon_seed membership (§5) forcing canon + craft-lineage lift. The deck/similarity consume tier; "good in its realm" is always relative to the realm.

Similarity v4 eligibility: candidate must share a top-realm (≥ 0.35) with the seed OR sit in an adjacent realm (affinity ≥ 0.25) AND be tier-compatible (within 1 tier; canon seeds admit canon+acclaimed only). Ordering: craft lineage + editorial co-membership + theme cosine (existing). Spirited Away test = acceptance: neighbors must be Ghibli/Takahata/Kon/Hosoda-class works and acclaimed folklore fantasies; no light-novel seasonal TV regardless of the Isekai tag.

## 4. Users in realm space

User profile projects through the same signatures → realm mixture (top ~6 realms + weights). Powers: "Your leanings" shows *your realms* with tier-aware copy; deck stratifies exploration across untouched realms (family quotas first, then realm quotas); Because-You gates by shared realm; the NTY fit adds a realm-alignment term (small, ≤ the contract's 0.20 total influence). Avoidance can target realms ("never isekai") — a realm-level kill switch that's honest and inspectable.

## 5. Canon seed (the desk's anchors, with citations)

`canon_seed(title, media_type, source, source_detail, year, category)` compiled by the swarm with web verification, then owner-blessed (Stage 3):
- Anime: Japan Media Arts Festival (Grand Prize/Excellence), Tokyo Anime Award, Annecy selections, r/anime classics canon (decade-scale consensus), ANN long-form critic lists.
- Manga: Kono Manga ga Sugoi!, Manga Taishō, Tezuka Cultural Prize, Kodansha Manga Award, Shogakukan Manga Award, Japan Media Arts manga division, Eisner-nominated manga.
Seed size target: 300–500 works. Canon membership forces tier=canon in the title's top realm.

## 6. The LLM descriptor pass (stage 2 compute)

Per visible-catalog title (score ≥ 70 pool, ~8k): structured JSON — realm confirmations (top 3 + weights 0–1), tone (3 of fixed 24-word vocabulary: whimsical, melancholic, brutal, cozy, cerebral, kinetic, tender, eerie, absurd, earnest, dark, warm, bleak, playful, solemn, lush, gritty, dreamlike, frantic, intimate, epic, quiet, hysterical, meditative), register (family / general / seinen-otaku / arthouse), era, pacing (slow-burn / steady / relentless), confidence (0–1). Worker: checkpointed script (synopsis-enrichment pattern), 16–20 parallel workers, ~4–7h wall for pass 1, QA pass on confidence < 0.7. Tokens ≈ 8–10M. Everything lands in `media_realm_llm` (raw JSON + adjusted membership delta with reason). Tail titles stay rules-only until they enter the visible pool.

## 7. AniList community edges — kept ON, but on probation

Import into `media_rec_edges` (bulk job). Then the evaluation harness: gold set of 100 seeds across realms with human-judged neighbors; precision@10 of (a) raw AniList edges, (b) our realm-gated graph, (c) edges∩gate. Ship only if (c) beats (b) materially; otherwise edges stay advisory metadata. We read their data; we don't inherit their taste.

## 8. Stage plan

- **Stage 1 (1 evening, deterministic):** signatures v1 (swarm drafts per §2, owner vetoes), the 3 matviews + tier, similarity v4 gate, Because-You + One Thing rewired, deck realm-stratification v1, leanings-as-realms. Acceptance: Spirited Away test + vending machine test + 20 hand-checked pairs across realms.
- **Stage 2 (1–2 days compute):** canon_seed compiled + owner blessing; LLM pass on 8k visible; membership adjustments applied.
- **Stage 3 (parallel):** edges import + evaluation harness; decision by numbers.
- **Stage 4 (continuous):** realm maintenance cron (split/merge reports, drift), deck co-occurrence as third association source, Discover P2/P3 rails re-targeted onto realms (The Shelf = "tonight's realm", Hidden Gem = high-tier low-popularity per realm).

## 9. Hard rules

No ML cosplay (no embeddings until this demonstrably plateaus) · every number inspectable in SQL · editorial veto points are signatures + affinity overrides + canon blessing, nothing else · avoidance and gates never hide a realm from Browse (lens stays neutral) · tags stay the substrate, realms are the meaning · the contract's 0.20 ranking-influence cap is untouched.
