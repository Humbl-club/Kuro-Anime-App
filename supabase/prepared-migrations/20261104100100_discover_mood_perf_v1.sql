-- Discover usability: mood query performance (2026-11-04, lead fix after the live timing check).
--
-- Measured as an authenticated user against production right after 20261104100000:
--   discover_mood_v1('cozy','MANGA')    statement timeout (8 s)
--   discover_mood_v1('intense','MANGA') statement timeout (8 s)
--   discover_mood_v1('short','MANGA')   2,658 ms
--   discover_mood_v1('cozy','ANIME')    407 ms
-- Cause: the realm branch read the view media_realm_membership_effective (a FULL JOIN of the
-- rules matview with editorial deltas and overrides) per candidate, plus a correlated NOT EXISTS over
-- the same view; no index can serve that. The manga "short" branch had no (status, popularity) index
-- (anime has idx_anime_status_popularity_id).
-- Change: candidates and the excluded set come from the indexed matview media_realm_membership
-- (realm index), aggregated once, then joined to anime/manga by primary key. Editorial realm deltas
-- and overrides do not affect mood pages (they still drive realm rails and the taste engine).
-- Same signature, return shape and grants. Adds idx_manga_status_popularity_id.
-- Rollback: re-run the discover_mood_v1 definition from 20261104100000 and
--   drop index if exists public.idx_manga_status_popularity_id.

begin;

set local lock_timeout = '3s';
set local statement_timeout = '120s';
set local search_path = public, extensions;

create index if not exists idx_manga_status_popularity_id
  on public.manga using btree (status, popularity desc nulls last, id desc);

create or replace function public.discover_mood_v1(
  p_mood text,
  p_media_type text default 'ANIME',
  p_limit integer default 24,
  p_offset integer default 0
)
returns table (
  media_type text, rank integer, id integer,
  title_english text, title_romaji text, title_native text,
  cover_image_large text, cover_image_medium text, banner_image text,
  format text, status text, episode_count integer, chapter_count integer, volumes integer,
  season_year integer, start_date_year integer,
  average_score integer, popularity integer, trending integer, favourites integer,
  genres text[], created_at timestamptz,
  franchise_id integer, list_status text,
  reason_media_id integer, reason_title text
)
language plpgsql
stable
security definer
set search_path = public, extensions
as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_uid_text text := auth.uid()::text;
  v_type text := upper(btrim(coalesce(p_media_type, '')));
  v_mood text := lower(btrim(coalesce(p_mood, '')));
  v_limit integer := least(60, greatest(1, coalesce(p_limit, 24)));
  v_offset integer := least(440, greatest(0, coalesce(p_offset, 0)));
  v_pool integer;
  v_pool_cap constant integer := 4000;
  v_got integer;
  v_distinct integer;
  v_threshold real := 0.25;
  v_cozy text[] := array['slice-of-life-iyashikei', 'food-craft', 'family-generations'];
  v_not_cozy text[] := array['horror-dread', 'tragedy-tearjerker', 'psychological-thriller'];
  v_intense text[] := array['psychological-thriller', 'horror-dread', 'dark-fantasy', 'war-military',
                            'crime-underworld', 'mind-game-strategy'];
  v_realms boolean := to_regclass('public.media_realm_membership') is not null;
  v_seed integer;
  v_seed_title text;
  v_ids integer[];
