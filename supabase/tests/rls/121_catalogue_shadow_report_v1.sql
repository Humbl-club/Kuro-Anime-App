-- 121_catalogue_shadow_report_v1.sql
-- Prepared 20261112100100_catalogue_shadow_report_v1.sql (NOT deployed): the service-only comparator
-- RPC catalogue_shadow_report_v1(p_medium, p_sample). Per field group and tier (top1k, top5k,
-- in_lists, curated, all) it returns {total, covered, compared, agreed, disagree_sample[]}, plus the
-- identity gate counts and the adult review numbers.
-- Fixture: 6 anime. 1 agrees everywhere (title differs only in punctuation/case), 2 agrees on year but
-- disagrees on format and is adult today with shadow false, 3 disagrees on year and is newly adult,
-- 4 has no shadow at all, 5 is in a user list, 6 is curated (proposed link only) and adult today.
-- Fixture limits: curated_rails / curated_rail_items are not in the DB fixture, so the test creates a
-- stand-in curated_rail_items (rolled back with the transaction; production has the real table).
-- The DB fixture is not production; popularity ranks here are 1..6, so top1k and top5k
-- hold all six titles. Tier boundaries at 1,000/5,000 rows are not exercised.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
\set ON_ERROR_STOP on
\o /dev/null
begin;
select tests.reset();

-- ---- 1. posture ---------------------------------------------------------------------
select tests.ok('the report function exists, is SECURITY DEFINER, plpgsql, with the fixed search_path',
  (select count(*) = 1 and bool_and(prosecdef) and bool_and(proconfig @> array['search_path=public, extensions'])
          and bool_and(prolang = (select oid from pg_language where lanname = 'plpgsql'))
   from pg_proc where pronamespace = 'public'::regnamespace and proname = 'catalogue_shadow_report_v1'));
select tests.ok('EXECUTE is denied to public, anon and authenticated and granted to service_role',
  to_regprocedure('public.catalogue_shadow_report_v1(text,integer)') is not null
  and not has_function_privilege('anon', 'public.catalogue_shadow_report_v1(text,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.catalogue_shadow_report_v1(text,integer)', 'execute')
  and not has_function_privilege('public', 'public.catalogue_shadow_report_v1(text,integer)', 'execute')
  and has_function_privilege('service_role', 'public.catalogue_shadow_report_v1(text,integer)', 'execute'));
select tests.ok('the title-normalising helper is not executable by clients',
  to_regprocedure('public.catalogue_norm_title(text)') is not null
  and not has_function_privilege('anon', 'public.catalogue_norm_title(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.catalogue_norm_title(text)', 'execute')
  and not has_function_privilege('public', 'public.catalogue_norm_title(text)', 'execute'));
select tests.eq('catalogue_norm_title folds case, accents, macrons and punctuation',
  public.catalogue_norm_title('  Ōkami-san:  Café Ñ! '), 'okami san cafe n');

select tests.as_anon();
select tests.denied('anon cannot run the report', $q$select public.catalogue_shadow_report_v1('anime')$q$);
select tests.reset();
select tests.make_user(1210);
select tests.as_user(tests.uid(1210));
select tests.denied('authenticated cannot run the report', $q$select public.catalogue_shadow_report_v1('anime')$q$);
select tests.reset();

-- ---- 2. fixture ---------------------------------------------------------------------
delete from public.anime_user_lists;
delete from catalogue_shadow_values;
delete from catalogue_id_links;
delete from public.anime;
insert into public.anime (id, anilist_id, popularity, title_english, title_romaji, format, status, start_date_year, episodes, is_adult) values
  (1210001, 1210001, 600, 'Foo Bar',  'Foo Bar R',  'TV', 'FINISHED', 2000, 12, false),
  (1210002, 1210002, 500, 'Second',   'Second R',   'TV', 'FINISHED', 2001, 24, true),
  (1210003, 1210003, 400, 'Third',    'Third R',    'TV', 'FINISHED', 2002, 13, false),
  (1210004, 1210004, 300, 'Fourth',   'Fourth R',   'TV', 'RELEASING', 2003, null, false),
  (1210005, 1210005, 200, 'Fifth',    'Fifth R',    'TV', 'FINISHED', 2004, 12, false),
  (1210006, 1210006, 100, 'Sixth',    'Sixth R',    'OVA', 'FINISHED', 2005, 2, true);
