-- PREPARED, not deployed: reduce the measured first-use catalogue working set.
-- Four exact materialized-view order indexes; one bounded realm covering index.
-- No table rows, refresh definitions, RPC bodies, grants, RLS or output ordering change.
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '90s';
create index idx_mv_anime_trending_cold_v1 on public.mv_anime_trending ((coalesce(trending,0)) desc,id desc) where coalesce(is_adult,false)=false and not ('Hentai'=any(coalesce(genres,'{}'::text[]))) and not ('Ecchi'=any(coalesce(genres,'{}'::text[]))) and coalesce(format,'') not in ('SPECIAL','MUSIC','TV_SHORT');
create index idx_mv_manga_trending_cold_v1 on public.mv_manga_trending ((coalesce(trending,0)) desc,id desc) where coalesce(is_adult,false)=false and not ('Hentai'=any(coalesce(genres,'{}'::text[]))) and not ('Ecchi'=any(coalesce(genres,'{}'::text[])));
create index idx_mv_anime_score_cold_v1 on public.mv_anime_top_rated ((coalesce(average_score,0)) desc,id desc) where coalesce(is_adult,false)=false and not ('Hentai'=any(coalesce(genres,'{}'::text[]))) and not ('Ecchi'=any(coalesce(genres,'{}'::text[]))) and coalesce(format,'') not in ('SPECIAL','MUSIC','TV_SHORT');
create index idx_mv_manga_score_cold_v1 on public.mv_manga_top_rated ((coalesce(average_score,0)) desc,id desc) where coalesce(is_adult,false)=false and not ('Hentai'=any(coalesce(genres,'{}'::text[]))) and not ('Ecchi'=any(coalesce(genres,'{}'::text[])));
-- Realm classification is optional: the existing reader uses its genre fallback if absent.
-- Production preflight requires this view present and its index ready for qualification.
do $realm_index$
begin
  if to_regclass('public.media_realm_membership') is not null then
    if (select relkind from pg_class where oid='public.media_realm_membership'::regclass) <> 'm' then
      raise exception 'media_realm_membership must be a materialized view';
    end if;
    create index idx_realm_mood_cold_v1 on public.media_realm_membership (media_type,realm,media_id) include (weight) where weight >= 0.25;
  end if;
end;
$realm_index$;
-- Every accepted fuzzy candidate already requires greatest(similarity(...)) >= 0.35.
-- Align the lossy GIN prefilter with that existing acceptance bound; ranking stays exact.
alter function public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer) set pg_trgm.similarity_threshold to '0.35';
alter function public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean) set pg_trgm.similarity_threshold to '0.35';
notify pgrst, 'reload schema';
commit;
