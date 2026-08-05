# Phase 1 acceptance — realm repair

Generated: 2026-08-05T21:24:06.860Z  
Summary: **13 PASS / 0 FAIL / 1 SOFT-FAIL / 1 SKIP-or-WARN**

| ID | Verdict | Evidence |
|---|---|---|
| P1 | PASS | Berserk top-25 penalized sub-merit (junk-class) titles: 0 (want 0), 25 results |
| P2 | PASS | penalized candidates at/above clean-edge band (score>=3.0): 0 of 3 penalized in top-25 |
| G1 | PASS | Ghibli-class anchors in top-12: Howl‘s Moving Castle, My Neighbor Totoro, Ponyo, The Secret World of Arrietty |
| G2 | PASS | Totoro rank: 2 |
| G3 | SOFT-FAIL | Hanako S2 rank absent vs Wolf Children absent (known SOFT-FAIL: importer isMain gap + tag space) |
| G4 | PASS | vending-class titles in SA top-25: 0 |
| G5 | PASS | Perfect Blue/Paprika realm rows >=0.2: 11 (structural path exists; genre-overlap cliff caveat recorded) |
| T1 | PASS | visible titles with effective membership >=0.25 and no tier row: 0 |
| T2 | PASS | 111=supernatural-yokai/canon, 221=kids-family/canon |
| C1 | PASS | realm-tier-refresh 50 4 * * * active=true |
| C2 | PASS | last run: succeeded |
| S1 | SKIP | --skip-latency |
| S2 | PASS | gold eval: 100/100 scored, generated 2026-08-05T17:10:05.096Z (heuristic labels; timeouts are the metric) |
| H1 | PASS | _ops_*/enqueue_realm_describe_batch functions remaining: 0 |
| H2 | PASS | security advisor ERRORs: 0 |

Full per-check SQL evidence: `reports/realm-repair/m1-verify.md`.