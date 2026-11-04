-- 86_theme_links_apple_v1.sql
-- Prepared 20261103100200_theme_links_apple_v1.sql (NOT deployed; needs 20261101000000):
-- Apple match columns on theme_links, media_themes_v1 re-created with the same first ten
-- columns plus five trailing Apple columns, the match-key rule (a match made for another
-- title/artist is never served), and the service-role writer upsert_theme_apple_matches_v1
-- (authorization, all-or-nothing validation, Apple-host URLs only, confidence >= 0.8, stale
-- rows skipped, "checked, no match" clears).
-- theme_links (20261007040000, live) is a prerequisite; media_themes_v1 is the subject.
-- @requires table public.theme_links
-- @requires table public.anime
\set ON_ERROR_STOP on
\o /dev/null
\set as_service 'select tests.reset(); select set_config(''request.jwt.claims'', ''{"role":"service_role"}'', true); set local role service_role;'
begin;

-- ---- 0. posture ---------------------------------------------------------------
select tests.eq('media_themes_v1 keeps its first ten columns in order and adds five trailing Apple columns',
  (select array_to_string(proargnames[2:16], ',') from pg_proc where oid = 'public.media_themes_v1(integer)'::regprocedure),
  'kind,sequence,title,artist,episodes,version,is_spoiler,is_nsfw,source,source_url,apple_track_id,apple_artwork_url,apple_preview_url,apple_music_url,apple_match_confidence');
select tests.ok('media_themes_v1 stays SECURITY DEFINER with search_path = public, extensions; anon may execute',
  (select prosecdef and proconfig @> array['search_path=public, extensions'] from pg_proc
     where oid = 'public.media_themes_v1(integer)'::regprocedure)
  and has_function_privilege('anon', 'public.media_themes_v1(integer)', 'execute')
  and has_function_privilege('authenticated', 'public.media_themes_v1(integer)', 'execute'));
