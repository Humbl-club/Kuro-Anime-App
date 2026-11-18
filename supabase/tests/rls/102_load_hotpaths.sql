-- Differential contract and real query-plan tests on the disposable fixture only.
-- @requires table public.anime
-- @requires table public.manga
-- @requires function public.search_anime_page(text,integer,float8,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)
-- @requires function public.browse_anime_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text)
\set ON_ERROR_STOP on
\o /dev/null
begin;
set local jit=off;
\ir ../fixtures/102_load_baseline.sql

-- Avoid unrelated ingestion triggers only in this local test transaction. Never hosted.
set local session_replication_role=replica;
insert into public.anime(id,title_romaji,title_english,title_native,format,status,popularity,trending,average_score,genres,is_adult,episodes,season_year,start_date_year,created_at)
select 8000000+n,
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
select 8000000+n,
 case when n%97=0 then 'Berserk' when n%101=0 then 'One Piece' else 'Generated title '||n end,
 case when n%97=0 then 'Berserk' when n%103=0 then 'Fate/stay night' else 'Independent story '||n end,
 case when n%101=0 then '日本語' else null end,'MANGA','FINISHED',case when n%13=0 then null else n%1000 end,n%200,n%100,
 case when n%59=0 then array['Hentai'] when n%61=0 then array['Ecchi'] when n%2=0 then array['Action'] else array['Drama'] end,n%71=0,50,1990+n%37,now()-(n%300)*interval '1 day'
from generate_series(1,42000) n;
set local session_replication_role=origin;
analyze public.anime;
analyze public.manga;

select tests.ok('search blob is identical to the prior concat_ws including null empty whitespace and Unicode',
 not exists(select 1 from unnest(array[null,'',' ',' Naruto ','日本語']) a
 cross join unnest(array[null,'',' ',' Naruto ','日本語']) b
 cross join unnest(array[null,'',' ',' Naruto ','日本語']) c
 where public.catalogue_search_blob_v1(a,b,c) is distinct from lower(trim(concat_ws(' ',nullif(a,''),nullif(b,''),nullif(c,''))))));

create temporary table load_contract_results(name text,passed boolean);
do $$ declare med text;q text;old jsonb;new jsonb;sort text;flt text; begin
 foreach med in array array['anime','manga'] loop
  foreach q in array array[null,'','a','na','Naruto','naroto','One Piece','Berserk','berser','Fate/stay','日本語','  Berserk ','%','a_b','"dragon ball"'] loop
   execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>$1,p_limit=>30) x',med) into old using q;
   execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>$1,p_limit=>30) x',med) into new using q;
   insert into load_contract_results values('search '||med||' '||coalesce(q,'<null>'),old=new);
  end loop;
  foreach sort in array array['popular','trending','topRated','newlyAdded','','unknown'] loop
   foreach flt in array array[null,'Action'] loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_browse_%I_page(p_sort=>$1,p_genre=>$2,p_limit=>30) x',med) into old using sort,flt;
    execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.browse_%I_page(p_sort=>$1,p_genre=>$2,p_limit=>30) x',med) into new using sort,flt;
    insert into load_contract_results values('browse '||med||' '||sort||' '||coalesce(flt,'all'),old=new);
   end loop;
  end loop;
 end loop;
