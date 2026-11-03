-- 84_character_voice_actors_v1.sql
-- Prepared 20261103100000_character_voice_actors_v1.sql (NOT deployed): the voice-actor link
-- table (public read, no client writes, cascades) and the three SECURITY INVOKER read RPCs
-- (anime_cast_v1, character_voice_actors_v1, staff_voice_roles_v1): role order, primary voice
-- actor per language, characters without a voice actor kept, adult anime excluded from the
-- person/character readers, typed errors.
-- The catalogue tables are prerequisites; every object the migration adds is under test.
-- @requires table public.anime
-- @requires table public.characters
-- @requires table public.staff
-- @requires table public.anime_characters
\set ON_ERROR_STOP on
\o /dev/null
\set as_service 'select tests.reset(); select set_config(''request.jwt.claims'', ''{"role":"service_role"}'', true); set local role service_role;'
begin;

-- ---- 0. posture ---------------------------------------------------------------
select tests.ok('character_voice_actors exists with RLS on',
  coalesce((select relrowsecurity from pg_class where oid = to_regclass('public.character_voice_actors')), false));
select tests.ok('anon and authenticated may SELECT, never INSERT/UPDATE/DELETE/TRUNCATE',
  has_table_privilege('anon', 'public.character_voice_actors', 'select')
  and has_table_privilege('authenticated', 'public.character_voice_actors', 'select')
  and not has_table_privilege('anon', 'public.character_voice_actors', 'insert')
  and not has_table_privilege('authenticated', 'public.character_voice_actors', 'insert')
  and not has_table_privilege('authenticated', 'public.character_voice_actors', 'update')
  and not has_table_privilege('authenticated', 'public.character_voice_actors', 'delete')
  and not has_table_privilege('authenticated', 'public.character_voice_actors', 'truncate')
  and has_table_privilege('service_role', 'public.character_voice_actors', 'insert'));
select tests.eq('the three readers are SECURITY INVOKER with search_path = public, extensions',
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('anime_cast_v1', 'character_voice_actors_v1', 'staff_voice_roles_v1')
      and not p.prosecdef and p.proconfig @> array['search_path=public, extensions']), 3::bigint);
select tests.ok('anon and authenticated may execute the readers',
  has_function_privilege('anon', 'public.anime_cast_v1(integer,text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.anime_cast_v1(integer,text,integer)', 'execute')
  and has_function_privilege('anon', 'public.character_voice_actors_v1(integer,text)', 'execute')
  and has_function_privilege('anon', 'public.staff_voice_roles_v1(integer,integer)', 'execute'));
select tests.ok('staff_id and character_id are indexed',
  exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'character_voice_actors_staff_idx')
  and exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'character_voice_actors_character_idx'));

-- ---- seed (superuser) ------------------------------------------------------------
insert into public.anime (id, title_romaji, cover_image_large, is_adult, popularity) values
  (840001, 'Cast Show', 'https://img.invalid/840001.jpg', false, 500),
  (840002, 'Adult Show', 'https://img.invalid/840002.jpg', true, 900),
  (840003, 'Sequel Show', 'https://img.invalid/840003.jpg', false, 100);
insert into public.characters (id, anilist_id, name_full, name_native) values
  (840101, 8401010, 'Main Hero', 'ヒーロー'),
  (840102, 8401020, 'Side Friend', null),
  (840103, 8401030, 'Quiet Extra', null);
insert into public.staff (id, anilist_id, name_full, name_native, image_large) values
  (840201, 8402010, 'Primary Voice', '主役', 'https://img.invalid/s1.jpg'),
  (840202, 8402020, 'Second Voice', null, null),
  (840203, 8402030, 'English Voice', null, null),
  (840204, 8402040, 'Adult Only Voice', null, null);
-- insertion order: the extra first, so role order (not import order) must put MAIN first
insert into public.anime_characters (anime_id, character_id, role) values
  (840001, 840103, 'BACKGROUND'),
  (840001, 840102, 'SUPPORTING'),
  (840001, 840101, 'MAIN'),
  (840003, 840101, 'MAIN'),
  (840002, 840101, 'MAIN');

-- ---- 1. client writes are refused ------------------------------------------------
select tests.as_user(tests.make_user(841));
select tests.denied('authenticated cannot insert voice-actor rows',
  $q$insert into public.character_voice_actors (anime_id, character_id, staff_id) values (840001, 840101, 840201)$q$);
select tests.denied('authenticated cannot delete voice-actor rows',
  $q$delete from public.character_voice_actors$q$);
select tests.as_anon();
select tests.denied('anon cannot insert voice-actor rows',
  $q$insert into public.character_voice_actors (anime_id, character_id, staff_id) values (840001, 840101, 840201)$q$);

