# Claude Code — Autonomous Phase 1→2→3 Prompt

**Paste everything below the line into Claude Code** (`claude --dangerously-skip-permissions` OK).  
Owner is away. You run until Phase 1 is fully done, then push Phase 2/3 as far as the plan allows without inventing owner judgments or blessing sites.

---

## PROMPT START

You are Claude Code working in `/Users/max/Kuro-Anime-App` on branch `kuro/taste-overhaul`.

### Mission

Execute the canonical plan:

**`docs/superpowers/specs/2026-08-04-realm-repair-and-critique-plan.md`**

Order is mandatory:

1. **Phase 1 — Repair** → finish completely (implement + verify + review + commit + push migration + docs)
2. **Phase 2 — Scoreboard** → prepare everything; run eval only if owner judgments exist; otherwise leave a clean handoff package (do NOT invent owner judgments)
3. **Phase 3 — Critique pilot** → complete Round 0 (site dossiers) fully; prepare Round 1 shortlist draft; STOP before any fetch/parse that requires owner-blessed sites

Do not wait for the owner. Do not ask clarifying questions. If blocked on credentials, try every local path (`Config/Shared.xcconfig`, `scripts/project_public.env`, `SUPABASE_*` env, linked `supabase` CLI). If still blocked, document the exact missing secret and continue all work that does not need it.

### Non-negotiable product rules (from CLAUDE.md + the plan)

- Update after every work initiative: `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, and `~/.claude/projects/-Applications-Kuro/memory/MEMORY.md`
- SQL: `SET search_path = public, extensions`; RLS on new tables; no bare DELETE/UPDATE without WHERE (`pg_safeupdate`)
- Do NOT restart Groq descriptor drain
- Do NOT flip `discover_realm_rails_v1` or `personalized_new_to_you_v1` to 100% — stay at 0%; demo via `--ff-on=` only
- Do NOT invent `owner_judgments.jsonl` content — owner-only
- Do NOT bless critique sites — owner-only after Round 0 dossiers
- Catalog IDs are Kuro `anime.id` / `manga.id`, not modern AniList IDs
- Penalty values stay **negative** (Feb convention). Phase 1 fix is operator change to `+ coalesce(penalty,0)`, NOT flipping stored signs, NOT `greatest(0, penalty)`
- Prefer few, sharp acceptance checks over sprawling test suites (see Testing doctrine below)
- Commit when a verify gate passes; push branch when Phase 1 DoD is met (`git push -u origin HEAD`). Do not force-push. Do not push to `main`.

### Orchestration model (mandatory)

You must use **multiple subagents** via the Task tool. Do not solo entire phases.

| Role | When | Job |
|---|---|---|
| **Implementer** | each Phase 1 fix | Write migration/SQL/scripts |
| **Verifier** | after each fix | Run that fix’s pass/fail checks against **live linked prod** |
| **Reviewer** | after each fix AND after Phase 1 complete | Defect-first review of the diff; must explicitly APPROVE or REJECT with reasons |
| **Security reviewer** | once after hygiene fix; once at Phase 1 end | Advisors + grants + secret leftovers |
| **Scout (Sonnet-class)** | Phase 3 Round 0 | Write site dossiers |
| **Planner/QA (strongest available)** | Phase 1 design choices, gate reports | Structure, final review |

**Reviewer gate rule:** If Reviewer REJECTS, Implementer fixes, Verifier re-runs, Reviewer re-reviews. Max 3 loops per fix. If still failing, stop that fix, write `reports/realm-repair/BLOCKED.md` with evidence, continue other fixes only if independent.

Run independent work in parallel (e.g. hygiene research || penalty SQL draft; dossier scouts in parallel after Phase 1).

### Testing doctrine (do NOT overtest)

Write **only** the checks below. No unit-test sprawl, no snapshot farms, no “test every branch of SQL.”

**Allowed test surfaces:**

1. **SQL acceptance scripts** under `scripts/realm_repair/` — small, runnable with service role or authenticated JWT
2. **One Node harness** `scripts/realm_repair/run_phase1_acceptance.js` that prints PASS/FAIL per check
3. **Gold eval** only in Phase 2 (existing `scripts/eval_realm_rec_gold.js`)

**Forbidden:** adding large Jest/XCTest suites for realm SQL; testing every affinity pair; synthetic fuzz of all 40 realms.

---

## PHASE 1 — Repair (autonomous, must complete)

Canonical text: plan §3. Prefer **one migration** if safe; split only if statement_timeout / transaction risks require it (tier rebuild + precompute may need their own migrations). Timestamp migrations after latest on disk.

### Fix 1 — Penalty operator

**Change:** In live `recommend_ids_similar_to_seeds` (and any identical copies you recreate), both anime and manga score branches:

```sql
-- FROM
- case when allow_gimmicks then 0.0 else greatest(0, coalesce(penalty,0))::float8 end
-- TO
- case when allow_gimmicks then 0.0 else /* keep subtraction of a negative = demote */
  /* plan says: replace with + coalesce(p.penalty,0) relative to the score expression */
