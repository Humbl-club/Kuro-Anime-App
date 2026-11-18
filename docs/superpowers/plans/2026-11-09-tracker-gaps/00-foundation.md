# Tracker gaps foundation (F1 traceability gate, F2 Library contract v2, F3 load-mix registration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every tracker-gap workstream three shared foundations: a gate that proves each Gherkin scenario maps to one existing test (and, separately, that a workstream is *accepted* from an execution record), an editable repeat count and started/finished dates through `LibraryEdit` (with the status-change date fill behind its own release switch), and an opt-in way to add new backend traffic to the load test at absolute rates, with a qualification mode that is the only source of release evidence.

**Architecture:** F1 is a Python checker (`check_bdd_traceability.py`, same style as `check_docs_current_state.py`) behind a shell gate. It has its own blocking self-test entry and a WARN entry in `run_all.sh`. "Resolved" (the named test exists) is the gate; "accepted" is a separate checker mode, `--accepted <workstream>`, that reads an execution record `docs/tracker-gaps-2026-11/acceptance/<workstream>.json` for the current HEAD (F1.3). F2 extends the `KuroLibrary` value types (`PartialDate`, `LibraryEdit`, `LibraryEntry`) and the existing PATCH path of `SupabaseLibraryBackend`. The three columns are live since 2026-10-08 and writable by the owner under the existing RLS policy, so no migration is needed. The status-change date fill lives in `LibraryStore.apply`, behind an injected gate wired to the server flag `library_date_autofill_v1` (default 0 %, checked before any request is sent), and Undo bypasses it. With the fence on, a fill adds a second write (the PATCH leg), so it is backend traffic with its own load profile `status-with-date-fill`. F2.5 widens the shared bare-plan rule (`TastePlanAction.isBarePlan`) so a Plan-key Undo never removes a plan that has since gained dates or a repeat count. F3 adds a per-file profile registry (`scripts/load/profiles/*.js`) that `backend_workload.js` loads. Profiles never change the predeclared mix: they run in a separate scheduler lane at their own absolute rates (`ratePerSecond`), with their own random stream, busy set, in-flight cap and safety window, and the report keeps the base lane (unchanged schema fields, unchanged pass rule) apart from the profile lane. The named workload `tracker-gaps-combined` lists every profile with an explicit rate. `--qualify` (populated-fixture preflight, strict validators, minimum samples, representative writes, cleanup verification) is the only mode whose results count as release evidence; the default wiring mode never does.

**Tech Stack:** Python 3 (stdlib `unittest`), bash, Swift 6.2 toolchain in Swift 5 mode (`KuroModules`, Swift Testing), SwiftUI (iOS 26 SDK), Node `node:test`, PostgreSQL 17 disposable fixture (`scripts/db/run_local_db_tests.sh`).

**Spec:** docs/superpowers/specs/2026-11-09-tracker-gaps-design.md + features/W9-lists.feature (Rule "Repeat count and dates are editable (F2 contract)", tagged `@workstream-F2`); F1 reads every `features/*.feature`. Program corrections of 2026-11-09 (owner-approved): release switches (decision 1), bare-plan Undo (decision 3), absolute-rate load model (decision 5), resolved vs accepted (decision 6), no manufactured red (decision 7).

## Global Constraints
- Spec §1: "Foundation tasks (in `00-foundation.md`): **F1** BDD traceability gate, **F2** Library contract v2 (editable repeat count and dates), **F3** load-mix registration for every new backend read."
- Spec §4: "`scripts/quality-gates/check_bdd_traceability.sh` parses every feature file, fails a scenario with zero or several test tags, and resolves each tag to an existing test function, SQL file or load profile. Registered in `run_all.sh` as WARN (blocking flag 0) until W2 lands, then blocking."
- Spec §4: "`@manual:<reason>` only together with `@owner-gate` (e.g. owner visual acceptance). Never for logic."
- Spec §3: "every new or changed backend read/write is assigned to one existing budget class, added to `scripts/load/backend_workload.js` (F3), and covered by an SQL-plan check."
- Spec §3: "A workstream that adds backend traffic is not released to users while the qualification is NOT QUALIFIED, and its change must not worsen the measured steady-state result. Budgets are never relaxed for a retry."
- Spec §3: "p95 end-to-end thresholds: **Browse/Search/Clubs/Progress ≤ 750 ms, Home/Detail ≤ 1200 ms, Discover/Moods ≤ 1500 ms, Edge Parse/Recommend ≤ 2500 ms**".
- Spec §6 W9: "repeat count and dates go through `LibraryEdit` (F2) to the existing `repeat_count`, `started_raw`, `finished_raw` columns."
- Spec §5.2 W9: "editable repeat count and started/finished dates (year, year-month or full date); status → Watching fills an empty start date, → Completed fills an empty finish date, with Undo".
- Spec §3 Architecture: "tracking reads/writes only through `LibraryStore` / `LibraryActions`; no second Supabase client; no Combine; `print` only inside `#if DEBUG`; no force unwraps."
- Spec §3 Data rules: "Do not interpret missing source history as newly deleted data." (Imported raw dates are never rewritten by an untouched editor save, and an unknown value is never auto-filled.)
- Spec §3 Navigation: "unsaved input uses `.kuroDiscardGuard`." Copy: "every user-facing string through `KuroLocale` (EN + DE)".
- Spec §3 Process: "build warning count does not rise above the 2026-10-31 baseline (60 unique Kuro-side warnings)."
- Spec §2 Release switches: "Every user-visible workstream has a server feature flag, default 0 %, checked before any request is sent: … and F2's date auto-fill `library_date_autofill_v1` (a status change that fills a date adds a second write, so it is backend traffic too). A feature whose RPC exists but whose flag is off sends nothing."
- Spec §3 Load model: "the predeclared qualification mix keeps its absolute arrival rate (20 rps) when profiles are enabled; profiles add their own absolute rates in a separate lane and are reported separately, so the base comparison is like-for-like. The combined workload `tracker-gaps-combined` states each profile's rate explicitly (guest traffic as an absolute rate, not a share)."
- Spec §3 Release evidence: "comes only from qualification mode: populated fixtures (no empty-answer passes), semantic assertions, representative writes (organisation saves, list create/reorder/rebalance/seed, status with date fill), typical and supported-maximum payloads, cleanup verification, and minimum samples of **≥ 100 completions per endpoint and ≥ 30 per library-size subgroup** (fewer → `insufficient`, never `pass`). Wiring mode may accept empty answers and is never release evidence."
- Spec D-H: per-feature release (recommended option b) needs "its own profile meets its class budget in an owner-approved qualification-mode run and the base 20 rps steady result does not worsen".
- Program decision 3: the bare-plan predicate also requires `repeatCount == 0`, no started date and no finished date. Program decision 6: "accepted" requires an execution record for the current HEAD; SQL scenarios count only from a passing DB run, load scenarios only with a qualification-mode run id. Program decision 7: red steps show missing or wrong current behaviour; never a deliberately wrong expectation.

## Review Focus
1. **Stored raw date forms that the app never wrote.** Imports stored `2024-00-00` and `2024-05-00` (MAL XML), `2024` and `2024-05` (AniList `fuzzyDate`), and full dates. If `PartialDate(raw:)` rejects any of them, the editor shows the field empty. If equality compares strings, an untouched Save rewrites `2024-00-00` as `2024`. Pinned by `PartialDateTests/acceptsEveryStoredImportForm`, `PartialDateTests/equalityIsByValueNotSpelling` and `TrackingDraftTests/untouchedDatesSendNothing` (Task F2.1, F2.4).
2. **Undo after a status change refills a date.** For example: Watching with no start date → Completed fills the finish date → Undo writes status Watching back. That is itself a "→ Watching" transition, so without a bypass the store would fill the start date. Pinned by `LibraryEditV2Tests/undoNeverFillsDates` (Task F2.3).
3. **Offline "→ Watching" with the fence on.** Today a status change uses the durable outbox only. An auto-filled date adds a PATCH leg, and offline that leg fails. Without a rule, every offline status change would report failure. Decision: an auto-filled date is best effort. If the PATCH carries nothing the caller named, its failure leaves the date empty and the outcome is still the durable `.applied`. Pinned by `LibraryEditV2Tests/offlineDurableStatusChangeStillAppliesWithoutDateFill` (Task F2.3). The same extra leg is why the fill has its own switch: while `library_date_autofill_v1` is off, a status change sends exactly what it sends today (fence on: the durable mutation and no PATCH). Pinned by `LibraryEditV2Tests/flagOffSendsNoRequest` and `CompositionGraphTests/dateAutofillFollowsTheServerFlag` (Task F2.3).
4. **Wrong day near midnight, or overwriting a value the app cannot see.** "Today" is computed in the injected calendar and time zone. For example, 2026-03-01T23:30Z in Europe/Berlin is 2026-03-02. Fill only when the entry is being created, or when its `sourceMetadata` is known and the raw is nil or blank. Never fill when metadata is unknown (a cached Home row) or when the raw exists but is unparseable. Pinned by `LibraryEditV2Tests/fillUsesInjectedCalendarNearMidnight` and `LibraryEditV2Tests/unknownOrUnparseableDatesAreNeverFilled` (Task F2.3).
5. **A traceability gate that silently passes.** Two failure modes:
   - Parsing errors: a `@deno:` name with spaces, `@manual:x @owner-gate` written on one line, or `@gated` above `Rule:`.
   - Resolution errors: `@Test("label") func x()`, `extension Suite`, or attributes split over lines.

   Either one makes the gate lie. The self-tests run as their own **blocking** gate entry, so a broken resolver fails `run_all.sh` instead of warning. Pinned by `BddTraceabilityTests.*` (Task F1.1, F1.2).
6. **"Accepted" that is really only "resolved".** Four ways an acceptance check would lie:
   - a record for an older commit (a record can never name the commit that contains it, so "equals HEAD" alone is unpassable, and "any ancestor" is meaningless);
   - an SQL scenario counted because its file exists, or because the harness printed `BLOCKED` / `PASS … scope(s) BLOCKED` for it;
   - a load scenario backed by a wiring-mode report, a report whose preflight did not pass, or a report with `insufficient` samples;
   - a scenario retagged after the record was written.

   Decision: HEAD equals the tested commit, or every commit since touches only `docs/tracker-gaps-2026-11/acceptance/` and the tree is clean outside it; SQL needs the per-file `PASS … 0 blocked markers` line in the stored log; load needs a `mode: "qualify"` report with `preflight.passed`, the profile's verdict `pass` and a cleanup report proving the profile's data is gone; each record entry carries the tag it tested. Pinned by `BddAcceptanceTests.*` (Task F1.3).
7. **Bare-plan widening changes four surfaces.** `TastePlanAction.isBarePlan` decides the Taste/Discover Plan key action (`.unplan` vs `.edit`), the Plan toast's Undo (`.remove` step), the Discover menu's Plan item (`DiscoverMenuOffer`) and Home's new-account block (`HomeShelfPolicy.onlyBarePlans`). After widening, a plan with a date or a repeat count opens the editor instead of coming off, its Undo writes nothing, and it ends the new-account block. An unparseable imported raw date also counts as a date (judged on the stored raw, not on `startedOn`), so a removal never loses it. Pinned by `FirstRunLaneTests/planUndoKeepsADatedPlan`, the extended `planKeyRule` / `newAccountEndsOnAStartedPlan` and `DUpreviewTests/menuOffer` (Task F2.5).
8. **A profile lane that disturbs the base lane.** Today `load_test_backend.js` has one LCG (drawn by both `chooseKind` and `requestFor`), one `busy` set, one in-flight cap and one rolling safety window across all samples. Sharing any of them with a profile lane shifts the base kind sequence, inflates base `droppedBusy` (so `samples.length === offered` fails) or lets profile errors stop the base lane silently. Decision: per-lane LCG, busy set, in-flight cap and rolling window; the stop file or either lane's safety stop halts both lanes and `stopReason` names the lane; `report.summary` stays base-only with the v1 field meanings. Pinned by `base lane is identical with a profile lane` (Task F3.1).
9. **A qualification that passes on nothing.** Empty arrays, unseeded actors, a 2,000-title subgroup with 12 samples, or a write profile that never verifies its cleanup. Decision: `loadProfiles` refuses a profile whose qualify-mode `validate` accepts any of its declared `emptyExamples`; `--qualify` refuses to start unless the preflight finds the declared subgroups, the seeded state and enough expected completions; verdicts are tri-state and `fail` > `insufficient` > `pass`; write profiles must declare `seed` and `cleanupCheck`. Base-lane pass semantics are unchanged (the base lane is not judged by the minimum-sample rule; flagged to the lead because at 20 rps × 600 s the 2,000-title subgroup of `parse`/`recommend` would be `insufficient`). Pinned by `qualification verdicts`, `qualify preflight refuses thin or empty setups` and `qualify mode rejects empty answers` (Task F3.1c).

## Success parameters
F-tasks have no §5.2 row of their own. They carry the W9 F2 clauses, the §2 release-switch rule, the §4 gate contract and the §3 F3 rules.

| Parameter | How it is measured | Expected |
|---|---|---|
| Every scenario has exactly one test tag, and each tag resolves (or is gated) | `scripts/quality-gates/check_bdd_traceability.sh; echo $?` | Before W2 lands: `0 tag errors`, every non-gated scenario `pending (not landed)`, exit 0, run_all summary `bdd-traceability` WARN entry. From W2 on (flag 1): every feature in `bdd_landed.txt` has `0 unresolved`, exit 0. When all land: `0 unresolved`, `0 pending`, exit 0. |
| Gate self-tests | `bash scripts/quality-gates/test_bdd_traceability.sh` | `OK (22 tests)` from unittest (git-dependent acceptance tests skip with a reason when `git` is absent), exit 0; run_all summary `bdd-selftest PASS` |
| "Accepted" needs an execution record for HEAD, not only resolution | `python3 scripts/quality-gates/check_bdd_traceability.py --accepted F2; echo $?` | exit 0 only when every in-scope F2 scenario has `pass` with valid run evidence in `docs/tracker-gaps-2026-11/acceptance/F2.json` for HEAD. At F4: the record exists and the command exits 1 naming only `Status changes with a date fill stay within budget` (`not accepted: blocked`, owner-approved qualification run pending) |
| Repeat count and dates (year, year-month, full) are editable through `LibraryEdit` | `cd Packages/KuroModules && swift test --filter LibraryEditV2Tests` | `repeatCountAndDatesTravelThroughLibraryEdit` passes |
| Date auto-fill is off unless `library_date_autofill_v1` is on, and off sends no date leg | `swift test --filter LibraryEditV2Tests/flagOffSendsNoRequest`; `xcodebuild … -only-testing:KuroTests/CompositionGraphTests` | both pass; flag off + fence on: one durable mutation, zero PATCH requests, `startedOn == .unchanged`; a hand-edited date is still one normal write |
| The date leg is never sent with another account's credential | `xcodebuild … -only-testing:KuroTests/DateFillCredentialLeaseTests` | `preDispatchSwitchSendsNoDateLegAsB` passes |
| Status → Watching / → Completed fills an empty date (flag on), and Undo restores it | `swift test --filter LibraryEditV2Tests/statusChangeFillsEmptyDatesWithUndo` | passes |
| Invalid dates are rejected and precision is kept | `swift test --filter PartialDateTests` | `rejectsImpossibleDatesAndKeepsPrecision` passes |
| Plan-key Undo (Taste and Discover share `TastePlanController`) never removes a plan that gained a date or a repeat count | `xcodebuild … -only-testing:KuroTests/FirstRunLaneTests -only-testing:KuroTests/DUpreviewTests` | `planUndoKeepsADatedPlan`, `planKeyRule`, `newAccountEndsOnAStartedPlan`, `menuOffer` pass |
| No migration needed for F2 | Evidence note `docs/tracker-gaps-2026-11/foundation/F2-no-migration.md` with the policy, grant and constraint search results quoted | present |
| Predeclared base lane unchanged, with or without profiles | `node --test scripts/load/backend_workload.test.js scripts/load/backend_runner.test.js` | `predeclared mix is unchanged` (first 1,000 `chooseKind` draws for seed 20261109 equal the frozen digest) and `base lane is identical with a profile lane` pass |
| Profiles run at their own absolute rate in a separate lane | `backend_workload.test.js` → `profiles keep their absolute rate` | passes (0.5 rps over 10 s = 5 arrivals at 2,000 ms spacing, independent of `--rps`) |
| Qualification never reports `pass` on thin, empty or unverified data | `backend_workload.test.js` → `qualification verdicts`, `qualify preflight refuses thin or empty setups`, `qualify mode rejects empty answers`; `backend_fixture.test.js` → `cleanup verifies profile data is absent` | pass; < 100 completions per endpoint or < 30 per covered subgroup → `insufficient`, exit code 3 |
| `tracker-gaps-combined` lists every profile with an explicit absolute rate | `backend_workload.test.js` → `combined workload names every profile with an explicit rate` | passes (base 20 rps; profile keys equal the registry; base + Σ rates ≤ 50) |
| The F2 date leg is in the load test | `node --test scripts/load/profiles/status-with-date-fill.test.js`; later an owner-approved `--qualify --workload=tracker-gaps-combined` run | unit tests pass; live: both legs (`:mutation`, `:date-patch`) p95 ≤ 750 ms (Progress class) with ≥ 100 completions each and ≥ 30 per covered subgroup |

