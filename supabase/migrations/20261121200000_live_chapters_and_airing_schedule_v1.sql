-- Live chapter truth & airing schedule v1 (prepared 2026-11-21).
--
-- 1. Adds `latest_chapter` (numeric) and `latest_chapter_at` (timestamptz) to `public.manga`
--    so ongoing manga expose chapters released so far independently of completed total `chapters`,
--    and grants column SELECT to `anon` and `authenticated` (preserving 126 column-grant parity).
-- 2. Backfills `manga.latest_chapter` monotonically from non-extra `public.chapters` rows and from
--    existing MangaUpdates `catalogue_source_records` payloads when positive chapter counts exist.
-- 3. Extends `public.home_bundle_v1` (SECURITY INVOKER, jit off, authenticated only) with
--    anime `next_episode_number`/`next_airing_at` and manga `latest_chapter`/`next_chapter_number`/`next_chapter_at`.
-- 4. Updates `public.collection_feed_page` (authenticated only) to return
--    `coalesce(m.chapters, floor(m.latest_chapter)::int) as chapter_count` for ongoing manga.

begin;
set local search_path = public, extensions;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

alter table public.manga
  add column if not exists latest_chapter numeric
    constraint manga_latest_chapter_check check (latest_chapter is null or (latest_chapter > 0 and latest_chapter <= 99999)),
  add column if not exists latest_chapter_at timestamptz;

grant select (latest_chapter, latest_chapter_at) on public.manga to anon, authenticated;

do $$
begin
  if to_regclass('public.chapters') is not null then
    with chap_max as (
      select c.manga_id, max(c.number)::numeric as max_ch
      from public.chapters c
      where coalesce(c.is_side_story, false) = false
        and coalesce(c.is_extra, false) = false
        and coalesce(c.is_omake, false) = false
        and c.number > 0
        and c.number <= 99999
      group by c.manga_id
    )
    update public.manga m
    set latest_chapter = greatest(coalesce(m.latest_chapter, 0), cm.max_ch),
        latest_chapter_at = coalesce(m.latest_chapter_at, now())
    from chap_max cm
    where m.id = cm.manga_id
      and cm.max_ch > coalesce(m.latest_chapter, 0);
  end if;

  if to_regclass('public.catalogue_id_links') is not null
     and to_regclass('public.catalogue_source_records') is not null then
    with mu_ch as (
      select l.kuro_id as manga_id,
             max(
               case
                 when (r.payload ->> 'latestChapter') ~ '^[1-9][0-9]{0,4}(\.[0-9]{1,3})?$'
                   then (r.payload ->> 'latestChapter')::numeric
                 else coalesce(
                   nullif((regexp_match(coalesce(r.payload ->> 'status', ''), '\m([1-9][0-9]{0,4})\+?\s+[Cc]hapters?\M'))[1], '')::numeric,
                   0
                 )
               end
             ) as mu_latest
      from public.catalogue_id_links l
      join public.catalogue_source_records r
        on r.source = 'mangaupdates'
       and r.medium = 'manga'
       and r.source_key = l.source_key
      where l.kind = 'manga'
        and l.source = 'mangaupdates'
        and l.status = 'accepted'
      group by l.kuro_id
    )
    update public.manga m
    set latest_chapter = greatest(coalesce(m.latest_chapter, 0), mc.mu_latest),
        latest_chapter_at = coalesce(m.latest_chapter_at, now())
    from mu_ch mc
    where m.id = mc.manga_id
      and mc.mu_latest > 0
      and mc.mu_latest <= 99999
      and mc.mu_latest > coalesce(m.latest_chapter, 0);
  end if;
end;
$$;

create or replace function public.home_bundle_v1(
  p_medium text,
  p_locale text default 'en'::text,
  p_window_days integer default 7,
  p_active_limit integer default 12,
  p_event_limit integer default 20,
  p_cursor text default null::text
)
returns jsonb
language plpgsql
stable
set search_path = public, extensions
as $function$
declare
  v_uid uuid := auth.uid();
  v_user text;
  v_limit integer;
  v_events integer;
  v_window integer;
  v_cursor_at timestamptz;
  v_cursor_id integer;
  v_active jsonb;
  v_upcoming jsonb;
  v_pending jsonb;
  v_club jsonb := '[]'::jsonb;
  v_club_state text := 'none';
  v_club_label text := 'Your clubs';
  v_publication bigint := 0;
  v_next text;
  v_event_page jsonb;
  v_pending_page jsonb;
