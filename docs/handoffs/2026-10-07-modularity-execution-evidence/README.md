# Modularity repairs — 7 October 2026

Owner requested execution with proportionate checks. See [active execution note](../../plans/2026-10-07-modularity-production-execution.md). The original architecture/register remains in scope; neither full completion nor production release is claimed.

## Implemented

- Retrieval cache version rag-v2 includes ANIME/MANGA/BOTH and never caches RPC errors/throws/malformed results. Recommendation rejects wrong-medium seeds. No cache purge/schema change or feature enablement.
- Exact account-deletion barrier errors map to terminal 403 in Apply/Undo and the Swift translator; other errors retain existing behavior.
- Live checkers use exact project origin, genuine Apply/Undo journal rows, strict 42501, real correlated Realtime activity/membership/removal delivery, bounded requests/channels and explicit cleanup status.
- The existing native multi-user journey now dispatches real ImportsService requests, simulates effects only at the server boundary and exercises real ClubsStore duplicate classification. No additional screen suite.
- Focused runners use a real available simulator and verify selected methods executed; default incomplete exit4, explicit developer partial mode remains available. Distinct method paths are not dynamic parameter counts.
- PostgREST Date cursors now encode fractional UTC Z through a shared production/test encoder; Auth/decoding unchanged and prior millisecond precision retained.
- Dashboard and six installer defaults use the established root resolver; applicable installed settings remain preserved. No installer/job executed.

## Evidence

- Retrieval/recommendation affected suites: 16 passed, 0 failed (implementation run). Independent focused cache/adapter review: 8 passed.
- Apply/Undo suites: 32 passed, 0 failed; independent new barrier cases: 2 passed.
- Actual-script offline checker suite: 12 passed, 0 failed; no service proof inferred from fakes.
- Native multi-user owner journey: 1 passed, 0 failed, confirmed in /private/tmp/kuro-native-owner-journey-oct07.xcresult. This is owner/transport fixture proof, not live RLS or screen walks.
- Fresh live journal probe: PASS; owner/outsider reads, all six table writes denied42501, actual Apply/Undo and both created accounts deleted with GoTrue rejection. Sanitized [report](journal-live.json).
- Native deletion-terminal contract: 1 passed, 0 failed, 0 skipped; exact barrier is terminal and another 403 remains uncertain. Structured result: /private/tmp/kuro-deletion-terminal-oct07-selected.xcresult. The earlier selector executed zero tests and was not counted; the corrected selector executed this test. An earlier concurrent Home/detail compilation mismatch was resolved by its owning lane.
- Cursor owner/SDK contracts: 2 passed, 0 failed, 0 skipped; [structured result](cursor-native-summary.json). Independent review accepted.
- Operational defaults: 13 offline checks passed; independent review accepted; six shell and three Node syntax checks clean.
- Register triage: 11 existing focused Deno tests passed, including 107 parser intended cases, 67 router intended cases and actual-handler alias roundtrip. F27/F28/F29/F31 were stale OPEN entries. Existing no-backfill/no-cron owner locks are accepted residuals.
- Current manifest covers 185 Swift files (134 app, 20 package including manifests/tests, 28 unit-test and 3 UI-test files); file coverage does not establish all remaining semantic/dependency gates.
- Source changes reviewed independently; selected source [digests](source-sha256.json) identify this slice, not every changing unrelated file. The source snapshot is not a frozen whole release candidate.

## Remaining release prerequisites

Supabase CLI has no access token / no callable MCP in this session. Public app API access works for scoped disposable tests, but deployment/version inspection is blocked. Service-role cleanup verification access is absent; do not create fresh Realtime test clubs without a complete cleanup path. The configured App Store Connect key file is absent. No function/migration deployment, App Store upload or flag activation by this initiative.

Separately changing Home/series files must stay isolated behind their product flags and independent review. Preserve their work. Remaining register findings and architecture/native qualification are not silently closed by these repairs.

## Status meanings and next executable boundary

`LOCALLY-ACCEPTED` records repaired source plus focused independent acceptance; deployment or screen/service qualifications in the same row remain open. `LIVE-PASS` here is the named bounded live contract only. The original completion register is retained, not replaced by a repair-only checklist.

Still-open local architecture items include shared model/RPC coupling, in-app boundary enforcement and private presentation workflow ownership/waiver evidence (F53/F54/F55/F56). Account-listener initial reconciliation (F84), representative mounted/native journeys and request/subscription baselines remain separate qualifications. These are not hidden by missing deployment access or reclassified as passed.

Next hosted action needs Supabase CLI login/project-scoped MCP for exact deployed inspection and compatible deployment. Fresh club probes additionally need an administrative cleanup-verification path. Native distribution needs the configured signing/upload credential, and a release candidate must isolate the separately changing Home/series work. No broad rerun or gate waiver is required merely because the prior checklist was large.
