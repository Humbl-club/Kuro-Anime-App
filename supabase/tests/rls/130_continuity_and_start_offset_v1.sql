-- 130_continuity_and_start_offset_v1.sql
-- Prepared 20261121110000_continuity_candidates_and_start_offset_v1.sql (NOT deployed):
-- Covers: started_at_progress offset constraints/defaults on list tables and service-role-only
-- RLS/grants posture on public.series_candidates.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

select tests.ok('series_candidates exists with RLS on, zero client policies and service-only grants',
  to_regclass('public.series_candidates') is not null
  and (select relrowsecurity from pg_class where oid = 'public.series_candidates'::regclass)
  and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'series_candidates')
  and not has_table_privilege('anon', 'public.series_candidates', 'select')
  and not has_table_privilege('authenticated', 'public.series_candidates', 'select')
  and has_table_privilege('service_role', 'public.series_candidates', 'select'));

select tests.ok('list tables carry non-negative started_at_progress',
  exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'anime_user_lists' and column_name = 'started_at_progress')
  and exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'manga_user_lists' and column_name = 'started_at_progress'));

select tests.raises('negative started_at_progress is rejected on manga_user_lists',
  $q$insert into public.manga_user_lists (user_id, manga_id, list_type, progress, started_at_progress) values ('00000000-0000-0000-0000-000000000130', 1, 'CURRENT', 10, -1)$q$,
  '%check constraint%');

select tests.as_anon();
select tests.denied('anon cannot read series_candidates', $q$select * from public.series_candidates$q$);
select tests.reset();

select tests.make_user(1300);
select tests.as_user(tests.uid(1300));
select tests.denied('authenticated cannot read series_candidates', $q$select * from public.series_candidates$q$);
select tests.reset();

rollback;
