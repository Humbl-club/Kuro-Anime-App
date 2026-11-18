-- 113_search_hidden_adult_count.sql
-- Prepared 20261118100000_search_hidden_adult_v1.sql (NOT deployed): search_{anime,manga}_page_v2
-- return {"items": <v1 rows>, "hidden_adult": <0..100>|null} and never leak an adult row; import
-- staging marks adult matches ADULT_NOT_LISTED. Disposable fixture only.
-- v2 / the import guard are the SUBJECT: not required, their absence must FAIL (not block).
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.library_import_jobs
-- @requires function public.start_library_import_v2(jsonb,text)
-- @requires function public.search_anime_page(text,integer,float8,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)
-- @requires function public.search_manga_page(text,integer,float8,integer,integer,boolean,boolean,boolean,boolean)
\set ON_ERROR_STOP on
\o /dev/null
begin;
set local jit = off;
\ir ../fixtures/102_load_baseline.sql
select tests.reset();

-- ---- 1. search fixtures ----------------------------------------------------------------
set local session_replication_role = replica;
insert into public.anime (id, title_romaji, title_english, cover_image_large, format, status, popularity, trending, average_score, genres, is_adult, episodes, season_year, start_date_year)
values
 (9105001, 'Velvet Hush',   'Velvet Hush',   'https://img.test/velvet.jpg', 'TV',      'FINISHED', 10, 0, 70, array['Drama'],  true,  12, 2020, 2020),
 (9105002, 'Quiet Harbor',  'Quiet Harbor',  null,                          'TV',      'FINISHED', 10, 0, 70, array['Drama'],  false, 12, 2020, 2020),
 (9105003, 'Silk Veil',     'Silk Veil',     null,                          'TV',      'FINISHED', 10, 0, 70, array['Hentai'], false, 12, 2020, 2020),
 (9105004, 'Satin Breeze',  'Satin Breeze',  null,                          'TV',      'FINISHED', 10, 0, 70, array['Ecchi'],  false, 12, 2020, 2020),
 (9105005, 'Lacquer Night', 'Lacquer Night', null,                          'SPECIAL', 'FINISHED', 10, 0, 70, array['Drama'],  true,  1,  2020, 2020),
 (9105006, 'Ember Rite',    'Ember Rite',    null,                          'TV',      'FINISHED', 10, 0, 70, array['Drama'],  true,  12, 2020, 2020);
insert into public.manga (id, title_romaji, title_english, format, status, popularity, trending, average_score, genres, is_adult, chapters, start_date_year)
values (9105001, 'Velvet Ledger', 'Velvet Ledger', 'MANGA', 'FINISHED', 10, 0, 70, array['Drama'], true, 40, 2020);
insert into public.anime (id, title_romaji, title_english, format, status, popularity, trending, average_score, genres, is_adult, episodes, season_year, start_date_year)
select 9106000 + n, 'Cap Test ' || n, 'Cap Test ' || n, 'TV', 'FINISHED', 10, 0, 70, array['Drama'], true, 12, 2020, 2020 from generate_series(1, 120) n;
-- the 22,000-row generated catalogue of 102 (plans + differential checks)
insert into public.anime(id,title_romaji,title_english,title_native,format,status,popularity,trending,average_score,genres,is_adult,episodes,season_year,start_date_year,created_at)
select 8100000+n,
 case when n%97=0 then 'Naruto: Shippuuden' when n%101=0 then 'One Piece' else 'Generated title '||n end,
 case when n%97=0 then 'Naruto' when n%103=0 then 'Fate/stay night' when n%113=0 then '' else 'Independent story '||n end,
 case when n%101=0 then '日本語' else null end,
 case when n%7=0 then 'SPECIAL' when n%5=0 then 'MOVIE' else 'TV' end,
 case when n%3=0 then 'RELEASING' else 'FINISHED' end,
 case when n%13=0 then null else n%1000 end,n%200,n%100,
 case when n%59=0 then array['Hentai'] when n%61=0 then array['Ecchi'] when n%2=0 then array['Action'] else array['Drama'] end,
 n%71=0,12,1990+n%37,1990+n%37,now()-(n%300)*interval '1 day'
