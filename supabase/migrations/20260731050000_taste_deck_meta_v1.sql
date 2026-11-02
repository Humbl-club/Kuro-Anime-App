-- ADR 2026-07-31 (addendum): Taste Deck v1.1 — meta strip on the image.
-- fetch_taste_deck_batch gains per-card meta so the deck can render a modern
-- capsule strip (episodes / seasons / dub / sub / volumes / chapters) while
-- title, genres and actions move below the image:
--   episodes       anime.episodes (null for manga)
--   chapters       manga.chapters (null for anime)
--   volumes        manga.volumes (null for anime) — feeds the "VOL n" chip
--   seasons_count  anime TV only: transitive PREQUEL/SEQUEL walk over
--                  media_relations (both directions, depth <= 10, visited-array
--                  cycle guard), counting DISTINCT related ANIME with format='TV'
--                  plus self. 1 when no relations exist; null for manga/non-TV.
--   has_dub        true iff any provider_availability row has a non-Japanese
--                  audio language; null when no availability rows (unknown != false)
--   has_sub        true iff any provider_availability row has non-empty
--                  subtitle_langs; null when no rows.
--
-- provider_availability has RLS enabled but no select policy (all prior readers
-- are SECURITY DEFINER RPCs). This function is SECURITY INVOKER, so it needs a
-- public read policy — availability rows are catalog-level, matching the
-- streaming_services_public_read / media_relations_select_all precedent.

-- ---------------------------------------------------------------------------
-- 0) Catalog-level read for availability rows (idempotent)
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'provider_availability'
      AND policyname = 'provider_availability_public_read'
  ) THEN
    CREATE POLICY provider_availability_public_read
      ON public.provider_availability
      FOR SELECT
      USING (true);
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) Seasons helper: transitive TV-sibling count for one anime (SECURITY INVOKER)
-- ---------------------------------------------------------------------------
create or replace function public._taste_deck_seasons_count(p_anime_id integer)
returns integer
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with recursive walk as (
    -- Outbound edges: self is the "from" side.
    select
      mr.to_media_id as anime_id,
      1 as depth,
      array[p_anime_id, mr.to_media_id] as visited
    from public.media_relations mr
    where mr.from_media_type = 'ANIME'
      and mr.from_media_id = p_anime_id
      and mr.relation_type in ('PREQUEL', 'SEQUEL')
      and mr.to_media_type = 'ANIME'
    union
    -- Inbound edges: self is the "to" side.
    select
      mr.from_media_id as anime_id,
      1 as depth,
      array[p_anime_id, mr.from_media_id] as visited
    from public.media_relations mr
    where mr.to_media_type = 'ANIME'
      and mr.to_media_id = p_anime_id
      and mr.relation_type in ('PREQUEL', 'SEQUEL')
      and mr.from_media_type = 'ANIME'
    union
    -- Transitive step across either edge direction.
    select
      case when mr.from_media_id = w.anime_id then mr.to_media_id else mr.from_media_id end,
      w.depth + 1,
      w.visited || case when mr.from_media_id = w.anime_id then mr.to_media_id else mr.from_media_id end
    from walk w
    join public.media_relations mr
      on mr.relation_type in ('PREQUEL', 'SEQUEL')
     and (
       (mr.from_media_type = 'ANIME' and mr.from_media_id = w.anime_id and mr.to_media_type = 'ANIME')
       or
       (mr.to_media_type = 'ANIME' and mr.to_media_id = w.anime_id and mr.from_media_type = 'ANIME')
     )
    where w.depth < 10
      and not (case when mr.from_media_id = w.anime_id then mr.to_media_id else mr.from_media_id end = any (w.visited))
  )
  select (count(distinct w.anime_id) filter (where a.format = 'TV'))::integer + 1
  from walk w
  join public.anime a on a.id = w.anime_id;
$$;

