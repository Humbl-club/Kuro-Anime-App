# W2 export: 2,000-title baseline

Test: `KuroTests/LibraryExportFlowTests/twoThousandTitleExportBaseline` (2,000 anime entries, signed-in
account, identities already cached by a first untimed JSON export, so no lookup batch is in the timed
window). Timed: `ContinuousClock.measure` around `LibraryExportService.export(_:)` for each format
(build in the service's off-main task, write with complete file protection into a temporary directory).

Environment: iOS Simulator "Kuro-Lane-W2", iPhone 17 Pro, iOS 26.2, created for this run (not the shared
owner device), `-parallel-testing-enabled NO`, run 2026-11-18, Mac host (a simulator, not a device).

| format | run 1 (s) | run 2 (s) | run 3 (s) | median (s) |
|---|---|---|---|---|
| MyAnimeList XML | 0.0368 | 0.0383 | 0.0320 | 0.0368 |
| CSV | 0.0344 | 0.0323 | 0.0313 | 0.0323 |
| JSON | 0.0841 | 0.0643 | 0.0625 | 0.0643 |

The test asserts only a 10 s sanity ceiling. Proposed gate for owner confirmation (spec): <= 2 s per
format at 2,000 titles. The simulator medians are about 30 to 60 times under that. Do not tighten the
assertion until the owner confirms the gate and a device number exists.

Not measured here: the identity lookup itself (4 sequential batches of 500 ids for 2,000 anime; network
time is outside this baseline and is the subject of the `export-mal-id-lookup` load profile), a device
run, and a library with tags and lists (the baseline passes none).