from generate_series(1,22000) n;
insert into public.manga(id,title_romaji,title_english,title_native,format,status,popularity,trending,average_score,genres,is_adult,chapters,start_date_year,created_at)
select 8100000+n,
 case when n%97=0 then 'Berserk' when n%101=0 then 'One Piece' else 'Generated title '||n end,
 case when n%97=0 then 'Berserk' when n%103=0 then 'Fate/stay night' else 'Independent story '||n end,
 case when n%101=0 then '日本語' else null end,'MANGA','FINISHED',case when n%13=0 then null else n%1000 end,n%200,n%100,
 case when n%59=0 then array['Hentai'] when n%61=0 then array['Ecchi'] when n%2=0 then array['Action'] else array['Drama'] end,n%71=0,50,1990+n%37,now()-(n%300)*interval '1 day'
from generate_series(1,22000) n;
set local session_replication_role = origin;
analyze public.anime;
analyze public.manga;

-- ---- 2. search matrix ------------------------------------------------------------------
create temporary table adult_v2 (name text primary key, r jsonb);
insert into adult_v2 values
 ('velvet',      public.search_anime_page_v2('velvet hush')),
 ('quiet',       public.search_anime_page_v2('quiet harbor')),
 ('silk',        public.search_anime_page_v2('silk veil')),
 ('satin',       public.search_anime_page_v2('satin breeze')),
 ('lacquer',     public.search_anime_page_v2('lacquer night')),
 ('ember_air',   public.search_anime_page_v2('ember rite', p_airing_only => true)),
 ('ember',       public.search_anime_page_v2('ember rite')),
 ('cursor',      public.search_anime_page_v2('velvet hush', p_cursor_rank => 600, p_cursor_popularity => 0, p_cursor_id => 1)),
 ('one_char',    public.search_anime_page_v2('v')),
 ('blank_trend', public.search_anime_page_v2('', p_trending => true)),
 ('manga',       public.search_manga_page_v2('velvet ledger')),
 ('cap',         public.search_anime_page_v2('cap test'));
\o
select tests.eq('velvet hush: no rows, hidden_adult 1', (select jsonb_array_length(r->'items')::text || '/' || (r->>'hidden_adult') from adult_v2 where name='velvet'), '0/1');
select tests.ok('response text contains none of the adult title, id or picture',
  (select r::text not like '%Velvet%' and r::text not like '%9105001%' and r::text not like '%velvet.jpg%' from adult_v2 where name='velvet'));
select tests.ok('quiet harbor: items has the non-adult id, hidden_adult 0',
  (select (r->'items'->0->>'id')::int = 9105002 and (r->>'hidden_adult')::int = 0 from adult_v2 where name='quiet'));
select tests.eq('silk veil (Hentai genre) counts 1 and returns no rows', (select jsonb_array_length(r->'items')::text || '/' || (r->>'hidden_adult') from adult_v2 where name='silk'), '0/1');
select tests.eq('satin breeze (Ecchi only) does not count', (select jsonb_array_length(r->'items')::text || '/' || (r->>'hidden_adult') from adult_v2 where name='satin'), '0/0');
select tests.eq('lacquer night (format-excluded) does not count', (select r->>'hidden_adult' from adult_v2 where name='lacquer'), '0');
select tests.eq('ember rite with the Airing refinement does not count', (select r->>'hidden_adult' from adult_v2 where name='ember_air'), '0');
select tests.eq('ember rite without a refinement counts 1', (select r->>'hidden_adult' from adult_v2 where name='ember'), '1');
select tests.ok('page 2 (cursor) carries hidden_adult null', (select r->'hidden_adult' = 'null'::jsonb from adult_v2 where name='cursor'));
select tests.ok('a 1-character query carries hidden_adult null', (select r->'hidden_adult' = 'null'::jsonb from adult_v2 where name='one_char'));
select tests.ok('a filters-only (blank) search carries hidden_adult null', (select r->'hidden_adult' = 'null'::jsonb from adult_v2 where name='blank_trend'));
select tests.eq('manga: velvet ledger no rows, hidden_adult 1', (select jsonb_array_length(r->'items')::text || '/' || (r->>'hidden_adult') from adult_v2 where name='manga'), '0/1');
select tests.eq('count is capped at 100', (select r->>'hidden_adult' from adult_v2 where name='cap'), '100');