revoke all on function public._taste_deck_seasons_count(integer) from public;
grant execute on function public._taste_deck_seasons_count(integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Deck batch fetch v1.1 (SECURITY INVOKER: catalog + caller's own rows)
--    Return type changed -> drop first; name/params identical, iOS unchanged.
-- ---------------------------------------------------------------------------
drop function if exists public.fetch_taste_deck_batch(integer);

create function public.fetch_taste_deck_batch(p_limit integer default 12)
returns table (
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  cover_image_medium text,
  cover_image_color text,
  genres text[],
  average_score integer,
  format text,
  year integer,
  synopsis text,
  episodes integer,
  chapters integer,
  volumes integer,
  seasons_count integer,
  has_dub boolean,
  has_sub boolean
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_lim integer := greatest(2, least(coalesce(p_limit, 12), 40));
  v_half integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  v_half := v_lim / 2;

  return query
  with anime_pool as (
    select
      'ANIME'::text as media_type,
      a.id as media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
      a.cover_image_large as cover_image_large,
      a.cover_image_medium as cover_image_medium,
      a.cover_image_color as cover_image_color,
      a.genres as genres,
      a.average_score as average_score,
      a.format as format,
      coalesce(a.season_year, a.start_date_year) as year,
      left(coalesce(a.description_normalized, ''), 300) as synopsis,
      a.episodes as episodes,
      null::integer as chapters,
      null::integer as volumes,
      (a.cover_image_large like '%/storage/v1/%') as mirrored,
      coalesce(a.popularity, 0) as popularity
    from public.anime a
    where coalesce(a.is_adult, false) = false
      and not ('Hentai' = any(coalesce(a.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(a.genres, '{}'::text[])))
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and coalesce(a.average_score, 0) >= 70
      and a.cover_image_large is not null
      and not exists (
        select 1 from public.anime_user_lists ul
        where ul.user_id = v_uid::text
          and ul.anime_id = a.id
      )
      and not exists (
        select 1 from public.taste_signal_events e
        where e.user_id = v_uid
          and e.media_type = 'ANIME'
          and e.media_id = a.id
          and e.event_type in ('deck_love', 'deck_known', 'deck_skip')
      )
    order by mirrored desc, popularity desc, a.id desc
    limit v_lim
  ),
  manga_pool as (
    select
      'MANGA'::text as media_type,
      m.id as media_id,
      coalesce(nullif(m.title_english, ''), m.title_romaji) as title,
      m.cover_image_large as cover_image_large,
      m.cover_image_medium as cover_image_medium,
      m.cover_image_color as cover_image_color,
      m.genres as genres,
      m.average_score as average_score,
      m.format as format,
      m.start_date_year as year,
      left(coalesce(m.description_normalized, ''), 300) as synopsis,
      null::integer as episodes,
      m.chapters as chapters,
      m.volumes as volumes,
      (m.cover_image_large like '%/storage/v1/%') as mirrored,
      coalesce(m.popularity, 0) as popularity
    from public.manga m
    where coalesce(m.is_adult, false) = false
      and not ('Hentai' = any(coalesce(m.genres, '{}'::text[])))
      and not ('Ecchi' = any(coalesce(m.genres, '{}'::text[])))
      and coalesce(m.average_score, 0) >= 70
      and m.cover_image_large is not null
      and not exists (
        select 1 from public.manga_user_lists ul
        where ul.user_id = v_uid::text
          and ul.manga_id = m.id
      )
      and not exists (
        select 1 from public.taste_signal_events e
        where e.user_id = v_uid
          and e.media_type = 'MANGA'
          and e.media_id = m.id
          and e.event_type in ('deck_love', 'deck_known', 'deck_skip')
      )
    order by mirrored desc, popularity desc, m.id desc
    limit v_lim
  ),
  ranked as (
    select
      p.*,
      row_number() over (
        partition by p.media_type
        order by p.mirrored desc, p.popularity desc, p.media_id desc
      ) as rn
    from (
      select * from anime_pool
      union all
      select * from manga_pool
    ) p
  ),
  counts as (
    select
      count(*) filter (where rk.media_type = 'ANIME') as a_count,
      count(*) filter (where rk.media_type = 'MANGA') as m_count
    from ranked rk
  ),
  quota as (
    -- Half/half; when one side starves the other side fills the remainder.
    -- Manga takes its half first, anime takes the rest, manga tops up last.
    select
      least(a_count, v_lim - least(m_count, v_half)) as a_take0,
      least(m_count, v_half) as m_take0
    from counts
  ),
  quota_final as (
    select
      q.a_take0 as a_take,
      least((select m_count from counts), v_lim - q.a_take0) as m_take
    from quota q
  )
  select
    r.media_type,
    r.media_id,
    r.title,
    r.cover_image_large,
    r.cover_image_medium,
    r.cover_image_color,
    r.genres,
    r.average_score,
    r.format,
    r.year,
    r.synopsis,
    r.episodes,
    r.chapters,
    r.volumes,
    case
      when r.media_type = 'ANIME' and r.format = 'TV'
        then public._taste_deck_seasons_count(r.media_id)
      else null
    end as seasons_count,
    avail.has_dub,
    avail.has_sub
  from ranked r
  cross join quota_final q
  left join lateral (
    -- Aggregates over zero rows yield null -> "unknown" stays distinct from false.
    select
      bool_or(exists (
        select 1
        from unnest(pa.audio_langs) as lang
        where lower(trim(lang)) not in ('', 'ja', 'jpn', 'japanese', 'unknown')
      )) as has_dub,
      bool_or(coalesce(array_length(pa.subtitle_langs, 1), 0) > 0) as has_sub
    from public.provider_availability pa
    where pa.media_type = r.media_type
      and pa.media_id = r.media_id
  ) avail on true
  where (r.media_type = 'ANIME' and r.rn <= q.a_take)
     or (r.media_type = 'MANGA' and r.rn <= q.m_take)
  order by r.mirrored desc, r.popularity desc, r.media_id desc;
end;
$$;

revoke all on function public.fetch_taste_deck_batch(integer) from public;
grant execute on function public.fetch_taste_deck_batch(integer) to authenticated, service_role;
