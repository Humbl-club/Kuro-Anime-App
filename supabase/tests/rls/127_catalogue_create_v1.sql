-- 127_catalogue_create_v1.sql
-- Prepared 20261112100450_catalogue_create_v1.sql (NOT deployed): catalogue_create_title_v1, the transactional insert
-- behind `catalogue-intake create` (Task 15c, insert mode).
-- Covers: posture (plpgsql, search_path, service-only); a created title has anilist_id NULL, visibility 'visible',
-- an accepted link (id_match) and shadow values; only whitelisted columns are taken (id, anilist_id, popularity ignored);
-- a second call with the same key creates nothing and returns the same id (idempotent); a title is required; unknown
-- medium/source refused; other titles and user list rows are untouched; Kuro ids of existing rows do not change.
-- Fixture limits: not production; the concurrent-race branch is exercised through a pre-existing accepted link only.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

select tests.ok('the create function is plpgsql, invoker, with the fixed search_path',
  (select count(*) = 1 and bool_and(proconfig @> array['search_path=public, extensions']) and bool_and(not prosecdef)
          and bool_and(prolang = (select oid from pg_language where lanname = 'plpgsql'))
   from pg_proc where pronamespace = 'public'::regnamespace and proname = 'catalogue_create_title_v1'));
select tests.ok('EXECUTE only for service_role',
  not has_function_privilege('anon', 'public.catalogue_create_title_v1(text,jsonb,text,text,numeric,jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.catalogue_create_title_v1(text,jsonb,text,text,numeric,jsonb)', 'execute')
  and not has_function_privilege('public', 'public.catalogue_create_title_v1(text,jsonb,text,text,numeric,jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.catalogue_create_title_v1(text,jsonb,text,text,numeric,jsonb)', 'execute'));

delete from public.manga_user_lists;
delete from catalogue_shadow_values;
delete from catalogue_id_links;
delete from public.anime;
delete from public.manga;
insert into public.anime (id, anilist_id, title_english, format) values (1270001, 1270001, 'Existing', 'TV');
select tests.make_user(1271);
insert into public.manga (id, anilist_id, title_english) values (1270101, 1270101, 'Listed');
insert into public.manga_user_lists (user_id, manga_id, list_type, progress) values (tests.uid(1271)::text, 1270101, 'READING', 1);

-- ---- insert ---------------------------------------------------------------------------
create temp table _r (n int, j jsonb);
insert into _r select 1, public.catalogue_create_title_v1('anime',
  '{"title_romaji":"New Show","format":"TV","start_date_year":2026,"start_date_month":11,"data_sources":["ann"],"id":424242,"anilist_id":5,"popularity":999999,"title_synonyms":["Nova"]}'::jsonb,
  'ann', '777', 1, '{"title_romaji":"New Show","format":"TV","start_date_year":2026,"data_sources":["ann"]}'::jsonb);
select tests.eq('created = true', (select (j ->> 'created')::boolean from _r where n = 1), true);
select tests.ok('the new row has anilist_id null, visibility visible, only whitelisted columns',
  exists (select 1 from public.anime a, _r where a.id = (_r.j ->> 'id')::int and _r.n = 1
          and a.anilist_id is null and a.catalogue_visibility = 'visible' and a.title_romaji = 'New Show'
          and a.format = 'TV' and a.start_date_year = 2026 and a.data_sources = array['ann']
          and a.title_synonyms = array['Nova'] and a.popularity is distinct from 999999 and a.id <> 424242));
select tests.eq('an accepted id_match link was written',
  (select count(*) from catalogue_id_links l, _r where l.kind = 'anime' and l.kuro_id = (_r.j ->> 'id')::int
     and l.source = 'ann' and l.source_key = '777' and l.status = 'accepted' and l.method = 'id_match'), 1::bigint);
select tests.eq('shadow values were written for the title',
  (select count(*) from catalogue_shadow_values s, _r where s.medium = 'anime' and s.media_id = (_r.j ->> 'id')::int), 4::bigint);

-- ---- idempotent ----------------------------------------------------------------------
insert into _r select 2, public.catalogue_create_title_v1('anime', '{"title_romaji":"New Show"}'::jsonb, 'ann', '777', 1, '{}'::jsonb);
select tests.eq('a second call creates nothing', (select (j ->> 'created')::boolean from _r where n = 2), false);
select tests.eq('and returns the same id', (select j ->> 'id' from _r where n = 2), (select j ->> 'id' from _r where n = 1));
select tests.eq('one new anime row exists', (select count(*) from public.anime), 2::bigint);

-- ---- manga, refusals, untouched rows --------------------------------------------------------
insert into _r select 3, public.catalogue_create_title_v1('manga',
  '{"title_english":"New Manga","format":"MANGA","volumes":3,"country_of_origin":"JP","is_adult":false}'::jsonb, 'mangaupdates', '4242', 1, '{"title_english":"New Manga"}'::jsonb);
select tests.eq('manga created with a link', (select count(*) from catalogue_id_links where kind = 'manga' and source = 'mangaupdates' and source_key = '4242' and status = 'accepted'), 1::bigint);
select tests.raises('a title is required', $q$select public.catalogue_create_title_v1('anime', '{"format":"TV"}'::jsonb, 'ann', '1', 1, '{}'::jsonb)$q$, '%a title is required%');
select tests.raises('an unknown medium is refused', $q$select public.catalogue_create_title_v1('book', '{"title_english":"x"}'::jsonb, 'ann', '1', 1, '{}'::jsonb)$q$, '%medium must be%');
select tests.raises('an unknown source is refused', $q$select public.catalogue_create_title_v1('anime', '{"title_english":"x"}'::jsonb, 'anilist', '1', 1, '{}'::jsonb)$q$, '%source%required%');
select tests.eq('the existing title and its Kuro id are unchanged', (select title_english from public.anime where id = 1270001), 'Existing');
select tests.eq('user list rows are untouched', (select count(*) from public.manga_user_lists where manga_id = 1270101), 1::bigint);
select tests.eq('a failed call left no half-written row', (select count(*) from public.anime), 2::bigint);
select tests.as_anon();
select tests.denied('anon cannot call it', $q$select public.catalogue_create_title_v1('anime', '{"title_english":"x"}'::jsonb, 'ann', '9', 1, '{}'::jsonb)$q$);
select tests.reset();
rollback;
