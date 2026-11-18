-- SUPERSEDED by 20261112100500_anilist_id_private_v1.sql (2026-11-18). DO NOT APPLY. Intentionally a no-op.
--
-- This was backend latency step 1c (docs/plans/2026-11-09-backend-latency-plan.md): the Discover "Newly added" rails read the
-- base tables and the two snapshot matviews mv_anime_newly_added / mv_manga_newly_added are dropped. Its two parts now live elsewhere:
--   * the rail change: discover_bundle in 20261112100401_catalogue_visibility_discover_v1.sql (built on this file's body, with the
--     visibility filter);
--   * the matview drop and refresh_discover_matviews_v1() for the four remaining matviews: 20261112100500_anilist_id_private_v1.sql
--     (which also rebuilds those four without anilist_id).
-- The original body (a discover_bundle copy that would erase 100401's visibility filter) is in git history. Test 104 now targets 100500.
begin;
commit;
