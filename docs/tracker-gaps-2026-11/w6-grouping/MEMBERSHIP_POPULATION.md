# W6 reviewed-membership population: options for owner decision D-G (2026-11-18)

Status: DECISION OPEN. Nothing here populates, publishes or applies anything. W6 ships dark behind
`collection_series_grouping_v1` (0 %) and is visually inert until reviewed membership exists.

## Evidence that membership is empty (repository evidence; production was not queried)
- `docs/overnight-2026-11-01/understand/product-surfaces.md` section 1.1 and `schema.md` section 4: `series`,
  `series_sections`, `series_entry_spans`, `mapping_revisions`, `mapping_revision_spans` are 8 kB heaps.
- `docs/overnight-2026-11-01/REPORT.md`: "Series grouping has no producer".
- `docs/overnight-2026-11-01/understand/CRITIC.md`: nothing outside SQL calls `publish_mapping_revision`.
- Fresh check needed before any publish: read-only `select count(*) from series where continuity='verified'`.

## What counts as reviewed (what the client reads)
`series.continuity = 'verified'` AND `series.grouping_state = 'approved'` AND `series_sections.state = 'approved'`
AND series medium = span medium. Only `publish_mapping_revision(uuid)` (service role) produces that. A `series` row
inserted with defaults is `approved` but `singleton` and never counts. Pinned by
`supabase/tests/rls/111_series_membership_read.sql` and `SeriesMembershipReaderTests`.
`media_franchise_components` / `media_franchise_ids_v1` (automatic relation components) are NOT membership.

## Option (a): owner-reviewed list
Candidates are proposed offline from same-medium AniList SEQUEL/PREQUEL chains; the owner marks rows approved and
fills the ordinal column (never taken from position or calendar season). Recommended for the first ~50 most-tracked
multi-season series. Needs the offline proposal tool (06-grouping Task 7 Steps 3-4, not built yet: it waits for D-G).

## Option (b): an explicitly approved rule
The rule is written out word for word by the owner. Its outputs still land as `proposed` revisions and are published
one series at a time with `reviewer = 'rule:<id> approved by <owner>'`.

## Risks common to both
- Republish risk (`docs/handoffs/2026-10-07-home-series-evidence/INDEPENDENT_REVIEW.md` line 159): a republish nulls
  section-scoped data, so each series is published once.
- Publishing is NOT gated by `collection_series_grouping_v1`: `home_bundle_v1`, `series_detail_bundle_v1`,
  `home_events_page_v1`, `home_pending_page_v1`, `collection_series_page_v1` read approved spans, so a publish changes
  Home/detail labels (`S<n>`, `series_id`) for every user who tracks a published title. Two tracked seasons of one
  published series can share a `HomeItem.id` (`seriesId ?? "entry:<id>"`, `Kuro/Home/HomeContracts.swift`): check
  before the first publish (06-grouping Task 8 Step 2).
- Rollback: a new revision that drops the series' spans, published once. Needs owner approval.

## Owner steps left
1. Choose (a) or (b) (or approve only the Task 8 pilot at ~10 series).
2. Approve the all-users Home/detail effect of a publish.
3. Approve each SQL file by name and SHA-256 before an operator applies it with the service role.
4. Then (and only then) set `collection_series_grouping_v1` (override rows for TestFlight accounts first).