begin
  if v_uid is null then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM';
  end if;
  v_user := v_uid::text;
  v_limit := least(50, greatest(1, coalesce(p_active_limit, 12)));
  v_events := least(50, greatest(1, coalesce(p_event_limit, 20)));
  v_window := least(90, greatest(1, coalesce(p_window_days, 7)));

  if p_cursor is not null and p_cursor <> '' then
    begin
      v_cursor_at := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::integer;
    exception when others then
      raise exception 'INVALID_CURSOR';
    end;
  end if;

  if p_medium = 'anime' then
    with resume_page as materialized (
      select l.* from public.anime_home_resume_v1 l
      where l.user_id = v_user
        and (v_cursor_at is null or l.updated_at < v_cursor_at
          or (l.updated_at = v_cursor_at and l.anime_id < v_cursor_id))
      order by l.updated_at desc, l.anime_id desc
      limit v_limit + 1
    ), page as (
      select l.anime_id as media_id, l.list_type, l.progress, l.progress_label, l.server_revision,
             l.lifecycle_id, l.updated_at, l.unit_id,
             coalesce(a.title_english, a.title_romaji, a.title_native, 'Untitled') as title,
             a.banner_image, a.cover_image_large, a.format, a.episodes, a.status as catalogue_status,
             a.next_episode_number, a.next_airing_at,
             sp.series_id, sec.ordinal as section_ordinal, sec.kind as section_kind, sec.name as section_name,
             mat.base_color, mat.deep_color, mat.wash_color, mat.edge_color, mat.ink_color, mat.image_digest
      from resume_page l
      join public.anime a on a.id = l.anime_id
      left join lateral (select sp.* from public.series_entry_spans sp
        join public.series sr on sr.id = sp.series_id and sr.grouping_state = 'approved'
        join public.series_sections ss on ss.id = sp.section_id and ss.state = 'approved'
        where sp.anime_id = l.anime_id order by ss.sort_order, sp.id limit 1) sp on true
      left join public.series_sections sec on sec.id = sp.section_id
      left join public.artwork_materials mat on mat.image_url = coalesce(a.banner_image, a.cover_image_large) and mat.is_current
      where l.user_id = v_user
        and l.list_type in ('WATCHING', 'PLANNING')
        and (
          v_cursor_at is null
          or l.updated_at < v_cursor_at
          or (l.updated_at = v_cursor_at and l.anime_id < v_cursor_id)
        )
      order by l.updated_at desc, l.anime_id desc
      limit v_limit + 1
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'media_id', media_id,
      'list_type', list_type,
      'progress', progress,
      'progress_label', progress_label,
      'server_revision', server_revision,
      'lifecycle_id', lifecycle_id,
      'unit_id', unit_id,
      'title', title,
      'banner_image', banner_image,
      'cover_image', cover_image_large,
      'format', format,
      'episodes', episodes,
      'catalogue_status', catalogue_status,
      'next_episode_number', next_episode_number,
      'next_airing_at', next_airing_at,
      'series_id', series_id,
      'section_ordinal', section_ordinal,
      'section_kind', section_kind,
      'section_name', section_name,
      'material', case when image_digest is null then null else jsonb_build_object(
        'image_digest', image_digest, 'base', base_color, 'deep', deep_color,
        'wash', wash_color, 'edge', edge_color, 'ink', ink_color
      ) end
    ) order by updated_at desc, media_id desc), '[]'::jsonb),
    (select case when count(*) > v_limit then
       (select updated_at::text || '|' || media_id::text from page order by updated_at desc, media_id desc offset v_limit - 1 limit 1)
       else null end from page)
    into v_active, v_next
    from (
      select * from page
      order by updated_at desc, media_id desc
      limit v_limit
    ) p;
  else
    with page as (
      select l.manga_id as media_id, l.list_type, l.progress, l.progress_label, l.server_revision,
             l.lifecycle_id, l.updated_at, l.unit_id, l.volumes_progress,
             coalesce(m.title_english, m.title_romaji, m.title_native, 'Untitled') as title,
             m.cover_image_large, m.format, m.chapters, m.volumes, m.status as catalogue_status,
             m.latest_chapter, m.next_chapter_number, m.next_chapter_at,
             sp.series_id,
             mat.base_color, mat.deep_color, mat.wash_color, mat.edge_color, mat.ink_color, mat.image_digest
      from public.manga_home_resume_v1 l
      join public.manga m on m.id = l.manga_id
      left join lateral (select sp.* from public.series_entry_spans sp
        join public.series sr on sr.id = sp.series_id and sr.grouping_state = 'approved'
        where sp.manga_id = l.manga_id order by sp.id limit 1) sp on true
      left join public.artwork_materials mat on mat.image_url = m.cover_image_large and mat.is_current
      where l.user_id = v_user
        and l.list_type in ('READING', 'PLANNING')
        and (
          v_cursor_at is null
          or l.updated_at < v_cursor_at
          or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id)
        )
      order by l.updated_at desc, l.manga_id desc
      limit v_limit
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'media_id', media_id,
      'list_type', list_type,
      'progress', progress,
      'progress_label', progress_label,
      'volumes_progress', volumes_progress,
      'server_revision', server_revision,
      'lifecycle_id', lifecycle_id,
      'unit_id', unit_id,
      'title', title,
      'cover_image', cover_image_large,
      'format', format,
      'chapters', chapters,
      'latest_chapter', latest_chapter,
      'next_chapter_number', next_chapter_number,
      'next_chapter_at', next_chapter_at,
      'volumes', volumes,
      'catalogue_status', catalogue_status,
      'series_id', series_id,
      'material', case when image_digest is null then null else jsonb_build_object(
        'image_digest', image_digest, 'base', base_color, 'deep', deep_color,
        'wash', wash_color, 'edge', edge_color, 'ink', ink_color
      ) end
    ) order by updated_at desc, media_id desc), '[]'::jsonb)
    into v_active
    from page;

    v_next := null;
    if (
      select count(*) from (
        select 1 from public.manga_home_resume_v1 l
        where l.user_id = v_user and l.list_type in ('READING', 'PLANNING')
          and (v_cursor_at is null or l.updated_at < v_cursor_at or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id))
        limit v_limit + 1
      ) s
    ) > v_limit then
      select l.updated_at::text || '|' || l.manga_id::text into v_next
      from public.manga_home_resume_v1 l
      where l.user_id = v_user and l.list_type in ('READING', 'PLANNING')
        and (v_cursor_at is null or l.updated_at < v_cursor_at or (l.updated_at = v_cursor_at and l.manga_id < v_cursor_id))
      order by l.updated_at desc, l.manga_id desc
      offset v_limit - 1
      limit 1;
    end if;
  end if;

  v_pending_page := public.home_pending_page_v1(p_medium, v_events, null);
  v_pending := v_pending_page -> 'items';

  begin
    with eligible as (
      select c.id, c.media_id, c.media_type, c.spoiler_scope, c.created_at,
             case when c.spoiler_scope = 'none' then c.text else null end as body,
             public.club_peer_display_name(c.user_id) as display_name
      from public.title_comments c
      where c.user_id <> v_uid
        and public.shares_club_at_least(c.user_id, 'status')
        and (
          (p_medium = 'anime' and c.media_type = 'ANIME')
          or (p_medium = 'manga' and c.media_type = 'MANGA')
        )
        and exists (
          select 1 from public.anime_user_lists al
          where p_medium = 'anime' and al.user_id = v_user and al.anime_id = c.media_id
          union all
          select 1 from public.manga_user_lists ml
          where p_medium = 'manga' and ml.user_id = v_user and ml.manga_id = c.media_id
        )
      order by c.created_at desc
      limit 6
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'comment_id', id,
      'media_id', media_id,
      'media_type', media_type,
      'spoiler_scope', spoiler_scope,
      'text', body,
      'display_name', display_name,
      'created_at', created_at
    ) order by created_at desc), '[]'::jsonb)
    into v_club
    from eligible;

    if jsonb_array_length(coalesce(v_club, '[]'::jsonb)) = 0 then
      v_club_state := 'none';
      v_club := '[]'::jsonb;
    else
      v_club_state := 'ok';
      v_club_label := 'Your clubs';
    end if;
  exception when others then
    v_club := '[]'::jsonb;
    v_club_state := 'error';
    v_club_label := 'Your clubs';
  end;

  select revision into v_publication
  from public.home_publications
  where user_id = v_user and medium = p_medium;
  v_publication := coalesce(v_publication, 0);

  v_event_page := public.home_events_page_v1(p_medium, v_window, v_events, null);
  v_upcoming := v_event_page -> 'items';
  return jsonb_build_object(
    'medium', p_medium,
    'locale', coalesce(p_locale, 'en'),
    'window_days', v_window,
    'as_of', now(),
    'home_revision', v_publication,
    'active', coalesce(v_active, '[]'::jsonb),
    'upcoming', coalesce(v_upcoming, '[]'::jsonb),
    'upcoming_total', v_event_page -> 'total',
    'events_cursor', v_event_page ->> 'next_cursor',
    'pending', v_pending,
    'pending_total', v_pending_page -> 'total',
    'pending_cursor', v_pending_page ->> 'next_cursor',
    'schedule_state', case
      when p_medium = 'manga' and jsonb_array_length(coalesce(v_upcoming, '[]'::jsonb)) = 0
        then 'no_verified_schedule'
      else 'ok'
    end,
    'next_cursor', v_next,
    'club', jsonb_build_object('state', v_club_state, 'label', v_club_label, 'items', coalesce(v_club, '[]'::jsonb))
  );
