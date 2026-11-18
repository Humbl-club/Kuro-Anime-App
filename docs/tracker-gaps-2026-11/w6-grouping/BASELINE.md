# W6 grouping baseline (2026-11-18)

Test: `SeriesListGroupingTests/groupingTwoThousandEntriesWithinBudget` (2,000 anime entries, 1,200 with reviewed
membership in 400 series of 3 seasons; 1 warm-up, 7 timed runs, median).

Host (Apple silicon Mac, macOS 27.0.1, `swift test -c release`), 5 runs, median ms:
2.692, 2.739, 2.646, 2.827, 2.672 (median of medians 2.692 ms).

Simulator: NOT measured. The plan names simulator 7FC4B58A-..., which this lane must not use; the lane's own
simulator runs the debug KuroTests only. A simulator/device release baseline remains open.

Gate: host median is far below 25 ms, so `proposedBudget` stays 50 ms (still "proposed, confirm after a
simulator baseline").

Non-vacuity check: with `proposedBudget = .microseconds(1)` the release run fails with
`Expectation failed: median <= SeriesListGrouping.proposedBudget`; reverted (git diff of the source is clean).
This test was added after the rule existed, so there is no honest red.
