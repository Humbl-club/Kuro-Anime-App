-- 125_catalogue_visibility_v1.sql
-- Prepared 20261112100400_catalogue_visibility_v1.sql and 20261112100401_catalogue_visibility_discover_v1.sql
-- (NOT deployed): anime/manga.catalogue_visibility ('visible' | 'list_only'),
-- catalogue_apply_visibility_v1 (identity 'new': titles without an accepted link become list_only) and the
-- browse/search/Discover/rail/recommendation readers that hide list_only titles.
-- Covers: the columns and their check; the apply function (service-only, batched, reversible when identity goes
-- back); browse and search (anime and manga) run against a list_only fixture title and do not return it;
-- every filtered reader of the inventory (docs/catalogue-sources-2026-11/visibility-readers.md) carries the
-- predicate the generator added (source check: the fixture cannot run readers whose tables it lacks, e.g.
-- curated rails, realm membership); the list read, the detail/by-id read, the export identity lookup shape and
-- get_media_ladder still return the list_only title (Review Focus 5: unlinkedListTitleStaysReadable too).
-- Fixture limits: not production; plans and the matview-backed rails are not exercised here.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

-- ---- 1. columns, check, posture --------------------------------------------------------
select tests.ok('both tables have catalogue_visibility text not null default visible',
  (select count(*) = 2 and bool_and(a.attnotnull) and bool_and(a.atthasdef) and bool_and(a.atttypid = 'text'::regtype)
   from pg_attribute a where a.attrelid in ('public.anime'::regclass, 'public.manga'::regclass)
    and a.attname = 'catalogue_visibility' and not a.attisdropped));
select tests.raises('an unknown visibility value is rejected',
  $q$update public.anime set catalogue_visibility = 'hidden' where false or id = (select min(id) from public.anime)$q$, '%catalogue_visibility_check%')
  where exists (select 1 from public.anime);
select tests.ok('the apply function is service-only and plpgsql with the fixed search_path',
  (select count(*) = 1 and bool_and(proconfig @> array['search_path=public, extensions'])
          and bool_and(not has_function_privilege('anon', oid, 'execute'))
          and bool_and(not has_function_privilege('authenticated', oid, 'execute'))
          and bool_and(not has_function_privilege('public', oid, 'execute'))
          and bool_and(has_function_privilege('service_role', oid, 'execute'))
   from pg_proc where pronamespace = 'public'::regnamespace and proname = 'catalogue_apply_visibility_v1'));
select tests.ok('the predicate helpers set search_path and are callable by clients',
  (select count(*) = 2 and bool_and(proconfig @> array['search_path=public, extensions'])
          and bool_and(has_function_privilege('anon', oid, 'execute'))
   from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('catalogue_anime_visible', 'catalogue_manga_visible')));

-- ---- 2. fixture -----------------------------------------------------------------------
delete from public.manga_user_lists;
delete from catalogue_id_links;
delete from public.anime;
delete from public.manga;
update catalogue_cutover set mode = 'anilist';
insert into public.anime (id, anilist_id, title_english, title_romaji, format, status, popularity, is_adult, genres, cover_image_large) values
  (1250001, 1250001, 'Visible Anime Zorblax', 'Visible Anime Zorblax R', 'TV', 'FINISHED', 100, false, array['Action'], 'https://x/1.jpg'),
  (1250002, 1250002, 'Hidden Anime Zorblax',  'Hidden Anime Zorblax R',  'TV', 'FINISHED', 900, false, array['Action'], 'https://x/2.jpg');
insert into public.manga (id, anilist_id, title_english, title_romaji, format, status, popularity, is_adult, genres, cover_image_large) values
  (1250101, 1250101, 'Visible Manga Zorblax', 'Visible Manga Zorblax R', 'MANGA', 'FINISHED', 100, false, array['Action'], 'https://x/3.jpg'),
  (1250102, 1250102, 'Hidden Manga Zorblax',  'Hidden Manga Zorblax R',  'MANGA', 'FINISHED', 900, false, array['Action'], 'https://x/4.jpg');
insert into catalogue_id_links (kind, kuro_id, source, source_key, method, confidence, status, decided_at) values
  ('anime', 1250001, 'wikidata', 'Q1250001', 'wikidata', 1, 'accepted', now()),
  ('manga', 1250101, 'wikidata', 'Q1250101', 'wikidata', 1, 'accepted', now()),
  ('anime', 1250002, 'ann', '99', 'title_match', 0.8, 'proposed', null);
select tests.make_user(1251);
insert into public.manga_user_lists (user_id, manga_id, list_type, progress) values (tests.uid(1251)::text, 1250102, 'READING', 3);

