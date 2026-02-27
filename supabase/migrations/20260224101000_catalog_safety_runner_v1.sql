begin;

-- Catalog safety state on anime/manga (additive, non-destructive).
alter table if exists public.anime
  add column if not exists safety_state text not null default 'pending',
  add column if not exists safety_blocked boolean not null default false,
  add column if not exists safety_reason_codes text[] not null default '{}'::text[],
  add column if not exists safety_rule_hits text[] not null default '{}'::text[],
  add column if not exists safety_model_label text null,
  add column if not exists safety_model_confidence numeric(4,3) null,
  add column if not exists safety_model_rationale text null,
  add column if not exists safety_suggested_lexicon text[] not null default '{}'::text[],
  add column if not exists safety_source_hash text null,
  add column if not exists safety_last_scanned_at timestamptz null,
  add column if not exists safety_last_attempt_at timestamptz null,
  add column if not exists safety_next_scan_at timestamptz null,
  add column if not exists safety_retry_count integer not null default 0,
  add column if not exists safety_last_error text null;

alter table if exists public.manga
  add column if not exists safety_state text not null default 'pending',
  add column if not exists safety_blocked boolean not null default false,
  add column if not exists safety_reason_codes text[] not null default '{}'::text[],
  add column if not exists safety_rule_hits text[] not null default '{}'::text[],
  add column if not exists safety_model_label text null,
  add column if not exists safety_model_confidence numeric(4,3) null,
  add column if not exists safety_model_rationale text null,
  add column if not exists safety_suggested_lexicon text[] not null default '{}'::text[],
  add column if not exists safety_source_hash text null,
  add column if not exists safety_last_scanned_at timestamptz null,
  add column if not exists safety_last_attempt_at timestamptz null,
  add column if not exists safety_next_scan_at timestamptz null,
  add column if not exists safety_retry_count integer not null default 0,
  add column if not exists safety_last_error text null;

alter table if exists public.anime
  drop constraint if exists anime_safety_state_check;
alter table if exists public.anime
  add constraint anime_safety_state_check
  check (safety_state in ('pending', 'safe', 'blocked', 'uncertain', 'failed'));

alter table if exists public.manga
  drop constraint if exists manga_safety_state_check;
alter table if exists public.manga
  add constraint manga_safety_state_check
  check (safety_state in ('pending', 'safe', 'blocked', 'uncertain', 'failed'));

create index if not exists idx_anime_safety_queue
  on public.anime (safety_state, safety_next_scan_at, safety_last_scanned_at, id);

create index if not exists idx_manga_safety_queue
  on public.manga (safety_state, safety_next_scan_at, safety_last_scanned_at, id);

create index if not exists idx_anime_safety_blocked
  on public.anime (safety_blocked, id)
  where safety_blocked = true;

create index if not exists idx_manga_safety_blocked
  on public.manga (safety_blocked, id)
  where safety_blocked = true;

-- Safety lexicon/rules (maintained over time).
create table if not exists public.catalog_safety_terms (
  id bigserial primary key,
  term text not null,
  language text not null,
  match_type text not null,
  weight integer not null,
  category text not null,
  active boolean not null default true,
  notes text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint catalog_safety_terms_language_check
    check (language in ('en', 'de', 'jp_romaji', 'any')),
  constraint catalog_safety_terms_match_type_check
    check (match_type in ('exact', 'contains', 'regex')),
  constraint catalog_safety_terms_weight_check
    check (weight >= 1 and weight <= 1000)
);

create unique index if not exists idx_catalog_safety_terms_unique
  on public.catalog_safety_terms (term, language, match_type, category);