select tests.eq('fixture: six anime', (select count(*) from public.anime), 6::bigint);

insert into catalogue_shadow_values (medium, media_id, field, value, source) values
  ('anime', 1210001, 'title_english',    '"foo-bar!"', 'wikidata'),
  ('anime', 1210001, 'start_date_year',  '2000', 'wikidata'),
  ('anime', 1210001, 'format',           '"TV"', 'ann'),
  ('anime', 1210001, 'episodes',         '12', 'ann'),
  ('anime', 1210001, 'title_native',     '"native"', 'wikidata'),
  ('anime', 1210002, 'title_english',    '"Second"', 'wikidata'),
  ('anime', 1210002, 'start_date_year',  '2001', 'wikidata'),
  ('anime', 1210002, 'format',           '"MOVIE"', 'ann'),
  ('anime', 1210002, 'episodes',         '1', 'ann'),
  ('anime', 1210002, 'is_adult',         'false', 'ann'),
  ('anime', 1210003, 'title_romaji',     '"Third R"', 'ann'),
  ('anime', 1210003, 'start_date_year',  '2003', 'wikidata'),
  ('anime', 1210003, 'format',           '"TV"', 'ann'),
  ('anime', 1210003, 'is_adult',         'true', 'ann'),
  ('anime', 1210005, 'title_english',    '"Fifth"', 'wikidata'),
  ('anime', 1210005, 'start_date_year',  '2004', 'wikidata'),
  ('anime', 1210005, 'format',           '"TV"', 'ann'),
  ('anime', 1210006, 'title_english',    '"Sixth"', 'wikidata'),
  ('anime', 1210006, 'start_date_year',  '2005', 'wikidata'),
  ('anime', 1210006, 'format',           '"OVA"', 'ann'),
  ('anime', 1210006, 'is_adult',         'true', 'ann'),
  ('anime', 1210006, 'review:adult',     '{"reason":"adult_today_no_source_says_adult"}', 'composer'),
  -- a manga shadow row must not leak into the anime report
  ('manga', 1210001, 'start_date_year',  '1999', 'mangaupdates');

insert into catalogue_id_links (kind, kuro_id, source, source_key, method, confidence, status, decided_at) values
  ('anime', 1210001, 'wikidata', 'Q1', 'wikidata', 1, 'accepted', now()),
  ('anime', 1210002, 'ann',      '2',  'title_match', 0.95, 'accepted', now()),
  ('anime', 1210003, 'wikidata', 'Q3', 'wikidata', 1, 'accepted', now()),
  ('anime', 1210005, 'ann',      '5',  'title_match', 0.95, 'accepted', now()),
  ('anime', 1210006, 'ann',      '6',  'title_match', 0.7,  'proposed', null);

select tests.make_user(1211);
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(1211)::text, 1210005, 'WATCHING', 1);
create table if not exists public.curated_rail_items (rail_id text, media_type text, anilist_id integer, rank integer);
insert into public.curated_rail_items (rail_id, media_type, anilist_id, rank) values ('cat121', 'ANIME', 1210006, 1);

-- ---- 3. the report as service_role --------------------------------------------------
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
create temp table r121 as select public.catalogue_shadow_report_v1('anime', 5) as j;
grant select on r121 to public;
reset role;

select tests.eq('medium and tier sizes', (select j->'tiers' from r121),
  '{"top1k":6,"top5k":6,"in_lists":1,"curated":1,"all":6}'::jsonb);

