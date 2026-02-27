-- Hardens synopsis enrichment so runs continue from where they left off without
-- reprocessing the same failed items every cycle.

begin;

alter table if exists public.anime
  add column if not exists synopsis_enhanced_retry_count integer not null default 0,
  add column if not exists synopsis_enhanced_last_attempt_at timestamptz null,
  add column if not exists synopsis_enhanced_next_retry_at timestamptz null,
  add column if not exists synopsis_enhanced_last_error text null,
  add column if not exists synopsis_enhanced_source_hash text null;

alter table if exists public.manga
  add column if not exists synopsis_enhanced_retry_count integer not null default 0,
  add column if not exists synopsis_enhanced_last_attempt_at timestamptz null,
  add column if not exists synopsis_enhanced_next_retry_at timestamptz null,
  add column if not exists synopsis_enhanced_last_error text null,
  add column if not exists synopsis_enhanced_source_hash text null;

create index if not exists idx_anime_synopsis_retry_queue
  on public.anime (synopsis_enhanced_state, synopsis_enhanced_next_retry_at, synopsis_enhanced_updated_at, updated_at)
  where description is not null;

create index if not exists idx_manga_synopsis_retry_queue
  on public.manga (synopsis_enhanced_state, synopsis_enhanced_next_retry_at, synopsis_enhanced_updated_at, updated_at)
  where description is not null;

update public.anime
set synopsis_enhanced_source_hash = md5(coalesce(description_normalized, description, ''))
where synopsis_enhanced_source_hash is null
  and coalesce(description, '') <> '';

update public.manga
set synopsis_enhanced_source_hash = md5(coalesce(description_normalized, description, ''))
where synopsis_enhanced_source_hash is null
  and coalesce(description, '') <> '';

-- Prevent immediate hot-looping on legacy failed rows.
update public.anime
set synopsis_enhanced_next_retry_at = coalesce(synopsis_enhanced_next_retry_at, now() + interval '6 hours')
where synopsis_enhanced_state = 'failed';

update public.manga
set synopsis_enhanced_next_retry_at = coalesce(synopsis_enhanced_next_retry_at, now() + interval '6 hours')
where synopsis_enhanced_state = 'failed';