-- ---- 3. apply: only once identity is new, reversible ---------------------------------------
select tests.eq('identity not new: nothing changes', public.catalogue_apply_visibility_v1('anime'), 0);
select tests.eq('all titles are still visible', (select count(*) from public.anime where catalogue_visibility = 'visible'), 2::bigint);
update catalogue_cutover set mode = 'new' where field_group = 'identity';
select tests.eq('identity new: the unlinked anime becomes list_only (a proposed link does not count)', public.catalogue_apply_visibility_v1('anime'), 1);
select tests.eq('the linked anime stays visible', (select catalogue_visibility from public.anime where id = 1250001), 'visible');
select tests.eq('the unlinked anime is list_only', (select catalogue_visibility from public.anime where id = 1250002), 'list_only');
select tests.eq('manga is separate: untouched until applied', (select count(*) from public.manga where catalogue_visibility = 'list_only'), 0::bigint);
select tests.eq('manga apply', public.catalogue_apply_visibility_v1('manga'), 1);
select tests.eq('a second apply changes nothing', public.catalogue_apply_visibility_v1('anime') + public.catalogue_apply_visibility_v1('manga'), 0);
select tests.raises('an unknown medium is refused', $q$select public.catalogue_apply_visibility_v1('book')$q$, '%medium must be%');

-- ---- 4. browse and search hide list_only titles ---------------------------------------------
select tests.ok('browse_anime_page hides the list_only anime and returns the visible one',
  (select array_agg(id order by id) from public.browse_anime_page(p_limit => 20)) = array[1250001]);
select tests.ok('browse_manga_page hides the list_only manga and returns the visible one',
  (select array_agg(id order by id) from public.browse_manga_page(p_limit => 20)) = array[1250101]);
select tests.ok('search_anime_page hides the list_only anime',
  (select array_agg(id order by id) from public.search_anime_page('Zorblax', 20)) = array[1250001]);
select tests.ok('search_manga_page hides the list_only manga',
  (select array_agg(id order by id) from public.search_manga_page('Zorblax', 20)) = array[1250101]);

-- ---- 5. unfiltered readers still return the list_only title -----------------------------------
select tests.as_anon();
select tests.eq('detail/by-id read (public table) still returns the list_only anime',
  (select count(*) from public.anime where id = 1250002), 1::bigint);
select tests.eq('export identity lookup shape still returns the list_only manga',
  (select count(*) from (select id, anilist_id, mal_id, title_english, title_romaji, title_native from public.manga where id in (1250102)) s), 1::bigint);
select tests.reset();
select tests.as_user(tests.uid(1251));
select tests.eq('unlinkedListTitleStaysReadable: the list row is still there and joins to the title',
  (select count(*) from public.manga_user_lists l join public.manga m on m.id = l.manga_id where l.manga_id = 1250102), 1::bigint);
select tests.eq('unlinkedListTitleStaysReadable: the stored title is intact',
  (select m.title_english from public.manga_user_lists l join public.manga m on m.id = l.manga_id where l.manga_id = 1250102), 'Hidden Manga Zorblax');
select tests.reset();

-- ---- 6. a title that gains a link comes back; identity back to anilist shows everything ----------------
insert into catalogue_id_links (kind, kuro_id, source, source_key, method, confidence, status, decided_at)
  values ('anime', 1250002, 'ann', '100', 'title_match', 0.95, 'accepted', now());
select tests.eq('a newly linked anime is shown again', public.catalogue_apply_visibility_v1('anime'), 1);
select tests.ok('and browse returns it', (select array_agg(id order by id) from public.browse_anime_page(p_limit => 20)) = array[1250001, 1250002]);
update catalogue_cutover set mode = 'anilist' where field_group = 'identity';
select tests.eq('identity back to anilist: every list_only title is visible again', public.catalogue_apply_visibility_v1('manga'), 1);
select tests.eq('no list_only title is left', (select count(*) from public.manga where catalogue_visibility = 'list_only'), 0::bigint);
select tests.eq('the batch limit is honoured', (select count(*) from (select public.catalogue_apply_visibility_v1('anime', 1)) s), 1::bigint);

-- ---- 7. every filtered reader carries the predicate (source check) -----------------------------------
create temp table _readers (name text, min_preds int);
insert into _readers values
  ('browse_anime_page', 1), ('browse_manga_page', 1), ('search_anime_page', 3), ('search_manga_page', 3),
  ('curated_rail_cards', 2), ('fetch_tonight_shelf', 2), ('fetch_daily_feature', 2), ('fetch_personalized_new_to_you', 2),
  ('fetch_realm_hidden_gem', 2), ('fetch_because_you_rail', 2), ('fetch_taste_deck_batch', 2),
  ('recommend_ids_similar_to_seeds', 2), ('_recommend_ids_similar_to_seeds_live', 2), ('media_similar_v1', 2),
  ('discover_bundle', 18), ('discover_section_page_v1', 4), ('discover_mood_v1', 4), ('_discover_page_v1', 2);
select tests.ok('every reader of the inventory exists, in one definition, and carries at least the predicates the generator added',
  not exists (
    select 1 from _readers r
    where (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = r.name) <> 1
       or (select regexp_count(p.prosrc, 'catalogue_visibility = ''visible''|catalogue_(anime|manga)_visible\(') from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname = r.name) < r.min_preds));
select tests.ok('the unfiltered readers do not carry the predicate (list, detail, export, import, ladder)',
  not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('collection_feed_page', 'home_bundle_v1', 'series_detail_bundle_v1', 'fetch_club_bundle', 'get_media_ladder')
    and p.prosrc like '%catalogue_visibility = ''visible''%'));
rollback;
