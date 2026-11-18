# Open work — master plan (2026-11-18)

Owner instruction 2026-11-18: finish every open item fully — built, tested, merged and live where
it may go live. This file is the single index. Detailed task steps stay in each plan:

- Backend latency: [2026-11-09-backend-latency-plan.md](2026-11-09-backend-latency-plan.md)
- Tracker gaps: [../superpowers/plans/2026-11-09-tracker-gaps/00-program.md](../superpowers/plans/2026-11-09-tracker-gaps/00-program.md) (read its "Lead notes 2026-11-18" first)
- Catalogue sources: [../superpowers/plans/2026-11-09-catalogue-sources.md](../superpowers/plans/2026-11-09-catalogue-sources.md)

## Rules that do not bend

- Nothing turns on for users unless its plan's release gate is met. "Merged" ≠ "flag on".
- Every SQL change: prepared migration → focused DB test (red then green) → owner-approved apply in
  one transaction with exact history → read-only live verification → promotion to `supabase/migrations`.
- Every hosted step is recorded in a receipt next to its plan. Production timing uses an interleaved
  A/B on the live database (fixture plans do not predict production; see latency receipt).
- Safety gates that protect users stay: Task 15d's revoke waits for an app release and retired old
  builds; the 1c matview drop goes with it; guest browsing (W5) waits for full qualification.
- Implementers work in isolated git worktrees on their own branches; the lead reviews, runs the
  checks and merges. Commits use explicit pathspecs.

## Done (2026-11-18)

- Backend latency 1a, 1b (+ fix-forward), 1d live and committed (`70eb3bc`); 1c parked into catalogue Task 15d.
- Agent-policy and cold-read work committed (`61eb137`, `4877e43`); working tree clean; unused worktree removed.
- Tracker plans renumbered to avoid clashes with applied migrations/tests.

## Waves

| Wave | Work | Owner gate | Goes live as |
| --- | --- | --- | --- |
| 0 | Verify branch (package, app unit, Release build, DB suite, Deno, gates) → PR to `main` → merge | none (merge) | code on `main` |
| 0b | TestFlight 26 from `main`: AniList image block + placeholders, W2 export hidden | TestFlight upload (owner instruction 2026-11-18) | build for testers |
| 1 | Tracker foundation F1 (traceability gate), F2.3–F2.5 (dates, repeat count, bare plan), F3 (load profiles), F3.2 | none | dark; F2 date fill flag 0 % |
| 1 | Catalogue Tasks 1, 2 (tables + switch; shared intake helpers) | none | prepared/offline |
| 2 | Catalogue Tasks 3–6 (Wikidata, ANN, MangaUpdates, pageviews), 7, 7b (precedence, credits), 8 (comparator) | none | offline; read-only live comparator |
| 2 | Tracker W2 Task 7–8, W3a alert offer, W4 18+ notice, W10 up next | none to build | W3a may go on (D-H a); others dark |
| 3 | Catalogue 15, 15b, 15c (single writer, browse visibility, **new titles**), 16 (source credit) | apply + deploy approval | new titles resume |
| 3 | Tracker W6 grouping, W9 tags/lists | D-G for visible effect | dark |
| 4 | Catalogue 15d (AniList ids private, + 1c drop) | app release, old builds retired | revoke |
| 4 | Load qualification run (F3 `--qualify`) | hosted load-test approval | unlocks D-H for backend-traffic features |
| 5 | Tracker W5 guest browsing | full qualification + data/access controls | dark until then |
| gated | Catalogue 9 (L1), 12 (L2), 13 (L3), 10 calibration (L4c), 11 (Q6), 14 (gold judgments), 17 (L4/L5 + §6 gates); tracker W1 (D-E), W3b (D-B), W8 (D-D), dub/where-to-watch (D-C) | owner decisions below | — |

## Owner decisions still needed (defaults the plans implement in brackets)

| Id | Decision | Default |
| --- | --- | --- |
| L1 | Episodes/airing provider: TheTVDB paid licence or TMDB commercial agreement | none — needs quotes; Task 9 waits, airing times stay frozen |
| L2 | Synopses from facts only, or Wikipedia text (CC BY-SA) as input | facts only; Wikipedia only if counsel agrees |
| L3 | Images: Kuro typographic art / licensed L1 art / press kits | (a) Kuro art now |
| L4 | Fate of stored AniList-derived data at Task 17 | factual stub |
| L5 | User AniList list import (`concierge-import-anilist`) | keep until Task 17, then remove |
| Q6 | AniDB tag data | terms check before Task 11; exclude if non-commercial |
| D-B/C/D/E | Manga chapter alerts, dub/where-to-watch, dark mode, Home Screen widget | not started |
| D-G | Who reviews series membership (W6 visible effect) | pilot of ≈10 owner-reviewed series |
| D-H | Release rule while NOT QUALIFIED | (a) blanket: only W3a goes on |
| Concierge | Retire the chat/recommend surface? (parse stays for imports) | keep |

