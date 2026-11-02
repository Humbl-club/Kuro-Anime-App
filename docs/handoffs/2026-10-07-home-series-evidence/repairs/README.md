# Home repair verification — proof boundaries and reproduction

This is current repair evidence in a concurrently edited working tree. Read [REPAIR_LEDGER.md](../REPAIR_LEDGER.md) first. No hosted activity is authorized by these commands. Do not accept an Xcode license, remove IPC, stop another process or deploy to make a check pass.

## Preserved results

- `package-integrated-76-pass.log`: 12 Supabase, 57 Library and 7 Core tests PASS.
- `home-actual-drain-canonical-pass.log`: actual Home + Library + real SQLite PASS; includes 100 overlapping taps, uncertain-response retry, ACK successor, unloaded Library, account/lifecycle isolation and exact cursor wire format. Only presentation error text is stubbed.
- `anilist-stream-7-pass.log`: offline stream and fidelity checks PASS; not a real provider/account journey.
- `enrichment-worker-8-pass.log`: actual approved Pillow palette extraction plus worker contracts PASS. The inherited extractor emits a Pillow deprecation warning; it did not fail. No provider or hosted request.
- `club-disclosure-syntax-only.log`: empty log from exit-0 Swift syntax parsing; NOT a native test-suite pass.
- `native-build-license-blocked.log`: Xcode license blocker. No native build/test qualification.
- `sql94-historical-50-pass.log`: earlier candidate, 50 assertions PASS on an audited fixture with incomplete migration replay. Predates later producer/edition/privacy/serving changes.
- `home-drain-unordered-encoder-failure.log`: earlier harness compared unordered JSON byte serialization. Canonical sorted-key comparison corrected that harness-only assertion; failure retained. The passing run still compares the full immutable semantic request, not just final progress.
- `db/explain-resume-page-1m.txt`: representative earlier 1M-list/5,000-user-row candidate. Home ~1,222ms, detail ~0.023ms, Collection ~21.325ms. Current query has changed; neither that result nor the earlier weaker `explain-exact-1m.txt` proves current performance.
- `db/explain-resume-analyzed-1m.txt.harness.log`: PostgreSQL startup failed; there is no completed current EXPLAIN result.
- `source-and-evidence-snapshot.json`: source hashes captured after checks, alongside log hashes. NOT a frozen candidate or exact run-time source manifest. Shared owners continue editing.

SQL95 declares 46 assertions; SQL96 is a two-session regression specification. Neither was executed. Five new native disclosure test cases (one parameterized case runs twice) are syntax parsed only. Focused independent source acceptance is recorded in the ledger; full candidate review remains necessary.

## Re-run available local checks

Run from `/Users/max/Kuro-Anime-App`. Do not use old compiler build products after the toolchain changes. The package run uses its own scratch directory:

```bash
env DYLD_LIBRARY_PATH=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib \
  DYLD_FRAMEWORK_PATH=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks \
  CLANG_MODULE_CACHE_PATH=/private/tmp/kuro-repair-clang-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/kuro-repair-swift-cache \
  SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
  SWIFT_EXEC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc \
  CC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang \
  /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test \
  --disable-sandbox --package-path Packages/KuroModules \
  --scratch-path /private/tmp/kuro-repair-package-integrated

/opt/homebrew/bin/python3.13 scripts/test_home_repair_drain.py
/opt/homebrew/bin/deno test --allow-read supabase/functions/concierge-import-anilist/run_test.ts
```

Worker tests require Python with Pillow; the verified bundled interpreter is:

```bash
/Users/max/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/test_series_enrichment_worker.py
```

These pass logs belong to their recorded executions, not future source revisions. Re-run affected tests after integration changes, then record source pins before and after each check.

## Blocked follow-up — do not execute until environment is available

Max instructed leaving the Mac's shared-memory resources alone. Fresh PostgreSQL cannot start. Xcode's license also requires the user's acceptance. The commands below describe remaining proof; they were NOT run against the current candidate.

```bash
KURO_DB_START_ATTEMPTS=1 scripts/db/run_local_db_tests.sh \
  --only series_home_foundation,library_import_counts,import_session_receipt,series_fence_races,series_home_review_repairs,series_producers_disclosure,series_enrichment_backfill_races \
  --report-dir /private/tmp/kuro-home-current-sql

KURO_DB_START_ATTEMPTS=1 KURO_PYTHON=/opt/homebrew/bin/python3.13 \
  KURO_EXPLAIN_REPORT=/private/tmp/kuro-home-current-explain.txt \
  scripts/db/explain_series_inner_plans.sh

xcodebuild -scheme Kuro -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:KuroTests/ClubDisclosureRepairTests
```

Required additional proof: deterministic finish-with-themes versus catalogue deletion and same-URL material completion races; current native integration/visual/accessibility/haptics; final independent review; provider/account imports; bounded user-approved launch-envelope measurements; fresh authorized live service and exact installed release journeys. Do not call these optional merely because local checks passed.
