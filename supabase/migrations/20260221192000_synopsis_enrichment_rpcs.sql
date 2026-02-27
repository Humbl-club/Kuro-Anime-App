-- RPCs for synopsis enrichment worker (service-role only).

begin;

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
    select
      'ANIME'::text,
      a.id,
      coalesce(a.title_english, a.title_romaji, a.title_native, 'Unknown') as title,
      a.description,
      a.description_normalized,
      a.synopsis_enhanced,
      a.synopsis_enhanced_state,
      coalesce(a.updated_at, a.created_at) as source_updated_at,
      a.synopsis_enhanced_updated_at
    from public.anime a
    where coalesce(a.description, '') <> ''
      and (
        a.synopsis_enhanced_state = 'pending'
        or a.synopsis_enhanced is null
        or a.synopsis_enhanced_updated_at is null
        or a.synopsis_enhanced_updated_at < coalesce(a.updated_at, a.created_at)
      )
    order by
      case a.synopsis_enhanced_state
        when 'pending' then 0
        when 'failed' then 1
        else 2
      end,
      coalesce(a.synopsis_enhanced_updated_at, to_timestamp(0)) asc,
      coalesce(a.last_synced_at, a.updated_at, a.created_at) desc,
      a.id asc
    limit v_limit;
    return;
  elsif v_media = 'MANGA' then
    return query
    select
      'MANGA'::text,
      m.id,
      coalesce(m.title_english, m.title_romaji, m.title_native, 'Unknown') as title,
      m.description,
      m.description_normalized,
      m.synopsis_enhanced,
      m.synopsis_enhanced_state,
      coalesce(m.updated_at, m.created_at) as source_updated_at,
      m.synopsis_enhanced_updated_at
    from public.manga m
    where coalesce(m.description, '') <> ''
      and (
        m.synopsis_enhanced_state = 'pending'
        or m.synopsis_enhanced is null
        or m.synopsis_enhanced_updated_at is null
        or m.synopsis_enhanced_updated_at < coalesce(m.updated_at, m.created_at)
      )
    order by
      case m.synopsis_enhanced_state
        when 'pending' then 0
        when 'failed' then 1
        else 2
      end,
      coalesce(m.synopsis_enhanced_updated_at, to_timestamp(0)) asc,
      coalesce(m.last_synced_at, m.updated_at, m.created_at) desc,
      m.id asc
    limit v_limit;
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
      synopsis_enhanced_state = 'ready'
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
      synopsis_enhanced_state = 'ready'
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
      synopsis_enhanced_source = case
        when v_reason is null then synopsis_enhanced_source
        else concat_ws(': ', coalesce(synopsis_enhanced_source, 'worker'), v_reason)
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
      synopsis_enhanced_source = case
        when v_reason is null then synopsis_enhanced_source
        else concat_ws(': ', coalesce(synopsis_enhanced_source, 'worker'), v_reason)
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

revoke all on function public.get_synopsis_enrichment_candidates(text, integer)
  from public, anon, authenticated;
revoke all on function public.upsert_synopsis_enhanced(text, integer, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.mark_synopsis_enhanced_failed(text, integer, text)
  from public, anon, authenticated;

grant execute on function public.get_synopsis_enrichment_candidates(text, integer)
  to service_role;
grant execute on function public.upsert_synopsis_enhanced(text, integer, text, jsonb)
  to service_role;
grant execute on function public.mark_synopsis_enhanced_failed(text, integer, text)
  to service_role;

commit;