-- facts_start_year: covered 5 (not 4), compared 5, agreed 4 (title 3 disagrees)
select tests.eq('start year, all tier', (select (j#>'{groups,facts_start_year,all}') - 'disagree_sample' from r121),
  '{"total":6,"covered":5,"compared":5,"agreed":4}'::jsonb);
select tests.eq('start year, in_lists tier', (select (j#>'{groups,facts_start_year,in_lists}') - 'disagree_sample' from r121),
  '{"total":1,"covered":1,"compared":1,"agreed":1}'::jsonb);
select tests.eq('start year, curated tier', (select (j#>'{groups,facts_start_year,curated}') - 'disagree_sample' from r121),
  '{"total":1,"covered":1,"compared":1,"agreed":1}'::jsonb);
select tests.eq('start year disagreement sample lists title 3 with both values',
  (select j#>'{groups,facts_start_year,all,disagree_sample}' from r121),
  '[{"id":1210003,"today":2002,"shadow":2003}]'::jsonb);

-- facts_format: title 2 disagrees (MOVIE vs TV)
select tests.eq('format, all tier', (select (j#>'{groups,facts_format,all}') - 'disagree_sample' from r121),
  '{"total":6,"covered":5,"compared":5,"agreed":4}'::jsonb);

-- facts_episodes: only FINISHED titles with both values are compared: 1 agrees, 2 disagrees (24 vs 1)
select tests.eq('episodes for finished titles, all tier', (select (j#>'{groups,facts_episodes,all}') - 'disagree_sample' from r121),
  '{"total":6,"covered":2,"compared":2,"agreed":1}'::jsonb);

-- titles: covered = a shadow display title (1,2,3 romaji,5,6 = 5); compared needs both english: 1,2,5,6 = 4, all agree after normalising
select tests.eq('titles, all tier', (select (j#>'{groups,titles,all}') - 'disagree_sample' from r121),
  '{"total":6,"covered":5,"compared":4,"agreed":4}'::jsonb);
select tests.eq('native titles covered, all tier', (select (j#>'{groups,titles_native,all}') - 'disagree_sample' from r121),
  '{"total":6,"covered":1,"compared":0,"agreed":0}'::jsonb);

-- identity: accepted non-AniList links on 1,2,3,5; title 6 has only a proposed link
select tests.eq('identity, all tier', (select (j#>'{groups,identity,all}') - 'disagree_sample' from r121),
  '{"total":6,"covered":4,"compared":0,"agreed":0}'::jsonb);
select tests.eq('identity, in_lists tier is fully covered', (select (j#>'{groups,identity,in_lists}') - 'disagree_sample' from r121),
  '{"total":1,"covered":1,"compared":0,"agreed":0}'::jsonb);
select tests.eq('identity, curated tier is not covered (proposed only)', (select (j#>'{groups,identity,curated}') - 'disagree_sample' from r121),
  '{"total":1,"covered":0,"compared":0,"agreed":0}'::jsonb);
select tests.eq('identity gate counts', (select j->'identity_gate' from r121),
  '{"accepted_links":4,"proposed_links":1,"duplicate_accepted_links":0,"proposed_only_titles":1}'::jsonb);

-- adult: shadow says: 2 false (today true: becomes non-adult), 3 true (today false: newly adult), 6 true (today true)
select tests.eq('adult, all tier', (select (j#>'{groups,adult,all}') - 'disagree_sample' from r121),
  '{"total":6,"covered":3,"compared":3,"agreed":1}'::jsonb);
select tests.eq('adult review numbers', (select j->'adult' from r121),
  '{"review_size":1,"becomes_non_adult":1,"newly_adult":1}'::jsonb);

-- the sample is capped by p_sample
create temp table r121b as select public.catalogue_shadow_report_v1('anime', 0) as j;
select tests.eq('p_sample 0 gives empty samples but the same counts',
  (select (j#>'{groups,facts_start_year,all}') from r121b),
  '{"total":6,"covered":5,"compared":5,"agreed":4,"disagree_sample":[]}'::jsonb);

-- ---- 4. manga and validation ----------------------------------------------------------
select tests.eq('manga report is separate: only the manga shadow row exists and no manga titles do',
  (select (public.catalogue_shadow_report_v1('manga')#>'{groups,facts_start_year,all}') - 'disagree_sample'),
  '{"total":0,"covered":0,"compared":0,"agreed":0}'::jsonb);
select tests.raises('an unknown medium is rejected', $$select public.catalogue_shadow_report_v1('novel')$$, '%medium must be anime or manga%');

rollback;