create table if not exists public.catalog_safety_audit (
  id bigserial primary key,
  media_type text not null,
  media_id integer not null,
  title text not null,
  decision_state text not null,
  blocked boolean not null default false,
  reason_codes text[] not null default '{}'::text[],
  rule_hits text[] not null default '{}'::text[],
  model_label text null,
  model_confidence numeric(4,3) null,
  model_rationale text null,
  suggested_lexicon text[] not null default '{}'::text[],
  scan_source_hash text null,
  scanned_at timestamptz not null default now(),
  constraint catalog_safety_audit_media_type_check
    check (media_type in ('ANIME', 'MANGA')),
  constraint catalog_safety_audit_decision_state_check
    check (decision_state in ('pending', 'safe', 'blocked', 'uncertain', 'failed'))
);

create index if not exists idx_catalog_safety_audit_lookup
  on public.catalog_safety_audit (media_type, media_id, scanned_at desc);

create index if not exists idx_catalog_safety_audit_state
  on public.catalog_safety_audit (decision_state, scanned_at desc);

alter table public.catalog_safety_terms enable row level security;
alter table public.catalog_safety_audit enable row level security;

-- service_role only (no policies added; service_role bypasses RLS).

insert into public.catalog_safety_terms (term, language, match_type, weight, category, notes)
values
  ('hentai', 'any', 'exact', 300, 'porn_core', 'core explicit term'),
  ('porn', 'en', 'contains', 250, 'porn_core', 'explicit porn marker'),
  ('porno', 'de', 'contains', 250, 'porn_core', 'explicit porn marker'),
  ('adult video', 'en', 'contains', 220, 'porn_core', null),
  ('x-rated', 'en', 'contains', 220, 'porn_core', null),
  ('nsfw', 'en', 'contains', 120, 'sexual_explicit', 'weak explicit marker'),
  ('uncensored sex', 'en', 'contains', 220, 'porn_core', null),
  ('explicit sex', 'en', 'contains', 220, 'porn_core', null),
  ('sex scene', 'en', 'contains', 80, 'sexual_explicit', null),
  ('rape', 'en', 'exact', 180, 'sexual_explicit', null),
  ('incest', 'en', 'exact', 180, 'sexual_explicit', null),
  ('blowjob', 'en', 'contains', 180, 'sexual_explicit', null),
  ('handjob', 'en', 'contains', 180, 'sexual_explicit', null),
  ('gangbang', 'en', 'contains', 180, 'sexual_explicit', null),
  ('bukkake', 'any', 'contains', 220, 'porn_core', null),
  ('fellatio', 'any', 'contains', 180, 'sexual_explicit', null),
  ('cunnilingus', 'any', 'contains', 180, 'sexual_explicit', null),
  ('masturbation', 'en', 'contains', 140, 'sexual_explicit', null),
  ('sexuelle inhalte', 'de', 'contains', 120, 'sexual_explicit', null),
  ('pornograf', 'de', 'contains', 250, 'porn_core', null),
  ('geschlechtsverkehr', 'de', 'contains', 140, 'sexual_explicit', null),
  ('vergewaltigung', 'de', 'contains', 180, 'sexual_explicit', null),
  ('inzest', 'de', 'contains', 180, 'sexual_explicit', null),
  ('hent[a4]i', 'any', 'regex', 300, 'porn_core', 'obfuscation variant'),
  ('p[o0]rn[o0]?', 'any', 'regex', 250, 'porn_core', 'obfuscation variant'),
  ('l[o0]licon', 'any', 'regex', 260, 'porn_core', null),
  ('sh[o0]tacon', 'any', 'regex', 260, 'porn_core', null),
  ('ero\s*manga', 'jp_romaji', 'regex', 180, 'sexual_explicit', null),
  ('ero\s*anime', 'jp_romaji', 'regex', 180, 'sexual_explicit', null),
  ('h\s*anime', 'jp_romaji', 'regex', 220, 'porn_core', null)
on conflict do nothing;

insert into public.system_flags(key, enabled)
values ('catalog_safety_enforce_v1', false)
on conflict (key) do nothing;

