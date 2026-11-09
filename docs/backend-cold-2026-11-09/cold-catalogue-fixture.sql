-- Native disposable PostgreSQL only; synthetic public catalogue, no production/user data.
\set ON_ERROR_STOP on
create schema extensions;
create extension pg_trgm with schema extensions;
create extension pg_buffercache with schema extensions;
create schema cold_test;
set search_path=public,extensions;
set jit=off;
create table anime(id int primary key,title_english text,title_romaji text,title_native text,cover_image_large text,cover_image_medium text,banner_image text,format text,status text,episodes int,season_year int,start_date_year int,average_score int,popularity int,trending int,favourites int,genres text[],created_at timestamptz,is_adult boolean,season text,padding text);
create table manga(id int primary key,title_english text,title_romaji text,title_native text,cover_image_large text,cover_image_medium text,format text,status text,chapters int,start_date_year int,average_score int,popularity int,trending int,favourites int,genres text[],created_at timestamptz,is_adult boolean,padding text);
insert into anime
select n,case when n%97=0 then 'Naruto' when n%103=0 then 'Fate/stay night' when n%113=0 then '' when n%127=0 then null else 'Independent story '||n end,
case when n%97=0 then 'Naruto: Shippuuden' when n%101=0 then 'One Piece' else 'Generated title '||n end,
case when n%101=0 then '日本語' when n%109=0 then '  ' else null end,
'https://images.test/'||n||'/large','https://images.test/'||n||'/medium',null,
case when n%7=0 then 'SPECIAL' when n%5=0 then 'MOVIE' else 'TV' end,
case when n%3=0 then 'RELEASING' else 'FINISHED' end,12,1990+n%37,1990+n%37,
case when n%17=0 then null else 60+n%41 end,case when n%13=0 then null else n%1000 end,case when n%19=0 then null else n%200 end,n%100,
case when n%59=0 then array['Hentai'] when n%61=0 then array['Ecchi'] when n%67=0 then null when n%2=0 then array['Action'] else array['Drama'] end,
'2026-11-09'::timestamptz-(n%300)*interval '1day',n%71=0,'FALL',
(select string_agg(md5(n::text||'-'||i::text),'') from generate_series(1,30)i)
from generate_series(1,22000)n;
insert into manga select n,case when n%97=0 then 'Berserk' when n%103=0 then 'Fate/stay night' when n%113=0 then '' else 'Independent story '||n end,
case when n%97=0 then 'Berserk' when n%101=0 then 'One Piece' else 'Generated title '||n end,
case when n%101=0 then '日本語' else null end,'https://images.test/'||n||'/large','https://images.test/'||n||'/medium','MANGA','FINISHED',50,1990+n%37,
case when n%17=0 then null else 60+n%41 end,case when n%13=0 then null else n%1000 end,case when n%19=0 then null else n%200 end,n%100,
case when n%59=0 then array['Hentai'] when n%61=0 then array['Ecchi'] when n%67=0 then null when n%2=0 then array['Action'] else array['Drama'] end,
'2026-11-09'::timestamptz-(n%300)*interval '1day',n%71=0,
(select string_agg(md5(n::text||'-'||i::text),'') from generate_series(1,30)i)
from generate_series(1,42000)n;
-- Wide materialized views preserve NULL/tie edges in addition to representative row counts.
create materialized view mv_anime_trending as select * from anime where id%9=0;
create materialized view mv_manga_trending as select * from manga where id%19=0;
create materialized view mv_anime_top_rated as select * from anime where id%31=0;
create materialized view mv_manga_top_rated as select * from manga where id%53=0;
do $$declare t text;col text;begin
for t,col in values ('mv_anime_trending','trending'),('mv_manga_trending','trending'),('mv_anime_top_rated','average_score'),('mv_manga_top_rated','average_score') loop
execute format('create unique index %I on %I(id)',t||'_id_uidx',t);
execute format('create index %I on %I(%I desc)',t||'_old_sort',t,col);
end loop;end$$;
create materialized view media_realm_membership as
select 'ANIME'::text as media_type,id as media_id,'realm-'||j as realm,((id*17+j*11)%100)::real/100 as weight from anime cross join generate_series(1,4)j
union all select 'MANGA',id,'realm-'||j,((id*17+j*11)%100)::real/100 from manga cross join generate_series(1,4)j;
create unique index media_realm_membership_uidx on media_realm_membership(media_type,media_id,realm);
create index media_realm_membership_realm_idx on media_realm_membership(realm);
vacuum analyze anime;
vacuum analyze manga;
vacuum analyze media_realm_membership;
vacuum analyze mv_anime_trending;
vacuum analyze mv_manga_trending;
vacuum analyze mv_anime_top_rated;
vacuum analyze mv_manga_top_rated;
\ir search-baseline.sql

create index if not exists idx_anime_load_popular_v1 on public.anime ((coalesce(popularity,0)) desc,id desc);
create index if not exists idx_anime_load_trending_v1 on public.anime ((coalesce(trending,0)) desc,id desc);
create index if not exists idx_anime_load_score_v1 on public.anime ((coalesce(average_score,0)) desc,id desc);
create index if not exists idx_anime_load_created_v1 on public.anime (created_at desc nulls last,id desc);
create index if not exists idx_anime_load_title_english_v1 on public.anime using gin ((lower(coalesce(title_english,''))) gin_trgm_ops);
create index if not exists idx_anime_load_title_romaji_v1 on public.anime using gin ((lower(coalesce(title_romaji,''))) gin_trgm_ops);
create index if not exists idx_anime_load_title_native_v1 on public.anime using gin ((lower(coalesce(title_native,''))) gin_trgm_ops);
create index if not exists idx_anime_load_title_blob_v1 on public.anime using gin ((public.catalogue_search_blob_v1(title_english,title_romaji,title_native)) gin_trgm_ops);
create index if not exists idx_anime_load_title_fts_v1 on public.anime using gin (to_tsvector('simple',public.catalogue_search_blob_v1(title_english,title_romaji,title_native)));
create index if not exists idx_manga_load_popular_v1 on public.manga ((coalesce(popularity,0)) desc,id desc);
create index if not exists idx_manga_load_trending_v1 on public.manga ((coalesce(trending,0)) desc,id desc);
create index if not exists idx_manga_load_score_v1 on public.manga ((coalesce(average_score,0)) desc,id desc);
create index if not exists idx_manga_load_created_v1 on public.manga (created_at desc nulls last,id desc);
create index if not exists idx_manga_load_title_english_v1 on public.manga using gin ((lower(coalesce(title_english,''))) gin_trgm_ops);
create index if not exists idx_manga_load_title_romaji_v1 on public.manga using gin ((lower(coalesce(title_romaji,''))) gin_trgm_ops);
create index if not exists idx_manga_load_title_native_v1 on public.manga using gin ((lower(coalesce(title_native,''))) gin_trgm_ops);
create index if not exists idx_manga_load_title_blob_v1 on public.manga using gin ((public.catalogue_search_blob_v1(title_english,title_romaji,title_native)) gin_trgm_ops);
create index if not exists idx_manga_load_title_fts_v1 on public.manga using gin (to_tsvector('simple',public.catalogue_search_blob_v1(title_english,title_romaji,title_native)));