create or replace function public.get_synopsis_enrichment_candidates(
  p_media_type text,
  p_limit integer default 25
)
returns table (
  media_type text,
  media_id integer,
  title text,
  source_description text,
  source_description_normalized text,
  synopsis_enhanced text,
  synopsis_enhanced_state text,
  source_updated_at timestamptz,
  synopsis_enhanced_updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_media text := upper(trim(coalesce(p_media_type, '')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 200));
begin
  if v_media = 'ANIME' then
    return query
    with candidates as (
      select a.id
      from public.anime a
      where coalesce(a.description, '') <> ''
        and coalesce(a.synopsis_enhanced_next_retry_at, to_timestamp(0)) <= now()
        and (
          a.synopsis_enhanced_state in ('pending', 'failed')
          or a.synopsis_enhanced is null
          or a.synopsis_enhanced_updated_at is null
          or a.synopsis_enhanced_updated_at < coalesce(a.updated_at, a.created_at)
          or a.synopsis_enhanced_source_hash is distinct from md5(coalesce(a.description_normalized, a.description, ''))
        )
      order by
        case
          when (
            a.synopsis_enhanced is null
            or a.synopsis_enhanced_updated_at is null
            or a.synopsis_enhanced_updated_at < coalesce(a.updated_at, a.created_at)
            or a.synopsis_enhanced_source_hash is distinct from md5(coalesce(a.description_normalized, a.description, ''))
          ) then 0
          when a.synopsis_enhanced_state = 'pending' then 1
          else 2
        end,
        coalesce(a.synopsis_enhanced_next_retry_at, to_timestamp(0)) asc,
        coalesce(a.synopsis_enhanced_updated_at, to_timestamp(0)) asc,
        a.id asc
      for update skip locked
      limit v_limit
    ),
    claimed as (
      update public.anime a
      set
        synopsis_enhanced_state = 'pending',
        synopsis_enhanced_last_attempt_at = now(),
        synopsis_enhanced_next_retry_at = now() + interval '20 minutes'
      from candidates c
      where a.id = c.id
      returning a.*
    )
    select
      'ANIME'::text,
      c.id,
      coalesce(c.title_english, c.title_romaji, c.title_native, 'Unknown') as title,
      c.description,
      c.description_normalized,
      c.synopsis_enhanced,
      c.synopsis_enhanced_state,
      coalesce(c.updated_at, c.created_at) as source_updated_at,
      c.synopsis_enhanced_updated_at
    from claimed c
    order by c.id asc;
    return;

  elsif v_media = 'MANGA' then
    return query
    with candidates as (
      select m.id
      from public.manga m
      where coalesce(m.description, '') <> ''
        and coalesce(m.synopsis_enhanced_next_retry_at, to_timestamp(0)) <= now()
        and (
          m.synopsis_enhanced_state in ('pending', 'failed')
          or m.synopsis_enhanced is null
          or m.synopsis_enhanced_updated_at is null
          or m.synopsis_enhanced_updated_at < coalesce(m.updated_at, m.created_at)
          or m.synopsis_enhanced_source_hash is distinct from md5(coalesce(m.description_normalized, m.description, ''))
        )
      order by
        case
          when (
            m.synopsis_enhanced is null
            or m.synopsis_enhanced_updated_at is null
            or m.synopsis_enhanced_updated_at < coalesce(m.updated_at, m.created_at)
            or m.synopsis_enhanced_source_hash is distinct from md5(coalesce(m.description_normalized, m.description, ''))
          ) then 0
          when m.synopsis_enhanced_state = 'pending' then 1
          else 2
        end,
        coalesce(m.synopsis_enhanced_next_retry_at, to_timestamp(0)) asc,
        coalesce(m.synopsis_enhanced_updated_at, to_timestamp(0)) asc,
        m.id asc
      for update skip locked
      limit v_limit
    ),
    claimed as (
      update public.manga m
      set
        synopsis_enhanced_state = 'pending',
        synopsis_enhanced_last_attempt_at = now(),
        synopsis_enhanced_next_retry_at = now() + interval '20 minutes'
      from candidates c
      where m.id = c.id
      returning m.*
    )
    select
      'MANGA'::text,
      c.id,
      coalesce(c.title_english, c.title_romaji, c.title_native, 'Unknown') as title,
      c.description,
      c.description_normalized,
      c.synopsis_enhanced,
      c.synopsis_enhanced_state,
      coalesce(c.updated_at, c.created_at) as source_updated_at,
      c.synopsis_enhanced_updated_at
    from claimed c
    order by c.id asc;
    return;
  end if;

  raise exception 'Unsupported media type for synopsis enrichment: %', p_media_type
    using errcode = '22023';
end;
$$;

create or replace function public.get_synopsis_enrichment_backlog_count(
  p_media_type text
)
returns table (
  backlog_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_media text := upper(trim(coalesce(p_media_type, '')));
begin
  if v_media = 'ANIME' then
    return query
    with base as (
      select
        a.synopsis_enhanced,
        a.synopsis_enhanced_state,
        a.synopsis_enhanced_updated_at,
        a.synopsis_enhanced_next_retry_at,
        coalesce(a.updated_at, a.created_at) as source_updated_at,
        (
          a.synopsis_enhanced is null
          or a.synopsis_enhanced_updated_at is null
          or a.synopsis_enhanced_updated_at < coalesce(a.updated_at, a.created_at)
          or a.synopsis_enhanced_source_hash is distinct from md5(coalesce(a.description_normalized, a.description, ''))
        ) as needs_refresh
      from public.anime a
      where coalesce(a.description, '') <> ''
    )
    select count(*)::integer
    from base b
    where
      b.needs_refresh
      or (
        b.synopsis_enhanced_state = 'pending'
        and coalesce(b.synopsis_enhanced_next_retry_at, to_timestamp(0)) <= now()
      )
      or (
        b.synopsis_enhanced_state = 'failed'
        and coalesce(b.synopsis_enhanced_next_retry_at, to_timestamp(0)) <= now()
      );
    return;

  elsif v_media = 'MANGA' then
    return query
    with base as (
      select
        m.synopsis_enhanced,
        m.synopsis_enhanced_state,
        m.synopsis_enhanced_updated_at,
        m.synopsis_enhanced_next_retry_at,
        coalesce(m.updated_at, m.created_at) as source_updated_at,
        (
          m.synopsis_enhanced is null
          or m.synopsis_enhanced_updated_at is null
          or m.synopsis_enhanced_updated_at < coalesce(m.updated_at, m.created_at)
          or m.synopsis_enhanced_source_hash is distinct from md5(coalesce(m.description_normalized, m.description, ''))
        ) as needs_refresh
      from public.manga m
      where coalesce(m.description, '') <> ''
    )
    select count(*)::integer
    from base b
    where
      b.needs_refresh
      or (
        b.synopsis_enhanced_state = 'pending'
        and coalesce(b.synopsis_enhanced_next_retry_at, to_timestamp(0)) <= now()
      )
      or (
        b.synopsis_enhanced_state = 'failed'
        and coalesce(b.synopsis_enhanced_next_retry_at, to_timestamp(0)) <= now()
      );
    return;
  end if;

  raise exception 'Unsupported media type for synopsis enrichment: %', p_media_type
    using errcode = '22023';
end;
$$;

create or replace function public.upsert_synopsis_enhanced(
  p_media_type text,
  p_media_id integer,
  p_text text,
  p_meta jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_media text := upper(trim(coalesce(p_media_type, '')));
  v_text text := nullif(trim(coalesce(p_text, '')), '');
  v_now timestamptz := now();
begin
  if v_text is null then
    raise exception 'Synopsis text must not be empty'
      using errcode = '22023';
  end if;

  if v_media = 'ANIME' then
    update public.anime
    set
      synopsis_enhanced = v_text,
      synopsis_enhanced_source = nullif(trim(coalesce(p_meta->>'source', '')), ''),
      synopsis_enhanced_model = nullif(trim(coalesce(p_meta->>'model', '')), ''),
      synopsis_enhanced_version = nullif(trim(coalesce(p_meta->>'version', '')), ''),
      synopsis_enhanced_updated_at = v_now,
      synopsis_enhanced_state = 'ready',
      synopsis_enhanced_retry_count = 0,
      synopsis_enhanced_next_retry_at = null,
      synopsis_enhanced_last_attempt_at = v_now,
      synopsis_enhanced_last_error = null,
      synopsis_enhanced_source_hash = md5(coalesce(description_normalized, description, ''))
    where id = p_media_id;

    if not found then
      raise exception 'Anime % not found', p_media_id
        using errcode = 'P0002';
    end if;
    return;
  elsif v_media = 'MANGA' then
    update public.manga
    set
      synopsis_enhanced = v_text,
      synopsis_enhanced_source = nullif(trim(coalesce(p_meta->>'source', '')), ''),
      synopsis_enhanced_model = nullif(trim(coalesce(p_meta->>'model', '')), ''),
      synopsis_enhanced_version = nullif(trim(coalesce(p_meta->>'version', '')), ''),
      synopsis_enhanced_updated_at = v_now,
      synopsis_enhanced_state = 'ready',
      synopsis_enhanced_retry_count = 0,
      synopsis_enhanced_next_retry_at = null,
      synopsis_enhanced_last_attempt_at = v_now,
      synopsis_enhanced_last_error = null,
      synopsis_enhanced_source_hash = md5(coalesce(description_normalized, description, ''))
    where id = p_media_id;

    if not found then
      raise exception 'Manga % not found', p_media_id
        using errcode = 'P0002';
    end if;
    return;
  end if;

  raise exception 'Unsupported media type for synopsis enrichment: %', p_media_type
    using errcode = '22023';
end;
$$;

create or replace function public.mark_synopsis_enhanced_failed(
  p_media_type text,
  p_media_id integer,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_media text := upper(trim(coalesce(p_media_type, '')));
  v_now timestamptz := now();
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  if v_media = 'ANIME' then
    update public.anime
    set
      synopsis_enhanced_state = 'failed',
      synopsis_enhanced_updated_at = v_now,
      synopsis_enhanced_last_attempt_at = v_now,
      synopsis_enhanced_last_error = coalesce(v_reason, synopsis_enhanced_last_error),
      synopsis_enhanced_retry_count = synopsis_enhanced_retry_count + 1,
      synopsis_enhanced_next_retry_at = case
        when coalesce(v_reason, '') = 'insufficient_source_text' then v_now + interval '7 days'
        when synopsis_enhanced_retry_count < 1 then v_now + interval '2 hours'
        when synopsis_enhanced_retry_count < 3 then v_now + interval '12 hours'
        when synopsis_enhanced_retry_count < 6 then v_now + interval '1 day'
        else v_now + interval '3 days'
      end
    where id = p_media_id;

    if not found then
      raise exception 'Anime % not found', p_media_id
        using errcode = 'P0002';
    end if;
    return;
  elsif v_media = 'MANGA' then
    update public.manga
    set
      synopsis_enhanced_state = 'failed',
      synopsis_enhanced_updated_at = v_now,
      synopsis_enhanced_last_attempt_at = v_now,
      synopsis_enhanced_last_error = coalesce(v_reason, synopsis_enhanced_last_error),
      synopsis_enhanced_retry_count = synopsis_enhanced_retry_count + 1,
      synopsis_enhanced_next_retry_at = case
        when coalesce(v_reason, '') = 'insufficient_source_text' then v_now + interval '7 days'
        when synopsis_enhanced_retry_count < 1 then v_now + interval '2 hours'
        when synopsis_enhanced_retry_count < 3 then v_now + interval '12 hours'
        when synopsis_enhanced_retry_count < 6 then v_now + interval '1 day'
        else v_now + interval '3 days'
      end
    where id = p_media_id;

    if not found then
      raise exception 'Manga % not found', p_media_id
        using errcode = 'P0002';
    end if;
    return;
  end if;

  raise exception 'Unsupported media type for synopsis enrichment: %', p_media_type
    using errcode = '22023';
end;
$$;

revoke all on function public.get_synopsis_enrichment_backlog_count(text)
  from public, anon, authenticated;
grant execute on function public.get_synopsis_enrichment_backlog_count(text)
  to service_role;

commit;
