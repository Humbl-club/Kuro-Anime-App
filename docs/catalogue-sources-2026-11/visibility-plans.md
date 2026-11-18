# list_only visibility: plans against budgets (catalogue Task 15b Step 4)

What this records, and what it does not. The predicate added to each reader is a plain comparison
`<alias>.catalogue_visibility = 'visible'` on a `text not null default 'visible'` column. Today every row is `visible`, so
the predicate is non-selective (selectivity 1) and changes no row count. The qualified budgets are Browse/Search <= 750 ms,
Discover <= 1,500 ms (AGENTS.md / spec section 4 item 3).

## Local evidence (disposable DB fixture, not production)

- First attempt used a SQL function `catalogue_is_visible(text)` as the predicate. The existing plan check
  `supabase/tests/rls/104_discover_newly_added_base.sql` ("newly added uses idx_anime_load_created_v1 without a Sort node")
  FAILED with it: a function call is opaque to the planner. It was replaced by the plain comparison and 104 passes
  again (run 2026-11-18: 104, 105, 106, 85 and 125 pass together).
- `105_search_staged` and `106_search_titles_topn` (search plan checks) pass with the predicate in place.

## Index decision

No partial index is added. A partial index `where catalogue_visibility = 'visible'` would only pay once a large share of
rows is `list_only`; until then it duplicates the existing created_at/popularity indexes for no plan gain. Revisit with a
production plan once the identity group is switched and the real `list_only` share is known.

## Still required before apply (not done, no production access)

- `EXPLAIN (ANALYZE, BUFFERS)` of `browse_*_page`, `search_*_page` and the Discover rails on a production-shaped copy
  (about 21,900 anime / 41,900 manga), with and without `list_only` rows, against the budgets above.
- The `catalogue_visibility` column add is a constant-default add (no table rewrite on PostgreSQL 11+); the migration sets
  `lock_timeout = 3s`. Both the add and the 18 reader `CREATE OR REPLACE FUNCTION` statements take brief catalog locks.
