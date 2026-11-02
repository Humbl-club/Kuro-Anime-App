-- ADR 2026-07-31: Taste Deck v1 (flag: taste_deck_v1).
-- - fetch_taste_deck_batch: one-title-at-a-time deck, never repeats, half anime / half manga.
-- - record_taste_deck_signal: writes deck_love/deck_known/deck_skip into taste_signal_events,
--   one deck signal per user/media (changing your mind works), retract supported, 300/day cap.
-- - fetch_my_taste_profile: caller reads their own user_taste_profiles row.
--
-- RLS note: user_taste_profiles already has RLS enabled plus policy taste_profiles_own_all
-- (for all using auth.uid() = user_id) from 20260203171100_concierge_core.sql, so select-own
-- is already enforced; nothing to add there.

-- ---------------------------------------------------------------------------
-- 1) Deck batch fetch (SECURITY INVOKER: reads only catalog + caller's own rows)
-- ---------------------------------------------------------------------------
create or replace function public.fetch_taste_deck_batch(p_limit integer default 12)
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
  synopsis text
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
    r.synopsis
  from ranked r, quota_final q
  where (r.media_type = 'ANIME' and r.rn <= q.a_take)
     or (r.media_type = 'MANGA' and r.rn <= q.m_take)
  order by r.mirrored desc, r.popularity desc, r.media_id desc;
end;
$$;

revoke all on function public.fetch_taste_deck_batch(integer) from public;
grant execute on function public.fetch_taste_deck_batch(integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) Deck signal writer (SECURITY DEFINER: writes taste events for JWT user)
-- ---------------------------------------------------------------------------
create or replace function public.record_taste_deck_signal(
  p_media_type text,
  p_media_id integer,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_media_type text := upper(trim(coalesce(p_media_type, '')));
  v_action text := lower(trim(coalesce(p_action, '')));
  v_event_type text;
  v_strength real;
  v_deleted integer := 0;
  v_day_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_media_type not in ('ANIME', 'MANGA') then
    raise exception 'unsupported media type: %', p_media_type using errcode = '22023';
  end if;
  if p_media_id is null then
    raise exception 'media_id required' using errcode = '22023';
  end if;
  if v_action not in ('love', 'known', 'skip', 'retract') then
    raise exception 'unsupported deck action: %', p_action using errcode = '22023';
  end if;

  -- Rate limit: max 300 deck events per user per rolling 24h (inserts only).
  -- Checked before the dedupe delete so a limited user keeps their prior signal.
  if v_action <> 'retract' then
    select count(*) into v_day_count
    from public.taste_signal_events
    where user_id = v_uid
      and event_type in ('deck_love', 'deck_known', 'deck_skip')
      and created_at > now() - interval '1 day';
    if v_day_count >= 300 then
      raise exception 'taste deck signal rate limit exceeded'
        using errcode = 'P0001', detail = 'RATE_LIMITED';
    end if;
  end if;

  -- One deck signal per user/media: drop the prior deck_* event first so a
  -- changed mind replaces instead of stacking. Non-deck events are untouched.
  delete from public.taste_signal_events
  where user_id = v_uid
    and media_type = v_media_type
    and media_id = p_media_id
    and event_type in ('deck_love', 'deck_known', 'deck_skip');
  get diagnostics v_deleted = row_count;

  if v_action = 'retract' then
    if v_deleted > 0 then
      perform public._taste_enqueue_recompute(v_uid, 'deck_retract');
    end if;
    return jsonb_build_object(
      'ok', true,
      'action', 'retract',
      'media_type', v_media_type,
      'media_id', case when v_deleted > 0 then p_media_id else null end,
      'deleted', v_deleted
    );
  end if;

  v_event_type := case v_action
    when 'love' then 'deck_love'
    when 'known' then 'deck_known'
    when 'skip' then 'deck_skip'
  end;
  v_strength := case v_action
    when 'love' then 0.55
    when 'known' then 0.25
    when 'skip' then -0.45
  end;

  insert into public.taste_signal_events (
    user_id, media_id, media_type, event_type, event_strength,
    signal_value, source_transition, is_import
  ) values (
    v_uid, p_media_id, v_media_type, v_event_type, v_strength,
    jsonb_build_object('action', v_action),
    jsonb_build_object('source', 'taste_deck'),
    false
  );

  -- Mirror _taste_emit_event: every inserted signal enqueues a profile recompute.
  perform public._taste_enqueue_recompute(v_uid, v_event_type);

  return jsonb_build_object(
    'ok', true,
    'action', v_action,
    'event_type', v_event_type,
    'event_strength', v_strength,
    'media_type', v_media_type,
    'media_id', p_media_id,
    'replaced_prior', v_deleted > 0
  );
end;
$$;

revoke all on function public.record_taste_deck_signal(text, integer, text) from public;
grant execute on function public.record_taste_deck_signal(text, integer, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) Caller reads own taste profile (SECURITY INVOKER; RLS policy already owns it)
-- ---------------------------------------------------------------------------
create or replace function public.fetch_my_taste_profile()
returns table (
  vector jsonb,
  updated_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  return query
  select p.vector, p.updated_at
  from public.user_taste_profiles p
  where p.user_id = auth.uid();
end;
$$;

revoke all on function public.fetch_my_taste_profile() from public;
grant execute on function public.fetch_my_taste_profile() to authenticated, service_role;