## File Structure
- `scripts/quality-gates/check_bdd_traceability.py`: parses feature files, counts test tags per scenario, honours `@gated`, and resolves tags. Exit 0 when clean, 1 on findings, 2 on usage error. F1.3 adds `--accepted <workstream>` and `--record-template <workstream>`.
- `docs/tracker-gaps-2026-11/acceptance/` (new, first record written in F4): one `<workstream>.json` execution record per workstream plus `logs/<workstream>-<run id>.txt`. Schema in Task F1.3 and the checker's header comment.
- `scripts/quality-gates/check_bdd_traceability.sh`: gate wrapper (`=== BDD traceability ===`; runs the checker on the real tree).
- `scripts/quality-gates/test_check_bdd_traceability.py`: unittest self-tests that build fixture trees in a temp directory.
- `scripts/quality-gates/test_bdd_traceability.sh`: blocking self-test gate wrapper.
- `scripts/quality-gates/run_all.sh`: registers `bdd-selftest:test_bdd_traceability.sh:1`, `bdd-traceability:check_bdd_traceability.sh:0` and (F3.1b) `load-profiles:test_load_profiles.sh:1`.
- `scripts/quality-gates/test_load_profiles.sh` (new, F3.1b): runs `node --test scripts/load/*.test.js scripts/load/profiles/*.test.js` (the profiles glob is skipped when the folder is absent); SKIP when `node` is missing.
- `Packages/KuroModules/Sources/KuroLibrary/PartialDate.swift` (new): the `PartialDate` value.
- `Packages/KuroModules/Sources/KuroLibrary/LibraryValues.swift`: `LibraryEdit` gets three fields; `LibraryEntry` gets three computed reads; every edit helper learns the fields; the date-fill rule.
- `Packages/KuroModules/Sources/KuroLibrary/LibraryContracts.swift`: `LibraryChange.isProgressOnly` includes the new fields.
- `Packages/KuroModules/Sources/KuroLibrary/LibraryStore.swift`: injected calendar and `dateAutofillEnabled` gate; date fill in `apply`; Undo bypass; best-effort fill leg.
- `Kuro/Services/FeatureFlags.swift`: `libraryDateAutofillV1Enabled` (`library_date_autofill_v1`). `Kuro/Composition/AppComposition.swift`: `makeLibrary(backend:dateAutofillEnabled:)` wires it.
- `KuroTests/IdentityCompositionTests.swift` (`CompositionGraphTests`): the flag wiring test. `KuroTests/DateFillCredentialLeaseTests.swift` (new): the date leg's credential-lease test.
- `Kuro/Views/TastePicksView.swift`: `TastePlanAction.isBarePlan` widened (F2.5); doc comments there and in `Kuro/Views/Home/HomeShelfPolicy.swift`.
- `KuroTests/LibraryTestSupport.swift`: `FakeLibraryBackend.entry(…, sourceMetadata:)` and the fake's `apply` learn the three fields. `KuroTests/FirstRunLaneTests.swift`, `KuroTests/DUpreviewTests.swift`: bare-plan tests.
- `Packages/KuroModules/Sources/KuroSupabase/SupabaseLibraryBackend.swift`: `body(for:)` maps the three fields; the base columns always include `repeat_count,started_raw,finished_raw`; `entry(from:)` always fills those three.
- `Packages/KuroModules/Tests/KuroLibraryTests/PartialDateTests.swift` (new), `LibraryEditV2Tests.swift` (new).
- `Packages/KuroModules/Tests/KuroSupabaseTests/SupabaseLibraryBackendTests.swift`: column constants and the new mapping tests.
- `KuroTests/PostgrestLibraryTransportTests.swift`: column constants.
- `Kuro/Views/TrackingDraft.swift`: `repeatCount`, `startedOn`, `finishedOn` with originals; `edit` and `hasChanges`.
- `Kuro/Views/AddToListSheet.swift`: new `SpreadDatesSection` and `SpreadRepeatSection` (custom precision picker); copy through `KuroLocale`.
- `Kuro/Views/PartialDatePicker.swift` (new): year / month / day wheel picker with "No month" / "No day", plus EN/DE copy.
- `KuroTests/TrackingDraftTests.swift`: date and repeat cases.
- `scripts/load/backend_workload.js`: `loadProfiles`, `TRACKER_GAP_PROFILES`, `selectProfiles`, `profileSchedule`, `loadWorkload`, `qualifyPreflight`, `qualifyVerdicts`, `QUALIFY_MIN`, `exitCodeFor`; `summarize` and `validateConfig` gain optional limits/selection parameters. `WEIGHTS`, `LIMITS`, `chooseKind`, `requestFor` and `validateResponse` stay unchanged for the base kinds.
- `scripts/load/backend_workload.test.js`: base invariance, absolute-rate, qualification and combined-workload tests.
- `scripts/load/backend_runner.test.js`: lane separation (F3.1), GET / anonymous / per-request class / PATCH / multi-step (F3.1b), qualify report and exit code (F3.1c).
- `scripts/load/backend_fixture.js` (+ `backend_fixture.test.js`): `seed-profiles` mode; `refresh` keeps `profileState`; `cleanup` runs each profile's `cleanupCheck` (F3.1c).
- `scripts/load/workloads/tracker-gaps-combined.js` (new, F3.1c): the named combined workload (base 20 rps + one explicit absolute rate per profile; each profile's own task adds its line, as with `bdd_landed.txt`).
- `scripts/load/profiles/` (new folder, created by the first profile; the loader tolerates its absence). Each profile is `<name>.js` plus its own `<name>.test.js`: `status-with-date-fill` (F3.1d), then W2, W4, W5, W6, W9, W10.
- `scripts/load_test_backend.js`: two lanes; `--tracker-gaps=<a,b|all>`, `--workload=<name>`, `--qualify`; GET, anonymous, PATCH and multi-step requests (F3.1b); report `schemaVersion: 2`.
- `supabase/tests/fixtures/library_2000.sql` (new): `pg_temp.load_library_2000(uuid, integer)` and `pg_temp.plan_uses_index(text, text)`.
- `supabase/tests/rls/112_library_2000_fixture.sql` (new): proves both helpers.
- `docs/tracker-gaps-2026-11/foundation/` (new): evidence notes.

---

### Task F1.1: BDD traceability checker (parse + count + gated)

**Files:** create `scripts/quality-gates/check_bdd_traceability.py` and `scripts/quality-gates/test_check_bdd_traceability.py`.

**Interfaces**
- Consumes: `docs/superpowers/specs/*/features/*.feature` (default glob relative to `--root`, default repo root).
- Produces (Python, importable by path):
  - `parse_feature(path: Path) -> list[Scenario]`, where `Scenario(file, line, name, test_tags: list[str], all_tags: set[str], gated: bool, workstream: str)`.
  - `check(root: Path, feature_glob: str) -> list[Finding]`, where `Finding(file, line, scenario, problem)`.
  - `main(argv) -> int` (0 = clean, 1 = findings, 2 = usage). CLI: `check_bdd_traceability.py [--root DIR] [--features GLOB]`.
- Tag grammar (pinned):
  - A tag line is a line whose first non-blank character is `@`.
  - Tokens are split on whitespace, with one exception: a token starting with `@deno:` consumes the rest of the line (the name after `::` may contain spaces).
  - Test-tag prefixes: `@pkg: @swift: @sql: @deno: @ui: @load: @manual:`. Any other `@word:` token is a finding (`unknown test layer`).
  - Plain tags (`@gated`, `@owner-gate`) carry no layer.
  - Pending tags attach to the next `Feature:`, `Rule:`, `Scenario:`, `Scenario Outline:` or `Example:` line. `Examples:` tags are ignored.
  - A scenario inherits the plain tags of its Rule and its Feature. A Rule scope ends at the next `Rule:` or at end of file.
  - `@gated` on the Feature or the Rule: the scenario is skipped for counting and resolution (counted as `gated`, never a "missing"/"unresolved" finding). The tag-shape checks below (`unknown test layer`, `@manual needs @owner-gate`) still apply to gated scenarios.
  - Exactly one test tag per non-gated scenario. Zero → `missing test tag`; two or more → `2 test tags (…)`.
  - `@manual:` without `@owner-gate` on the scenario, its Rule or its Feature → `@manual needs @owner-gate`.
  - Workstream (used by F1.3): the nearest plain tag `@workstream-<ID>` (Scenario, then Rule, then Feature) wins; otherwise the feature file basename up to its first `-` (`W9-lists.feature` → `W9`). The F2 Rule of `W9-lists.feature` carries `@workstream-F2`.
  - Two scenarios with the same name in one feature file → `duplicate scenario name` (tag-shape class; F1.3 keys records by file and scenario name, never by line number, because other lanes append lines).

Steps
- [ ] Write the failing tests in `test_check_bdd_traceability.py` (`class BddTraceabilityParseTests(unittest.TestCase)`). Each test writes a feature file into `tempfile.TemporaryDirectory()` and imports the checker with `importlib.util.spec_from_file_location` (no `sys.path` reliance). Exact assertions:
  - `test_valid_single_tag`: one scenario tagged `@sql:rls/107_x.sql`. `parse_feature` → 1 scenario, `test_tags == ["@sql:rls/107_x.sql"]`.
  - `test_missing_tag`: an untagged scenario → one finding, with `problem == "missing test tag"` and `line` equal to the `Scenario:` line number.
  - `test_two_tags`: `@pkg:A/b @swift:C/d` → `problem == "2 test tags (@pkg:A/b, @swift:C/d)"`.
  - `test_deno_name_with_spaces`: `@deno:supabase/functions/x/handler_test.ts::deletes tags and custom lists` → the test tag equals the whole string.
  - `test_manual_requires_owner_gate`: `@manual:awaits-D-D @owner-gate` → no finding; `@manual:awaits-D-D` alone → `@manual needs @owner-gate`.
  - `test_gated_feature_and_rule_skip`: `@gated` above `Feature:` skips every scenario. `@gated @owner-gate` above a `Rule:` skips only that Rule's scenarios, and the next Rule's untagged scenario is still a finding. A gated scenario tagged `@manual:awaits-D-X` with no `@owner-gate` in scope is still a `@manual needs @owner-gate` finding.
  - `test_unknown_layer`: `@foo:bar` → `unknown test layer @foo:bar`.
  - `test_workstream_and_duplicate_names`: in `W9-x.feature`, a scenario under a Rule tagged `@workstream-F2` has `workstream == "F2"` and a scenario under the next Rule has `"W9"`; a Feature-level `@workstream-W3a` in `W3-y.feature` gives `"W3a"`. Two scenarios named `Same` in one file → one `duplicate scenario name` finding on the second.
- [ ] Run `python3 scripts/quality-gates/test_check_bdd_traceability.py`. Expected FAIL: `FileNotFoundError` / `ModuleNotFoundError` for `check_bdd_traceability.py`.
- [ ] Implement `parse_feature`, the counting rules and `main`. The header comment states the grammar above verbatim. stdlib only (`pathlib`, `re`, `dataclasses`, `argparse`, `subprocess`).
- [ ] Run the tests again. Expected: `OK` (8 tests).
- [ ] Commit: `git add scripts/quality-gates/check_bdd_traceability.py scripts/quality-gates/test_check_bdd_traceability.py`; message `F1: BDD traceability checker parses scenarios and test tags`.

### Task F1.2: Tag resolution, gate wrappers and run_all registration

**Files:** modify `check_bdd_traceability.py` and `test_check_bdd_traceability.py`; create `check_bdd_traceability.sh` and `test_bdd_traceability.sh`; modify `scripts/quality-gates/run_all.sh`.

**Interfaces**
- `resolve(root: Path, tag: str) -> str | None`: returns None when resolved, otherwise the reason. Rules (pinned):
  - `@pkg:Suite/name`: searched in `Packages/KuroModules/Tests/**/*.swift`.
  - `@swift:Suite/name`: searched in `KuroTests/**/*.swift`.
  - In both cases a declaration `struct|class|enum|actor|extension Suite` must exist. Inside its brace-matched body there must be a `func name(` whose preceding attribute window contains `@Test`. The window runs from the previous `func`, `{` or `}` to the `func`, so `@Test("label", .timeLimit(.minutes(1)))`, `@MainActor @Test` and attributes on earlier lines all count. Before brace matching, comments (`//`, `/* */`) and string literals (`"…"`, `"""…"""`, `#"…"#`) are blanked, keeping offsets, so braces inside strings never count.
  - `@ui:Class/name`: searched in `KuroUITests/**/*.swift` (XCTest). `name` must be the full XCTest method name and start with `test`; any other name is a tag-shape finding `@ui name must be the XCTest method (test…)` (no auto-prefixing). Inside `class Class` there must be `func name(`. **W5 note:** the tag is `@ui:GuestBrowsingUITests/testSignedOutLaunchShowsDiscoverNotAuthWall` and requires `func testSignedOutLaunchShowsDiscoverNotAuthWall()`.
  - `@sql:<path>`: `supabase/tests/<path>` must exist as a file.
  - `@deno:<file>::<name>`: `<file>` must exist and contain `Deno.test("<name>"`, `Deno.test('<name>'` or `name: "<name>"` inside a `Deno.test({`.
  - `@load:<profile>`: `node -e` prints `JSON.stringify(Object.keys(require("<root>/scripts/load/backend_workload.js").TRACKER_GAP_PROFILES))`, and the profile must be in that list. Missing `node` → reason `node not available`. A missing export (before F3) → reason `no TRACKER_GAP_PROFILES (F3)`.
  - `@manual:` with `@owner-gate`: always resolved (reported in the summary as `manual (owner gate)`).
- **Landed scope (resolves "WARN until W2 lands, then blocking").** `scripts/quality-gates/bdd_landed.txt` lists feature-file basenames, one per line (`#` comments allowed; the file may be absent = empty). Tag-shape findings (`missing test tag`, `N test tags`, `unknown test layer`, `@manual needs @owner-gate`, `@ui name must be…`) count for every feature file. Resolution findings (`unresolved`) count only for listed features; for the others they are printed as `pending (not landed)` and do not change the exit code. CLI flag `--landed FILE` (default `scripts/quality-gates/bdd_landed.txt` under `--root`). So the gate can be blocking from W2 on without failing on lanes whose tests do not exist yet.
- Output: one line per finding, `<relative file>:<line>: <scenario name>: <problem>`, then `Summary: <n> scenarios, <g> gated, <m> manual, <r> resolved, <u> unresolved, <p> pending (not landed), <t> tag errors`.
- Gate wrappers:
  - `check_bdd_traceability.sh`: `set -uo pipefail`, then runs `python3 "$SCRIPT_DIR/check_bdd_traceability.py" "$@"` and exits with its code (no arguments = the gate; F1.3's `--accepted <WS>` and `--record-template <WS>` pass through, so `check_bdd_traceability.sh --accepted W9` and `python3 …/check_bdd_traceability.py --accepted W9` are the same command).
  - `test_bdd_traceability.sh`: runs `python3 "$SCRIPT_DIR/test_check_bdd_traceability.py"`.
- `run_all.sh` `GATES` additions, placed after `navigation`:
  - `"bdd-selftest:test_bdd_traceability.sh:1"`: the checker's own unit tests; blocking.
  - `"bdd-traceability:check_bdd_traceability.sh:0"`: Gherkin scenario → test map (tracker gaps). WARN until W2 lands (spec §4). W2's final task creates `bdd_landed.txt` with `W2-export.feature` and flips this flag to `1`; every later workstream's final task appends its own feature file (see `00-program.md` → Shared files and merge order).

Steps
- [ ] Add failing tests (`class BddTraceabilityResolveTests`). Each builds a mini tree under the temp root:
  - `test_swift_testing_resolution`: `KuroTests/A.swift` declares a suite in two parts. The first part is `@MainActor\n@Suite("x", .timeLimit(.minutes(1)))\nstruct LibraryTagsStoreTests {`, containing `@Test("Filter {by} tag") func filterByTagShowsOnlyTaggedEntries() async {}` (a brace inside the label). The second part is an `extension LibraryTagsStoreTests { @Test\n func second() {} }`. Both `@swift:` tags resolve. `@swift:LibraryTagsStoreTests/missing` → reason `no @Test func missing in LibraryTagsStoreTests`. A `func helper()` without `@Test` does not resolve.
  - `test_pkg_resolution_scope`: the same suite placed under `KuroTests/` does not resolve `@pkg:` (`suite … not found in Packages/KuroModules/Tests`).
  - `test_ui_resolution_xctest`: `final class GuestBrowsingUITests: XCTestCase { func testSignedOutLaunchShowsDiscoverNotAuthWall() {} }` resolves `@ui:GuestBrowsingUITests/testSignedOutLaunchShowsDiscoverNotAuthWall`. The un-prefixed tag `@ui:GuestBrowsingUITests/signedOutLaunchShowsDiscoverNotAuthWall` → tag-shape finding `@ui name must be the XCTest method (test…)`.
  - `test_landed_scope`: two feature files, each with one unresolved `@swift:` tag. With `bdd_landed.txt` listing only the first → exit 1, one `unresolved` finding for the first file and one `pending (not landed)` line for the second. With an empty/absent list → exit 0 and `2 pending (not landed)`. A `missing test tag` in the unlisted file → exit 1 (tag shape counts everywhere).
  - `test_sql_and_deno_resolution`: `supabase/tests/rls/107_library_tags.sql` resolves. `Deno.test("deletes tags and custom lists", …)` in `supabase/functions/x/handler_test.ts` resolves the spaced name. A file that is missing, or that holds a different name, gives the matching reasons.
  - `test_load_resolution`: a temp `scripts/load/backend_workload.js` exporting `TRACKER_GAP_PROFILES = { "collection-with-tags-and-lists": {} }` resolves; a different profile name gives `unknown load profile`. The test is skipped with a reason when `shutil.which("node")` is None.
  - `test_cli_exit_codes`: a clean tree → exit 0 and output containing `0 unresolved`; a tree with one unresolved tag → exit 1, and the output line starts with `docs/superpowers/specs/s/features/W.feature:3:`.
- [ ] Run them. Expected FAIL: `AttributeError: module has no attribute 'resolve'`.
- [ ] Implement `resolve` and the summary; create both wrappers (`chmod +x`); register both gates.
- [ ] Run `python3 scripts/quality-gates/test_check_bdd_traceability.py`. Expected `OK` (15 tests). Then run `bash scripts/quality-gates/check_bdd_traceability.sh; echo "exit=$?"` on the real tree (no `bdd_landed.txt` yet). Expected: `0 tag errors`, `12 gated` (W1 4, W3 Rule 1, W7 3, W8 3, W10 Rule 1), every other scenario `pending (not landed)`, `exit=0`. Then `python3 scripts/quality-gates/check_bdd_traceability.py --landed <(ls docs/superpowers/specs/2026-11-09-tracker-gaps/features/ | grep feature); echo "exit=$?"` → the unresolved findings for the not-yet-written tests and `exit=1`. Record both summary lines in the evidence note as the baseline.
- [ ] Run `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 SKIP_RAILS_AUDIT=1 KURO_ALLOW_PARTIAL_VERIFY=1 scripts/quality-gates/run_all.sh | tail -30`. Expected rows: `bdd-selftest PASS` and `bdd-traceability WARN`. No other row changes.
- [ ] Commit: `git add scripts/quality-gates/check_bdd_traceability.py scripts/quality-gates/test_check_bdd_traceability.py scripts/quality-gates/check_bdd_traceability.sh scripts/quality-gates/test_bdd_traceability.sh scripts/quality-gates/run_all.sh`; message `F1: resolve BDD tags to tests; register self-test (blocking) and traceability (WARN) gates`. (`bdd_landed.txt` is created by W2's final task, not here.)

### Task F1.3: "Accepted" needs an execution record (`--accepted <workstream>`)

**Why:** the gate proves a scenario's test *exists* ("resolved"). A workstream is *accepted* only when every in-scope scenario *ran and passed* at the commit being shipped, with evidence of the right kind (program decision 6). The gate entries of F1.2 are unchanged; this is a separate mode, run by each workstream's final task and by the program release checklist (lead propagates to `00-program.md`).

**Files:** modify `scripts/quality-gates/check_bdd_traceability.py` and `scripts/quality-gates/test_check_bdd_traceability.py`; create `scripts/quality-gates/testdata/bdd_acceptance_logs/` (captured real log lines, one file per layer).

**Interfaces**
- CLI: `check_bdd_traceability.py --accepted <WS> [--root DIR] [--features GLOB]` and `check_bdd_traceability.py --record-template <WS>`. Exit 0 accepted, 1 not accepted, 2 usage (unknown option, empty `<WS>`, both modes at once).
- Python: `accepted(root: Path, workstream: str, feature_glob: str) -> tuple[list[Finding], AcceptanceSummary]`, `record_template(root: Path, workstream: str, feature_glob: str) -> dict`, `git_head(root) -> str`.
- Record path: `docs/tracker-gaps-2026-11/acceptance/<WS>.json`. Schema (`schemaVersion: 1`, all keys required unless marked optional):
```json
{
  "schemaVersion": 1,
  "workstream": "F2",
  "testedCommit": "<40 hex: the commit the runs below executed on>",
  "recordedAt": "<ISO-8601 UTC>",
  "runs": [{
    "id": "pkg-1",
    "layer": "pkg | swift | sql | deno | ui | load | manual",
    "command": "<exact command line that was run>",
    "context": {
      "kind": "local | simulator | local-db | live-read-only | load-qualification | owner",
      "simulator": "<UUID; swift and ui only>",
      "loadReport": "<repo path of the runner report; load only>",
      "loadRunKey": "<report.runKey; load only>",
      "cleanupReport": "<repo path of the fixture cleanup output; load only>",
      "owner": "<who accepted; manual only>",
      "evidence": "<repo path; manual only>"
    },
    "exitCode": 0,
    "log": "docs/tracker-gaps-2026-11/acceptance/logs/<WS>-<id>.txt"
  }],
  "scenarios": [{
    "feature": "W9-lists.feature",
    "scenario": "Editing repeat count and dates",
    "tag": "@pkg:LibraryEditV2Tests/repeatCountAndDatesTravelThroughLibraryEdit",
    "result": "pass | fail | blocked | insufficient",
    "run": "pkg-1",
    "note": "<optional>"
  }],
  "unresolvedGates": ["<owner decision or pending run, in words>"]
}
```
- Acceptance rules (pinned; each violation is one finding line `<WS>: <feature>: <scenario>: <problem>` or `<WS>: record: <problem>`):
  1. The record exists, parses, has `schemaVersion == 1`, `workstream == <WS>` and a 40-hex `testedCommit`.
  2. Commit: `testedCommit == git rev-parse HEAD`, **or** `git merge-base --is-ancestor <testedCommit> HEAD` and `git diff --name-only <testedCommit> HEAD` lists only paths under `docs/tracker-gaps-2026-11/acceptance/`. In both cases `git status --porcelain` shows nothing outside that folder. Otherwise `record is for <sha>; HEAD <sha> changed outside acceptance records` / `uncommitted changes outside acceptance records`.
  3. In scope: every non-gated scenario (all feature files) whose workstream (F1.1 rule) equals `<WS>`. Gated scenarios of `<WS>` are printed as `gated (excluded)`; if any exist, `unresolvedGates` must be non-empty (`gated scenarios but no unresolved gate named`).
  4. Each in-scope scenario has exactly one entry keyed by (`feature`, `scenario`): missing → `no result`; two → `2 results`; an entry naming a scenario that no longer exists → `stale record entry`. `tag` must equal the scenario's current test tag (`tag changed since record`). `result` must be `pass`; `fail` / `blocked` / `insufficient` → `not accepted: <result>`; any other value → `invalid result <value>`.
  5. Evidence for each `pass`: the `run` id exists, its `layer` equals the tag's layer, `exitCode == 0`, and `log` exists in the repo. Per layer:
     - `pkg`, `swift`, `ui`, `deno`: the log has a **passed line** for the test (the name is the part after `/`, or after `::`); a name that appears only on a skipped, disabled or failed line does not count (`test did not pass in log`). Patterns, pinned against real captured logs: `pkg` (`swift test`, Swift Testing) `Test <name>\(\) passed`; `swift` (`xcodebuild`, Swift Testing) `Test case '<Suite>/<name>\(\)' passed` or `Test <name>\(\) passed`; `ui` (XCTest) `Test Case '-\[\S+ <Class> <name>\]' passed`; `deno` `^<name> \.\.\. ok`. `swift`/`ui` also need `context.simulator`.
     - `sql`: `context.kind` is `local-db` (command contains `run_local_db_tests.sh`) or `live-read-only`; the log has a line matching `^PASS\s+<basename>\s+\d+ assertions, 0 blocked markers, \d+ findings$` (the harness's per-file line, `scripts/db/run_local_db_tests.sh` ~line 322). `BLOCKED <basename>`, `FAIL  <basename>`, a `scope(s) BLOCKED` suffix, a non-zero blocked-marker count or no line → `SQL test did not run and pass`. File existence never counts.
     - `load`: `context.kind == "load-qualification"`; `loadReport` exists and has `mode == "qualify"`, `runKey == context.loadRunKey`, `preflight.passed == true` and `lanes.profiles.profiles[<profile>].verdict == "pass"`; `cleanupReport` exists and every cleanup entry for an account with state for that profile has `profileData[<profile>] == "absent"` (F3.1c). Otherwise `load evidence is not a passing qualification run` (wiring report, failed preflight, `insufficient`, missing cleanup).
     - `manual`: `context.kind == "owner"`, non-empty `owner`, `evidence` exists.
  6. Summary: `Accepted <WS>: <n>/<n> scenarios pass at <sha>` (exit 0) or `NOT accepted <WS>: <p>/<n> pass, <f> findings` (exit 1), then the `gated (excluded)` lines and `unresolvedGates`.
- `--record-template <WS>` prints a schema-valid skeleton: `testedCommit` = HEAD, `runs: []`, every in-scope scenario with its current tag, `result: "blocked"`, `run: null`, and one `unresolvedGates` placeholder per gated Rule. It never writes a file.

Steps
- [ ] Add failing tests (`class BddAcceptanceTests`). Each builds a temp tree, runs `git init -q`, commits with a fixed author (`-c user.name=t -c user.email=t@example.invalid`), and is skipped with a reason when `shutil.which("git")` is None:
  - `test_accepted_scope_and_happy_path`: `W9-x.feature` with one Rule tagged `@workstream-F2` (one `@pkg:` scenario) and one plain Rule (one `@swift:` scenario); `--accepted W9` with a record that passes only the `@swift:` scenario, a run log containing its test name and `testedCommit == HEAD` → exit 0, `Accepted W9: 1/1`; the F2 scenario is not required. Removing the entry → exit 1 with `no result`.
  - `test_record_commit_rules`: record for the previous commit while HEAD changed `KuroTests/A.swift` → exit 1 (`changed outside acceptance records`); record for the previous commit while HEAD only added `docs/tracker-gaps-2026-11/acceptance/W9.json` → exit 0; an untracked `Kuro/x.swift` → exit 1 (`uncommitted changes`).
  - `test_sql_requires_passing_run`: scenario `@sql:rls/107_x.sql` (file present). No log → exit 1. Log `BLOCKED 107_x.sql …` → 1. Log `PASS  107_x.sql  12 assertions, 1 blocked markers, 0 findings` → 1. Log `PASS  107_x.sql  12 assertions, 0 blocked markers, 0 findings, 1 scope(s) BLOCKED` → 1. Log `PASS  107_x.sql  12 assertions, 0 blocked markers, 0 findings` → 0.
  - `test_load_requires_qualification_report`: report `mode: "wiring"` → 1; `mode: "qualify"` with the profile verdict `insufficient` → 1; `preflight.passed: false` → 1; `runKey` mismatch → 1; cleanup report with `profileData.<profile> == "present"` → 1; qualify + pass + absent → 0.
  - `test_results_and_tags`: `blocked`, `fail`, `insufficient` → `not accepted: <result>`; `"ok"` → `invalid result ok`; a `pkg` run whose log names the test only on a `skipped` line (exit code 0) → `test did not pass in log`; record tag `@swift:A/old` while the scenario now says `@swift:A/new` → `tag changed since record`; an entry for a removed scenario → `stale record entry`.
  - `test_gated_and_manual`: a gated Rule's scenarios are listed `gated (excluded)` and not required; with `unresolvedGates: []` → `gated scenarios but no unresolved gate named`. A `@manual:awaits-D-D @owner-gate` scenario passes only with a `manual` run whose context is `owner` with `owner` and an existing `evidence` path.
  - `test_record_template`: `--record-template W9` prints JSON with HEAD, every in-scope scenario `blocked`; feeding it back as the record → `--accepted W9` exit 1 with every scenario `not accepted: blocked`.
- [ ] Run `python3 scripts/quality-gates/test_check_bdd_traceability.py`. Expected FAIL: `error: unrecognized arguments: --accepted` (exit 2) / `AttributeError: module has no attribute 'accepted'`.
- [ ] Capture one real passing log line per layer from existing tests (e.g. `swift test --filter SupabaseLibraryBackendTests`, an existing `KuroTests` suite on the owned simulator, an existing `KuroUITests` method, `deno test --no-prompt supabase/functions/concierge-apply/`) into `scripts/quality-gates/testdata/bdd_acceptance_logs/` and use them as the pattern fixtures of `BddAcceptanceTests` (so the patterns match real tool output, not a guess).
- [ ] Implement `accepted`, `record_template`, the git helpers (`subprocess.run(["git", "-C", root, …], check=False)`) and the two CLI modes; extend the header comment with the schema and rules above.
- [ ] Run again. Expected `OK (22 tests)` (or the 7 acceptance tests reported as skipped without `git`). Run `bash scripts/quality-gates/check_bdd_traceability.sh` on the real tree: summary unchanged from F1.2 (the new mode is not part of the gate).
- [ ] Commit: `git add scripts/quality-gates/check_bdd_traceability.py scripts/quality-gates/test_check_bdd_traceability.py scripts/quality-gates/testdata/bdd_acceptance_logs/`; message `F1: accepted mode requires an execution record for HEAD (SQL from a passing DB run, load from a qualification run)`.

### Task F2.1: `PartialDate`

**Files:** create `Packages/KuroModules/Sources/KuroLibrary/PartialDate.swift` and `Packages/KuroModules/Tests/KuroLibraryTests/PartialDateTests.swift`.

**Interfaces (Produces, binding):**
```swift
public struct PartialDate: Equatable, Hashable, Sendable, Codable, Comparable {
    public enum Precision: Sendable, Equatable { case year, month, day }
    public init?(raw: String)                       // see accepted forms below
    public init?(year: Int, month: Int? = nil, day: Int? = nil)
    public static func day(of date: Date, in calendar: Calendar) -> PartialDate   // "today" for the fill rule
    public let year: Int
    public let month: Int?                          // nil for .year
    public let day: Int?                            // nil for .year/.month
    public var precision: Precision { get }
    public var raw: String { get }                  // canonical: "2024", "2024-05", "2024-05-07"
    public var zeroPadded: String { get }           // MAL export form: "2024-00-00", "2024-05-00", "2024-05-07" (for W2)
    // Codable: single string value `raw`; decoding uses init?(raw:) and throws DecodingError.dataCorrupted on nil.
    // Comparable: (year, month ?? 0, day ?? 0) lexicographic.
}
```
- Accepted `raw` forms, after trimming whitespace: `YYYY`, `YYYY-MM`, `YYYY-MM-DD`, `YYYY-00-00` (→ year), `YYYY-MM-00` (→ month).
- Rejected: `0000-00-00`, empty, year outside 1…9999, month outside 1…12 (when present and not zero-padded), a day that does not exist in its month (Gregorian leap rule as in `MALExportParser.date`), `YYYY-00-DD` with a day but no month, any other separator or any extra characters.
- `init(year:month:day:)` applies the same rules (day requires month).

Steps
- [ ] Write the failing tests (`struct PartialDateTests`, `@Suite("PartialDate: stored forms, validation, precision")`):
  - `@Test func rejectsImpossibleDatesAndKeepsPrecision()` (traced). Assertions:
    - `#expect(PartialDate(raw: "2024-02-30") == nil)`
    - `#expect(PartialDate(raw: "2023-02-29") == nil)`
    - `#expect(PartialDate(raw: "2024-02-29")?.precision == .day)`
    - `#expect(PartialDate(raw: "2024")?.precision == .year)`
    - `#expect(PartialDate(raw: "2024")?.raw == "2024")`
    - `#expect(PartialDate(raw: "2024-02")?.precision == .month)`
    - `#expect(PartialDate(raw: "2024-02")?.raw == "2024-02")`
    - `#expect(PartialDate(raw: "2024-13") == nil)`
    - `#expect(PartialDate(raw: "0000-00-00") == nil)`
    - `#expect(PartialDate(raw: "2024-00-15") == nil)`
    - `#expect(PartialDate(raw: "24-02-01") == nil)`
    - `#expect(PartialDate(raw: "2024/02/01") == nil)`
  - `@Test func acceptsEveryStoredImportForm()`: `"2024-00-00"` → `.year`, raw `"2024"`. `"2024-05-00"` → `.month`, raw `"2024-05"`. `" 2024-05-07 "` → `.day`. `"2024-05"` → `zeroPadded == "2024-05-00"`.
  - `@Test func equalityIsByValueNotSpelling()`: `PartialDate(raw: "2024-00-00") == PartialDate(raw: "2024")`, and `PartialDate(raw: "2024-05-00") == PartialDate(raw: "2024-05")`.
  - `@Test func codableRoundTripsRawAndRejectsGarbage()`: JSON-encoding `["d": PartialDate(raw:"2024-05")!]` gives `{"d":"2024-05"}`; decoding `{"d":"2024-02-30"}` throws.
  - `@Test func dayOfDateUsesTheGivenCalendar()`: in a calendar with `TimeZone(identifier: "Europe/Berlin")`, `PartialDate.day(of: 2026-03-01T23:30:00Z)` has raw `"2026-03-02"`; in UTC it is `"2026-03-01"`.
- [ ] Run `cd Packages/KuroModules && swift test --filter PartialDateTests`. Expected FAIL: `cannot find 'PartialDate' in scope`.
- [ ] Implement `PartialDate.swift` (Foundation only; no `DateFormatter`; parse by UTF-8 bytes like `MALExportParser.date`).
- [ ] Run again. Expected: 5 tests pass.
- [ ] Commit: `git add Packages/KuroModules/Sources/KuroLibrary/PartialDate.swift Packages/KuroModules/Tests/KuroLibraryTests/PartialDateTests.swift`; message `F2: PartialDate accepts every stored import form, validates and keeps precision`.

### Task F2.2: `LibraryEdit` / `LibraryEntry` v2 and the PATCH mapping

**Files:** modify `LibraryValues.swift`, `LibraryContracts.swift`, `SupabaseLibraryBackend.swift`, `SupabaseLibraryBackendTests.swift` and `KuroTests/PostgrestLibraryTransportTests.swift`; create `Packages/KuroModules/Tests/KuroLibraryTests/LibraryEditV2Tests.swift`.

**Migration verdict (record in `docs/tracker-gaps-2026-11/foundation/F2-no-migration.md`, quoting each source):**
1. The columns exist live: `repeat_count integer not null default 0`, `started_raw text` and `finished_raw text` on both list tables (`supabase/prepared-migrations/20261007040000_series_home_foundation_v1.sql` lines 21–25 and 36–40, applied 2026-10-08).
2. The owner may write them through PATCH: the only policy is `"Users can manage their own lists" … for all to authenticated using (auth.uid()::text = user_id) with check (…)` (`supabase/migrations/20260807000000_baseline_capture_v1.sql:2201`). `grep -rniE "grant update *\(|revoke update" supabase/migrations supabase/prepared-migrations` finds no column grant on the list tables, and there is no CHECK on these three columns.
3. The list triggers do not block it: `list_account_write_lock` and `list_entry_revision_fence` only lock and advance `server_revision`; `series_unit_owner` fires only on `unit_id`/media id.
4. The durable outbox and `apply_progress_mutations_v1` carry only position and status, so dates always take the PATCH leg. When a progress intent is waiting, the drain's `rebaseUnsent` (in `LibraryProgress.swift`, inside `withMutationReservation`) adopts the revision the PATCH advanced, so the PATCH leg does not create a fence conflict.

Conclusion: no `20261110090000_library_edit_v2.sql`. The value range of `repeat_count` (0…999) is enforced on the client (`LibraryError.invalidValue(field: "repeatCount")`). Owner follow-up (optional, not in this plan): a server CHECK `repeat_count between 0 and 999` if direct writers other than the app appear.

**Interfaces (Produces, binding names):**
```swift
// LibraryEdit
public var repeatCount: FieldChange<Int>          // default .unchanged; .clear is invalid (NOT NULL); 0...999
public var startedOn: FieldChange<PartialDate>    // default .unchanged; .clear → started_raw = null
public var finishedOn: FieldChange<PartialDate>   // default .unchanged
public init(status:progress:rating:notes:verdict:repeatCount:startedOn:finishedOn:)   // new params last, all defaulted
// LibraryEntry (computed, read-only)
public var repeatCount: Int        { sourceMetadata?.repeatCount ?? 0 }
public var startedOn: PartialDate? { sourceMetadata?.startedRaw.flatMap(PartialDate.init(raw:)) }
public var finishedOn: PartialDate?{ sourceMetadata?.finishedRaw.flatMap(PartialDate.init(raw:)) }
public var datesKnown: Bool        { sourceMetadata != nil }   // nil = server value unknown (cached/provisional row)
```
- Helpers learn the fields:
  - `isEmpty`, `validationError`, `patchBodyOmittingProgress` (now includes `repeatCount`, `startedOn` and `finishedOn`), `restoring(_:)` and `reverting(_:to:)`.
    - `restoring` sets the three fields only when `entry.datesKnown`; otherwise `.unchanged`.
    - `reverting` compares `repeatCount` and the parsed dates; a nil previous date → `.clear`.
  - `applying(_:at:)` writes `startedRaw = date.raw` / `finishedRaw` / `repeatCount` into `sourceMetadata`. It creates `LibrarySourceMetadata()` **only when the edit names one of the three fields**. An edit without them (notes, status) leaves a nil `sourceMetadata` nil, so an optimistic edit on a cached row never flips `datesKnown` to true.
  - `withEditedFields(of:from:)` copies the three back from `prior`.
- `LibraryChange.isProgressOnly` also requires `previous.repeatCount == current.repeatCount`, `previous.startedOn == current.startedOn` and `previous.finishedOn == current.finishedOn`.
- `SupabaseLibraryBackend.body(for:kind:)`:
  - `repeatCount .set(n)` → `"repeat_count": .int(n)`.
  - `startedOn .set(d)` → `"started_raw": .string(d.raw)`; `.clear` → `"started_raw": .null`. The same for `finished_raw`.
- `ListTable.columns`: the base string becomes `id,user_id,<media>_id,list_type,progress,rating,notes,verdict,created_at,updated_at,repeat_count,started_raw,finished_raw`. The fence suffix drops those three (no duplicates).
- `entry(from:)`: always builds `sourceMetadata`. With the fence off, only `repeatCount`, `startedRaw` and `finishedRaw` are set; everything else stays nil.

Steps
- [ ] Write the failing traced test in `LibraryEditV2Tests.swift`: `@MainActor @Suite("Library contract v2: repeat count and dates") struct LibraryEditV2Tests`, with `@Test func repeatCountAndDatesTravelThroughLibraryEdit() async`. It uses `ControlledBackend` (Tests/KuroLibraryTests/Support):
  1. Seed the entry `anime 1` (rowId 7, `.current`, `sourceMetadata: LibrarySourceMetadata(repeatCount: 0)`, so the dates are known and empty).
  2. `store.apply(LibraryEdit(repeatCount: .set(2), startedOn: .set(PartialDate(raw:"2024-05")!), finishedOn: .set(PartialDate(raw:"2024-07-14")!)), to: key)`.
  3. Expect the backend request `.edit(edit, createIfMissing: nil, baseRevision: nil)` with exactly these three fields set.
  4. Answer with a row whose metadata is `repeatCount 2`, `startedRaw "2024-05"`, `finishedRaw "2024-07-14"`.
  5. `#expect(store.entry(for: key)?.repeatCount == 2)`
  6. `#expect(store.entry(for: key)?.startedOn?.precision == .month)`
  7. `#expect(store.entry(for: key)?.finishedOn?.raw == "2024-07-14")`
  8. The optimistic projection (read before the answer) already shows `startedOn?.raw == "2024-05"`.
- [ ] Untraced, same suite:
  - `@Test func validationRejectsNegativeOrHugeRepeatCountAndClear()`: `.set(-1)`, `.set(1000)` and `.clear` → `.failed(.invalidValue(field: "repeatCount"))`, with no backend call.
  - `@Test func dateOnlyChangeIsNotProgressOnly()`: a `LibraryChange` whose previous and current differ only in `startedOn` → `isProgressOnly == false`.
  - `@Test func revertingRestoresEmptyDatesWithClear()`: `reverting(current(started 2024), to: previous(no date, datesKnown))` → `startedOn == .clear`, `status == .unchanged`.
- [ ] Add failing tests to `SupabaseLibraryBackendTests.swift` (`@Suite("Library contract v2 mapping") struct SupabaseLibraryBackendV2Tests`):
  - `bodyMapsRepeatCountAndDates()`: the body equals `["repeat_count": .int(2), "started_raw": .string("2024-05"), "finished_raw": .null]` for `.set(2)`, `.set(2024-05)`, `.clear`.
  - `fenceOffSelectAlwaysCarriesDateColumns()`: the select `columns` equals the new base string for anime and manga.
  - `notesOnlyPatchKeepsDatesWithFenceOff()`: the PATCH answers a row with `started_raw "2024-00-00"`, and the entry has `startedOn == PartialDate(raw:"2024")`.
  - `fenceOnStatusEditSendsDatesInSidePatch()`: with the fence on, `LibraryEdit(status:.set(.current), startedOn:.set(2026-03-02))` → the fence mutation carries status, and the following PATCH body is exactly `["started_raw": .string("2026-03-02")]`.
  - Update the `animeColumns` / `mangaColumns` constants, and the `common` set at line 505, to the new strings.
- [ ] Update `KuroTests/PostgrestLibraryTransportTests.swift` lines 23–24 to the new column strings (the test is otherwise unchanged). Then run `grep -rn "verdict,created_at,updated_at\"\|select=id,user_id" KuroTests Packages/KuroModules/Tests`, and update every remaining literal that pins the fence-off column list, including any `ListTablesScript` match on `select`.
- [ ] Run `cd Packages/KuroModules && swift test --filter "LibraryEditV2Tests|SupabaseLibraryBackendV2Tests"`. Expected FAIL: `extra argument 'repeatCount' in call` / `value of type 'LibraryEntry' has no member 'startedOn'`.
- [ ] Implement the interfaces above.
- [ ] Run `swift test` (whole package). Expected: all pass, including the existing `SupabaseLibraryBackendTests` with the updated constants and `SeriesHomeFoundationTests`.
- [ ] Commit: `git add Packages/KuroModules/Sources/KuroLibrary/LibraryValues.swift Packages/KuroModules/Sources/KuroLibrary/LibraryContracts.swift Packages/KuroModules/Sources/KuroSupabase/SupabaseLibraryBackend.swift Packages/KuroModules/Tests/KuroLibraryTests/LibraryEditV2Tests.swift Packages/KuroModules/Tests/KuroSupabaseTests/SupabaseLibraryBackendTests.swift KuroTests/PostgrestLibraryTransportTests.swift docs/tracker-gaps-2026-11/foundation/F2-no-migration.md`; message `F2: repeat count and dates travel through LibraryEdit on the existing PATCH path`.

### Task F2.3: Status changes fill empty dates (with Undo), safely

**Files:** modify `LibraryValues.swift`, `LibraryStore.swift`, `LibraryEditV2Tests.swift`, `Kuro/Services/FeatureFlags.swift`, `Kuro/Composition/AppComposition.swift` and `KuroTests/IdentityCompositionTests.swift` (`struct CompositionGraphTests`); create `KuroTests/DateFillCredentialLeaseTests.swift`.

**Interfaces**
```swift
// LibraryValues.swift
extension LibraryEdit {
    /// The edit plus auto-filled dates: status → .current fills startedOn, → .completed fills finishedOn,
    /// only when the status actually changes (current?.status != new, or creating), the edit leaves that
    /// date `.unchanged`, and the date is empty: creating (`current == nil`), or `current.datesKnown` and
    /// the raw is nil or blank. Never when the raw exists but does not parse. `.repeating` fills nothing.
    package func fillingEmptyDates(current: LibraryEntry?, creating: Bool, today: PartialDate)
        -> (edit: LibraryEdit, autoFilled: Bool)
}
// LibraryStore.swift (new defaulted parameters; every store not built by AppComposition stays off)
public init(backend:sinks:now:calendar: Calendar = .autoupdatingCurrent,
            dateAutofillEnabled: @escaping @MainActor () -> Bool = { false })
public func apply(_ edit: LibraryEdit, to key: MediaKey, createIfMissing: ListStatus? = nil) async -> LibraryOutcome
//   = apply(edit, to:key, createIfMissing:, fillsEmptyDates: true)
func apply(_ edit: LibraryEdit, to key: MediaKey, createIfMissing: ListStatus?, fillsEmptyDates: Bool) async -> LibraryOutcome
//   fills only when `fillsEmptyDates && dateAutofillEnabled()`, evaluated once at entry, before the optimistic
//   projection and before any backend call (release switch, program decision 1).
// undo(_:) calls the internal overload with fillsEmptyDates: false.
// FeatureFlags.swift
var libraryDateAutofillV1Enabled: Bool { evaluate("library_date_autofill_v1") }   // absent row = off (read `evaluate` first and confirm)
// AppComposition.swift
static func makeLibrary(backend: any LibraryBackend,
                        dateAutofillEnabled: @escaping @MainActor () -> Bool = { false }) -> (store: LibraryStore, sinks: LibraryChangeSinks)
//   makeGraph (call site ~line 204): makeLibrary(backend: libraryBackend, dateAutofillEnabled: { [flags] in flags.libraryDateAutofillV1Enabled })
```
- Release switch: `library_date_autofill_v1` stays at 0 % (no `feature_flags` row is needed for 0 %) until D-H allows it. While off, a status change sends exactly what it sends today; manual date and repeat edits in the editor are a normal edit (one write) and are allowed. With the fence on, the fill is a second request (the PATCH leg), so it is backend traffic: profile `status-with-date-fill` (Task F3.1d).
- Durable branch rule (pinned): when `autoFilled == true` and the caller's own `edit.patchBodyOmittingProgress.isEmpty`, a failed PATCH leg does not turn the outcome into `.failed`. The durable outcome is returned and the projection drops the auto-filled date (its pending mutation settles `.keepBase`). In every other case the existing behaviour stays (`.retryable("Progress is saved on this device; other fields could not be saved: …")`).
- **Credential lease for the date leg (program decision 2).** The auto-filled PATCH leg is a new private request, and `LibraryStore` → `PostgrestLibraryTransport` take no credential lease today (05-guest.md Review Focus 6). F2 runs that leg (only the leg F2 adds; existing edits are unchanged) inside the account's lease: `LibraryStore.init` gains `credentialLease: (any LibraryCredentialLease)? = nil` with `public protocol LibraryCredentialLease: Sendable { @MainActor func withLease<T: Sendable>(for account: AccountContext, _ operation: @escaping @MainActor @Sendable () async throws -> T) async throws -> T }` (KuroLibrary); the app's composition passes an adapter over `AccountSessionCoordinator.withCredentialLease(for:_:)` (`Packages/KuroModules/Sources/KuroCore/AccountSession.swift:120`, pattern `Kuro/Home/HomeStore.swift:99`). A `CancellationError` from the lease is the best-effort failure above (status stays applied, date stays empty). Pinned by `DateFillCredentialLeaseTests/preDispatchSwitchSendsNoDateLegAsB`.
- `save(_:status:)` (insert-ignore) is unchanged: one-tap Plan and the toggle never write dates.
- No other status path exists to cover. `advanceProgress` intents carry no status (`LibraryProgress.swift` `advanceProgress` builds `ProgressIntent` without `status`). `_apply_progress_mutations_for_user` (`20261008100000`) has no auto-complete, so a +1 at the last unit never changes status and needs no fill. If a future change adds auto-complete, it must call the same rule.
- Imports (server RPCs) never pass through this rule.

Steps
- [ ] Write the failing traced test `@Test func statusChangeFillsEmptyDatesWithUndo() async`. The store uses `now: { 2026-03-01T23:30:00Z }`, a calendar with `Europe/Berlin` and `dateAutofillEnabled: { true }` (every fill test below builds its store with the gate on; only `flagOffSendsNoRequest` leaves it off); the entry is `.planning` with `sourceMetadata(repeatCount: 0)` and no dates; the fence is off (`ControlledBackend`).
  1. `let outcome = await store.apply(LibraryEdit(status: .set(.current)), to: key)`.
  2. The backend request edit has `startedOn == .set(PartialDate(raw: "2026-03-02")!)` and `finishedOn == .unchanged`.
  3. Answer with the row (status WATCHING, `started_raw "2026-03-02"`). `#expect(store.entry(for: key)?.startedOn?.raw == "2026-03-02")`.
  4. `let change = try #require(outcome.change)`, then `await store.undo(change)`. The backend request is `LibraryEdit(status: .set(.planning), startedOn: .clear)`.
  5. Answer the row back. `#expect(store.entry(for: key)?.status == .planning)`, `#expect(store.entry(for: key)?.startedOn == nil)`.
- [ ] Untraced. These two groups are red for different reasons (program decision 7, no manufactured red):
  - **Missing behaviour (fail on their assertions today):** `completedFillsFinishNotStart`, `fillUsesInjectedCalendarNearMidnight`, `creatingAsWatchingFillsStart`.
  - **Guards (pin what the fill must never do; today they are red only because the `calendar:` / `dateAutofillEnabled:` init parameters do not exist, and their behavioural assertions already hold, which is their point):** `undoNeverFillsDates`, `unknownOrUnparseableDatesAreNeverFilled`, `offlineDurableStatusChangeStillAppliesWithoutDateFill`, `explicitDateBeatsFill`, `flagOffSendsNoRequest`.
  - `@Test func completedFillsFinishNotStart()`: `.current` (no dates) → `.completed` fills only `finishedOn == 2026-03-02`.
  - `@Test func undoNeverFillsDates()`: an entry `.current` with no start date → `.completed` (fills finish) → `undo`. The request is `status .set(.current)`, `finishedOn .clear` and `startedOn .unchanged`.
  - `@Test func fillUsesInjectedCalendarNearMidnight()`: the same instant in a UTC calendar fills `"2026-03-01"`.
  - `@Test func unknownOrUnparseableDatesAreNeverFilled()`: three cases send `startedOn == .unchanged`:
    - an entry with `sourceMetadata == nil` (rowId 7);
    - an entry with `startedRaw "not-a-date"`;
    - an entry already `.current` re-saved as `.current`;
    - a cached row (`sourceMetadata == nil`) that first receives an optimistic notes-only edit and then `.current`. The notes edit leaves `datesKnown == false`, so nothing is filled.
  - `@Test func creatingAsWatchingFillsStart()`: `apply(LibraryEdit(status:.set(.current)), to: key, createIfMissing: .current)` on an untracked title → `startedOn == .set(2026-03-02)`.
  - `@Test func offlineDurableStatusChangeStillAppliesWithoutDateFill() async throws`: reuse the outbox harness of `LibraryProgressOwnerTests.swift` (read it first). The progress outbox is attached and the fence is on. The side PATCH answers `LibraryError.retryable(message: "offline")`. The outcome is `.applied`, the projection's status is `.current`, and `startedOn == nil`.
  - `@Test func explicitDateBeatsFill()`: `LibraryEdit(status:.set(.current), startedOn:.set(2020))` sends 2020.
  - `@Test("Flag off: a status change adds no date leg; a hand-edited date is still one normal write") func flagOffSendsNoRequest() async throws` (traced; binding name per program decision 1). Store built with the default gate (off). Two parts:
    1. Fence on, using the outbox harness of `LibraryProgressOwnerTests.swift` (the only case in which a fill is an extra request): an entry `.planning` with `sourceMetadata(repeatCount: 0)` and no dates; `apply(LibraryEdit(status: .set(.current)), to: key)` → outcome `.applied`; exactly one durable mutation carrying status WATCHING; **zero** backend `.edit` (PATCH) calls; the projection's `startedOn == nil`.
    2. Then `apply(LibraryEdit(startedOn: .set(try #require(PartialDate(raw: "2024-05")))), to: key)` → exactly one backend `.edit` whose edit has `startedOn == .set(2024-05)` and nothing auto-added. Fence off (`ControlledBackend`): the status change's single PATCH edit has `startedOn == .unchanged`.
- [ ] Add the app wiring test to `CompositionGraphTests` (read the suite first and reuse its graph, fake-backend and sign-in path): `@Test func dateAutofillFollowsTheServerFlag() async`. Two graphs via `AppComposition.testingGraph(…, libraryBackend: FakeLibraryBackend, flags: FeatureFlags(userDefaults: <isolated>, launchArguments: L))`: use the creating path, which fills without `sourceMetadata` (so the test needs no F2.5 fake extension): `graph.libraryActions.apply(LibraryEdit(status: .set(.current)), to: <untracked key>, createIfMissing: .current)`. With `L = []` the recorded `.edit` has `startedOn == .unchanged`; with `L = ["--ff-on=library_date_autofill_v1"]` (DEBUG override) it has `startedOn` matching `.set(_)` (pattern match, no wall-clock date in the assertion). Red today: `value of type 'FeatureFlags' has no member 'libraryDateAutofillV1Enabled'` / the second graph sends `.unchanged`.
- [ ] Add `KuroTests/DateFillCredentialLeaseTests.swift`: `@MainActor @Suite(.timeLimit(.minutes(1))) struct DateFillCredentialLeaseTests` with `@Test func preDispatchSwitchSendsNoDateLegAsB() async throws`, modelled on `CredentialLeaseTests.preDispatchSwitchSendsNothingAsB` (`KuroTests/CredentialLeaseTests.swift:48`; reuse `signedInAsAKeepingBsSession`). `SessionSDKHarness(…, flags: FeatureFlags(userDefaults: <fresh suite>, launchArguments: ["--ff-on=library_date_autofill_v1", "--ff-on=series_foundation_v1"]))` (F2 adds this `flags: FeatureFlags? = nil` parameter to `SessionSDKHarness.init` in `KuroTests/IdentityCompositionTests.swift`, forwarded to `AppComposition.testingGraph(flags:)`, which already accepts it; F2 merges before W2 and W9, which then find it present). Sign in as A keeping B's SDK session; A's `.planning` entry with known metadata and no dates; start `graph.libraryActions.apply(LibraryEdit(status: .set(.current)), to: key)`; the responder holds the durable mutation's answer; release it, then `h.storage.replace(with: sessionB)` and `applySession(userId: B)` before the PATCH leg dispatches. Expect no `anime_user_lists` PATCH whose `bearerSubject` is B and none at all after the switch; the outcome is not a success for B. Red today: the build fails (`'FeatureFlags' has no member 'libraryDateAutofillV1Enabled'`, `extra argument 'credentialLease'`); once those exist and before the leg is leased, the assertion fails with a recorded PATCH carrying B's bearer (genuine missing behaviour).
- [ ] Run `swift test --filter LibraryEditV2Tests`. Expected FAIL: `startedOn == .unchanged` (no fill yet) / `extra argument 'calendar'` / `extra argument 'dateAutofillEnabled'`.
- [ ] Implement `fillingEmptyDates`, the `calendar`, `dateAutofillEnabled` and `credentialLease` init parameters, the internal `apply` overload, the durable best-effort rule, the leased date leg, the `FeatureFlags` accessor and the `makeLibrary` wiring (`makeLibrary(backend:dateAutofillEnabled:credentialLease:)`).
- [ ] Run `swift test`. Expected: the whole package passes. Run `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/CompositionGraphTests -only-testing:KuroTests/DateFillCredentialLeaseTests -only-testing:KuroTests/CredentialLeaseTests`. Expected: pass.
- [ ] Commit: `git add Packages/KuroModules/Sources/KuroLibrary/LibraryValues.swift Packages/KuroModules/Sources/KuroLibrary/LibraryStore.swift Packages/KuroModules/Tests/KuroLibraryTests/LibraryEditV2Tests.swift Kuro/Services/FeatureFlags.swift Kuro/Composition/AppComposition.swift KuroTests/IdentityCompositionTests.swift KuroTests/DateFillCredentialLeaseTests.swift`; message `F2: status change fills empty start/finish date behind library_date_autofill_v1; Undo restores without refilling; offline fill is best effort`.

### Task F2.4: Tracking editor: repeat count and dates (discard-guarded)

**Files:** modify `Kuro/Views/TrackingDraft.swift`, `Kuro/Views/AddToListSheet.swift` and `KuroTests/TrackingDraftTests.swift`; create `Kuro/Views/PartialDatePicker.swift` and `KuroTests/TrackingEditorRenderTests.swift`.

**Interfaces**
```swift
// TrackingDraft
var repeatCount: Int                 // 0...999 (stepper)
var startedOn: PartialDate?
var finishedOn: PartialDate?
let originalRepeatCount: Int
let originalStartedOn: PartialDate?
let originalFinishedOn: PartialDate?
let datesKnown: Bool                 // entry == nil || entry.datesKnown
// edit(maxProgress:): repeatCount/startedOn/finishedOn sent ONLY when they differ by value from the originals;
// a cleared date the entry had → .clear; unchanged → .unchanged. When !datesKnown, the three are never sent
// unless the user changed them (the original is then "unknown", and any user value is .set).
// hasChanges(from:) also compares the three by value.
// PartialDatePicker.swift
struct PartialDatePicker: View {      // year wheel (1900...current year+1), month wheel ("No month" + 12), day wheel ("No day" + valid days)
    @Binding var value: PartialDate?
    let label: String                 // "Started" / "Begonnen", "Finished" / "Beendet"
}
enum TrackingDateCopy { static func started(german:) ; finished(german:) ; noDate(german:) ; noMonth(german:) ; noDay(german:) ; clear(german:) ; repeatCount(_:medium:german:) }
```
- AddToListSheet:
  - `SpreadDatesSection` (two rows; tapping a row expands an inline `PartialDatePicker`, never a sheet over the sheet).
  - `SpreadRepeatSection` (shown when `status == .completed || .repeating || repeatCount > 0`; label "Rewatched N times" / "N-mal erneut gesehen", manga "Reread" / "erneut gelesen").
  - Both sit between the Score and Notes sections.
  - The existing `.kuroDiscardGuard(isDirty:…)` already reads `draft.hasChanges(from: baseline)`, so the new fields are guarded through `hasChanges`.
  - Monochrome; tokens only; `KuroLocale` copy; `.accessibilityLabel` on each row ("Started, May 2024").

Steps
- [ ] Add failing tests to `TrackingDraftTests` (the existing `struct TrackingDraftTests`):
  - `untouchedDatesSendNothing()`: an entry with metadata `startedRaw "2024-00-00"`, `repeatCount 1` → `TrackingDraft(entry:).edit(maxProgress: 12)` has `startedOn == .unchanged`, `finishedOn == .unchanged` and `repeatCount == .unchanged`.
  - `changedDatesAndRepeatAreSent()`: set `startedOn = 2024-05`, `finishedOn = nil` (original `2024-07-14`) and `repeatCount = 2` → `.set(2024-05)`, `.clear`, `.set(2)`.
  - `hasChangesSeesDatesAndRepeat()`: a draft equal to the baseline → false; changing only `finishedOn` → true; changing only `repeatCount` → true.
  - `unknownDatesNeverCleared()`: an entry with `sourceMetadata == nil` (a cached row) and an untouched draft → all three `.unchanged`.
- [ ] Add the failing render test `KuroTests/TrackingEditorRenderTests.swift` (`@MainActor @Suite("Tracking editor v2 renders", .serialized) struct TrackingEditorRenderTests`). Host it in a window attached to the foreground `UIWindowScene`, as `NavdetailTests` does.
  - Test `datesAndRepeatRenderAtLargestTypeInBothLanguages()`. For EN and DE at `.accessibility5`, `AddToListSheet` renders for:
    - a completed anime with `startedOn 2024-05`, `finishedOn 2024-07-14` and `repeatCount 2`;
    - a manga.
  - Assert a non-zero height and `hasAmbiguousLayout == false`.
  - `TrackingDateCopy` returns non-empty EN ≠ DE strings for every key.
- [ ] Run `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/TrackingDraftTests`. Expected FAIL: `value of type 'TrackingDraft' has no member 'startedOn'`.
- [ ] Implement the draft fields, `PartialDatePicker` and the two sections.
- [ ] Run again. Expected: all `TrackingDraftTests` and `QuickStatusChangeTests` pass. Also run `-only-testing:KuroTests/NavclubsTests -only-testing:KuroTests/DUpreviewTests` (both reference `TrackingDraft`). Expected: pass.
- [ ] Run `scripts/quality-gates/check_branded_states.sh && scripts/quality-gates/check_navigation.sh && scripts/quality-gates/check_architecture.sh`. Expected: 0 offenders each.
- [ ] Commit: `git add Kuro/Views/TrackingDraft.swift Kuro/Views/AddToListSheet.swift Kuro/Views/PartialDatePicker.swift KuroTests/TrackingDraftTests.swift KuroTests/TrackingEditorRenderTests.swift`; message `F2: tracking editor edits repeat count and partial dates; untouched imported dates are never rewritten`.

### Task F2.5: A bare plan has no dates and no repeat count (Plan-key Undo never removes them)

**Why:** after F2.2 a planned entry can carry a repeat count and dates. Today `TastePlanAction.isBarePlan` (`Kuro/Views/TastePicksView.swift:605`; the program brief calls it `TastePlanPolicy`, the code name is `TastePlanAction`) ignores them. So: Plan key → the user sets a start date in the editor → the Plan toast's Undo (`TastePlanController.undo`, step `.remove`, guarded only by `isBarePlan`) removes the entry and the date with it. Discover runs the same controller (`DiscoverFeedbackController.swift:215` calls `plans.undo`; `DiscoverMoodPage` and `DiscoverCardActions` hold a `TastePlanController`), so one fix and one controller test cover both pages (program decision 3). Depends on F2.2 (`LibraryEntry.repeatCount` / `startedOn` / `finishedOn`).

**Files:** modify `Kuro/Views/TastePicksView.swift`, `Kuro/Views/Home/HomeShelfPolicy.swift` (doc comment only), `KuroTests/LibraryTestSupport.swift`, `KuroTests/FirstRunLaneTests.swift` and `KuroTests/DUpreviewTests.swift`.

**Interfaces**
```swift
// TastePicksView.swift — TastePlanAction
static func isBarePlan(_ entry: LibraryEntry) -> Bool
//   existing: status == .planning, progress == 0, notes nil/blank, rating == nil, verdict == nil
//   new:      entry.repeatCount == 0
//             && (entry.sourceMetadata?.startedRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
//             && (entry.sourceMetadata?.finishedRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
//   Judged on the stored raw, not on `startedOn`: an unparseable imported raw ("not-a-date") gives startedOn == nil
//   but is still something a removal would lose. A cached row (sourceMetadata == nil) stays bare, as today.
// The doc comments on TastePlanAction and HomeShelfPolicy.onlyBarePlans list the new conditions.
// LibraryTestSupport.swift — FakeLibraryBackend
static func entry(_ kind:, _ id:, rowId:, status:, progress:, rating:, notes:, verdict:,
                  sourceMetadata: LibrarySourceMetadata? = nil) -> LibraryEntry        // new defaulted parameter
// the fake's apply(_:to:) writes repeatCount / startedOn / finishedOn into sourceMetadata exactly as
// LibraryEdit.applying(_:at:) does (F2.2): creates metadata only when the edit names one of the three fields.
```
- Effects (Review Focus 7): a dated or rewatched plan → Plan key opens the editor (`.edit`), Plan toast Undo writes nothing, the Discover menu offers the editor, and the plan ends Home's new-account block.

Steps
- [ ] Add failing tests:
  - `FirstRunLaneTests/planUndoKeepsADatedPlan` (traced), `@Test("Plan-key Undo never removes a plan that has since gained a date or a repeat count") func planUndoKeepsADatedPlan() async throws`, using `FacadeHarness` and `FakeLibraryBackend` as `unplanAndUndo` does:
    1. Untracked card 42; `plans.tap(card, …)` → `.added`, toast offers Undo.
    2. `await service.libraryActions.apply(LibraryEdit(startedOn: .set(try #require(PartialDate(raw: "2026-11-09")))), to: card.key, createIfMissing: nil)` → `.applied`.
    3. `let writes = backend.writeCalls.count`; `let undo = plans.undo(library: service.library, actions: service.libraryActions, german: false)`.
    4. `#expect(undo == nil)`; `#expect(backend.writeCalls.count == writes)` (no `.remove`); `#expect(service.library.entry(for: card.key)?.status == .planning)`; `#expect(service.library.entry(for: card.key)?.startedOn?.raw == "2026-11-09")`.
    5. Same flow on card 43 with `LibraryEdit(repeatCount: .set(1))` instead of a date → same expectations.
    Red today: `isBarePlan` is true for both entries, so `undo` returns a task and the last write is `.remove(card.key)` (wrong current behaviour).
  - Extend `FirstRunLaneTests/planKeyRule`: `.planning` with `sourceMetadata: LibrarySourceMetadata(repeatCount: 1)` → `.edit`; with `startedRaw: "2024-05"` → `.edit`; with `finishedRaw: "2024"` → `.edit`; with `startedRaw: "not-a-date"` → `.edit`; with `LibrarySourceMetadata(repeatCount: 0)` and no dates → `.unplan`; `sourceMetadata == nil` → `.unplan` (unchanged).
  - Extend `FirstRunLaneTests/newAccountEndsOnAStartedPlan`: `[planning, planning with startedRaw "2026-11-09"]` → `HomeShelfPolicy.onlyBarePlans == false`.
  - Extend `DUpreviewTests/menuOffer`: a planned entry with `startedRaw "2024-05"` → `offer.plan == .edit`.
- [ ] Run `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/FirstRunLaneTests -only-testing:KuroTests/DUpreviewTests`. Expected FAIL: `planUndoKeepsADatedPlan` (`undo != nil`, last write `.remove`), `planKeyRule` (`.unplan` where `.edit` is expected), `newAccountEndsOnAStartedPlan`, `menuOffer`.
- [ ] Implement the widened predicate, the fake's `sourceMetadata` parameter and field handling, and the doc comments.
- [ ] Run again plus `-only-testing:KuroTests/DiscoverPageFeedbackTests -only-testing:KuroTests/DiscoverPageBuildTests -only-testing:KuroTests/HomeToastRound3Tests` (other `TastePlanController` / `FakeLibraryBackend` users). Expected: all pass.
- [ ] Commit: `git add Kuro/Views/TastePicksView.swift Kuro/Views/Home/HomeShelfPolicy.swift KuroTests/LibraryTestSupport.swift KuroTests/FirstRunLaneTests.swift KuroTests/DUpreviewTests.swift`; message `F2: a bare plan has no dates or repeat count, so Plan-key Undo never removes them`.

### Task F3.1: Profile registry and a separate absolute-rate profile lane

**Files:** modify `scripts/load/backend_workload.js`, `scripts/load/backend_workload.test.js`, `scripts/load/backend_runner.test.js` and `scripts/load_test_backend.js`.

**Load model (program decision 5, spec §3 Load model).** The predeclared base mix keeps its absolute arrival rate (`--rps`, 20 in qualification) and its kind sequence unchanged when profiles are enabled. Profiles add their own absolute rates (`ratePerSecond`) on top, in a separate scheduler lane, and are reported separately, so the base regression comparison stays like-for-like. Profiles never enter `WEIGHTS` or `chooseKind`. (The earlier `weight` model, which diluted the base mix, is retired. Conversion for plans written against it: weight *w* of the predeclared 100 at the 20 rps base ≙ `ratePerSecond = 0.2 × w`, e.g. W2's 1 → 0.2 rps, W4's 5 → 1 rps, W5's 25 → 5 rps; a plan that states its own rate keeps it (W9 5 rps, W10 2 rps). Final rates: the `tracker-gaps-combined` table in F3.1c.)

**Interfaces (Produces):**
```js
// scripts/load/profiles/<name>.js  (one file per profile; status-with-date-fill (F3.1d), then W2, W4, W5, W6, W9, W10)
module.exports = {
  name: "<name>",                 // must equal the file basename
  budgetClass: "browse",          // one of Object.keys(LIMITS); budget = LIMITS[budgetClass] (F3.1b adds budgetClasses / operations)
  ratePerSecond: 0.8,             // absolute arrivals per second in the profile lane; finite, 0 < r <= 10; independent of --rps
  librarySizes: [25, 100, 2000],  // optional: fixture library-size subgroups that supply actors (default: every size present;
                                  //   anonymous profiles ignore actors)
  writes: false,                  // true when any request writes (F3.1c then requires seed and cleanupCheck)
  request(actor, fixture, seq, random, core) { return { path: "/rest/v1/rpc/…", body: {…} }; },
  validate(data, actor, request, ctx) { return boolean; },   // ctx = { mode: "wiring" | "qualify" }; HTTP 2xx checked first
};
// Profiles must NOT require backend_workload.js (circular load); they receive core = { requestFor, validateResponse, ORIGIN, now }
// (now: () => Date; the runner passes () => new Date(), tests inject a fixed clock).

// scripts/load/backend_workload.js (additions; WEIGHTS, LIMITS, chooseKind, requestFor and validateResponse unchanged)
function loadProfiles(dir = path.join(__dirname, "profiles"))
  // -> frozen { [name]: profile }; {} when dir is absent; ignores *.test.js; throws on any invalid profile,
  //    including a `weight` field ("weight is retired: declare ratePerSecond (weight w ≙ 0.2·w rps at the 20 rps base)")
const TRACKER_GAP_PROFILES = loadProfiles();
function selectProfiles(spec = {}, profiles = TRACKER_GAP_PROFILES)
  // spec = { names?: string[] (["all"] = every profile), rates?: { [name]: number } (a named workload's explicit rates) }
  // -> frozen { profiles: [{ name, ratePerSecond, profile }], totalRate, limits: { [kind]: ms } } (profile kinds only)
  // unknown name or invalid rate throws; {} -> { profiles: [], totalRate: 0, limits: {} }
function profileSchedule(selection, durationSeconds)
  // -> [{ atMs, name, seq }] sorted by atMs, then name: profile p's i-th arrival at i * 1000 / p.ratePerSecond,
  //    for i < ceil(durationSeconds * p.ratePerSecond). Deterministic; exact absolute rates.
function summarize(samples, offered, seconds, limits = LIMITS)
  // iterates Object.keys(limits); LIMITS has the same keys in the same order as WEIGHTS, so base output is unchanged
function validateConfig(c, fixture, selection = EMPTY_SELECTION)
  // base rules unchanged; adds: c.rps + selection.totalRate <= 50; base planned + profile planned <= 20,000;
  // c.only names a base kind only (profiles never run through --only)
module.exports = { ...existing, loadProfiles, TRACKER_GAP_PROFILES, selectProfiles, profileSchedule, exitCodeFor };
```
- Runner `scripts/load_test_backend.js`: `run(config, fixture, { profiles = W.TRACKER_GAP_PROFILES } = {})`.
  - `--tracker-gaps=a,b|all` → `config.trackerGaps`; `selection = W.selectProfiles({ names: config.trackerGaps ?? [] }, profiles)`.
  - **Base lane:** today's loop, byte-for-byte in behaviour, with its own LCG (`seed = config.seed`), its own `busyBase` set, in-flight cap `min(100, vus)` and rolling safety window over base samples only. Without profiles the run is identical to today.
  - **Profile lane:** walks `profileSchedule(selection, config.duration)` concurrently with the base lane (both awaited with `Promise.all`). It has its own LCG (`(config.seed ^ 0x9e3779b9) >>> 0`), its own `busyProfile` set, its own in-flight cap `min(100, vus)` and its own rolling window. Actor choice is deterministic: cycle the profile's covered library-size subgroups, then round-robin within the subgroup, so each subgroup gets an equal share of the profile's rate. A busy actor (in this lane) is a dropped arrival counted in `lanes.profiles.droppedBusy`; a base request never drops because of a profile request.
  - **Safety:** the stop file, or either lane's rolling stop, halts both lanes; `stopReason` is prefixed `base:` or `profiles:`.
  - **Report `schemaVersion: 2`:** every v1 field keeps its meaning and is computed from base samples only (`summary`, `byLibrarySize`, `byMedium`, `weights`, `windows`, `samples`, `droppedBusy`, `maxInFlight`, `distinctAccounts`), and the v1 rule for `summary.pass` is unchanged. New: `mode` (`"wiring"` until F3.1c), `runKey` (`fixture.runId + "@" + startedAt`), and, when profiles are selected, `lanes.profiles = { selection: [{ name, ratePerSecond }], offered, droppedBusy, skippedSteps: {}, summary: W.summarize(profileSamples, offered, elapsed, selection.limits), byLibrarySize, samples, verdict: "wiring" }`.
  - **Exit code** (`W.exitCodeFor(report)`, exported): 0 when the base passes and every profile sample is ok; 1 otherwise (F3.1c adds 3).
- Fixture seeding for profile data is **wiring-mode tolerant**: in wiring mode a profile must accept an actor without seeded data and validate an empty but well-formed answer. Release evidence needs `--qualify` with seeded, populated fixtures (Task F3.1c).
- Why selection is opt-in: profile RPCs answer 404 (PGRST202) until their prepared migrations are approved, so they never run unless named.

Steps
- [ ] **Characterization first (not a red step):** before touching `backend_workload.js`, compute the frozen digest: `node -e` with the LCG of `load_test_backend.js` (seed 20261109) over the unmodified module, 1,000 `W.chooseKind(random)` draws joined by `,`, SHA-256. Paste the hex into the test as `FROZEN_MIX_DIGEST` and record it in the evidence note. Test `predeclared mix is unchanged`: the digest matches; `W.WEIGHTS` / `W.LIMITS` deep-equal their current literals; the `summarize` endpoint keys for one browse sample equal `["browse"]`. It passes before and after this task by design.
- [ ] Write the failing tests in `backend_workload.test.js`:
  - `selection is empty without opt-in`: `W.selectProfiles({})` deep-equals `{ profiles: [], totalRate: 0, limits: {} }`.
  - `profiles keep their absolute rate`: `const P = W.loadProfiles(tmpDir)` with temp profiles `x-test` (`browse`, 0.5 rps) and `z-test` (`detail`, 2 rps). `W.profileSchedule(W.selectProfiles({ names: ["x-test", "z-test"] }, P), 10)` → 5 `x-test` arrivals at 0, 2000, 4000, 6000, 8000 ms and 20 `z-test` arrivals at 500 ms spacing; `totalRate === 2.5`; `limits["x-test"] === 750`, `limits["z-test"] === 1200`; with `rates: { "x-test": 1 }` → 10 `x-test` arrivals. The base schedule (`i * 1000 / rps`) and `WEIGHTS` are untouched by either selection.
  - `invalid profiles are refused`: each throws in `loadProfiles`: name ≠ file name, `budgetClass "fast"`, `ratePerSecond` 0, −1, 10.5, `NaN`, `"1"`, a missing `validate`, and a `weight: 4` field (message names `ratePerSecond`). `ratePerSecond 10` loads.
  - `missing profiles directory yields no profiles`: `loadProfiles("/nonexistent")` deep-equals `{}`.
  - `config bounds cover both lanes`: with a 6 rps selection, `validateConfig({ ...config, rps: 45 }, fixture, sel)` throws `Invalid bounded rps`; `rps: 20` does not; `only: "x-test"` throws.
- [ ] Write the failing runner test in `backend_runner.test.js` (reuse its `t.mock.method(global, "fetch", …)` double; it answers **immediately** with a valid body per base kind and per profile path, so no arrival is dropped for timing reasons): `base lane is identical with a profile lane`. Run A: `{ rps: 10, duration: 1, vus: 2 }` without profiles. Run B: same config plus a temp `x-test` profile at 5 rps injected through `run(config, fixture, { profiles: P })` with `trackerGaps: ["x-test"]`. Assert: `droppedBusy === 0` in both runs (precondition; otherwise the comparison is timing noise); the base samples' `kind` and `sequence` lists are equal in A and B; `offered` and the `summary.endpoints` keys are equal (no latency or timing value is compared); no base sample has kind `x-test`; `B.lanes.profiles.summary.endpoints["x-test"].requests === 5`; `B.schemaVersion === 2`; a profile sample that fails validation leaves `B.summary.pass` as in A and makes `W.exitCodeFor(B) === 1`.
- [ ] Run `node --test scripts/load/backend_workload.test.js scripts/load/backend_runner.test.js`. Expected FAIL: `TypeError: W.selectProfiles is not a function` / `W.loadProfiles is not a function`; `B.lanes` is `undefined`.
- [ ] Implement the registry, `selectProfiles`, `profileSchedule`, the limits-aware `summarize`, the selection-aware `validateConfig`, `exitCodeFor`, the two lanes and the v2 report.
- [ ] Run `node --test scripts/load/*.test.js`. Expected: all pass, including the frozen digest and the existing fixture, runner and transport tests unchanged.
- [ ] Commit: `git add scripts/load/backend_workload.js scripts/load/backend_workload.test.js scripts/load/backend_runner.test.js scripts/load_test_backend.js`; message `F3: tracker-gap profiles run in a separate absolute-rate lane; base mix and report unchanged`.

### Task F3.1b: Profile request options (GET, anonymous, per-request class, operations, PATCH, multi-step) and the profile test gate

**Why:** W2 and W6 read public tables with PostgREST GET; W5 sends anonymous requests across four budget classes under one profile (`guest-browse`); W9 and F2 write (organisation deltas, list create/reorder/rebalance/seed, status with a date fill), and the F2 date fill is two sequential requests (the durable status mutation, then a PATCH). Every profile ships its own `profiles/<name>.test.js`, which no gate runs today. Without this task each plan would invent its own runner change.

**Files:** modify `scripts/load/backend_workload.js`, `scripts/load/backend_workload.test.js`, `scripts/load/backend_runner.test.js`, `scripts/load_test_backend.js`, `scripts/quality-gates/run_all.sh`; create `scripts/quality-gates/test_load_profiles.sh`.

**Interfaces (Produces, binding for every profile plan):**
- `request(actor, fixture, seq, random, core)` returns one request `{ path, body?, method?: "GET" | "POST" | "PATCH", prefer?: string, anonymous?: boolean, budgetClass?: string, operation?: string, payload?: "typical" | "maximum" }`, or an action `{ steps: [request, …] }` (1–3 steps, each naming its `operation`).
  - `method` defaults to `"POST"`. `"GET"`: no body and no `Content-Type`; `path` carries the query string. `"PATCH"`: JSON body, `Content-Type: application/json` and `Prefer: <prefer ?? "return=representation">`.
  - `anonymous: true`: the runner sends `apikey: <anonKey>` and `Authorization: Bearer <anonKey>`, never `actor.token`. `validateConfig` does not require a seeded account for such samples.
  - Per-request class: a profile that returns `budgetClass` per request declares its classes up front as `budgetClasses: [<LIMITS keys>]`. Samples are recorded as `"<name>:<budgetClass>"` with limit `LIMITS[budgetClass]`. When `budgetClasses` is declared, `selectProfiles` emits only the `"<name>:<class>"` limit keys (no bare `<name>` key); a declared class with zero samples in a run is skipped by `summarize`, as predeclared kinds already are. Without `budgetClasses` the single `budgetClass` applies under the bare `<name>` key.
  - Operations: a profile that issues different endpoints (reads and writes, or the legs of one action) declares `operations: { "<op>": { budgetClass: <LIMITS key>, share?: number } }`. Every request or step must name a declared `operation`; samples are recorded as `"<name>:<op>"` with limit `LIMITS[operations[op].budgetClass]`. `share` (0 < s ≤ 1, summing to 1 when given; equal split otherwise) is the operation's expected fraction of the profile's arrivals, used by the F3.1c preflight; for the legs of a multi-step action every leg has the action's share. `operations` and `budgetClasses` are mutually exclusive (`loadProfiles` throws). A request naming an undeclared operation is a failed sample with error `undeclared_operation`.
  - Multi-step actions: the runner sends the steps in order for the same actor, which stays busy (profile lane) for the whole action. The first failed step ends the action; each later step is counted in `lanes.profiles.skippedSteps["<name>:<op>"]` and is not a sample. Each sent step is one sample; `validate(data, actor, step, ctx)` is called per step.
  - `payload` is recorded on the sample; `summarize` adds `byPayload` per kind when any sample carries one.
  - `core = { requestFor, validateResponse, ORIGIN, now }` (the module's own functions plus the clock, `now: () => Date`), so a profile can reuse a predeclared request body without `require`-ing `backend_workload.js` and never reads the wall clock directly.
- `validate` is called only after an HTTP 2xx; a non-2xx (including PGRST202 404) is always a failed sample.

Steps
- [ ] Write the failing tests:
  - `backend_workload.test.js` → `profile request options`: a temp profile `y-test` with `budgetClasses: ["browse", "detail"]` returning `{ method: "GET", anonymous: true, budgetClass: seq % 2 ? "detail" : "browse", path: "/rest/v1/anime?id=eq.1" }` → `W.selectProfiles({ names: ["y-test"] }, P).limits["y-test:browse"] === 750` and `["y-test:detail"] === 1200`; no bare `"y-test"` key; `budgetClasses: ["fast"]` throws in `loadProfiles`; `request` receives `core.requestFor === W.requestFor`. A temp profile `w-test` with `operations: { a: { budgetClass: "progress" }, b: { budgetClass: "progress" } }` → limits `w-test:a` and `w-test:b` = 750; declaring both `operations` and `budgetClasses` throws; `operations` with shares summing to 0.9 throws.
  - `backend_runner.test.js` → `GET and anonymous requests`: a `y-test` GET sample is sent with `method: "GET"`, no body, `Authorization: "Bearer " + fixture.anonKey`, and is summarised under `y-test:browse` / `y-test:detail`; a POST profile sample still carries `actor.token`. Read `backend_runner.test.js` first and reuse its fetch double.
  - `backend_runner.test.js` → `PATCH and multi-step actions`: `w-test` returns `{ steps: [{ operation: "a", path: "/rest/v1/rpc/x", body: {} }, { operation: "b", method: "PATCH", path: "/rest/v1/anime_user_lists?id=eq.1", body: { started_raw: "2026-03-02" } }] }`. The fetch double sees POST then PATCH, in order, both with `actor.token`, the PATCH with `Prefer: return=representation` and the JSON body; one sample each under `w-test:a` and `w-test:b`. When step `a` answers 500, step `b` is not sent and `lanes.profiles.skippedSteps["w-test:b"] === 1`. A request with `operation: "zz"` → failed sample `undeclared_operation`.
- [ ] Run `node --test scripts/load/backend_workload.test.js scripts/load/backend_runner.test.js`. Expected FAIL: `limits["y-test:browse"]` is `undefined` / request sent as POST / PATCH never sent.
- [ ] Implement the options in `backend_workload.js` (`loadProfiles` validation, `selectProfiles` limits, `core`) and `load_test_backend.js` (method, headers, `Prefer`, steps, sample kind, `skippedSteps`, `byPayload`).
- [ ] Create `scripts/quality-gates/test_load_profiles.sh` (`set -uo pipefail`; SKIP exit 0 with a message when `node` is absent; runs `node --test scripts/load/*.test.js` plus `scripts/load/profiles/*.test.js` when that glob matches) and register `"load-profiles:test_load_profiles.sh:1"` in `run_all.sh` after `bdd-traceability`.
- [ ] Run `bash scripts/quality-gates/test_load_profiles.sh`. Expected: all pass, including the frozen-digest and lane-identity tests.
- [ ] Commit: `git add scripts/load/backend_workload.js scripts/load/backend_workload.test.js scripts/load/backend_runner.test.js scripts/load_test_backend.js scripts/quality-gates/test_load_profiles.sh scripts/quality-gates/run_all.sh`; message `F3: profile GET/anonymous/per-request class/operations/PATCH/multi-step options and the load-profiles gate`.

### Task F3.1c: Qualification mode (`--qualify`), the combined workload and fixture seed/cleanup hooks

**Why:** spec §3 Release evidence: only a qualification-mode run counts (populated fixtures, semantic assertions, representative writes, typical and maximum payloads, cleanup verification, ≥ 100 completions per endpoint and ≥ 30 per library-size subgroup, otherwise `insufficient`). Wiring mode (the default) stays tolerant and is never release evidence. F1.3's `--accepted` reads exactly the fields defined here.

**Files:** modify `scripts/load/backend_workload.js`, `scripts/load/backend_workload.test.js`, `scripts/load/backend_runner.test.js`, `scripts/load/backend_fixture.js`, `scripts/load/backend_fixture.test.js`, `scripts/load_test_backend.js`; create `scripts/load/workloads/tracker-gaps-combined.js`.

**Interfaces (Produces, binding for every profile plan):**
```js
// Profile fields for qualification (checked by loadProfiles, F3.1c):
//   emptyExamples: [[], {}, …]     required, >= 1: answers that validate(…, { mode: "qualify" }) must REJECT.
//                                  loadProfiles calls validate(example, STUB_ACTOR, STUB_REQUEST, { mode: "qualify" }) for each
//                                  and throws "<name>: validate accepts an empty answer in qualify mode" if any returns true
//                                  (a throw counts as rejection). For write operations: a missing or mismatching outcome.
//   requires(fixture, actor) -> string | null   optional: why this actor is not populated enough (e.g. "no seeded lists")
//   payloads: ["typical", "maximum"]            optional; each request then names its payload; the maximum must be the
//                                               supported maximum (e.g. 2,000 items in one list, 10 tags per entry)
//   seed({ actor, fixture, call, core }) -> Promise<state>     required when writes: true (and for any read that needs data);
//                                               returns JSON-serialisable state stored at actor.profileState[name]
//   cleanupCheck({ actor, state, call }) -> Promise<boolean>  required when writes: true (and whenever seed is declared):
//                                               true when the profile's data for this (deleted) account is gone
// backend_workload.js
const QUALIFY_MIN = Object.freeze({ endpoint: 100, subgroup: 30, payload: 30 });
function loadWorkload(name, dir = path.join(__dirname, "workloads"))
  // -> frozen { name, baseRps, profiles: { [name]: ratePerSecond } }; unknown or invalid throws
function qualifyPreflight(config, fixture, selection, min = QUALIFY_MIN)
  // -> { passed: true, expected: { [kind]: { completions, bySubgroup, byPayload } } }; throws listing every problem:
  //    - expected completions per endpoint = duration × rate × share < min.endpoint
  //      ("<kind>: expected 60 completions < 100; raise its rate or the duration")
  //    - expected per covered subgroup (÷ number of covered subgroups) < min.subgroup (anonymous profiles: no subgroup check);
  //      per declared payload (÷ number of declared payloads) < min.payload
  //    - a declared library size with no actor in the fixture (e.g. no 2,000-title account)
  //    - profile.requires(fixture, actor) non-null for any covered actor ("Fixture not populated for <name>: <reason> (n actors)")
function qualifyVerdicts(samples, selection, min = QUALIFY_MIN)
  // -> { verdict, profiles: { [name]: { verdict, endpoints: { [kind]: { verdict, completions, p95, limit,
  //        bySubgroup: { [size]: { completions, p95, verdict } }, byPayload: { [payload]: { completions, p95, verdict } } } } } } }
  //    endpoint: "fail" if any sample is not ok, or p95 > limit overall or in any covered subgroup / payload;
  //              else "insufficient" if completions < min.endpoint, or any covered subgroup < min.subgroup,
  //              or any declared payload < min.payload; else "pass".
  //    profile and lane: "fail" > "insufficient" > "pass". Anonymous samples have no subgroup.
// exitCodeFor(report): 0 pass; 1 fail (base fail, a failed profile sample, profile verdict fail, or qualify without
//   preflight.passed); 3 insufficient (qualify mode, nothing failed, some verdict insufficient).
```
- `scripts/load/workloads/tracker-gaps-combined.js`: `module.exports = Object.freeze({ name: "tracker-gaps-combined", baseRps: 20, profiles: Object.freeze({}) })`. Each profile's own task adds one line `"<name>": <ratePerSecond>` (F3.1d adds the first; W plans append theirs, the guest profile as an absolute rps, not a share). Final content once every plan has landed (each rate is the one its plan declares; a 600 s run meets ≥ 100 completions per endpoint and ≥ 30 per covered subgroup at these rates, arithmetic in each plan):

| Profile | Plan | `ratePerSecond` | Smallest endpoint in 600 s | Smallest subgroup |
|---|---|---|---|---|
| `status-with-date-fill` | F3.1d | 0.4 | 240 per leg | 80 (3 sizes) |
| `export-mal-id-lookup` | W2 Task 7 | 0.2 | 120 | 40 (3 sizes) |
| `search-with-hidden-adult-count` | W4 Task 6 | 1 | 600 | 150 (4 sizes) |
| `guest-browse` | W5 Task 7 | 5 (anonymous, absolute) | 250 (`discover`, 5/60 of draws) | none (anonymous) |
| `collection_series_membership` | W6 Task 4 | 1 | 600 | 200 (3 sizes) |
| `collection-with-tags-and-lists` | W9 Task W9.8 | 5 | 120 (each 4 % operation) | 60 (2 sizes) |
| `collection-up-next` | W10 Task 7 | 2 | 120 (each write operation) | 60 (2 sizes) |

Base 20 rps + profiles 14.6 rps = 34.6 rps ≤ the 50 rps bound of `validateConfig`.
- Runner:
  - `--workload=<name>` → `W.loadWorkload(name)`; `selection = selectProfiles({ names: Object.keys(w.profiles), rates: w.profiles })`; `config.rps` defaults to `w.baseRps`, and an explicit `--rps` that differs throws (`the combined workload keeps the base at <baseRps> rps`). `--workload` and `--tracker-gaps` are mutually exclusive.
  - `--qualify` → `config.mode = "qualify"`. The CLI runs `W.qualifyPreflight(config, fixture, selection)` **before** `run` (a refused preflight sends nothing and exits 1) and passes its result in: `run(config, fixture, { profiles, preflight })`. In qualify mode `validate` gets `{ mode: "qualify" }`.
  - Report (qualify): `mode: "qualify"`, `preflight` (as returned), `workload` (name or the `--tracker-gaps` list), `lanes.profiles.verdict` and `lanes.profiles.profiles` from `qualifyVerdicts`. `report.summary` (base) keeps the v1 pass rule; the base lane is not judged by the minimum-sample rule (Review Focus 9; owner/lead decision whether the base should be).
- Fixture `scripts/load/backend_fixture.js`:
  - New mode `manage("seed-profiles", file, { anonKey, serviceKey, profiles })` (CLI: `KURO_LOAD_WORKLOAD=<name>` or `KURO_LOAD_PROFILES=a,b|all`). Requires a completed `setup`. For each selected profile with `seed`, for each covered actor without `actor.profileState?.[name]`, calls `seed({ actor, fixture: f, call, core })` with the fixture's existing `call(path, body, { method, token, allowNotFound })`, stores the result and `save()`s after each actor (resumable). Returns `{ runId, seeded: { [name]: count } }`.
  - `refresh` keeps `actor.profileState` untouched, and its `writeEntry` read (`order=anime_id&limit=1`, line ~85) excludes every anime id recorded in the actor's `profileState` (`&anime_id=not.in.(…)`), so a seeded profile row never becomes the base `progress` kind's `writeEntry`.
  - `cleanup`: after an account's auth 404 is confirmed, for every profile named in `actor.profileState` (looked up in the registry; an unregistered name throws `cleanup cannot verify unregistered profile <name>`), `await cleanupCheck({ actor, state, call })` must be true; the cleanup entry gains `profileData: { [name]: "absent" }`; false throws `Profile data cleanup not confirmed (<name>, account <index>)`. The cleanup output is the `cleanupReport` that F1.3 reads.

Steps
- [ ] Write the failing tests:
  - `backend_workload.test.js` → `qualification verdicts` (one temp profile, `browse`, `librarySizes: [25, 2000]`): 99 ok fast samples → endpoint `insufficient`; 100 ok fast samples with 29 in the 2000 subgroup → `insufficient`; 100 with ≥ 30 in each subgroup → `pass`; one non-ok among 200 → `fail`; overall p95 751 ms → `fail`; a declared `maximum` payload with 10 samples → `insufficient`; the lane verdict is never `pass` while any endpoint is `insufficient`; `exitCodeFor` maps the three to 0 / 1 / 3, and a qualify report with `preflight.passed !== true` to 1.
  - `qualify preflight refuses thin or empty setups`: rate 0.1 over 600 s (60 expected) throws naming the kind; a profile declaring 2000 against a fixture without a 2,000-title account throws; `requires` returning `"no seeded lists"` for an actor throws `Fixture not populated`; a 0.5 rps profile over 600 s with two covered subgroups passes (300 expected, 150 per subgroup).
  - `qualify mode rejects empty answers`: a temp profile whose `validate` returns true for `[]` in qualify mode throws in `loadProfiles`; a correct profile accepts `[]` with `{ mode: "wiring" }` and rejects it with `{ mode: "qualify" }`; `writes: true` without `seed` or `cleanupCheck` throws.
  - `combined workload names every profile with an explicit rate`: `const w = W.loadWorkload("tracker-gaps-combined")`; `w.baseRps === 20`; `Object.keys(w.profiles).sort()` deep-equals `Object.keys(W.TRACKER_GAP_PROFILES).sort()`; every rate is finite, 0 < r ≤ 10; `20 + Σ rates ≤ 50`. (While the registry is empty this holds with two empty sets; it is enforced as each profile lands.)
  - `backend_runner.test.js` → `qualify report and exit code`: a short run with a temp profile in qualify mode and an injected `preflight: { passed: true, expected: {} }` → `report.mode === "qualify"`, `report.runKey.startsWith(fixture.runId + "@")`, `lanes.profiles.verdict === "insufficient"` (few samples), `W.exitCodeFor(report) === 3`; the same run without `preflight` → `exitCodeFor === 1`; validate received `{ mode: "qualify" }`.
  - `backend_fixture.test.js` (read it first; reuse its fetch double and `setup(t, overrides)`): `seed-profiles seeds once per covered actor and refresh keeps profile state` (a second call seeds nothing; `refresh` leaves `profileState` equal, and its revision read carries `anime_id=not.in.(<seeded id>)` so `writeEntry.mediaId` is never the seeded row); `cleanup verifies profile data is absent` (`cleanupCheck` true → entry `profileData: { "x-test": "absent" }`; false → throws `Profile data cleanup not confirmed`; an unregistered profile name in `profileState` → throws before deletion of the next account).
- [ ] Run `node --test scripts/load/*.test.js`. Expected FAIL: `TypeError: W.qualifyVerdicts is not a function` / `W.loadWorkload is not a function` / `Bounded fixture mode, credentials and account count required` for `seed-profiles`.
- [ ] Implement the qualify fields in `loadProfiles`, `loadWorkload`, `qualifyPreflight`, `qualifyVerdicts`, the runner flags and report fields, the workload file and the fixture modes.
- [ ] Run `bash scripts/quality-gates/test_load_profiles.sh`. Expected: all pass, including every earlier load test unchanged.
- [ ] Commit: `git add scripts/load/backend_workload.js scripts/load/backend_workload.test.js scripts/load/backend_runner.test.js scripts/load/backend_fixture.js scripts/load/backend_fixture.test.js scripts/load_test_backend.js scripts/load/workloads/tracker-gaps-combined.js`; message `F3: qualification mode (preflight, strict validators, minimum samples, cleanup checks) and the tracker-gaps-combined workload`.

### Task F3.1d: Load profile `status-with-date-fill` (the F2 date leg)

**Why:** with the fence on, a status change that fills a date is the durable mutation plus a PATCH leg (Task F2.3), so `library_date_autofill_v1` adds backend traffic and needs a profile before D-H can release it. Undo of such a change is the same two legs. Depends on F2.3, F3.1b and F3.1c.

**Files:** create `scripts/load/profiles/status-with-date-fill.js` and `scripts/load/profiles/status-with-date-fill.test.js`; modify `scripts/load/workloads/tracker-gaps-combined.js`.

**Interfaces (Produces):**
```js
module.exports = {
  name: "status-with-date-fill",
  operations: { mutation: { budgetClass: "progress" }, "date-patch": { budgetClass: "progress" } },   // both legs of every action
  ratePerSecond: 0.4,            // actions/s → 240 per leg in 600 s; 80 per covered subgroup
  librarySizes: [25, 100, 2000], // size-0 accounts have nothing to change
  writes: true,
  payloads: ["typical"],         // a single-row change; the supported maximum is the 2,000-title library, covered by its subgroup
  emptyExamples: [[], {}, { items: [] }],
  requires(fixture, actor),      // "no seeded date-fill entry" unless actor.profileState["status-with-date-fill"].rowId is an integer
  seed({ actor, fixture, call }),// one dedicated PLANNING anime row per covered actor, media id from fixture.media.anime not in the
                                 //   actor's library, no dates; inserted with the actor token exactly as
                                 //   SupabaseLibraryBackend.insertIfMissing does (read it, ~line 120; mirror path and Prefer);
                                 //   returns { rowId, mediaId, lifecycleId, revision, phase: "fill" }.
                                 //   Never actor.writeEntry: the PATCH advances server_revision and would stale the base progress kind.
  request(actor, fixture, seq, random, core),
    // -> { steps: [
    //   { operation: "mutation", path: "/rest/v1/rpc/apply_progress_mutations_v1",
    //     body: { p_mutations: [{ mutation_id, medium: "anime", media_id, lifecycle_id, base_revision,
    //                             status: phase === "fill" ? "WATCHING" : "PLANNING" }] } },
    //   { operation: "date-patch", method: "PATCH",
    //     path: "/rest/v1/anime_user_lists?id=eq.<rowId>&select=id,list_type,started_raw,server_revision",
    //     body: { started_raw: phase === "fill" ? todayIn("Europe/Berlin", core.now()) : null } } ] }
    //   The PATCH mirrors the fence-on side PATCH of SupabaseLibraryBackend (read it; same table path, filter and Prefer).
  validate(data, actor, step, ctx),
    // mutation: items[0].mutation_id matches, outcome "applied", integer server_revision → state.revision
    // date-patch: exactly one row, started_raw equals the sent value, list_type matches the phase,
    //             integer server_revision → state.revision; the phase flips only after both legs succeed
  cleanupCheck({ actor, state, call }),  // service-role GET /rest/v1/anime_user_lists?id=eq.<rowId>&select=id → []
  todayIn(timeZone, date),               // exported helper: "YYYY-MM-DD" via Intl.DateTimeFormat("en-CA", { timeZone })
};
```
- Combined workload line: `"status-with-date-fill": 0.4`.

Steps
- [ ] Write the failing `status-with-date-fill.test.js` (`node:test`, no network; a `call` double for seed/cleanup):
  - `fill and undo legs`: phase `fill` → step 1 status `WATCHING` with the stored `lifecycle_id` / `base_revision`, step 2 PATCH body `{ started_raw: "2026-03-02" }` with `core.now = () => new Date("2026-03-01T23:30:00Z")` (Europe/Berlin); phase `undo` → `PLANNING` and `{ started_raw: null }`.
  - `revision threads through both legs`: the mutation's `server_revision` 8 is stored; the PATCH answer's `server_revision` 9 becomes the next action's `base_revision`; the phase flips only after the PATCH validates.
  - `qualify validation is strict`: each `emptyExamples` entry is rejected with `{ mode: "qualify" }`; a PATCH answer with `started_raw` different from the sent value, or two rows, is rejected; `loadProfiles(path.dirname(__filename))` loads the profile (so the qualify checks of F3.1c pass).
  - `seed uses a dedicated row and cleanup checks it`: `seed` skips media ids already in the actor's library, never touches `actor.writeEntry`, and returns `phase: "fill"`; `requires` is null after seeding and names the reason before; `cleanupCheck` is true for `[]` and false for `[{ id }]`.
- [ ] Run `node --test scripts/load/profiles/status-with-date-fill.test.js`. Expected FAIL: `Cannot find module './status-with-date-fill'`.
- [ ] Implement the profile and add its line to `tracker-gaps-combined.js`.
- [ ] Run `bash scripts/quality-gates/test_load_profiles.sh`. Expected: all pass, including `combined workload names every profile with an explicit rate` (registry and workload now both name `status-with-date-fill`).
- [ ] Commit: `git add scripts/load/profiles/status-with-date-fill.js scripts/load/profiles/status-with-date-fill.test.js scripts/load/workloads/tracker-gaps-combined.js`; message `F3: status-with-date-fill load profile for the F2 date leg (Progress class, qualification-ready)`.
- [ ] Not in this plan (owner-approved, D-H): `node scripts/load/backend_fixture.js seed-profiles <fixture>` with `KURO_LOAD_WORKLOAD=tracker-gaps-combined`, then `node scripts/load_test_backend.js --production --qualify --workload=tracker-gaps-combined --duration=600 --fixture=<private> --output=docs/tracker-gaps-2026-11/load/<runKey>.json`, then fixture `cleanup` saved as the `cleanupReport`. Only that run can turn the F2 load scenario `pass` in `acceptance/F2.json`.

### Task F3.2: 2,000-title SQL plan-check fixture

**Files:** create `supabase/tests/fixtures/library_2000.sql` and `supabase/tests/rls/112_library_2000_fixture.sql`.

**Interfaces (Produces, psql include via `\ir ../fixtures/library_2000.sql`, inside the test's transaction):**
```sql
-- pg_temp.load_library_2000(p_user uuid, p_noise_users integer default 400, p_noise_rows integer default 250) returns integer
--   inserts catalogue rows 9100001..9101400 (anime) and 9100001..9100600 (manga) if missing,
--   2,000 list rows for p_user::text (1,400 anime + 600 manga; statuses spread 40/30/20/5/5 % WATCHING|READING/
--   PLANNING/COMPLETED/PAUSED/DROPPED), plus p_noise_rows rows each for p_noise_users users tests.make_user(1000..)
--   (many small libraries: the user holds 2,000 of ~102,000 rows, about 2 %, so the planner's choice reflects production
--   selectivity, not a 10 % slice); runs with session_replication_role=replica (no list triggers),
--   then ANALYZE on the four tables; returns the user's row count.
-- pg_temp.plan_uses_index(p_query text, p_index text) returns boolean
--   EXPLAIN (FORMAT JSON) p_query; true when any node is Index Scan / Index Only Scan / Bitmap Index Scan
--   with "Index Name" = p_index; RAISE NOTICE 'PLAN %' with the plan for the evidence log.
```
(plpgsql bodies, fixture rule.)

Steps
- [ ] Write the failing test `112_library_2000_fixture.sql`. Header: `-- @requires table public.anime_user_lists`, `-- @requires table public.manga_user_lists`. Body: `begin; \ir ../fixtures/library_2000.sql`, then:
  - `select tests.make_user(1);`
  - `tests.eq('2,000 rows for the user', pg_temp.load_library_2000(tests.uid(1)), 2000)`
  - `tests.eq('noise users hold their own rows', (select count(*) from public.anime_user_lists where user_id <> tests.uid(1)::text) + (select count(*) from public.manga_user_lists where user_id <> tests.uid(1)::text), 100000::bigint)`
  - `tests.ok('an owner-scoped list read uses the (user_id, anime_id) unique index', pg_temp.plan_uses_index(format('select anime_id from public.anime_user_lists where user_id=%L', tests.uid(1)::text), '<name of the live unique index on (user_id, anime_id)>'))`. Read the exact index name from the fixture with `\di public.anime_user_lists*` first and pin it.
  - Negative control proving the positive check means something (a permanent part of the test, rolled back with the transaction; not a red step and not a temporary mutation): `alter table public.anime_user_lists drop constraint <that constraint>;` (rolled back with the transaction), then `tests.ok('without the index the same query is not reported as using it', not pg_temp.plan_uses_index(<same query>, '<same index>'))`.
  - W9's 107/108 use this fixture and the same pair: the positive assertion, then drop the index and assert false. W2 (110), W4 (105), W6 (111) and W10 (109) build their own catalogue-scale data in the `102_load_hotpaths.sql` style and assert index use on the EXPLAIN text directly.
  - `rollback;`
- [ ] Run `scripts/db/run_local_db_tests.sh --only 112_library_2000`. Expected FAIL: `psql: … library_2000.sql: No such file or directory`.
- [ ] Implement the fixture.
- [ ] Run again. Expected: `TESTS : 1 test files, 4 assertions passed`. If the positive plan check picks a seq scan at this size, fix the fixture's selectivity or statistics (`analyze`). Never use `enable_seqscan=off`, which would prove nothing.
- [ ] Commit: `git add supabase/tests/fixtures/library_2000.sql supabase/tests/rls/112_library_2000_fixture.sql`; message `F3: shared 2,000-title library fixture and plan-uses-index helper for SQL plan checks`.

### Task F4: Docs, memory, verification and evidence

**Files:** `CURRENT_APP_STATE.md`, `CURRENT_APP_STATE_PLAIN.md`, `IMPLEMENTATION_PLAN_Variation1.md`, `CLAUDE.md` (file-map counts, gate list, flag list), `~/.claude/projects/-Users-max-Kuro-Anime-App/memory/MEMORY.md`, `docs/tracker-gaps-2026-11/foundation/EVIDENCE.md`, and `docs/tracker-gaps-2026-11/acceptance/F2.json` + `acceptance/logs/F2-*.txt`.

Steps
- [ ] Rule 1 updates:
  - `CURRENT_APP_STATE.md`: describe the F1 gate (two entries) and the `--accepted` mode with its record schema, F2 (`PartialDate`, `LibraryEdit` v2, the fill rule behind `library_date_autofill_v1` at 0 %, always-selected columns, no migration, the widened bare-plan rule) and F3 (profile registry, separate absolute-rate lane, report v2, `--qualify`, `tracker-gaps-combined`, `status-with-date-fill`); append to the Change Log. Add `library_date_autofill_v1` (0 %) to the feature-flag list in `CLAUDE.md` and `CURRENT_APP_STATE.md`.
  - `CURRENT_APP_STATE_PLAIN.md`: the same in plain English, with a Change Log entry.
  - `IMPLEMENTATION_PLAN_Variation1.md`: tracker-gaps F1–F3 status.
  - Update the inventory sentences the docs gate checks (`**Current repo inventory:** <n> app Swift files…`, `### iOS app — <n> Swift files in \`Kuro/\``, package Swift count) to the new counts: +1 app file (`PartialDatePicker.swift`), +3 package files (`PartialDate.swift`, `PartialDateTests.swift`, `LibraryEditV2Tests.swift`) and +1 KuroTests file (`DateFillCredentialLeaseTests.swift`, F2.3); F2.5 adds no Swift file. Run `python3 scripts/quality-gates/check_docs_current_state.py` and expect `PASS`.
- [ ] Rule 2: in MEMORY.md, record:
  - the new files;
  - the gotchas: `@ui:` tags must name the full `test…` XCTest method; resolution findings count only for features in `bdd_landed.txt`; "resolved" ≠ "accepted" (`--accepted <WS>` needs a record for HEAD; commit docs before running the tests that the record cites, then commit only the record); profile RPCs are opt-in until approved; profiles never `require` `backend_workload.js` (use `core`); `weight` is retired, profiles declare `ratePerSecond` and never touch the base mix; only `--qualify` runs are release evidence; dates are always selected; Undo bypasses the fill; the fill is off unless `library_date_autofill_v1` is on; a plan with a date or repeat count is not a bare plan;
  - the counts.
- [ ] Full verification (expected outputs):
  - `SKIP_IOS_BUILD=1 SKIP_IOS_TEST=1 scripts/quality-gates/run_all.sh` → no FAIL. `bdd-selftest PASS`, `bdd-traceability WARN`. The local-db row is PASS or BLOCKED (exit 4 is the documented fixture state).
  - `xcodebuild -project Kuro.xcodeproj -scheme Kuro -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests` → `** TEST SUCCEEDED **`.
  - A build-warning count of unique Kuro-side warnings ≤ 60 (same counting method as the 2026-10-31 baseline).
  - `scripts/quality-gates/check_architecture.sh`, `check_navigation.sh` and `check_branded_states.sh` → 0 offenders.
  - `bash scripts/quality-gates/check_bdd_traceability.sh` → summary line recorded; `0 tag errors` expected on the current feature files.
  - `cd Packages/KuroModules && swift test` → all pass.
  - `scripts/db/run_local_db_tests.sh` → `TESTS … PASS (executed tests only)`.
  - `bash scripts/quality-gates/test_load_profiles.sh` (`node --test scripts/load/*.test.js scripts/load/profiles/*.test.js`) → all pass.
- [ ] Write `docs/tracker-gaps-2026-11/foundation/EVIDENCE.md`, containing:
  - the red and green lines of each traced test;
  - the traceability baseline summary;
  - the frozen `chooseKind` digest;
  - a link to `F2-no-migration.md`;
  - the expected `--accepted F2` result below (stated in advance, so nothing outside the acceptance folder changes after the record).
- [ ] Commit: `git add CURRENT_APP_STATE.md CURRENT_APP_STATE_PLAIN.md IMPLEMENTATION_PLAN_Variation1.md CLAUDE.md docs/tracker-gaps-2026-11/foundation/EVIDENCE.md`; message `Docs: tracker-gaps foundation (F1 gate, F2 Library contract v2, F3 load profiles)`. Memory is outside the repository and is not staged.
- [ ] F2 acceptance record (after the docs commit, so the tested commit is HEAD): run every command that an F2 scenario's tag names at HEAD, saving each output to `docs/tracker-gaps-2026-11/acceptance/logs/F2-<run id>.txt`:
  - `cd Packages/KuroModules && swift test --filter "LibraryEditV2Tests|PartialDateTests"` (layer `pkg`, context `local`);
  - `xcodebuild … -destination 'platform=iOS Simulator,id=7FC4B58A-430C-457D-A017-6B0095723F3F' test -only-testing:KuroTests/FirstRunLaneTests` (layer `swift`, context `simulator` with that UUID).
  Start from `python3 scripts/quality-gates/check_bdd_traceability.py --record-template F2 > docs/tracker-gaps-2026-11/acceptance/F2.json`, fill `runs` and set each scenario's `result` from its run. The load scenario `Status changes with a date fill stay within budget` stays `blocked` with `unresolvedGates: ["owner-approved qualification run (--qualify --workload=tracker-gaps-combined), D-H"]`.
- [ ] Run `python3 scripts/quality-gates/check_bdd_traceability.py --accepted F2; echo "exit=$?"`. Expected: `NOT accepted F2: 5/6 pass`, one finding `not accepted: blocked` for the load scenario, `exit=1`. F2 is "resolved, not accepted" until the qualification run. Do not edit `EVIDENCE.md` or any file outside the acceptance folder after this point (that would make the record stale); `EVIDENCE.md` states this expected result in advance.
- [ ] Commit only the record: `git add docs/tracker-gaps-2026-11/acceptance/F2.json docs/tracker-gaps-2026-11/acceptance/logs/`; message `F2: acceptance record (resolved; load qualification pending)`. Re-run `--accepted F2`: same result (the commit touched only the acceptance folder).