end;
$function$;

alter function public.home_bundle_v1(text, text, integer, integer, integer, text) set jit to 'off';
revoke all on function public.home_bundle_v1(text, text, integer, integer, integer, text) from public, anon;
grant execute on function public.home_bundle_v1(text, text, integer, integer, integer, text) to authenticated;

create or replace function public.collection_feed_page(
  p_limit integer default 80,
  p_cursor_updated_at timestamptz default null,
  p_cursor_source_rank integer default null,
  p_cursor_row_id integer default null,
  p_list_type_anime text default null,
  p_list_type_manga text default null
)
returns table (
  list_updated_at timestamptz,
  source_rank integer,
  list_row_id integer,
  media_type text,
  id integer,
  title_english text,
  title_romaji text,
  title_native text,
  cover_image_large text,
  cover_image_medium text,
  banner_image text,
  format text,
  status text,
  episode_count integer,
  chapter_count integer,
  season_year integer,
  start_date_year integer,
  average_score integer,
  popularity integer,
  trending integer,
  favourites integer,
  genres text[],
  created_at timestamptz
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with uid as (
    select auth.uid()::text as user_id
  ),
  params as (
    select greatest(1, least(coalesce(p_limit, 80), 120))::int as lim
  ),
  feed as (
    select
      l.updated_at as list_updated_at,
      0::int as source_rank,
      l.id as list_row_id,
      'ANIME'::text as media_type,
      a.id,
      a.title_english,
      a.title_romaji,
      a.title_native,
      a.cover_image_large,
      a.cover_image_medium,
      a.banner_image,
      a.format,
      a.status,
      a.episodes as episode_count,
      null::int as chapter_count,
      a.season_year,
      a.start_date_year,
      a.average_score,
      a.popularity,
      a.trending,
      a.favourites,
      a.genres,
      a.created_at
    from public.anime_user_lists l
    join public.anime a on a.id = l.anime_id
    where
      l.user_id = (select user_id from uid)
      and (p_list_type_anime is null or l.list_type = p_list_type_anime)

    union all

    select
      l.updated_at as list_updated_at,
      1::int as source_rank,
      l.id as list_row_id,
      'MANGA'::text as media_type,
      m.id,
      m.title_english,
      m.title_romaji,
      m.title_native,
      m.cover_image_large,
      m.cover_image_medium,
      null::text as banner_image,
      m.format,
      m.status,
      null::int as episode_count,
      coalesce(m.chapters, floor(m.latest_chapter)::int) as chapter_count,
      null::int as season_year,
      m.start_date_year,
      m.average_score,
      m.popularity,
      m.trending,
      m.favourites,
      m.genres,
      m.created_at
    from public.manga_user_lists l
    join public.manga m on m.id = l.manga_id
    where
      l.user_id = (select user_id from uid)
      and (p_list_type_manga is null or l.list_type = p_list_type_manga)
  )
  select *
  from feed f
  where
    p_cursor_updated_at is null
    or f.list_updated_at < p_cursor_updated_at
    or (
      f.list_updated_at = p_cursor_updated_at
      and p_cursor_source_rank is not null
      and f.source_rank > p_cursor_source_rank
    )
    or (
      f.list_updated_at = p_cursor_updated_at
      and p_cursor_source_rank is not null
      and f.source_rank = p_cursor_source_rank
      and f.list_row_id < coalesce(p_cursor_row_id, 2147483647)
    )
  order by f.list_updated_at desc, f.source_rank asc, f.list_row_id desc
  limit (select lim from params);
$$;

revoke all on function public.collection_feed_page(integer, timestamptz, integer, integer, text, text) from public, anon;
grant execute on function public.collection_feed_page(integer, timestamptz, integer, integer, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