-- ---- 2. the service role writes (as bulk-import-anime does) ----------------------
:as_service
insert into public.character_voice_actors (anime_id, character_id, staff_id, language, sort_order) values
  (840001, 840101, 840202, 'JAPANESE', 1),
  (840001, 840101, 840201, 'JAPANESE', 0),
  (840001, 840101, 840203, 'ENGLISH', 0),
  (840001, 840102, 840202, 'JAPANESE', 0),
  (840003, 840101, 840201, 'JAPANESE', 0),
  (840002, 840101, 840204, 'JAPANESE', 0);
select tests.reset();
select tests.raises('language must be an AniList StaffLanguage token',
  $q$insert into public.character_voice_actors (anime_id, character_id, staff_id, language) values (840001, 840103, 840201, 'japanese; drop')$q$,
  '%character_voice_actors_language_check%');

-- ---- 3. anime_cast_v1 ------------------------------------------------------------
select tests.as_anon();
select tests.eq('cast: MAIN, SUPPORTING, other; every character kept; primary JP voice actor (sort 0)',
  (select string_agg(character_name_full || '=' || coalesce(staff_name_full, '-'), ',')
     from public.anime_cast_v1(840001)),
  'Main Hero=Primary Voice,Side Friend=Second Voice,Quiet Extra=-');
select tests.eq('cast: ENGLISH picks the English voice actor only',
  (select string_agg(character_name_full || '=' || coalesce(staff_name_full, '-'), ',')
     from public.anime_cast_v1(840001, 'english')),
  'Main Hero=English Voice,Side Friend=-,Quiet Extra=-');
select tests.eq('cast: limit is honoured', (select count(*) from public.anime_cast_v1(840001, 'JAPANESE', 1)), 1::bigint);
select tests.eq('cast: roles and ids come back',
  (select string_agg(role || '/' || character_anilist_id || '/' || coalesce(staff_anilist_id::text, '-') || '/' || coalesce(language, '-'), ',')
     from public.anime_cast_v1(840001)),
  'MAIN/8401010/8402010/JAPANESE,SUPPORTING/8401020/8402020/JAPANESE,BACKGROUND/8401030/-/-');
select tests.eq('cast: an anime without characters is empty', (select count(*) from public.anime_cast_v1(999999)), 0::bigint);
select tests.raises('cast: invalid id raises INVALID_MEDIA_ID', $q$select * from public.anime_cast_v1(0)$q$, 'INVALID_MEDIA_ID:%');
select tests.raises('cast: invalid language raises INVALID_LANGUAGE',
  $q$select * from public.anime_cast_v1(840001, 'x')$q$, 'INVALID_LANGUAGE:%');

-- ---- 4. character_voice_actors_v1 ------------------------------------------------
select tests.eq('character: primary first, both JP voices, adult-only role hidden',
  (select string_agg(name_full || ':' || array_to_string(anime_ids, '+'), ',')
     from public.character_voice_actors_v1(840101)),
  'Primary Voice:840001+840003,Second Voice:840001');
select tests.eq('character: ENGLISH', (select string_agg(name_full, ',') from public.character_voice_actors_v1(840101, 'ENGLISH')),
  'English Voice');
select tests.eq('character: none stored -> empty', (select count(*) from public.character_voice_actors_v1(840103)), 0::bigint);

-- ---- 5. staff_voice_roles_v1 -----------------------------------------------------
select tests.eq('staff: roles across anime, most popular first',
  (select string_agg(character_name_full || '@' || title_romaji || '/' || role, ',')
     from public.staff_voice_roles_v1(840201)),
  'Main Hero@Cast Show/MAIN,Main Hero@Sequel Show/MAIN');
select tests.eq('staff: a person voicing only in adult anime has no visible roles',
  (select count(*) from public.staff_voice_roles_v1(840204)), 0::bigint);
select tests.eq('staff: language is reported',
  (select string_agg(distinct language, ',') from public.staff_voice_roles_v1(840203)), 'ENGLISH');
select tests.raises('staff: invalid id raises INVALID_MEDIA_ID', $q$select * from public.staff_voice_roles_v1(-1)$q$, 'INVALID_MEDIA_ID:%');
select tests.reset();

-- ---- 6. cascades -------------------------------------------------------------------
delete from public.staff where id = 840202;
select tests.eq('deleting a person removes their voice-actor rows',
  (select count(*) from public.character_voice_actors where staff_id = 840202), 0::bigint);
delete from public.anime where id = 840003;
select tests.eq('deleting an anime removes its voice-actor rows',
  (select count(*) from public.character_voice_actors where anime_id = 840003), 0::bigint);

select tests.reset();
rollback;