select tests.ok('writer and key helper: service role only',
  not has_function_privilege('anon', 'public.upsert_theme_apple_matches_v1(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'public.upsert_theme_apple_matches_v1(jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.upsert_theme_apple_matches_v1(jsonb)', 'execute')
  and not has_function_privilege('anon', 'public._theme_apple_key(text,text)', 'execute')
  and not has_function_privilege('authenticated', 'public._theme_apple_key(text,text)', 'execute'));
select tests.ok('writer is SECURITY DEFINER with search_path = public, extensions',
  (select prosecdef and proconfig @> array['search_path=public, extensions'] from pg_proc
     where oid = 'public.upsert_theme_apple_matches_v1(jsonb)'::regprocedure));
select tests.ok('theme_links keeps RLS on', (select relrowsecurity from pg_class where oid = 'public.theme_links'::regclass));

-- ---- seed (superuser) ------------------------------------------------------------
insert into public.anime (id, title_romaji) values (860001, 'Song Show');
insert into public.theme_links (id, anime_id, role, sequence_order, song_title, artist, match_state, source_identity, source) values
  ('86000000-0000-4000-8000-000000000001', 860001, 'op', 1, 'Gurenge', 'LiSA', 'search', 'animethemes:860001:1', 'animethemes'),
  ('86000000-0000-4000-8000-000000000002', 860001, 'ed', 1, 'from the edge', 'FictionJunction feat. LiSA', 'search', 'animethemes:860001:2', 'animethemes'),
  ('86000000-0000-4000-8000-000000000003', 860001, 'insert', 1, 'Kamado Tanjiro no Uta', null, 'search', 'animethemes:860001:3', 'animethemes');

-- ---- 1. clients cannot write ------------------------------------------------------
select tests.as_user(tests.make_user(861));
select tests.denied('authenticated cannot call the writer', $q$select public.upsert_theme_apple_matches_v1('[]'::jsonb)$q$);
select tests.eq('authenticated cannot set Apple columns through the table API (no UPDATE policy: 0 rows)',
  tests.affected($q$update public.theme_links set apple_track_id = 1 where anime_id = 860001$q$), 0::bigint);
select tests.as_anon();
select tests.denied('anon cannot call the writer', $q$select public.upsert_theme_apple_matches_v1('[]'::jsonb)$q$);
select tests.eq('before any match: Apple columns are null in media_themes_v1',
  (select count(*) from public.media_themes_v1(860001) where apple_track_id is not null), 0::bigint);
select tests.reset();

-- ---- 2. validation is all-or-nothing ---------------------------------------------
:as_service
select tests.raises('confidence below 0.8 raises LOW_CONFIDENCE',
  $q$select public.upsert_theme_apple_matches_v1(jsonb_build_array(jsonb_build_object(
      'theme_id', '86000000-0000-4000-8000-000000000001', 'expected_title', 'Gurenge', 'expected_artist', 'LiSA',
      'apple_track_id', 1488408568, 'confidence', 0.79, 'apple_music_url', 'https://music.apple.com/us/album/x?i=1')))$q$,
  'LOW_CONFIDENCE:%');
select tests.raises('a match without a confidence raises LOW_CONFIDENCE',
  $q$select public.upsert_theme_apple_matches_v1(jsonb_build_array(jsonb_build_object(
      'theme_id', '86000000-0000-4000-8000-000000000001', 'expected_title', 'Gurenge', 'expected_artist', 'LiSA',
      'apple_track_id', 1488408568, 'apple_music_url', 'https://music.apple.com/us/album/x?i=1')))$q$,
  'LOW_CONFIDENCE:%');
select tests.raises('a non-Apple music URL raises INVALID_APPLE_URL',
  $q$select public.upsert_theme_apple_matches_v1(jsonb_build_array(jsonb_build_object(
      'theme_id', '86000000-0000-4000-8000-000000000001', 'expected_title', 'Gurenge', 'expected_artist', 'LiSA',
      'apple_track_id', 1488408568, 'confidence', 0.95, 'apple_music_url', 'https://music.apple.com.evil.invalid/x')))$q$,
  'INVALID_APPLE_URL:%');
select tests.raises('an http artwork URL raises INVALID_APPLE_URL',
  $q$select public.upsert_theme_apple_matches_v1(jsonb_build_array(jsonb_build_object(
      'theme_id', '86000000-0000-4000-8000-000000000001', 'expected_title', 'Gurenge', 'expected_artist', 'LiSA',
      'apple_track_id', 1488408568, 'confidence', 0.95, 'apple_music_url', 'https://music.apple.com/us/album/x?i=1',
      'apple_artwork_url', 'http://is1-ssl.mzstatic.com/a.jpg')))$q$,
  'INVALID_APPLE_URL:%');
select tests.raises('a preview on another host raises INVALID_APPLE_URL',
  $q$select public.upsert_theme_apple_matches_v1(jsonb_build_array(jsonb_build_object(
      'theme_id', '86000000-0000-4000-8000-000000000001', 'expected_title', 'Gurenge', 'expected_artist', 'LiSA',
      'apple_track_id', 1488408568, 'confidence', 0.95, 'apple_music_url', 'https://music.apple.com/us/album/x?i=1',
      'apple_preview_url', 'https://cdn.invalid/preview.m4a')))$q$,
  'INVALID_APPLE_URL:%');
select tests.raises('Apple URLs without a track id are refused',
  $q$select public.upsert_theme_apple_matches_v1(jsonb_build_array(jsonb_build_object(
      'theme_id', '86000000-0000-4000-8000-000000000001', 'expected_title', 'Gurenge', 'expected_artist', 'LiSA',
      'apple_track_id', null, 'apple_music_url', 'https://music.apple.com/us/album/x?i=1')))$q$,
  'INVALID_ROW:%');
select tests.raises('one bad row fails the whole call (the good row is not written)',
  $q$select public.upsert_theme_apple_matches_v1(jsonb_build_array(
      jsonb_build_object('theme_id', '86000000-0000-4000-8000-000000000002', 'expected_title', 'from the edge',
        'expected_artist', 'FictionJunction feat. LiSA', 'apple_track_id', 1488408600, 'confidence', 0.9,
        'apple_music_url', 'https://music.apple.com/us/album/y?i=2'),
      jsonb_build_object('theme_id', 'not-a-uuid', 'expected_title', 'x', 'expected_artist', null)))$q$,
  'INVALID_THEME_ID:%');
select tests.reset();
select tests.eq('nothing was written by the failed calls',
  (select count(*) from public.theme_links where anime_id = 860001 and (apple_track_id is not null or apple_checked_at is not null)), 0::bigint);

-- ---- 3. a match, a no-match and a stale row ---------------------------------------
:as_service
select public.upsert_theme_apple_matches_v1(jsonb_build_array(
  jsonb_build_object('theme_id', '86000000-0000-4000-8000-000000000001', 'expected_title', 'Gurenge', 'expected_artist', 'LiSA',
    'apple_track_id', 1488408568, 'confidence', 0.97,
    'apple_artwork_url', 'https://is1-ssl.mzstatic.com/image/thumb/Music/a/100x100bb.jpg',
    'apple_preview_url', 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview/a.m4a',
    'apple_music_url', 'https://music.apple.com/jp/album/gurenge/1488408555?i=1488408568'),
  jsonb_build_object('theme_id', '86000000-0000-4000-8000-000000000003', 'expected_title', 'Kamado Tanjiro no Uta',
    'expected_artist', null, 'apple_track_id', null),
  jsonb_build_object('theme_id', '86000000-0000-4000-8000-000000000002', 'expected_title', 'from the edge (old)',
    'expected_artist', 'FictionJunction feat. LiSA', 'apple_track_id', 1488408600, 'confidence', 0.9,
    'apple_music_url', 'https://music.apple.com/us/album/y?i=2'),
  jsonb_build_object('theme_id', '86000000-0000-4000-8000-0000000000ff', 'expected_title', 'Gone', 'expected_artist', null)
)) as w1 \gset
select tests.reset();
select tests.eq('writer counts: one match, one checked no-match, two stale (changed title, unknown id)',
  :'w1'::jsonb, '{"matched":1,"cleared":1,"stale":2}'::jsonb);
select tests.eq('the no-match row is marked checked and carries no Apple data',
  (select (apple_checked_at is not null)::text || '/' || coalesce(apple_track_id::text, 'null')
     from public.theme_links where id = '86000000-0000-4000-8000-000000000003'), 'true/null');
select tests.eq('the stale row was not touched',
  (select (apple_checked_at is null and apple_track_id is null) from public.theme_links
     where id = '86000000-0000-4000-8000-000000000002'), true);

select tests.as_anon();
select tests.eq('media_themes_v1 serves the confident match as trailing columns',
  (select apple_track_id || '/' || apple_match_confidence || '/' || (apple_preview_url like 'https://audio-ssl.itunes.apple.com/%')
          || '/' || (apple_artwork_url like 'https://is1-ssl.mzstatic.com/%') || '/' || (apple_music_url like 'https://music.apple.com/%')
     from public.media_themes_v1(860001) where title = 'Gurenge'),
  '1488408568/0.97/true/true/true');
select tests.eq('the old ten columns are unchanged for the matched row',
  (select kind || sequence || '/' || title || '/' || artist || '/' || source from public.media_themes_v1(860001) where title = 'Gurenge'),
  'OP1/Gurenge/LiSA/animethemes');
select tests.reset();

-- ---- 4. a corrected title/artist never keeps the old match -----------------------
update public.theme_links set artist = 'LiSA & Someone Else' where id = '86000000-0000-4000-8000-000000000001';
select tests.as_anon();
select tests.eq('after an artist correction the stored match is no longer served',
  (select coalesce(apple_track_id::text, 'null') || '/' || coalesce(apple_preview_url, 'null')
     from public.media_themes_v1(860001) where title = 'Gurenge'), 'null/null');
select tests.reset();
update public.theme_links set artist = '  LiSA ' where id = '86000000-0000-4000-8000-000000000001';
select tests.as_anon();
select tests.eq('whitespace/case-only differences keep the key (normalised), so the match is served again',
  (select apple_track_id from public.media_themes_v1(860001) where title = 'Gurenge'), 1488408568::bigint);
select tests.reset();

-- ---- 5. table CHECKs back the writer ------------------------------------------------
select tests.raises('a stored match below 0.8 violates the shape check',
  $q$update public.theme_links set apple_match_confidence = 0.5 where id = '86000000-0000-4000-8000-000000000001'$q$,
  '%theme_links_apple_match_shape_check%');
select tests.raises('a partial match (URL without track id) violates the shape check',
  $q$update public.theme_links set apple_music_url = 'https://music.apple.com/x' where id = '86000000-0000-4000-8000-000000000003'$q$,
  '%theme_links_apple_match_shape_check%');
select tests.raises('a non-Apple artwork host violates its check',
  $q$update public.theme_links set apple_artwork_url = 'https://example.invalid/a.jpg' where id = '86000000-0000-4000-8000-000000000001'$q$,
  '%theme_links_apple_artwork_check%');

-- ---- 6. a later no-match clears a previous match -----------------------------------
update public.theme_links set artist = 'LiSA' where id = '86000000-0000-4000-8000-000000000001';
:as_service
select public.upsert_theme_apple_matches_v1(jsonb_build_array(
  jsonb_build_object('theme_id', '86000000-0000-4000-8000-000000000001', 'expected_title', 'Gurenge', 'expected_artist', 'LiSA')
)) as w2 \gset
select tests.reset();
select tests.eq('no-match after a match: counted as cleared', :'w2'::jsonb, '{"matched":0,"cleared":1,"stale":0}'::jsonb);
select tests.eq('the previous match is gone',
  (select count(*) from public.theme_links where id = '86000000-0000-4000-8000-000000000001' and apple_track_id is not null), 0::bigint);

select tests.reset();
rollback;
