-- 20261118150000_refresh_queue_hardening_v1.sql
-- PREPARED, NOT APPLIED. Owner approval required to deploy. Independent review finding.
--
-- enqueue_media_availability_refresh(text,int,text) and enqueue_media_relation_refresh(text,int,text) are
-- callable by any signed-in user (the relation one also by anon). They accepted any media id and an unbounded
-- free-text reason, so a caller could insert unlimited queue rows, reset rows a worker was handling, and pin
-- everything at availability priority 0 (detail_open / user_tap within 15 minutes).
--
-- New rules (both functions; signatures, return types and defaults unchanged, bodies otherwise as in
-- 20260319123000 / 20260307150000):
--   1. The media must exist (public.anime / public.manga). Unknown ids write nothing
--      (availability returns {"error":"unknown_media"}; relation returns silently, as before).
--   2. p_reason must be one of the values the app and the SQL priority ladder use; a blank reason keeps the
--      old default. Anything else is rejected (availability {"error":"invalid_reason"}; relation 22023).
--        availability: detail_open, on_demand_open, user_tap, on_demand, scheduled
--          (app: ProviderAvailabilityStore+DetailLinks 'detail_open', enqueueAvailabilityRefreshIfStale default
--           'on_demand_open'; ProfileFreshnessCard knows 'user_tap'; priority CASE knows detail_open/user_tap)
--        relation: detail_open, concierge_recommend, discover_primary, on_demand
--          (app: AnimeDetailSections/MangaDetailSections 'detail_open', ConciergeView 'concierge_recommend',
--           EditorialDiscoverView 'discover_primary'; SQL default 'on_demand')
--   3. Rows in progress are never reset. Relation queue: a 'processing' row is left untouched. Availability
--      state has no 'processing' status (pending/ok/error/unresolved); an already-pending row that already
--      carries a priority reason (detail_open/user_tap) is left untouched, so repeated calls cannot keep
--      re-pinning it or moving its next_refresh_at; a pending row with a lower-priority reason may still be
--      upgraded once.
--   4. Authenticated callers get a per-user bucket: 30 calls per 5 minutes per function, through the existing
--      public.rate_limit_hit / rate_limit_buckets (keys 'user:<uid>:enqueue_availability:300' and
--      '...:enqueue_relation:300'). Over the limit: availability {"error":"rate_limited","retry_after_s":n};
--      relation returns silently (the app ignores the result; the cooldown/prefetch paths just retry later).
--      Service-role calls (auth.uid() is null) are not limited.
--   5. Grants restated: availability authenticated + service_role (as deployed); relation authenticated +
--      service_role. anon is revoked from the relation function: the guest build sends none (CatalogStore guards
--      on the account), and 20261118110000 removes it from the anon allowlist anyway; here it cannot be used
--      unauthenticated even if applied alone.
-- Limits: availability_refresh_state has no per-user attribution, so a signed-in user can still queue up to
-- 30 distinct existing titles per function per 5 minutes; it is bounded, not zero.
-- Idempotent: CREATE OR REPLACE. All functions plpgsql, search_path = public, extensions.

begin;

create or replace function public.enqueue_media_availability_refresh(
  p_media_type text,
  p_media_id int,
  p_reason text default 'on_demand'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  mt text := upper(trim(coalesce(p_media_type, '')));
  normalized_reason text := coalesce(nullif(trim(p_reason), ''), 'scheduled');
  uid uuid := auth.uid();
  hits integer;
  exists_ boolean;
begin
  if mt not in ('ANIME', 'MANGA') then
    return jsonb_build_object('error', 'invalid_media_type');
  end if;
  if normalized_reason not in ('detail_open', 'on_demand_open', 'user_tap', 'on_demand', 'scheduled') then
    return jsonb_build_object('error', 'invalid_reason');
  end if;
  if p_media_id is null then
    return jsonb_build_object('error', 'unknown_media');
  end if;
  if mt = 'ANIME' then
    select exists (select 1 from public.anime where id = p_media_id) into exists_;
  else
    select exists (select 1 from public.manga where id = p_media_id) into exists_;
  end if;
  if not exists_ then
    return jsonb_build_object('error', 'unknown_media');
  end if;

  if uid is not null then
    hits := public.rate_limit_hit('user:' || uid::text || ':enqueue_availability:300', 300);
    if hits > 30 then
      return jsonb_build_object(
        'error', 'rate_limited',
        'retry_after_s', 300 - (extract(epoch from now())::integer % 300)
      );
    end if;
  end if;

  insert into public.provider_availability_refresh_state (
    media_type, media_id, source_name, status, next_refresh_at, retry_count,
    updated_at, last_requested_at, request_reason, last_error
  ) values (
    mt, p_media_id, 'watchmode', 'pending', now(), 0,
    now(), now(), normalized_reason, null
  )
  on conflict (media_type, media_id, source_name)
  do update set
    status = 'pending',
    next_refresh_at = now(),
    updated_at = now(),
    last_requested_at = now(),
    request_reason = excluded.request_reason
  where not (
    public.provider_availability_refresh_state.status = 'pending'
    and public.provider_availability_refresh_state.request_reason in ('detail_open', 'user_tap')
  );

  return jsonb_build_object(
    'success', true,
    'media_type', mt,
    'media_id', p_media_id,
    'queued_at', now(),
    'request_reason', normalized_reason
  );
end;
$$;

revoke all on function public.enqueue_media_availability_refresh(text, int, text) from public;
grant execute on function public.enqueue_media_availability_refresh(text, int, text) to authenticated, service_role;

create or replace function public.enqueue_media_relation_refresh(
  p_media_type text,
  p_media_id int,
  p_reason text default 'on_demand'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  normalized_media_type text := upper(trim(coalesce(p_media_type, '')));
  normalized_reason text := coalesce(nullif(trim(p_reason), ''), 'on_demand');
  uid uuid := auth.uid();
  hits integer;
  exists_ boolean;
begin
  if normalized_media_type not in ('ANIME', 'MANGA') then
    raise exception 'Unsupported media type for ladder refresh: %', p_media_type
      using errcode = '22023';
  end if;
  if normalized_reason not in ('detail_open', 'concierge_recommend', 'discover_primary', 'on_demand') then
    raise exception 'Unsupported reason for ladder refresh' using errcode = '22023';
  end if;
  if p_media_id is null then
    return;
  end if;

  if normalized_media_type = 'ANIME' then
    select exists (select 1 from public.anime where id = p_media_id) into exists_;
  else
    select exists (select 1 from public.manga where id = p_media_id) into exists_;
  end if;
  if not exists_ then
    return;
  end if;

  if uid is not null then
    hits := public.rate_limit_hit('user:' || uid::text || ':enqueue_relation:300', 300);
    if hits > 30 then
      return;
    end if;
  end if;

  insert into public.media_relation_refresh_queue (
    media_type, media_id, reason, status, requested_at,
    last_attempt_at, last_completed_at, retry_count, last_error, updated_at
  )
  values (
    normalized_media_type, p_media_id, normalized_reason, 'pending', now(),
    null, null, 0, null, now()
  )
  on conflict (media_type, media_id)
  do update set
    reason = excluded.reason,
    status = 'pending',
    requested_at = now(),
    last_error = null,
    updated_at = now()
  where public.media_relation_refresh_queue.status <> 'processing';
end;
$$;

revoke all on function public.enqueue_media_relation_refresh(text, int, text) from public;
revoke all on function public.enqueue_media_relation_refresh(text, int, text) from anon;
grant execute on function public.enqueue_media_relation_refresh(text, int, text) to authenticated, service_role;

commit;