create or replace function public.get_catalog_safety_candidates(
  p_media_type text,
  p_limit integer default 200
)
returns table (
  media_type text,
  media_id integer,
  title text,
  title_english text,
  title_romaji text,
  title_native text,
  source_description text,
  source_description_normalized text,
  genres text[],
  source_hash text,
  source_updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_media text := upper(trim(coalesce(p_media_type, '')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 200), 1000));
begin
  if v_media = 'ANIME' then
    return query
    with candidates as (
      select
        a.id,
        md5(lower(concat_ws(' ',
          coalesce(a.title_english, ''),
          coalesce(a.title_romaji, ''),
          coalesce(a.title_native, ''),
          coalesce(a.description_normalized, a.description, ''),
          coalesce(array_to_string(a.genres, ' '), '')
        ))) as computed_hash
      from public.anime a
      where coalesce(a.safety_next_scan_at, to_timestamp(0)) <= now()
      order by
        case when a.safety_source_hash is distinct from md5(lower(concat_ws(' ',
          coalesce(a.title_english, ''),
          coalesce(a.title_romaji, ''),
          coalesce(a.title_native, ''),
          coalesce(a.description_normalized, a.description, ''),
          coalesce(array_to_string(a.genres, ' '), '')
        ))) then 0 else 1 end,
        coalesce(a.safety_last_scanned_at, to_timestamp(0)) asc,
        a.id asc
      for update skip locked
      limit v_limit
    ),
    claimed as (
      update public.anime a
      set
        safety_state = 'pending',
        safety_last_attempt_at = now(),
        safety_next_scan_at = now() + interval '20 minutes'
      from candidates c
      where a.id = c.id
      returning a.*, c.computed_hash
    )
    select
      'ANIME'::text,
      c.id,
      coalesce(c.title_english, c.title_romaji, c.title_native, 'Unknown') as title,
      c.title_english,
      c.title_romaji,
      c.title_native,
      c.description,
      c.description_normalized,
      c.genres,
      c.computed_hash,
      coalesce(c.updated_at, c.created_at) as source_updated_at
    from claimed c
    order by c.id asc;
    return;
  end if;

  if v_media = 'MANGA' then
    return query
    with candidates as (
      select
        m.id,
        md5(lower(concat_ws(' ',
          coalesce(m.title_english, ''),
          coalesce(m.title_romaji, ''),
          coalesce(m.title_native, ''),
          coalesce(m.description_normalized, m.description, ''),
          coalesce(array_to_string(m.genres, ' '), '')
        ))) as computed_hash
      from public.manga m
      where coalesce(m.safety_next_scan_at, to_timestamp(0)) <= now()
      order by
        case when m.safety_source_hash is distinct from md5(lower(concat_ws(' ',
          coalesce(m.title_english, ''),
          coalesce(m.title_romaji, ''),
          coalesce(m.title_native, ''),
          coalesce(m.description_normalized, m.description, ''),
          coalesce(array_to_string(m.genres, ' '), '')
        ))) then 0 else 1 end,
        coalesce(m.safety_last_scanned_at, to_timestamp(0)) asc,
        m.id asc
      for update skip locked
      limit v_limit
    ),
    claimed as (
      update public.manga m
      set
        safety_state = 'pending',
        safety_last_attempt_at = now(),
        safety_next_scan_at = now() + interval '20 minutes'
      from candidates c
      where m.id = c.id
      returning m.*, c.computed_hash
    )
    select
      'MANGA'::text,
      c.id,
      coalesce(c.title_english, c.title_romaji, c.title_native, 'Unknown') as title,
      c.title_english,
      c.title_romaji,
      c.title_native,
      c.description,
      c.description_normalized,
      c.genres,
      c.computed_hash,
      coalesce(c.updated_at, c.created_at) as source_updated_at
    from claimed c
    order by c.id asc;
    return;
  end if;

  raise exception 'Unsupported media type for catalog safety: %', p_media_type
    using errcode = '22023';
end;
$$;

