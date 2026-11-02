# Acceptance — Spirited Away similarity gate (2026-08-02)

Seed: Kuro `anime.id` 111 (AniList 199).

## Diagnosis

| Leak | Path |
|---|---|
| Re:ZERO S4 | Shared `grand-adventure` @ 0.30 (seed S included it at T=0.25) |
| JUJUTSU KAISEN | Shared `supernatural-yokai` @ 0.50; affinity `battle-shounen`↔`yokai` measured 0.93 |

## Fix (`20260802140000_spirited_away_gate_harden.sql`)

1. Canon seeds: `seed_realms` + shared-pass use weight ≥ **0.35**
2. Canon seeds: shared pass also requires candidate **top realm ∈ S**
3. Affinity vetoes: `battle-shounen`↔`supernatural-yokai`, `isekai-reincarnation`↔`auteur-cinema`

## Result (top 12, post-fix)

1. Princess Mononoke  
2. Howl’s Moving Castle  
3. The Boy and the Heron  
4. xxxHOLiC  
5. Noragami Aragoto  
6. Natsume’s Book of Friends the Movie  
7. InuYasha the Movie 2  
8. The Eccentric Family  
9. Kamisama Kiss  
10. Toilet-bound Hanako-kun Season 2  
11. Suzume  
12. Okko’s Inn  

**LEAKS:** none (Re:ZERO / JJK / Slime-class absent).

Ghibli/folklore/yokai neighborhood restored. Residual: some soft-supernatural TV remains acceptable under yokai/auteur S; further polish via affinity overrides if needed.