-- differential: v2.items = v1 rows, v1 order, both media, page 1 and a page-2 cursor
create temporary table adult_diff (name text, ok boolean);
do $diff$
declare med text; q text; v1 jsonb; v2 jsonb; c jsonb;
begin
  foreach med in array array['anime','manga'] loop
    foreach q in array array['naruto','one','fate','berserk','quiet'] loop
      execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>$1,p_limit=>5) x', med) into v1 using q;
      execute format('select public.search_%I_page_v2(p_query=>$1,p_limit=>5)->''items''', med) into v2 using q;
      insert into adult_diff values ('page1 '||med||' '||q, v1 = v2);
      if jsonb_array_length(v1) = 5 then
        c := v1->-1;
        execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>$1,p_limit=>5,p_cursor_rank=>$2,p_cursor_popularity=>$3,p_cursor_id=>$4) x', med) into v1 using q,(c->>'rank')::float8,(c->>'popularity')::int,(c->>'id')::int;
        execute format('select public.search_%I_page_v2(p_query=>$1,p_limit=>5,p_cursor_rank=>$2,p_cursor_popularity=>$3,p_cursor_id=>$4)', med) into v2 using q,(c->>'rank')::float8,(c->>'popularity')::int,(c->>'id')::int;
        insert into adult_diff values ('page2 '||med||' '||q, v1 = v2->'items' and v2->'hidden_adult' = 'null'::jsonb);
      end if;
    end loop;
  end loop;
end $diff$;
select tests.eq('v2.items equals v1 rows for every differential query', (select count(*) from adult_diff where not ok), 0::bigint);
select tests.ok('differential executed with page-2 cursors', (select count(*) from adult_diff) >= 10 and exists (select 1 from adult_diff where name like 'page2%'));

-- ---- 3. posture ------------------------------------------------------------------------
select tests.ok('anon and authenticated may execute both v2 functions',
  has_function_privilege('anon', 'public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)', 'execute')
  and has_function_privilege('anon', 'public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)', 'execute')
  and has_function_privilege('authenticated', 'public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)', 'execute'));
select tests.ok('the internal count helpers are not executable by anon or authenticated',
  not has_function_privilege('anon', 'public._search_hidden_adult_anime_v1(text,boolean,boolean,boolean,boolean,boolean,text,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public._search_hidden_adult_anime_v1(text,boolean,boolean,boolean,boolean,boolean,text,integer)', 'execute')
  and not has_function_privilege('anon', 'public._search_hidden_adult_manga_v1(text,boolean,boolean,boolean,boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public._search_hidden_adult_manga_v1(text,boolean,boolean,boolean,boolean)', 'execute'));
select tests.ok('all four are definer, plpgsql, search_path public+extensions, jit off, threshold 0.35',
  (select count(*) = 4 and bool_and(prosecdef and prolang = (select oid from pg_language where lanname = 'plpgsql')
          and proconfig @> array['search_path=public, extensions','jit=off','pg_trgm.similarity_threshold=0.35'])
   from pg_proc where oid in (
     'public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'::regprocedure,
     'public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'::regprocedure,
     'public._search_hidden_adult_anime_v1(text,boolean,boolean,boolean,boolean,boolean,text,integer)'::regprocedure,
     'public._search_hidden_adult_manga_v1(text,boolean,boolean,boolean,boolean)'::regprocedure)));
select tests.ok('v1 stays staged and untouched: still the three-stage bodies at threshold 0.35',
  (select bool_and(prosrc like '%$blank$%' and prosrc like '%$strong$%' and prosrc like '%$fuzzy$%'
                   and proconfig @> array['pg_trgm.similarity_threshold=0.35'])
   from pg_proc where oid in (
     'public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'::regprocedure,
     'public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'::regprocedure)));

-- ---- 4. EXPLAIN of the exact count SQL --------------------------------------------------
create temporary table adult_plans (medium text, plan jsonb);
do $plans$
declare med text; src text; q text; plan jsonb; i integer;
begin
  foreach med in array array['anime','manga'] loop
    select prosrc into src from pg_proc where proname = '_search_hidden_adult_' || med || '_v1' and pronamespace = 'public'::regnamespace;
    q := split_part(src, '$count$', 2);
    for i in reverse 8..2 loop
      q := replace(q, '$' || i::text, case when i between 2 and 6 then 'false' else 'null' end);
    end loop;
    q := replace(q, '$1', quote_literal('velvet hush'));
    execute 'explain (analyze, format json) ' || q into plan;
    insert into adult_plans values (med, plan);
    raise notice 'ADULT_COUNT_PLAN %: %', med, plan;
  end loop;
end $plans$;
select tests.ok('count SQL uses a Bitmap Index Scan on a title index and never a Seq Scan on the catalogue',
  (select count(*) = 2 from adult_plans where plan::text like '%Bitmap Index Scan%' and plan::text like '%_load_title_%'
     and plan::text not like '%"Node Type": "Seq Scan"%'));