begin
  if v_type not in ('ANIME', 'MANGA') then
    raise exception 'INVALID_MEDIUM: p_media_type must be ANIME or MANGA';
  end if;
  if v_mood not in ('short', 'cozy', 'intense', 'like_last_loved') then
    raise exception 'INVALID_MOOD: p_mood must be short, cozy, intense or like_last_loved';
  end if;
  v_pool := least(v_pool_cap, (v_offset + v_limit) * 2 + 40);

  if v_mood = 'like_last_loved' then
    -- like_last_loved: the caller's seed; signed out or no seed answers no rows.
    if v_uid is null then
      return;
    end if;
    if v_type = 'ANIME' then
      select ul.anime_id into v_seed
      from public.anime_user_lists ul
      where ul.user_id = v_uid_text and ul.list_type = 'COMPLETED'
      order by (coalesce(ul.rating, 0) >= 8) desc, ul.updated_at desc, ul.anime_id desc
      limit 1;
    else
      select ul.manga_id into v_seed
      from public.manga_user_lists ul
      where ul.user_id = v_uid_text and ul.list_type = 'COMPLETED'
      order by (coalesce(ul.rating, 0) >= 8) desc, ul.updated_at desc, ul.manga_id desc
      limit 1;
    end if;
    if v_seed is null then
      select e.media_id into v_seed
      from public.taste_signal_events e
      where e.user_id = v_uid and e.media_type = v_type and e.event_type = 'deck_love'
      order by e.created_at desc, e.id desc
      limit 1;
    end if;
    if v_seed is null then
      return;
    end if;
    if v_type = 'ANIME' then
      select coalesce(a.title_english, a.title_romaji, a.title_native) into v_seed_title
      from public.anime a where a.id = v_seed;
    else
      select coalesce(m.title_english, m.title_romaji, m.title_native) into v_seed_title
      from public.manga m where m.id = v_seed;
    end if;
    select array_agg(r.media_id order by r.ord) into v_ids
    from public.recommend_ids_similar_to_seeds(v_type, array[v_seed], 60, false)
         with ordinality as r(media_id, overlap_count, score, ord)
    where r.media_id <> v_seed;

    return query
    select * from public._discover_page_v1(
      v_uid, v_type, coalesce(v_ids, '{}'::integer[]), true, v_limit, v_offset, v_seed, v_seed_title
    );
    return;
  end if;

  loop
    if v_mood = 'short' then
      if v_type = 'ANIME' then
        select array_agg(s.aid order by s.pop desc, s.aid desc) into v_ids
        from (
          select a.id as aid, coalesce(a.popularity, 0) as pop
          from public.anime a
          where coalesce(a.is_adult, false) = false
            and not (coalesce(a.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
            and nullif(btrim(coalesce(a.cover_image_large, a.cover_image_medium, '')), '') is not null
            and coalesce(a.average_score, 0) >= 70
            and ((upper(coalesce(a.format, '')) in ('TV', 'ONA', 'OVA') and a.status = 'FINISHED'
                  and a.episodes between 1 and 13)
                 or (upper(coalesce(a.format, '')) = 'MOVIE' and a.duration between 1 and 25))
            and (v_uid is null or not exists (
                  select 1 from public.taste_signal_events e
                  where e.user_id = v_uid and e.media_type = 'ANIME' and e.media_id = a.id
                    and e.event_type in ('deck_skip', 'deck_known')
                    and e.created_at > now() - interval '365 days'))
            and (v_uid is null or not exists (
                  select 1 from public.anime_user_lists ul
                  where ul.user_id = v_uid_text and ul.anime_id = a.id))
          order by pop desc, aid desc
          limit v_pool
        ) s;
      else
        select array_agg(s.mid order by s.pop desc, s.mid desc) into v_ids
        from (
          select m.id as mid, coalesce(m.popularity, 0) as pop
          from public.manga m
          where coalesce(m.is_adult, false) = false
            and not (coalesce(m.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
            and nullif(btrim(coalesce(m.cover_image_large, m.cover_image_medium, '')), '') is not null
            and coalesce(m.average_score, 0) >= 70
            and m.status = 'FINISHED'
            and (m.chapters between 1 and 50 or (m.chapters is null and m.volumes between 1 and 5))
            and (v_uid is null or not exists (
                  select 1 from public.taste_signal_events e
                  where e.user_id = v_uid and e.media_type = 'MANGA' and e.media_id = m.id
                    and e.event_type in ('deck_skip', 'deck_known')
                    and e.created_at > now() - interval '365 days'))
            and (v_uid is null or not exists (
                  select 1 from public.manga_user_lists ul
                  where ul.user_id = v_uid_text and ul.manga_id = m.id))
          order by pop desc, mid desc
          limit v_pool
        ) s;
      end if;
    elsif v_realms then
      execute $q$
        with cand as (
          select r.media_id as mid, sum(r.weight)::real as w
          from public.media_realm_membership r
          where r.media_type = $1 and r.realm = any($2) and r.weight >= $4
          group by r.media_id
        ), excl as (
          select distinct x.media_id as mid
          from public.media_realm_membership x
          where x.media_type = $1 and x.realm = any($3) and x.weight >= $4
        )
        select array_agg(s.mid order by s.w desc, s.pop desc, s.mid desc)
        from (
          select c.mid, c.w, coalesce(t.pop, 0) as pop
          from cand c
          join (
            select a.id, a.popularity as pop, a.average_score as sc, a.genres as g, a.is_adult as adult, a.format as f,
                   coalesce(a.cover_image_large, a.cover_image_medium, '') as cover
            from public.anime a where $1 = 'ANIME'
            union all
            select m.id, m.popularity, m.average_score, m.genres, m.is_adult, m.format,
                   coalesce(m.cover_image_large, m.cover_image_medium, '')
            from public.manga m where $1 = 'MANGA'
          ) t on t.id = c.mid
          where coalesce(t.adult, false) = false
            and not (coalesce(t.g, '{}'::text[]) && array['Hentai', 'Ecchi'])
            and nullif(btrim(t.cover), '') is not null
            and coalesce(t.sc, 0) >= 65
            and ($1 = 'MANGA' or upper(coalesce(t.f, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT'))
            and ($5 = false or not ('Horror' = any(coalesce(t.g, '{}'::text[]))))
            and not exists (select 1 from excl e where e.mid = c.mid)
            and ($7::uuid is null or not exists (
                  select 1 from public.taste_signal_events e
                  where e.user_id = $7 and e.media_type = $1 and e.media_id = c.mid
                    and e.event_type in ('deck_skip', 'deck_known')
                    and e.created_at > now() - interval '365 days'))
            and ($7::uuid is null or not exists (
                  select 1 from public.anime_user_lists ul
                  where $1 = 'ANIME' and ul.user_id = $7::text and ul.anime_id = c.mid))
            and ($7::uuid is null or not exists (
                  select 1 from public.manga_user_lists ul
                  where $1 = 'MANGA' and ul.user_id = $7::text and ul.manga_id = c.mid))
          order by 2 desc, 3 desc, 1 desc
          limit $6
        ) s
      $q$ into v_ids
      using v_type,
            case when v_mood = 'cozy' then v_cozy else v_intense end,
            case when v_mood = 'cozy' then v_not_cozy else array[]::text[] end,
            v_threshold, v_mood = 'cozy', v_pool, v_uid;
    elsif v_type = 'ANIME' then
      select array_agg(s.aid order by s.pop desc, s.aid desc) into v_ids
      from (
        select a.id as aid, coalesce(a.popularity, 0) as pop
        from public.anime a
        where coalesce(a.is_adult, false) = false
          and not (coalesce(a.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
          and nullif(btrim(coalesce(a.cover_image_large, a.cover_image_medium, '')), '') is not null
          and coalesce(a.average_score, 0) >= 65
          and upper(coalesce(a.format, '')) not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
          and case when v_mood = 'cozy'
                   then 'Slice of Life' = any(coalesce(a.genres, '{}'::text[]))
                        and not (coalesce(a.genres, '{}'::text[]) && array['Horror', 'Thriller', 'Psychological'])
                   else coalesce(a.genres, '{}'::text[]) && array['Thriller', 'Horror', 'Psychological'] end
          and (v_uid is null or not exists (
                select 1 from public.taste_signal_events e
                where e.user_id = v_uid and e.media_type = 'ANIME' and e.media_id = a.id
                  and e.event_type in ('deck_skip', 'deck_known')
                  and e.created_at > now() - interval '365 days'))
          and (v_uid is null or not exists (
                select 1 from public.anime_user_lists ul
                where ul.user_id = v_uid_text and ul.anime_id = a.id))
        order by pop desc, aid desc
        limit v_pool
      ) s;
    else
      select array_agg(s.mid order by s.pop desc, s.mid desc) into v_ids
      from (
        select m.id as mid, coalesce(m.popularity, 0) as pop
        from public.manga m
        where coalesce(m.is_adult, false) = false
          and not (coalesce(m.genres, '{}'::text[]) && array['Hentai', 'Ecchi'])
          and nullif(btrim(coalesce(m.cover_image_large, m.cover_image_medium, '')), '') is not null
          and coalesce(m.average_score, 0) >= 65
          and case when v_mood = 'cozy'
                   then 'Slice of Life' = any(coalesce(m.genres, '{}'::text[]))
                        and not (coalesce(m.genres, '{}'::text[]) && array['Horror', 'Thriller', 'Psychological'])
                   else coalesce(m.genres, '{}'::text[]) && array['Thriller', 'Horror', 'Psychological'] end
          and (v_uid is null or not exists (
                select 1 from public.taste_signal_events e
                where e.user_id = v_uid and e.media_type = 'MANGA' and e.media_id = m.id
                  and e.event_type in ('deck_skip', 'deck_known')
                  and e.created_at > now() - interval '365 days'))
          and (v_uid is null or not exists (
                select 1 from public.manga_user_lists ul
                where ul.user_id = v_uid_text and ul.manga_id = m.id))
        order by pop desc, mid desc
        limit v_pool
      ) s;
    end if;

    v_got := coalesce(cardinality(v_ids), 0);
    exit when v_got < v_pool or v_pool >= v_pool_cap;
    select count(distinct coalesce(fc.component_label, x.mid)) into v_distinct
    from unnest(v_ids) as x(mid)
    left join public.media_franchise_components fc on fc.media_type = v_type and fc.media_id = x.mid;
    exit when v_distinct > v_offset + v_limit;
    v_pool := least(v_pool_cap, v_pool * 2);
  end loop;

  return query
  select * from public._discover_page_v1(
    v_uid, v_type, coalesce(v_ids, '{}'::integer[]), true, v_limit, v_offset
  );
end;
$$;

revoke all on function public.discover_mood_v1(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.discover_mood_v1(text, text, integer, integer) to anon, authenticated, service_role;

commit;
