-- W10 Up next: library_up_next_v1 posture, row rules and the 2,000-title plan check.
-- Disposable local fixture only, never hosted.
-- @requires table public.media_relations
-- @requires table public.series_entry_spans
-- @requires table public.taste_signal_events
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
begin;

select tests.ok('library_up_next_v1 is SECURITY INVOKER, STABLE, plpgsql, search_path = public, extensions',
  (select not prosecdef and provolatile='s' and prolang=(select oid from pg_language where lanname='plpgsql')
          and proconfig @> array['search_path=public, extensions']
     from pg_proc where oid='public.library_up_next_v1(text,integer)'::regprocedure));
select tests.ok('authenticated may execute; anon and PUBLIC may not',
  has_function_privilege('authenticated','public.library_up_next_v1(text,integer)','execute')
  and not has_function_privilege('anon','public.library_up_next_v1(text,integer)','execute')
  and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.oid='public.library_up_next_v1(text,integer)'::regprocedure and a.grantee=0));
select tests.ok('invoker prerequisites: authenticated can read every relation the body reads',
  has_table_privilege('authenticated','public.media_relations','select')
  and has_table_privilege('authenticated','public.series','select')
  and has_table_privilege('authenticated','public.series_sections','select')
  and has_table_privilege('authenticated','public.series_entry_spans','select')
  and has_table_privilege('authenticated','public.taste_signal_events','select')
  and has_table_privilege('authenticated','public.anime_user_lists','select')
  and has_table_privilege('authenticated','public.manga_user_lists','select'));
select tests.ok('the body never reads media_franchise_components (no client grant: invoker trap)',
  (select prosrc not like '%media_franchise_components%' from pg_proc
    where oid='public.library_up_next_v1(text,integer)'::regprocedure));
select tests.raises('an unknown medium is a typed error in the MESSAGE',
  $$select * from public.library_up_next_v1('film', 30)$$, '%INVALID_MEDIUM%');

rollback;