create or replace function public.upsert_catalog_safety_result(
  p_media_type text,
  p_media_id integer,
  p_decision_state text,
  p_blocked boolean default null,
  p_rule_hits text[] default '{}'::text[],
  p_reason_codes text[] default '{}'::text[],
  p_model_label text default null,
  p_model_confidence numeric default null,
  p_model_rationale text default null,
  p_suggested_lexicon text[] default '{}'::text[],
  p_source_hash text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_media text := upper(trim(coalesce(p_media_type, '')));
  v_state text := lower(trim(coalesce(p_decision_state, '')));
  v_blocked boolean := coalesce(p_blocked, v_state = 'blocked');
  v_next_scan timestamptz;
  v_title text;
begin
  if v_state not in ('safe', 'blocked', 'uncertain') then
    raise exception 'Unsupported decision state for catalog safety: %', p_decision_state
      using errcode = '22023';
  end if;

  v_next_scan := case
    when v_state = 'blocked' then now() + interval '7 days'
    when v_state = 'uncertain' then now() + interval '3 days'
    else now() + interval '30 days'
  end;

  if v_media = 'ANIME' then
    update public.anime a
    set
      safety_state = v_state,
      safety_blocked = v_blocked,
      safety_reason_codes = coalesce(p_reason_codes, '{}'::text[]),
      safety_rule_hits = coalesce(p_rule_hits, '{}'::text[]),
      safety_model_label = nullif(trim(coalesce(p_model_label, '')), ''),
      safety_model_confidence = p_model_confidence,
      safety_model_rationale = nullif(trim(coalesce(p_model_rationale, '')), ''),
      safety_suggested_lexicon = coalesce(p_suggested_lexicon, '{}'::text[]),
      safety_source_hash = nullif(trim(coalesce(p_source_hash, '')), ''),
      safety_last_scanned_at = now(),
      safety_last_attempt_at = now(),
      safety_next_scan_at = v_next_scan,
      safety_retry_count = 0,
      safety_last_error = null
    where a.id = p_media_id
    returning coalesce(a.title_english, a.title_romaji, a.title_native, 'Unknown') into v_title;

    if not found then
      raise exception 'Anime % not found', p_media_id
        using errcode = 'P0002';
    end if;

    insert into public.catalog_safety_audit (
      media_type,
      media_id,
      title,
      decision_state,
      blocked,
      reason_codes,
      rule_hits,
      model_label,
      model_confidence,
      model_rationale,
      suggested_lexicon,
      scan_source_hash,
      scanned_at
    ) values (
      'ANIME',
      p_media_id,
      v_title,
      v_state,
      v_blocked,
      coalesce(p_reason_codes, '{}'::text[]),
      coalesce(p_rule_hits, '{}'::text[]),
      nullif(trim(coalesce(p_model_label, '')), ''),
      p_model_confidence,
      nullif(trim(coalesce(p_model_rationale, '')), ''),
      coalesce(p_suggested_lexicon, '{}'::text[]),
      nullif(trim(coalesce(p_source_hash, '')), ''),
      now()
    );
    return;
  end if;

  if v_media = 'MANGA' then
    update public.manga m
    set
      safety_state = v_state,
      safety_blocked = v_blocked,
      safety_reason_codes = coalesce(p_reason_codes, '{}'::text[]),
      safety_rule_hits = coalesce(p_rule_hits, '{}'::text[]),
      safety_model_label = nullif(trim(coalesce(p_model_label, '')), ''),
      safety_model_confidence = p_model_confidence,
      safety_model_rationale = nullif(trim(coalesce(p_model_rationale, '')), ''),
      safety_suggested_lexicon = coalesce(p_suggested_lexicon, '{}'::text[]),
      safety_source_hash = nullif(trim(coalesce(p_source_hash, '')), ''),
      safety_last_scanned_at = now(),
      safety_last_attempt_at = now(),
      safety_next_scan_at = v_next_scan,
      safety_retry_count = 0,
      safety_last_error = null
    where m.id = p_media_id
    returning coalesce(m.title_english, m.title_romaji, m.title_native, 'Unknown') into v_title;

    if not found then
      raise exception 'Manga % not found', p_media_id
        using errcode = 'P0002';
    end if;

    insert into public.catalog_safety_audit (
      media_type,
      media_id,
      title,
      decision_state,
      blocked,
      reason_codes,
      rule_hits,
      model_label,
      model_confidence,
      model_rationale,
      suggested_lexicon,
      scan_source_hash,
      scanned_at
    ) values (
      'MANGA',
      p_media_id,
      v_title,
      v_state,
      v_blocked,
      coalesce(p_reason_codes, '{}'::text[]),
      coalesce(p_rule_hits, '{}'::text[]),
      nullif(trim(coalesce(p_model_label, '')), ''),
      p_model_confidence,
      nullif(trim(coalesce(p_model_rationale, '')), ''),
      coalesce(p_suggested_lexicon, '{}'::text[]),
      nullif(trim(coalesce(p_source_hash, '')), ''),
      now()
    );
    return;
  end if;

  raise exception 'Unsupported media type for catalog safety: %', p_media_type
    using errcode = '22023';
end;
$$;

create or replace function public.mark_catalog_safety_failed(
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
  v_reason text := nullif(trim(coalesce(p_reason, '')), '');
  v_retry integer;
  v_backoff_minutes integer;
  v_title text;
begin
  if v_media = 'ANIME' then
    update public.anime a
    set
      safety_state = 'failed',
      safety_retry_count = a.safety_retry_count + 1,
      safety_last_attempt_at = now(),
      safety_last_error = coalesce(v_reason, 'unknown_error')
    where a.id = p_media_id
    returning
      safety_retry_count,
      coalesce(a.title_english, a.title_romaji, a.title_native, 'Unknown')
    into v_retry, v_title;

    if not found then
      raise exception 'Anime % not found', p_media_id
        using errcode = 'P0002';
    end if;

    v_backoff_minutes := least(1440, greatest(10, ((power(2, least(v_retry, 8))::int) * 5)));

    update public.anime
    set safety_next_scan_at = now() + make_interval(mins => v_backoff_minutes)
    where id = p_media_id;

    insert into public.catalog_safety_audit (
      media_type, media_id, title, decision_state, blocked,
      reason_codes, rule_hits, model_label, model_confidence,
      model_rationale, suggested_lexicon, scan_source_hash, scanned_at
    ) values (
      'ANIME', p_media_id, v_title, 'failed', false,
      array[coalesce(v_reason, 'unknown_error')]::text[], '{}'::text[], null, null,
      null, '{}'::text[], null, now()
    );
    return;
  end if;

  if v_media = 'MANGA' then
    update public.manga m
    set
      safety_state = 'failed',
      safety_retry_count = m.safety_retry_count + 1,
      safety_last_attempt_at = now(),
      safety_last_error = coalesce(v_reason, 'unknown_error')
    where m.id = p_media_id
    returning
      safety_retry_count,
      coalesce(m.title_english, m.title_romaji, m.title_native, 'Unknown')
    into v_retry, v_title;

    if not found then
      raise exception 'Manga % not found', p_media_id
        using errcode = 'P0002';
    end if;

    v_backoff_minutes := least(1440, greatest(10, ((power(2, least(v_retry, 8))::int) * 5)));

    update public.manga
    set safety_next_scan_at = now() + make_interval(mins => v_backoff_minutes)
    where id = p_media_id;

    insert into public.catalog_safety_audit (
      media_type, media_id, title, decision_state, blocked,
      reason_codes, rule_hits, model_label, model_confidence,
      model_rationale, suggested_lexicon, scan_source_hash, scanned_at
    ) values (
      'MANGA', p_media_id, v_title, 'failed', false,
      array[coalesce(v_reason, 'unknown_error')]::text[], '{}'::text[], null, null,
      null, '{}'::text[], null, now()
    );
    return;
  end if;

  raise exception 'Unsupported media type for catalog safety: %', p_media_type
    using errcode = '22023';
end;
$$;

create or replace function public.get_catalog_safety_open_gaps(
  p_limit integer default 200
)
returns table (
  media_type text,
  media_id integer,
  title text,
  decision_state text,
  model_label text,
  model_confidence numeric,
  rule_hits text[],
  reason_codes text[],
  suggested_lexicon text[],
  last_scanned_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  with rows as (
    select
      'ANIME'::text as media_type,
      a.id as media_id,
      coalesce(a.title_english, a.title_romaji, a.title_native, 'Unknown') as title,
      a.safety_state as decision_state,
      a.safety_model_label as model_label,
      a.safety_model_confidence as model_confidence,
      a.safety_rule_hits as rule_hits,
      a.safety_reason_codes as reason_codes,
      a.safety_suggested_lexicon as suggested_lexicon,
      a.safety_last_scanned_at as last_scanned_at
    from public.anime a
    where a.safety_state = 'uncertain'

    union all

    select
      'MANGA'::text as media_type,
      m.id as media_id,
      coalesce(m.title_english, m.title_romaji, m.title_native, 'Unknown') as title,
      m.safety_state as decision_state,
      m.safety_model_label as model_label,
      m.safety_model_confidence as model_confidence,
      m.safety_rule_hits as rule_hits,
      m.safety_reason_codes as reason_codes,
      m.safety_suggested_lexicon as suggested_lexicon,
      m.safety_last_scanned_at as last_scanned_at
    from public.manga m
    where m.safety_state = 'uncertain'
  )
  select
    r.media_type,
    r.media_id,
    r.title,
    r.decision_state,
    r.model_label,
    r.model_confidence,
    coalesce(r.rule_hits, '{}'::text[]) as rule_hits,
    coalesce(r.reason_codes, '{}'::text[]) as reason_codes,
    coalesce(r.suggested_lexicon, '{}'::text[]) as suggested_lexicon,
    r.last_scanned_at
  from rows r
  order by r.last_scanned_at desc nulls last, r.media_type asc, r.media_id asc
  limit greatest(1, least(coalesce(p_limit, 200), 2000));
$$;

create or replace function public.get_catalog_safety_backlog_count(
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
    select count(*)::integer
    from public.anime a
    where coalesce(a.safety_next_scan_at, to_timestamp(0)) <= now();
    return;
  end if;

  if v_media = 'MANGA' then
    return query
    select count(*)::integer
    from public.manga m
    where coalesce(m.safety_next_scan_at, to_timestamp(0)) <= now();
    return;
  end if;

  raise exception 'Unsupported media type for catalog safety: %', p_media_type
    using errcode = '22023';
end;
$$;

revoke all on function public.get_catalog_safety_candidates(text, integer)
  from public, anon, authenticated;
revoke all on function public.upsert_catalog_safety_result(text, integer, text, boolean, text[], text[], text, numeric, text, text[], text)
  from public, anon, authenticated;
revoke all on function public.mark_catalog_safety_failed(text, integer, text)
  from public, anon, authenticated;
revoke all on function public.get_catalog_safety_open_gaps(integer)
  from public, anon, authenticated;
revoke all on function public.get_catalog_safety_backlog_count(text)
  from public, anon, authenticated;

grant execute on function public.get_catalog_safety_candidates(text, integer)
  to service_role;
grant execute on function public.upsert_catalog_safety_result(text, integer, text, boolean, text[], text[], text, numeric, text, text[], text)
  to service_role;
grant execute on function public.mark_catalog_safety_failed(text, integer, text)
  to service_role;
grant execute on function public.get_catalog_safety_open_gaps(integer)
  to service_role;
grant execute on function public.get_catalog_safety_backlog_count(text)
  to service_role;

commit;