end $$;
do $$ declare med text;old jsonb;new jsonb;c jsonb;sort text;flag text;term text;v_int integer;v_date timestamptz; begin
 foreach med in array array['anime','manga'] loop
  foreach flag in array array['p_trending','p_new_season','p_classics','p_hidden_gems'] loop
   execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>'''',%I=>true,p_limit=>30) x',med,flag) into old;
   execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>'''',%I=>true,p_limit=>30) x',med,flag) into new;
   insert into load_contract_results values('search flag '||med||' '||flag,old=new and jsonb_array_length(old)>0);
  end loop;
  term:=case when med='anime' then 'Naruto' else 'Berserk' end;
  execute format('select jsonb_agg(to_jsonb(x)) from pg_temp.old_search_%I_page(p_query=>$1,p_limit=>10) x',med) into old using term;
  c:=old->-1;
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_search_%I_page(p_query=>$1,p_limit=>10,p_cursor_rank=>$2,p_cursor_popularity=>$3,p_cursor_id=>$4) x',med) into old using term,(c->>'rank')::float8,(c->>'popularity')::integer,(c->>'id')::integer;
  execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.search_%I_page(p_query=>$1,p_limit=>10,p_cursor_rank=>$2,p_cursor_popularity=>$3,p_cursor_id=>$4) x',med) into new using term,(c->>'rank')::float8,(c->>'popularity')::integer,(c->>'id')::integer;
  insert into load_contract_results values('search cursor '||med,old=new and jsonb_array_length(old)>0);
  foreach sort in array array['popular','trending','topRated','newlyAdded'] loop
   execute format('select jsonb_agg(to_jsonb(x)) from pg_temp.old_browse_%I_page(p_sort=>$1,p_limit=>10) x',med) into old using sort;
   c:=old->-1;
   v_int:=coalesce((c->>case when sort='trending' then 'trending' when sort='topRated' then 'average_score' else 'popularity' end)::integer,0);
   v_date:=(c->>'created_at')::timestamptz;
   execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from pg_temp.old_browse_%I_page(p_sort=>$1,p_limit=>10,p_cursor_int=>$2,p_cursor_ts=>$3,p_cursor_id=>$4) x',med) into old using sort,v_int,v_date,(c->>'id')::integer;
   execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.browse_%I_page(p_sort=>$1,p_limit=>10,p_cursor_int=>$2,p_cursor_ts=>$3,p_cursor_id=>$4) x',med) into new using sort,v_int,v_date,(c->>'id')::integer;
   insert into load_contract_results values('browse cursor '||med||' '||sort,old=new and jsonb_array_length(old)>0);
  end loop;
  execute format('select jsonb_agg(to_jsonb(x)) from pg_temp.old_browse_%I_page(p_format=>$1,p_limit=>10) x',med) into old using case when med='anime' then 'SPECIAL' else 'MANGA' end;
  execute format('select jsonb_agg(to_jsonb(x)) from public.browse_%I_page(p_format=>$1,p_limit=>10) x',med) into new using case when med='anime' then 'SPECIAL' else 'MANGA' end;
  insert into load_contract_results values('explicit format '||med,old=new and jsonb_array_length(old)>0);
 end loop;
end $$;
select tests.eq('all 74 differential Search/Browse rankings, filters and cursors match', (select count(*) from load_contract_results where not passed),0::bigint);
select tests.eq('differential checks executed', (select count(*) from load_contract_results),74::bigint);
select tests.ok('both Search functions have custom plans and no JIT; public contract remains definer',
 -- 20261109123758 (live) tightened the lossy GIN prefilter to the 0.35 acceptance bound; a later
 -- CREATE OR REPLACE must keep it (20261109200000 does), so 0.3 is no longer accepted here.
 (select bool_and(prosecdef and prolang=(select oid from pg_language where lanname='plpgsql') and proconfig @> array['search_path=public, extensions','jit=off','pg_trgm.similarity_threshold=0.35']) from pg_proc where oid in (
 'public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'::regprocedure,
 'public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'::regprocedure)));

-- Real EXPLAIN over the exact dynamically executed Search SQL, with representative bindings.
-- Since 20261109200000 the trigram work lives in the $fuzzy$ stage (strong stage: 105).
create temporary table load_query_plans(medium text,plan jsonb);
do $$ declare med text;src text;q text;plan jsonb;i integer; begin
 foreach med in array array['anime','manga'] loop
  select prosrc into src from pg_proc where proname='search_'||med||'_page' and pronamespace='public'::regnamespace;
  q:=split_part(src,'$fuzzy$',2);
  for i in reverse 13..3 loop
   q:=replace(q,'$'||i::text,case when i between 6 and 10 and not(med='manga' and i=10) then 'false' when i=13 or (med='manga' and i=10) then '30' else 'null' end);
  end loop;
  -- manga: 'berzerk' (a misspelling) instead of 'berser', which is now a strong prefix match
  q:=replace(replace(q,'$2','30'),'$1',quote_literal(case when med='anime' then 'naroto' else 'berzerk' end));
  execute 'explain(analyze,buffers,format json) '||q into plan;
  insert into load_query_plans values(med,plan);
  raise notice 'LOAD_PLAN %: %',med,plan;
 end loop;
end $$;
\o
select medium,plan from load_query_plans;
\o /dev/null
select tests.ok('selective fuzzy Search uses real title GIN indexes in both media',
 (select count(*)=2 from load_query_plans where plan::text like '%Bitmap Index Scan%' and plan::text like '%_load_title_%'));
\o
select name,passed from load_contract_results where not passed;
select medium,plan from load_query_plans;
\o /dev/null
rollback;
