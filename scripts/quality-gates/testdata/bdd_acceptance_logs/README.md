# Captured log lines for the BDD acceptance tests

Each file holds lines that the matching `check_bdd_traceability.py --accepted` pattern must recognise.

| File | Origin |
|---|---|
| `pkg-swift-testing.log` | Real: `swift test --filter SupabaseLibraryBackendTests` in `Packages/KuroModules` (2026-11-18, exit 0), first 26 pass lines. Swift Testing prints the display label (`Test "label" passed`) when `@Test("label")` is set, and `Test name() passed` otherwise. |
| `swift-xcodebuild.log` | Real: lines from `docs/handoffs/2026-10-07-integrated-release-evidence/simulator-auth-repaired-pass.log` (`Test case 'Suite/name()' passed on '...'`). |
| `deno-test.log` | Real: first 8 lines of `deno test --no-prompt supabase/functions/concierge-apply/` (2026-11-18, exit 0), with ANSI colour codes kept. |
| `sql-local-db.log` | Produced with the exact printf format of `scripts/db/run_local_db_tests.sh` (the per-file PASS line). Not a capture of a DB run. |
| `ui-xctest.log` | Written by hand in the standard xcodebuild XCTest format; no real KuroUITests log was available (needs a simulator). Replace with a real capture when one exists. |
