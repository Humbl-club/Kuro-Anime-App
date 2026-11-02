-- kuro:replay-no-transaction
-- 20261101010100_perf_drop_duplicate_indexes.sql
-- PREPARED, NOT DEPLOYED (2026-11-01 overnight production pass, lane 1 / SQL).
-- Deploying needs explicit owner approval.
--
-- HOW TO APPLY: DROP INDEX CONCURRENTLY cannot run inside a transaction block. Apply this
-- file with psql in autocommit mode, e.g.
--     psql "$APPROVED_DB_URL" -v ON_ERROR_STOP=1 -f 20261101010100_perf_drop_duplicate_indexes.sql
-- NOT with `psql -1`/`--single-transaction` and NOT through a runner that wraps each file in
-- a transaction (whether `supabase db push` does is for the owner to confirm before use; if
-- it does, run this file by hand and then record it with `supabase migration repair`).
-- Requires 20261101010000 (assert_exact_duplicate_index_v1). The first line marks the file
-- for scripts/db/replay_migrations.sh, which applies it without -1.
--
-- Each DROP is preceded (in the guard block below) by assert_exact_duplicate_index_v1,
-- which raises NOT_EXACT_DUPLICATE: unless the index is a plain, valid, non-unique,
-- non-partial, non-expression btree with exactly the same columns, opclasses, collations
-- and sort options as a valid PRIMARY KEY / UNIQUE index on the same table. Under
-- ON_ERROR_STOP the run halts before any drop when one pair fails. An index that is
-- already gone is skipped (IF EXISTS), so a partial run can be resumed.
--
-- Exact duplicates verified from the DDL (supabase/migrations/20260807000000_baseline_capture_v1.sql
-- section 4 vs the section 3 constraints; schema.md section 5.1), 22 indexes:
--   duplicate               survivor (constraint index)    baseline line (dup / constraint)
--   idx_anime_id            anime_pkey (id)                1753 / 562
--   idx_manga_id            manga_pkey (id)                1801 / 738
--   idx_characters_id       characters_pkey (id)           1790 / 661
--   idx_staff_id            staff_pkey (id)                1831 / 815
--   idx_authors_id          authors_pkey (id)              1786 / 639
--   idx_studios_id          studios_pkey (id)              1834 / 826
--   idx_tags_id             tags_pkey (id)                 1837 / 837
--   idx_volumes_id          volumes_pkey (id)              1840 / 848
--   idx_anime_anilist_id    anime_anilist_id_key           1749 / 859
--   idx_manga_anilist_id    manga_anilist_id_key           1798 / 1079
--   idx_characters_anilist_id  characters_anilist_id_key   1789 / 1002
--   idx_staff_anilist_id    staff_anilist_id_key           1830 / 1167
--   idx_authors_anilist_id  authors_anilist_id_key         1785 / 947
--   idx_studios_anilist_id  studios_anilist_id_key         1833 / 1200
--   idx_tags_anilist_id     tags_anilist_id_key            1836 / 1233
--   idx_anime_mal_id        anime_mal_id_key               1754 / 881
--   idx_manga_mal_id        manga_mal_id_key               1802 / 1101
--   idx_characters_mal_id   characters_mal_id_key          1791 / 1024
--   idx_staff_mal_id        staff_mal_id_key               1832 / 1189
--   idx_authors_mal_id      authors_mal_id_key             1787 / 969
--   idx_studios_mal_id      studios_mal_id_key             1835 / 1222
--   idx_tags_mal_id         tags_mal_id_key                1839 / 1244
-- No other migration or prepared file creates, drops or references these 22 names.
-- Not dropped (not proven duplicates): the join-table single-column indexes, idx_anime_status,
-- idx_external_links_media and the single-column sort indexes (prefix-subsumed only; schema.md
-- 5.2 says measure after the Browse rewrite), and the unique keys on always-null columns
-- (need a live count first, schema.md Q4).
--
-- Also here because it needs CONCURRENTLY: idx_catalog_safety_audit_state (18 MB, 0 scans in
-- 88 days, no reader of catalog_safety_audit by decision_state; schema.md 5.3).
-- idx_catalog_safety_audit_lookup is KEPT (prune_catalog_safety_audit_v1 uses it).

do $$
declare p record;
begin
  if to_regprocedure('public.assert_exact_duplicate_index_v1(text,text)') is null then
    raise exception 'MISSING_PREREQUISITE: apply 20261101010000_perf_hotpaths.sql first';
  end if;
  for p in select * from (values
    ('public.idx_anime_id', 'public.anime_pkey'),
    ('public.idx_manga_id', 'public.manga_pkey'),
    ('public.idx_characters_id', 'public.characters_pkey'),
    ('public.idx_staff_id', 'public.staff_pkey'),
    ('public.idx_authors_id', 'public.authors_pkey'),
    ('public.idx_studios_id', 'public.studios_pkey'),
    ('public.idx_tags_id', 'public.tags_pkey'),
    ('public.idx_volumes_id', 'public.volumes_pkey'),
    ('public.idx_anime_anilist_id', 'public.anime_anilist_id_key'),
    ('public.idx_manga_anilist_id', 'public.manga_anilist_id_key'),
    ('public.idx_characters_anilist_id', 'public.characters_anilist_id_key'),
    ('public.idx_staff_anilist_id', 'public.staff_anilist_id_key'),
    ('public.idx_authors_anilist_id', 'public.authors_anilist_id_key'),
    ('public.idx_studios_anilist_id', 'public.studios_anilist_id_key'),
    ('public.idx_tags_anilist_id', 'public.tags_anilist_id_key'),
    ('public.idx_anime_mal_id', 'public.anime_mal_id_key'),
    ('public.idx_manga_mal_id', 'public.manga_mal_id_key'),
    ('public.idx_characters_mal_id', 'public.characters_mal_id_key'),
    ('public.idx_staff_mal_id', 'public.staff_mal_id_key'),
    ('public.idx_authors_mal_id', 'public.authors_mal_id_key'),
    ('public.idx_studios_mal_id', 'public.studios_mal_id_key'),
    ('public.idx_tags_mal_id', 'public.tags_mal_id_key')
  ) as t(dup, survivor) loop
    perform public.assert_exact_duplicate_index_v1(p.dup, p.survivor);
  end loop;
end $$;

drop index concurrently if exists public.idx_anime_id;
drop index concurrently if exists public.idx_manga_id;
drop index concurrently if exists public.idx_characters_id;
drop index concurrently if exists public.idx_staff_id;
drop index concurrently if exists public.idx_authors_id;
drop index concurrently if exists public.idx_studios_id;
drop index concurrently if exists public.idx_tags_id;
drop index concurrently if exists public.idx_volumes_id;
drop index concurrently if exists public.idx_anime_anilist_id;
drop index concurrently if exists public.idx_manga_anilist_id;
drop index concurrently if exists public.idx_characters_anilist_id;
drop index concurrently if exists public.idx_staff_anilist_id;
drop index concurrently if exists public.idx_authors_anilist_id;
drop index concurrently if exists public.idx_studios_anilist_id;
drop index concurrently if exists public.idx_tags_anilist_id;
drop index concurrently if exists public.idx_anime_mal_id;
drop index concurrently if exists public.idx_manga_mal_id;
drop index concurrently if exists public.idx_characters_mal_id;
drop index concurrently if exists public.idx_staff_mal_id;
drop index concurrently if exists public.idx_authors_mal_id;
drop index concurrently if exists public.idx_studios_mal_id;
drop index concurrently if exists public.idx_tags_mal_id;

drop index concurrently if exists public.idx_catalog_safety_audit_state;
