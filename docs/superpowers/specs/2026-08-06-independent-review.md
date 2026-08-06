# Independent Review — Kuro taste-overhaul branch (2026-08-06)

**Reviewer:** Kimi K3 (external to the Claude Code sessions that built eras 2–5; era 1 was my own swarm's work, reviewed with the same hostility).
**Method:** 5 adversarial agents — backend truth, serving-quality live probes, scoreboard recomputation, content audit (30 descriptors + critique pilot), iOS/git truth. Nothing in this report comes from trusting the dossier; every verdict cites a re-run check. Reference plan: `2026-08-04-realm-repair-and-critique-plan.md` (the decision lock — not the July 31 plan).

**Headline verdict:** The engineering record is unusually honest — exact row counts reproduce (225,541 / 2,946 / 7,220×14.3 / 91.9%), incidents are on the record, fixes verify live. **But the two headline quality numbers (0.512 → 0.823) rest entirely on model self-judgment with zero human vetoes, and the 5,548-row descriptor corpus that anchors the LLM layer is template junk.** The system is real; the measurement of how good it is remains unproven.

---

## 1. Claim grades (major claims, evidence-cited)

### Era 1 (overnight swarm)
| Claim | Verdict | Evidence |
|---|---|---|
| Deck at index 0, concierge archived, NOT FOR ME, endless, single-source leanings + YOUR REALMS | TRUE | live tree + simulator screenshots (fresh build, `com.Kuro.app`) |
| Taste math live-tested, 3 bugs fixed that night | TRUE | functionally re-verified by era-3/4 audits; RPCs all green today |
| Clubs trust pack / image convergence / ledger | TRUE (not re-probed this pass) | migrations present + applied |

### Era 2 (realm graph)
| Claim | Verdict | Evidence |
|---|---|---|
| 40 realms, 842 signatures, matviews, canon_seed, 103k edges | TRUE | live counts: edges 103,007 rows / 7,220 seeds / avg 14.3 (exact) |
| 7,166 LLM descriptors | TRUE but TWO CORPORA | see §3 — 77% are template junk |
| "Groq writer abandoned mid-drain" | MISLEADING framing | Groq wrote 1.5%; the bulk writer (kimi-k3-max, 77%) produced the junk corpus |

### Era 3 (audit + lock)
| Claim | Verdict | Evidence |
|---|---|---|
| Audit findings (dead cron, split-brain, timeouts, inert penalty) | TRUE | all confirmed fixed in era 4; era-3's "7 uncommitted migrations" now committed |

### Era 4 (repair)
| Claim | Verdict | Evidence |
|---|---|---|
| Migrations applied, no drift, advisors 0 ERRORs | TRUE | `migration list` clean; advisors 0 ERROR (but 143 WARN + 2 plpgsql_check temp-table findings unmentioned — "lint clean" would be false) |
| media_similar_titles 225,541 rows; 2,946 entry points | TRUE, exact | live counts |
| Tier rebuilt from effective membership | TRUE | `rebuild_media_realm_tier` reads `_effective`; 0 visible tier-less titles |
| Nightly cron chain green unattended | PARTIAL | exactly **one** unattended night on record (08-05); driver 320/0, tier 136s green — "proven over time" is not yet earned |
| OOM outage + fix | TRUE | incident documented in migration header; advisory-lock builder + driver live; 7,537 seeds, 0 stale |
| Penalty convention restored (Feb `+negative`) | TRUE + latent gap | penalties strictly demote now; **no CHECK constraint on penalty sign** — a positive row silently becomes a boost again |
| p95 1.9–3.6s → 42–105ms | PARTIAL — unscoped | precomputed seeds: 85–125ms ✓. **Non-store seeds: 1,463–3,122ms live fallback, sometimes only 4 rows.** "p95 ≤105ms" holds only if the app never seeds outside the store |

### Era 5 (measurement → fork → pilot)
| Claim | Verdict | Evidence |
|---|---|---|
| SA rail = Miyazaki list, Totoro #2 | TRUE | live probe: Howl's, **Totoro #2**, Kiki's, Ponyo, Mononoke, Arrietty, Nausicaä, Porco — 8/12 Ghibli, zero junk |
| Raw edges P@10 0.847/0.850 | ~TRUE | recomputed 0.857 from raw files (dossier's 0.847 matches no clean recomputation; harness today says 0.850 — snapshot drift, directionally fine) |
| Gated cosine 0.512 | TRUE (arithmetic) | reproduces exactly, harsh-unknowns convention |
| **Gated 0.823 after fork** | **UNVERIFIED magnitude** | not reproducible from the committed harness (0.791 vs heuristic labels); baseline and post-fork scored against **different label sets**; delta pass used the *lenient* unknown convention (claimed 85.5% vs honest 80.1%); see §2 |
| 91.9% top-10 slots edge-sourced | TRUE on gold set (919/1000 exact) | **but 50% on an adversarial 20-seed sample** (Totoro, MHA S1, Chainsaw Man, Berserk serve all-cosine rails) — coverage is canon-skewed; the headline is a gold-set metric |
| Entry-point canonicalization (2,946) | **PARTIAL — adversarial failures** | AoT Final Part 2 rail: sequel at #1 + 3 same-franchise entries incl. recap movies; TR S2 → TR S2 Part 2 at #1; Death Parade→Danganronpa bridge exists but at **#15, below the rendered fold**. Works where remap landed; fails 2/3 adversarial franchise probes |
| Realm audit: 13.4% misfiled, 20% vs 3% tripwire, 393 applied | TRUE | every rate reproduces to the decimal from raw files; 5 spot-checked overrides sane |
| Critique pilot: 25 reviews, 100% quote fidelity, 0 misattributions | TRUE | 5/5 independent verbatim source checks (WET, Experiments in Manga, animeanime.jp incl. JP); skip-don't-guess discipline documented |
| Parser PROVEN, coverage structural | FAIR + one omission | `critic_reviews`/`media_critic_claims` are **42501 for the client role — the app cannot read them today**; every craft score has n_reviews=1 ("consensus" = one voice) |

## 2. The measurement problem (soft spot #1, answered)

**No human has confirmed a single one of the 1,839 + 302 verdicts.** The owner veto file is an unfilled template; the veto tool is an external link with no local evidence of use. The README's own ship rule ("no edges into ranking until an owner pass clears the gate") was bypassed — edges-first is live on model self-judgment alone.

Design gaps found on recompute:
- The "4 parallel judges" are **4 disjoint shards with zero overlap** — inter-judge agreement is impossible to compute; reasons+confidence are the only QC.
- The 0.512→0.823 comparison uses **different label sets** for the two arms; the delta labels were created by judging the fork's own output with one same-family judge per item.
- Convention slip: harsh unknowns-as-misses in v1 (hurts gated), lenient unknowns-excluded in the delta claim (flatters the fork).
- Judgment quality itself is decent on spot-reads (content-specific reasons, real negative judgments, 1,733/1,839 unique reasons) — the problem is provenance, not sloppiness.

**Cheapest fix (unchanged from the skeptic's bench):** the owner judges a blind, random ~5% subsample (~100 verdicts across both shards + unknowns) against the `why` trails — one evening, zero infrastructure. ≥85% human-model agreement retroactively calibrates the whole scoreboard. Until then: **0.823 is directional, not measured.**

## 3. The descriptor corpus problem (soft spot #5, answered — worse than stated)

`media_realm_llm` is two corpora sharing one table:
- **1,618 rows (swarm/QA/Groq)** — genuinely good: accurate, hallucination-free in 20 close reads, on-voice.
- **5,548 rows (77%, `kimi-k3-max`)** — template junk: `"<Title> lands in <realm-slug> — <genre dump>. <lowercased synopsis truncated mid-word>"`. 400/400 sampled contain "lands in"; 362/400 end without sentence punctuation. Confidence is hard-floored at 0.7 (min = median), so the least-informed writer never expresses doubt. Worse: its genre-keyword realm guesses (Fairy Tail 100YQ tagged isekai 0.59 — it has no isekai content; El-Melloi II tagged supernatural-yokai) are **stamped into the delta overlay** (`media_realm_membership_delta`: 95.75% flat +0.2 verified exactly).

**Verdict:** if descriptors are user-visible anywhere, the k3 rows must be hidden or regenerated — they'd embarrass the product on contact. The delta overlay is mostly inert by uniformity, but its non-flat residue inherits those misassignments. Coverage of the visible pool is decent (89.2%); quality is the issue, not quantity.

## 4. Defects found, ranked

1. **Canonicalization gaps in the served rails** (era-5 tail, unreviewed — the harsh look found them): sequel-at-#1 and 3-same-franchise rails incl. recaps on AoT Final P2; TR S2→S2P2; the showcase bridge sits at #15. *Fix: canonicalization pass over sequel/recap relations (they're missing from media_relations), and the bridge should rank within the fold.*
2. **Live-fallback tails**: non-store seeds hit 1.5–3.1s and can return 4 rows. *Fix: seed coverage check or graceful rail-hide client-side; scope the p95 claim.*
3. **Craft lift over-promotes**: a 63-score Vending Machine is "acclaimed" right now via a director with 11 canon works (and `%director%` matches Art Director). *Fix: lift should require the candidate's own score ≥ ~70, or cap lift at solid for sub-70.*
4. **Penalty sign is custom, not structure**: no CHECK(penalty ≤ 0). One insert re-creates the hidden-boost failure mode that took a night to diagnose.
5. **Edge-floor asymmetry**: the 2.6 edge floor > 2.5 cosine cap → penalized edge candidates can never fall below clean cosine candidates; "demotion" is intra-band only.
6. **Critique tables client-invisible** (42501) — the layer is a DB artifact until grants/RLS for read are designed.
7. **Docs gate red**: CURRENT_APP_STATE counts stale again (222 → 229 migrations).
8. Nits: `.bak` files ship in the app bundle; ContentView comment cites the wrong bundle id (`com.kuro.app` vs `com.Kuro.app`); some served titles have null `title_english`.

## 5. The soft spots, answered one by one

1. **Judge provenance** — confirmed the sharpest issue in the dossier. Fix is one evening of owner judging (§2).
2. **AniList dependency** — real and sharper than stated: edges-first serving means the flagship surface inherits AniList's community graph, and coverage is canon-skewed (50% edge share off-canon). The identity tension isn't resolved, it's *accepted*; the realm graph currently only demotes/backfills. The own-graph path (deck co-occurrence + critique consensus + realm structure) is the sunset route for the dependency.
3. **Correction-layer sunset** — confirmed: `realm_audit_overrides` is temporary-by-contract with no Phase-5 regrade in existence. Bridges calcify.
4. **Pilot scale** — confirmed + worse: mechanism trustworthy, delivery nonexistent (client can't read the tables), consensus untested at n=1.
5. **Unaudited majority** — confirmed: 3,000 of 11,629 served titles audited; the low-w1 re-review queue is designed, not built. The w1<0.55 tripwire (20% vs 3% error) is validated and should drive that queue.
6. **Era-5 tail unreviewed** — confirmed and it mattered: this review found the canonicalization failures there (§4.1).
7. **Owner walls** — veto pass still pending (now the single highest-value hour available), IMPORT_SECRET literal still in cron commands, flag ramps still owner decisions (all realm flags verified 0%).

## 6. What I could not verify

- Service-role-only surfaces (media_similar_titles contents, ops views) beyond count-level probes — no service key by design.
- The 0.823's per-seed detail (ranked lists not stored in artifacts).
- Nightly-chain robustness beyond the single recorded unattended night.
- Death Parade→Danganronpa editorial bridge *correctness* (it's documented as an editorial decision; it's just buried at #15).

## 7. Bottom line for the owner

The realm architecture works and is honest where it counts — the SA rail today (Howl's, Totoro #2, Kiki's, Mononoke…) is the product you asked for, live. The repair era's engineering is real and well-documented. But three things need your hand before any ramp: **(1) the veto hour** (§2 — until then all quality numbers are self-graded), **(2) hide-or-regenerate the 5,548 template descriptors** before they touch a user, **(3) the canonicalization sequel/recap pass** — because right now the era-5 tail is the weakest link, and it's the one that skipped review.
