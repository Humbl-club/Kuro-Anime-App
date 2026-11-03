-- 20261103100100_media_similar_v1.sql
-- PREPARED, NOT DEPLOYED (2026-11-03 details/songs pass, DATA lane). Deploying needs explicit
-- owner approval. Nothing here schedules a job or writes data.
--
-- Owner item 1 ("More like this" on detail pages from media_similar_titles).
--
-- Read access finding (verified against the migration chain, 2026-11-03):
--   public.media_similar_titles has RLS on, NO policies and NO client grants on purpose
--   (20260804130000): anon/authenticated cannot read the table. The app already reads it
--   through public.recommend_ids_similar_to_seeds(text, integer[], integer, boolean)
--   (SECURITY DEFINER, EXECUTE granted to anon + authenticated; latest body 20260806020000):
--   indexed store read, franchise dedupe, own-franchise exclusion, the caller's own list
--   excluded via auth.uid(), live-scorer fallback for a seed the store has not met.
--   That RPC returns ids only, so the detail page needed a second round trip to hydrate cards.
--
-- What it adds: media_similar_v1(p_media_type, p_media_id, p_limit), a THIN wrapper over that
-- same RPC (single seed, gimmicks off). It does not re-implement any ranking or dedupe logic:
-- it keeps the RPC's order (rank = 1-based position after the filters), joins the card columns of the result kind
-- (column names = the app's CatalogColumns.animeCard / mangaCard, so the existing Anime/Manga
-- models decode the rows), and drops adult titles and titles without a cover (the live
-- fallback path does not filter covers). SECURITY INVOKER: the caller's own role runs the
-- granted RPC and the public-read anime/manga tables.
--
-- Account dependence: the wrapped RPC excludes the CALLER's own list titles, so a result is
-- per account. Clients must key any cache by account (the app's RecommendationsReader does).
--
-- Rollback: drop function public.media_similar_v1(text, integer, integer).

begin;

set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = public, extensions;

create or replace function public.media_similar_v1(p_media_type text, p_media_id integer, p_limit integer default 12)
returns table (
  media_type text, rank integer, similarity_score real,
  id integer, title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episodes integer, chapters integer, volumes integer,
  season text, season_year integer, start_date_year integer,
  next_episode_number integer, next_airing_at timestamptz,
  average_score integer, popularity integer, trending integer, favourites integer, genres text[],
  is_adult boolean, created_at timestamptz, updated_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_type text := upper(btrim(coalesce(p_media_type, '')));
  v_limit integer := least(30, greatest(1, coalesce(p_limit, 12)));
  -- A few extra ids so the adult/cover filter rarely leaves the rail short.
  v_fetch integer := least(50, least(30, greatest(1, coalesce(p_limit, 12))) + 8);
begin
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
  if p_media_id is null or p_media_id < 1 then
    raise exception 'INVALID_MEDIA_ID: p_media_id must be a positive id';
  end if;

  if v_type = 'ANIME' then
    return query
    select 'ANIME'::text, (row_number() over (order by r.ord))::integer, r.score,
           a.id, a.title_english, a.title_romaji, a.title_native,
           a.cover_image_large, a.cover_image_medium, a.banner_image,
           a.format, a.status, a.episodes, null::integer, null::integer,
           a.season, a.season_year, a.start_date_year,
           a.next_episode_number, a.next_airing_at,
           a.average_score, a.popularity, a.trending, a.favourites, a.genres,
           a.is_adult, a.created_at, a.updated_at
    from public.recommend_ids_similar_to_seeds('ANIME', array[p_media_id], v_fetch, false)
         with ordinality as r(media_id, overlap_count, score, ord)
    join public.anime a on a.id = r.media_id
    where a.id <> p_media_id
      and coalesce(a.is_adult, false) = false
      and nullif(btrim(a.cover_image_large), '') is not null
    order by r.ord
    limit v_limit;
  else
    return query
    select 'MANGA'::text, (row_number() over (order by r.ord))::integer, r.score,
           m.id, m.title_english, m.title_romaji, m.title_native,
           m.cover_image_large, m.cover_image_medium, null::text,
           m.format, m.status, null::integer, m.chapters, m.volumes,
           null::text, null::integer, m.start_date_year,
           null::integer, null::timestamptz,
           m.average_score, m.popularity, m.trending, m.favourites, m.genres,
           m.is_adult, m.created_at, m.updated_at
    from public.recommend_ids_similar_to_seeds('MANGA', array[p_media_id], v_fetch, false)
         with ordinality as r(media_id, overlap_count, score, ord)
    join public.manga m on m.id = r.media_id
    where m.id <> p_media_id
      and coalesce(m.is_adult, false) = false
      and nullif(btrim(m.cover_image_large), '') is not null
    order by r.ord
    limit v_limit;
  end if;
end;
$$;

revoke all on function public.media_similar_v1(text, integer, integer) from public;
grant execute on function public.media_similar_v1(text, integer, integer) to anon, authenticated, service_role;

comment on function public.media_similar_v1(text, integer, integer) is
  '20261103100100 (prepared). "More like this" for one title: a thin SECURITY INVOKER wrapper over recommend_ids_similar_to_seeds (single seed, gimmicks off; its order, franchise dedupe, own-franchise exclusion and caller-list exclusion are kept as-is) joined to the card columns of the result kind (CatalogColumns.animeCard / mangaCard names). Adult titles and titles without a cover are dropped. p_limit 1-30 (default 12); rank = 1-based position among the returned rows (wrapped order kept). Per account (caller list excluded). Raises INVALID_MEDIUM: / INVALID_MEDIA_ID:.';

commit;