```

Read plan §3.1 carefully: the score expression becomes effectively  
`similarity_mults + coalesce(penalty,0)` where penalty rows are negative.

**Do NOT** flip rows in `editorial_penalty_tags`.

**Acceptance (exactly these):**

| ID | Check |
|---|---|
| P1 | Seed Berserk anime (resolve Kuro id by title) top-25 contains **zero** clear low-canon isekai junk (Overlord / slime / “reborn” seasonal class). Soft-fail with listed offenders if any. |
| P2 | For a known isekai-tagged candidate that previously ranked, its score does not **increase** vs a pre-fix snapshot you capture before migrating (save `reports/realm-repair/penalty-before.json`). |

**Reviewer:** confirm operator matches Feb convention; no sign flip in table.

### Fix 2 — Gates → costs

**Change:** Hard exclude ONLY:

- tier distance > 1
- (no shared family AND affinity < 0.6)

Everything else becomes score multipliers:

- shared top realm ×1.0
- adjacent (affinity ≥ 0.6) ×0.85
- same family only ×0.65

Membership ≥0.35 becomes a weight term, not an entry cliff.  
**Remove** the two Spirited Away seed-specific affinity vetoes once costs land.

Also put **Kon** in acceptance (gap called out in prior review): Perfect Blue and/or Paprika should be able to appear in SA neighborhood if craft/realm costs allow — not a hard requirement to be #1–3, but must not be structurally impossible solely due to yokai cliff.

**Acceptance:**

| ID | Check |
|---|---|
| G1 | Spirited Away (id `111`) top-12 still Ghibli-class heavy (Mononoke / Howl’s / Boy and the Heron or equivalent present) |
| G2 | Totoro (id `221`) **re-enters** top-25 |
| G3 | Toilet-bound Hanako-kun S2 ranks **below** Wolf Children in SA list (or Hanako absent and Wolf Children present) |
| G4 | “Vending machine” / gag isekai class still **absent** from top-25 (tier hard gate) |
| G5 | Perfect Blue (`286` if still that id — resolve) OR Paprika is not structurally excluded by top-realm-in-S cliff alone (document membership/cost path) |

**Reviewer:** reject if vetoes remain “whack-a-mole” without the cost model; reject if hard exclusions wider than plan.

### Fix 3 — Tier from effective + backfill

**Change:** Rebuild `media_realm_tier` definition to read `media_realm_membership_effective` (not raw membership). Backfill so visible titles with membership all have a tier row.

**Acceptance:**

| ID | Check |
|---|---|
| T1 | `count` of visible non-adult titles with membership ≥0.35 (or in effective) and **no** tier row = **0** |
| T2 | Spirited Away / Totoro still have a tier row; spot-check 5 random previously-missing ids if you logged them |

**Reviewer:** confirm split-brain closed; dependents (`media_realm_profile` etc.) still compile.

### Fix 4 — Tier refresh cron

**Change:** Staged rebuild (temp → swap) and/or raised `statement_timeout` inside the cron job body. Must not rely on in-migration `REFRESH` that times out in a transaction.

**Acceptance:**

| ID | Check |
|---|---|
| C1 | Trigger/run the job once successfully (or prove schedule + a manual invoke succeeds) |
| C2 | Evidence in `cron.job_run_details` (or equivalent) of success — if you cannot wait for 2 natural runs, document one green manual run + scheduled definition, and leave a follow-up note |

**Reviewer:** reject if still “full refresh in migration txn.”

### Fix 5 — Precompute `media_similar_titles`

**Change:** Nightly (or on-demand rebuild) table/matview: top-30 neighbors per `(media_type, media_id)` from repaired scorer. `recommend_ids_similar_to_seeds` becomes a cheap read (+ multi-seed blend).

**Acceptance:**

| ID | Check |
|---|---|
| S1 | RPC p95 under authenticated < **200ms** on 20 warm calls (Spirited Away, Berserk, Frieren, random 17) — record timings in report |
| S2 | `scripts/eval_realm_rec_gold.js` completes **100/100 seeds** with **zero** statement timeouts (judgments may still be heuristic for this smoke — timeouts are the metric) |

**Reviewer:** reject if RPC still does heavy recursive CTE per call as the hot path.

### Fix 6 — Hygiene

**Change:**

- Drop `_ops_import_secret_from_cron()` and related secret-scraping leftovers
- Fix SECURITY DEFINER view advisors: `realm_affinity_effective`, `media_realm_llm_pending`, `media_realm_profile` — prefer `security_invoker` or revoke dangerous grants; **`media_realm_profile` must not be granted to `anon`**

**Acceptance:**

| ID | Check |
|---|---|
| H1 | Function `_ops_import_secret_from_cron` gone |
| H2 | `get_advisors(security)` ERROR count for these views = 0 (or documented residual with severity) |

**Reviewer:** security-reviewer subagent required.

### Phase 1 Definition of Done (all required)

- [ ] Fixes 1–6 implemented and pushed to linked Supabase (`supabase db push --linked --include-all` with noninteractive yes)
- [ ] `scripts/realm_repair/run_phase1_acceptance.js` → all checks PASS (C2 may be WARN with evidence)
- [ ] Report: `reports/realm-repair/phase1-acceptance.md` + JSON
- [ ] Reviewer APPROVE on final Phase 1 diff
- [ ] Migrations committed on `kuro/taste-overhaul` and **`git push`**
- [ ] Docs triad + MEMORY updated
- [ ] Checksums updated if your quality gate requires it (`scripts/quality-gates/check_migrations.sh --update`)

**Only then** enter Phase 2.

---

## PHASE 2 — Scoreboard (autonomous up to owner wall)

### Do now (no owner)

1. Ensure `eval/realm_rec_gold/owner_shortlists.jsonl` + `owner_judgments.template.jsonl` are current post-repair (regenerate shortlists if RPC shape changed).
2. Write `reports/realm-repair/phase2-owner-handoff.md` with:
   - exact commands to fill judgments
   - how long / ≥50 seed rule
   - how to run eval after
3. If `owner_judgments.jsonl` **already exists** with ≥50 judged seeds: run eval, append baseline P@10 table into the plan doc §4 area (or `reports/realm-rec-gold/baseline-post-repair.md`). Re-decide edges ship/no-ship on that data.
4. If judgments **missing**: create empty `owner_judgments.jsonl` is **forbidden**. Stop Phase 2 measurement. Continue to Phase 3 Round 0.

### Reviewer

Approve handoff clarity; reject if eval still uses circular heuristic as “baseline.”

---

## PHASE 3 — Critique pilot Round 0 (+ Round 1 draft only)

Canonical: plan §5.

### Round 0 — Site dossiers (autonomous, parallel subagents)

Scout **8–12** niche critique sites (EN + JP). Classes from plan:

- craft/animation (Sakuga-type)
- long-form named critics (THEM-type)
- content-aware desks (for `media_content_notes`)
- manga-first (Mangasplaining / Manga Bookshelf-type)
- JP critic/seasonal essay desks

**OUT:** MAL/AniList aggregates, Crunchyroll Awards, pure user-score farms.

For each site write **one page** to `reports/critique-pilot/dossiers/<slug>.md`:

name · URL · anime/manga/both · language · named critics? · depth · archive size estimate · robots.txt + TOS posture · accessibility (index/RSS) · lens · proposed tier A–E · one example review URL

Also write `reports/critique-pilot/dossiers/README.md` recommending a **3–4 site pilot slate** (Fable/strong model judgment) — clearly labeled **PROPOSED, not blessed**.

**Do NOT** insert into `critic_sources` as blessed. You may draft a seed SQL file commented `OWNER_BLESS_REQUIRED`.

### Round 1 — Title shortlist draft only

Build `scripts/data/critique_pilot_titles.DRAFT.json` using plan rules (overlap-first, gold seeds, anchors, ≥25% manga, cap 150–200). Label DRAFT. Do not fetch reviews.

### STOP before Round 2

Do **not** fetch/parse reviews, create critique tables in prod, or run swarm until owner blesses sites + titles.

### Reviewer

Approve dossier quality + legal posture notes; reject if dossiers lack robots/TOS or propose aggregators.

---

## Reporting & commits

After Phase 1:  
`reports/realm-repair/phase1-acceptance.md`

After Phase 2 prep:  
`reports/realm-repair/phase2-owner-handoff.md`

After Phase 3 Round 0:  
`reports/critique-pilot/dossiers/` + `SUMMARY.md`

Commit style: concise why-focused messages. Prefer several commits (per fix or per phase) over one megacommit. Push `kuro/taste-overhaul`.

Final message to user (when you stop) must include:

1. Phase 1 PASS/FAIL table (P1–H2)
2. Migration versions pushed
3. What Phase 2 needs from owner (judgments)
4. Proposed 3–4 pilot sites (unblessed)
5. Exact next owner actions (plan §10 checklist subset)

### Absolute stops (safe)

- Missing service role when required for push/ops → document + continue offline work
- Acceptance fail after 3 review loops on a fix → BLOCKED.md + continue others
- Never force-push; never push main; never enable flags to 100%
- Never store full review prose in the database

## PROMPT END

---

## How to launch (owner)

```bash
cd /Users/max/Kuro-Anime-App
claude --dangerously-skip-permissions
# paste PROMPT START … PROMPT END
```

Optional: open a second Claude Code for **reviewer-only** by pasting only the Reviewer sections and pointing it at the implementer’s branch.

When you return, read:

1. `reports/realm-repair/phase1-acceptance.md`
2. `reports/realm-repair/phase2-owner-handoff.md`
3. `reports/critique-pilot/dossiers/SUMMARY.md`
4. Plan §10 checklist
