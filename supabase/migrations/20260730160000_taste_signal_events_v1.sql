-- Sprint 01: durable taste signal capture from list mutations.
-- Live rating scale is 1-10 on list tables (not 10-100). Thresholds: high>=8, low<=4.
-- Import origin uses short-lived taste_import_context (PostgREST cannot span SET LOCAL).

create table if not exists public.taste_signal_events (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  media_id integer not null,
  media_type text not null check (media_type in ('ANIME', 'MANGA')),
  event_type text not null,
  event_strength real not null,
  signal_value jsonb not null default '{}'::jsonb,
  source_transition jsonb not null default '{}'::jsonb,
  is_import boolean not null default false,
  import_session_id uuid null references public.import_sessions(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists taste_signal_events_user_created_idx
  on public.taste_signal_events (user_id, created_at desc);

create index if not exists taste_signal_events_user_media_idx
  on public.taste_signal_events (user_id, media_type, media_id, created_at desc);

create index if not exists taste_signal_events_type_idx
  on public.taste_signal_events (event_type);

alter table public.taste_signal_events enable row level security;

drop policy if exists taste_signal_events_select_own on public.taste_signal_events;
create policy taste_signal_events_select_own
  on public.taste_signal_events
  for select
  to authenticated
  using (user_id = (select auth.uid()));

-- Clients must not forge events; triggers insert as table owner / security definer path.
revoke insert, update, delete on public.taste_signal_events from anon, authenticated;
grant select on public.taste_signal_events to authenticated;
grant all on public.taste_signal_events to service_role;
grant usage, select on sequence public.taste_signal_events_id_seq to service_role;

create table if not exists public.taste_profile_recompute_queue (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text not null default 'signal',
  requested_at timestamptz not null default now(),
  processed_at timestamptz null
);

alter table public.taste_profile_recompute_queue enable row level security;
revoke all on public.taste_profile_recompute_queue from anon, authenticated;
grant all on public.taste_profile_recompute_queue to service_role;

-- Short-lived import context for edge apply (one row per user).
create table if not exists public.taste_import_context (
  user_id uuid primary key references auth.users(id) on delete cascade,
  session_id uuid not null references public.import_sessions(id) on delete cascade,
  expires_at timestamptz not null
);

alter table public.taste_import_context enable row level security;
revoke all on public.taste_import_context from anon, authenticated;
grant all on public.taste_import_context to service_role;
-- Authenticated users may set/clear only their own context (concierge-apply uses user JWT).
grant select, insert, update, delete on public.taste_import_context to authenticated;
drop policy if exists taste_import_context_own on public.taste_import_context;
create policy taste_import_context_own
  on public.taste_import_context
  for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create or replace function public.begin_taste_import_context(p_session_id uuid, p_ttl_seconds integer default 300)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_session_id is null then
    raise exception 'session required';
  end if;
  insert into public.taste_import_context as c (user_id, session_id, expires_at)
  values (
    auth.uid(),
    p_session_id,
    now() + make_interval(secs => greatest(30, least(coalesce(p_ttl_seconds, 300), 1800)))
  )
  on conflict (user_id) do update
    set session_id = excluded.session_id,
        expires_at = excluded.expires_at;
end;
$$;

create or replace function public.clear_taste_import_context()
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    return;
  end if;
  delete from public.taste_import_context where user_id = auth.uid();
end;
$$;

revoke all on function public.begin_taste_import_context(uuid, integer) from public;
revoke all on function public.clear_taste_import_context() from public;
grant execute on function public.begin_taste_import_context(uuid, integer) to authenticated, service_role;
grant execute on function public.clear_taste_import_context() to authenticated, service_role;

create or replace function public._taste_parse_user_id(p_text text)
returns uuid
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_text is null or length(trim(p_text)) = 0 then
    return null;
  end if;
  return trim(p_text)::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

create or replace function public._taste_enqueue_recompute(p_user_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    return;
  end if;
  insert into public.taste_profile_recompute_queue as q (user_id, reason, requested_at, processed_at)
  values (p_user_id, coalesce(p_reason, 'signal'), now(), null)
  on conflict (user_id) do update
    set reason = excluded.reason,
        requested_at = excluded.requested_at,
        processed_at = null;
end;
$$;

create or replace function public._taste_emit_event(
  p_user_id uuid,
  p_media_id integer,
  p_media_type text,
  p_event_type text,
  p_event_strength real,
  p_signal_value jsonb,
  p_source_transition jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_import boolean := false;
  v_session_id uuid := null;
begin
  if p_user_id is null or p_media_id is null or p_media_type is null or p_event_type is null then
    return;
  end if;

  select c.session_id
    into v_session_id
  from public.taste_import_context c
  where c.user_id = p_user_id
    and c.expires_at > now()
  limit 1;

  v_is_import := v_session_id is not null;

  insert into public.taste_signal_events (
    user_id, media_id, media_type, event_type, event_strength,
    signal_value, source_transition, is_import, import_session_id
  ) values (
    p_user_id,
    p_media_id,
    p_media_type,
    p_event_type,
    p_event_strength,
    coalesce(p_signal_value, '{}'::jsonb),
    coalesce(p_source_transition, '{}'::jsonb),
    v_is_import,
    v_session_id
  );

  perform public._taste_enqueue_recompute(p_user_id, p_event_type);
end;
$$;

create or replace function public._taste_meaningful_progress(
  p_media_type text,
  p_media_id integer,
  p_old_progress integer,
  p_new_progress integer
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
declare
  v_old integer := coalesce(p_old_progress, 0);
  v_new integer := coalesce(p_new_progress, 0);
  v_delta integer;
  v_total integer;
begin
  if v_new <= v_old then
    return false;
  end if;
  v_delta := v_new - v_old;

  if p_media_type = 'ANIME' then
    select nullif(episodes, 0) into v_total from public.anime where id = p_media_id;
    if v_total is not null then
      return v_delta >= greatest(3, ceil(v_total * 0.25)::integer) or v_new >= greatest(3, ceil(v_total * 0.25)::integer);
    end if;
    return v_new >= 3 and v_delta >= 1;
  else
    select nullif(chapters, 0) into v_total from public.manga where id = p_media_id;
    if v_total is not null then
      return v_delta >= greatest(5, ceil(v_total * 0.20)::integer) or v_new >= greatest(5, ceil(v_total * 0.20)::integer);
    end if;
    return v_new >= 5 and v_delta >= 1;
  end if;
end;
$$;

create or replace function public.taste_capture_list_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_media_id integer;
  v_media_type text;
  v_old_status text;
  v_new_status text;
  v_old_progress integer;
  v_new_progress integer;
  v_old_rating integer;
  v_new_rating integer;
  v_old_verdict text;
  v_new_verdict text;
  v_transition jsonb;
  v_noop boolean;
begin
  if tg_op = 'DELETE' then
    v_user_id := public._taste_parse_user_id(old.user_id);
    if v_user_id is null then
      return old;
    end if;
    if tg_table_name = 'anime_user_lists' then
      v_media_type := 'ANIME';
      v_media_id := old.anime_id;
    else
      v_media_type := 'MANGA';
      v_media_id := old.manga_id;
    end if;
    v_transition := jsonb_build_object(
      'op', 'DELETE',
      'old', jsonb_build_object(
        'list_type', old.list_type,
        'progress', old.progress,
        'rating', old.rating,
        'verdict', old.verdict
      )
    );
    if old.list_type = 'PLANNING'
       and old.created_at > now() - interval '24 hours' then
      perform public._taste_emit_event(
        v_user_id, v_media_id, v_media_type,
        'planned_add_removed_quickly', -0.20,
        jsonb_build_object('list_type', old.list_type),
        v_transition
      );
    end if;
    return old;
  end if;

  -- INSERT / UPDATE
  v_user_id := public._taste_parse_user_id(new.user_id);
  if v_user_id is null then
    -- Never block list writes on bad user_id text.
    return new;
  end if;

  if tg_table_name = 'anime_user_lists' then
    v_media_type := 'ANIME';
    v_media_id := new.anime_id;
  else
    v_media_type := 'MANGA';
    v_media_id := new.manga_id;
  end if;

  if tg_op = 'UPDATE' then
    v_old_status := old.list_type;
    v_old_progress := old.progress;
    v_old_rating := old.rating;
    v_old_verdict := old.verdict;
  else
    v_old_status := null;
    v_old_progress := null;
    v_old_rating := null;
    v_old_verdict := null;
  end if;

  v_new_status := new.list_type;
  v_new_progress := new.progress;
  v_new_rating := new.rating;
  v_new_verdict := new.verdict;

  v_noop := tg_op = 'UPDATE'
    and v_old_status is not distinct from v_new_status
    and v_old_progress is not distinct from v_new_progress
    and v_old_rating is not distinct from v_new_rating
    and v_old_verdict is not distinct from v_new_verdict;

  if v_noop then
    return new;
  end if;

  v_transition := jsonb_build_object(
    'op', tg_op,
    'old', case when tg_op = 'UPDATE' then jsonb_build_object(
      'list_type', v_old_status,
      'progress', v_old_progress,
      'rating', v_old_rating,
      'verdict', v_old_verdict
    ) else null end,
    'new', jsonb_build_object(
      'list_type', v_new_status,
      'progress', v_new_progress,
      'rating', v_new_rating,
      'verdict', v_new_verdict
    )
  );

  -- Status / lifecycle
  if tg_op = 'INSERT' and v_new_status = 'PLANNING' then
    perform public._taste_emit_event(
      v_user_id, v_media_id, v_media_type,
      'planned_add', 0.10,
      jsonb_build_object('list_type', v_new_status),
      v_transition
    );
  end if;

  if v_new_status in ('WATCHING', 'READING')
     and (tg_op = 'INSERT' or v_old_status is distinct from v_new_status) then
    if tg_op = 'UPDATE'
       and v_old_status = 'COMPLETED'
       and v_new_status in ('WATCHING', 'READING') then
      perform public._taste_emit_event(
        v_user_id, v_media_id, v_media_type,
        'rewatch_reread', 0.90,
        jsonb_build_object('from', v_old_status, 'to', v_new_status),
        v_transition
      );
    else
      perform public._taste_emit_event(
        v_user_id, v_media_id, v_media_type,
        'status_current', 0.30,
        jsonb_build_object('list_type', v_new_status),
        v_transition
      );
    end if;
  end if;

  if v_new_status = 'COMPLETED'
     and (tg_op = 'INSERT' or v_old_status is distinct from v_new_status) then
    perform public._taste_emit_event(
      v_user_id, v_media_id, v_media_type,
      'completed', 0.70,
      jsonb_build_object('list_type', v_new_status),
      v_transition
    );
  end if;

  if v_new_status = 'DROPPED'
     and (tg_op = 'INSERT' or v_old_status is distinct from v_new_status) then
    perform public._taste_emit_event(
      v_user_id, v_media_id, v_media_type,
      'dropped', -0.80,
      jsonb_build_object('list_type', v_new_status),
      v_transition
    );
  end if;

  -- Progress
  if public._taste_meaningful_progress(v_media_type, v_media_id, v_old_progress, v_new_progress) then
    perform public._taste_emit_event(
      v_user_id, v_media_id, v_media_type,
      'meaningful_progress', 0.45,
      jsonb_build_object('from', v_old_progress, 'to', v_new_progress),
      v_transition
    );
  end if;

  -- Rating (DB scale 1-10)
  if v_new_rating is not null
     and v_new_rating is distinct from v_old_rating then
    if v_new_rating >= 8 then
      perform public._taste_emit_event(
        v_user_id, v_media_id, v_media_type,
        'rating_high', 0.70,
        jsonb_build_object('rating', v_new_rating),
        v_transition
      );
    elsif v_new_rating <= 4 then
      perform public._taste_emit_event(
        v_user_id, v_media_id, v_media_type,
        'rating_low', -0.70,
        jsonb_build_object('rating', v_new_rating),
        v_transition
      );
    end if;
  end if;

  -- Verdict
  if v_new_verdict is not null
     and v_new_verdict is distinct from v_old_verdict then
    if v_new_verdict = 'MASTERPIECE' then
      perform public._taste_emit_event(
        v_user_id, v_media_id, v_media_type,
        'verdict_masterpiece', 1.00,
        jsonb_build_object('verdict', v_new_verdict),
        v_transition
      );
    elsif v_new_verdict = 'OKAY' then
      perform public._taste_emit_event(
        v_user_id, v_media_id, v_media_type,
        'verdict_okay', 0.55,
        jsonb_build_object('verdict', v_new_verdict),
        v_transition
      );
    elsif v_new_verdict = 'BAD' then
      perform public._taste_emit_event(
        v_user_id, v_media_id, v_media_type,
        'verdict_bad', -0.85,
        jsonb_build_object('verdict', v_new_verdict),
        v_transition
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists taste_capture_anime_user_lists on public.anime_user_lists;
create trigger taste_capture_anime_user_lists
  after insert or update or delete on public.anime_user_lists
  for each row execute function public.taste_capture_list_mutation();

drop trigger if exists taste_capture_manga_user_lists on public.manga_user_lists;
create trigger taste_capture_manga_user_lists
  after insert or update or delete on public.manga_user_lists
  for each row execute function public.taste_capture_list_mutation();

-- BEFORE trigger to bump updated_at on UPDATE (capture function also sets it on NEW for UPDATE path,
-- but AFTER triggers cannot mutate NEW for persistence — add explicit BEFORE bump).
create or replace function public.taste_bump_list_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists taste_bump_anime_user_lists_updated_at on public.anime_user_lists;
create trigger taste_bump_anime_user_lists_updated_at
  before update on public.anime_user_lists
  for each row execute function public.taste_bump_list_updated_at();

drop trigger if exists taste_bump_manga_user_lists_updated_at on public.manga_user_lists;
create trigger taste_bump_manga_user_lists_updated_at
  before update on public.manga_user_lists
  for each row execute function public.taste_bump_list_updated_at();