## Progress log

Append one line per landed step: date, wave, item, commit, checks, hosted receipt.

- 2026-11-18 wave 0: tree committed (`61eb137`, `4877e43`, `70eb3bc`); plans renumbered; this index written.
- 2026-11-18 wave 1: tracker F1.1–F1.3 BDD traceability gate merged (7c4bd2d..c9972b3); 25 self-tests pass; gate 86 scenarios / 14 resolved / 60 pending / 0 errors.
- 2026-11-18 wave 1: catalogue Tasks 1–2 merged (d39eb01, 8499df2): prepared 20261112100000 + test 120 (39 assertions); _shared catalogue helpers; Deno _shared 48, bulk-import-anime 32, -manga 17, release-intake 28 pass. Lead rulings: shadow mode keeps AniList as writer; no source CHECK; shadow/snapshot cleanup deferred to Task 15.
- 2026-11-18 wave 1: tracker F3.1–F3.1d + F3.2 merged (46d18e2..823b85a): load-profiles gate 6 files pass; DB test 112 (7 assertions) pass; apply_progress_mutations_v1 confirmed live (read-only).
- 2026-11-18 wave 0: PR #11 merged to main (b1e095f) after package tests, KuroTests 1,204/1,204, Release build, DB suite 46 files / 1,391, gates 10/10, Deno and policy checks. W4 live precondition recorded (d51d528).
- 2026-11-18 wave 0b: TestFlight 26 (widget-less variant, branch `release/testflight-26`, worktree /Users/max/Kuro-wt/tf26) archived OK; **upload BLOCKED**: App Store Connect returns 403 FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED. The account holder must accept the pending agreement in App Store Connect (Business / Agreements); then rerun the export/upload from the saved archive.
- 2026-11-18 wave 2: W2 Tasks 7–8 merged (5e6d61b..ca9ce89): load gate 7 files, DB 110 (10) pass, BDD gate blocking for W2; acceptance 12/13 (load scenario needs qualification run). State docs updated.
- 2026-11-18 wave 2: catalogue Tasks 3–6 merged (catalogue-intake Edge Function: Wikidata, ANN, MangaUpdates, pageviews; link-trust hardening): Deno catalogue-intake 58, _shared 72, regression suites pass; 15 polite live source requests recorded in fixtures/README.md. Not deployed.
- 2026-11-18 wave 2: catalogue Tasks 7, 7b, 8 merged (precedence/compose, credits resolution, comparator RPC 20261112100100 + test 121, report script): Deno catalogue-intake 84, _shared 81; DB 120 (39) + 121 (25); node report 15. Adult rule: Hentai only counts; ecchi/yaoi left to owner. Not applied/deployed.
- 2026-11-18 review: F2 independent review found 3 important defects (removal Undo fills dates and drops dates/repeat even flag-off; detail +1 Undo leaves filled start date; unloaded projection treated as new → overwrites imported dates) + minors (fill before durable status, unknown values editable as empty, lease test gap). Fix lane running. **Do not ship a build from main until the F2 fix lands** (editor date/repeat fields are visible without a flag).
- 2026-11-18 review: catalogue backend independent review — no critical; important: cross-batch duplicate Wikidata claim accepted, compose has no per-title budget, shadow rows never deleted; minors (1,000-row truncation, stalls on one bad item, MU acceptance weaker, report gate/cast issues, trigger race). Fix lane running; no catalogue hosted step until it lands.
- 2026-11-18 wave 2: W4 18+ notice merged (d4128c7..fc93126): prepared 20261118100000 (sha256 cd033675…854d, not applied) + test 113 (27); 97/105/102 still pass; load gate 8 files; BDD gate: W4 landed, 24 resolved / 0 unresolved. Flag search_adult_notice_v1 0 %. Needs: independent review of the import adult-guard trigger before apply; qualification run before flag.
- 2026-11-18 tests: merged-state KuroTests 1,218/1,219; the one failure (ImportsContractTests.lateServerWriteOfPreviousAccountIsDropped, F33 account-switch cancellation) is intermittent on main too (2/3 failed), so pre-existing; debug lane running to decide production race vs test race.
- 2026-11-18 review fixes: catalogue backend review items 1–12 + queued-link security fix merged (7 commits): Deno catalogue-intake 128, _shared 81; DB 120/121/122 (85 incl. new two-session race test); report 15. WDQS 500-id query 2.7 s (one sample), client timeout 45 s.