-- ---- 5. import staging marks adult matches ----------------------------------------------
\o /dev/null
select tests.make_user(1050);
insert into public.anime(id, title_romaji, mal_id, is_adult, genres) values
 (9105101, 'Velvet Hush Import', 9905101, true,  array['Drama']),
 (9105102, 'Velvet Two Import',  9905102, true,  array['Drama']),
 (9105103, 'Hentai Genre Import', 9905103, false, array['Hentai']),
 (9105104, 'Plain Import',       9905104, false, array['Drama']);
select tests.as_user(tests.uid(1050));
select public.start_library_import_v2('{"provider":"myanimelist","source_kind":"export","source_identity":"adult.xml","media":["anime"],"statuses":[]}'::jsonb, 'adult-notice-action-1050') as started \gset
select :'started'::jsonb->>'job_id' as job \gset
select public.prepare_import_chunk_v2(:'job'::uuid, '[
 {"medium":"anime","external_id":"9905101","values":{"status":"watching","progress":1}},
 {"medium":"anime","external_id":"9905102","values":{"status":"watching","progress":1}},
 {"medium":"anime","external_id":"9905103","values":{"status":"plan_to_watch","progress":0}},
 {"medium":"anime","external_id":"9905104","values":{"status":"watching","progress":2}},
 {"medium":"anime","external_id":"9905999","title":"Unknown source label","values":{"status":"watching","progress":1}}
]'::jsonb, '{}'::jsonb) as chunk1 \gset
\o
select tests.eq('the three adult items are unmatched with detail ADULT_NOT_LISTED, no media id, identity unresolved',
  (select count(*) from public.library_import_items where job_id = :'job'::uuid and external_id in ('9905101','9905102','9905103')
     and disposition = 'unmatched' and detail like 'ADULT_NOT_LISTED:%' and media_id is null and identity_resolved = false), 3::bigint);
select tests.ok('the plain item stays new with its media id; the unknown item is unmatched without the adult code',
  (select bool_and(case external_id
            when '9905104' then disposition = 'new' and media_id = 9105104
            when '9905999' then disposition = 'unmatched' and detail not like 'ADULT_NOT_LISTED:%' end)
   from public.library_import_items where job_id = :'job'::uuid and external_id in ('9905104','9905999')));
\o /dev/null
select public.prepare_import_chunk_v2(:'job'::uuid, '[
 {"medium":"anime","external_id":"9905101","values":{"status":"watching","progress":1}},
 {"medium":"anime","external_id":"9905102","values":{"status":"watching","progress":1}},
 {"medium":"anime","external_id":"9905103","values":{"status":"plan_to_watch","progress":0}}
]'::jsonb, '{}'::jsonb) as chunk2 \gset
\o
select tests.eq('re-sending the same chunk keeps the adult items unmatched/ADULT_NOT_LISTED',
  (select count(*) from public.library_import_items where job_id = :'job'::uuid and external_id in ('9905101','9905102','9905103')
     and disposition = 'unmatched' and detail like 'ADULT_NOT_LISTED:%' and media_id is null), 3::bigint);
select tests.ok('import_items_page_v2 shows the adult item as unmatched with the code in detail',
  (select bool_and(i->>'disposition' = 'unmatched' and i->>'detail' like 'ADULT_NOT_LISTED:%' and i->>'media_id' is null)
   from jsonb_array_elements(public.import_items_page_v2(:'job'::uuid)->'items') i where i->>'external_id' = '9905101'));
select tests.reset();
select tests.eq('_import_v2_counts: unmatched 4 and adult_not_listed 3',
  (public._import_v2_counts(:'job'::uuid)->>'unmatched') || '/' || (public._import_v2_counts(:'job'::uuid)->>'adult_not_listed'), '4/3');
-- scope: an item applied before this migration keeps its disposition and media id
update public.library_import_items set media_id = 9105101, disposition = 'added' where job_id = :'job'::uuid and external_id = '9905104';
select tests.ok('a row updated to added with an adult media id (pre-migration import) is untouched',
  (select disposition = 'added' and media_id = 9105101 from public.library_import_items where job_id = :'job'::uuid and external_id = '9905104'));
select tests.ok('the guard function is not executable by anon or authenticated',
  not has_function_privilege('anon', 'public._import_item_adult_guard_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public._import_item_adult_guard_v1()', 'execute'));
select medium, plan from adult_plans;
\o /dev/null
rollback;
