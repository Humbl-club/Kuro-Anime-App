-- 129_refresh_queue_hardening.sql
-- Prepared 20261118150000_refresh_queue_hardening_v1.sql (NOT deployed). enqueue_media_availability_refresh and
-- enqueue_media_relation_refresh: the media must exist, the reason is a fixed set (the values the app sends),
-- rows in progress are never reset, signed-in callers get 30 calls / 5 minutes per function, and the app's
-- signed-in calls keep working. Disposable local fixture only, never hosted.
-- @requires table public.anime
-- @requires table public.manga
-- @requires table public.provider_availability_refresh_state
-- @requires table public.media_relation_refresh_queue
-- @requires function public.enqueue_media_availability_refresh(text,integer,text)
-- @requires function public.enqueue_media_relation_refresh(text,integer,text)
-- @requires function public.rate_limit_hit(text,integer)
\set ON_ERROR_STOP on
begin;

set local session_replication_role = replica;
insert into public.anime (id, anilist_id, title_romaji, format, status, popularity, genres, is_adult)
values (1290001, 1290001, 'T129 anime', 'TV', 'FINISHED', 1, array['Action'], false);
insert into public.manga (id, anilist_id, title_romaji, format, status, popularity, genres, is_adult)
values (1290002, 1290002, 'T129 manga', 'MANGA', 'FINISHED', 1, array['Action'], false);
set local session_replication_role = origin;

select tests.make_user(1291);
select tests.make_user(1292);

-- ---- A. the app's signed-in calls keep working ---------------------------------------------------------
select tests.as_user(tests.uid(1291));
select tests.ok('availability: detail_open on an existing anime queues it',
  (public.enqueue_media_availability_refresh('ANIME', 1290001, 'detail_open')->>'success')::boolean);
select tests.ok('availability: on_demand_open (the Swift default) on an existing manga queues it',
  (public.enqueue_media_availability_refresh('manga', 1290002, 'on_demand_open')->>'success')::boolean);
select public.enqueue_media_relation_refresh('ANIME', 1290001, 'detail_open');
select public.enqueue_media_relation_refresh('MANGA', 1290002, 'concierge_recommend');
select public.enqueue_media_relation_refresh('ANIME', 1290001, 'discover_primary');
select tests.reset();
select tests.eq('availability rows written with the sent reason',
  (select string_agg(media_type || ':' || request_reason, ',' order by media_type)
   from public.provider_availability_refresh_state where media_id in (1290001, 1290002)),
  'ANIME:detail_open,MANGA:on_demand_open');
select tests.eq('relation rows written (last reason wins for the anime)',
  (select string_agg(media_type || ':' || reason, ',' order by media_type)
   from public.media_relation_refresh_queue where media_id in (1290001, 1290002)),
  'ANIME:discover_primary,MANGA:concierge_recommend');

-- ---- B. the media must exist --------------------------------------------------------------------------
select tests.as_user(tests.uid(1291));
select tests.eq('availability: unknown media id is rejected',
  public.enqueue_media_availability_refresh('ANIME', 1299999, 'detail_open')->>'error', 'unknown_media');
select tests.eq('availability: null media id is rejected',
  public.enqueue_media_availability_refresh('ANIME', null, 'detail_open')->>'error', 'unknown_media');
select tests.eq('availability: an anime id is not a manga id',
  public.enqueue_media_availability_refresh('MANGA', 1290001, 'detail_open')->>'error', 'unknown_media');
select public.enqueue_media_relation_refresh('ANIME', 1299999, 'detail_open');
select tests.reset();
select tests.eq('no queue row for unknown media (both queues)',
  (select count(*) from public.provider_availability_refresh_state where media_id in (1299999))
  + (select count(*) from public.media_relation_refresh_queue where media_id in (1299999)), 0::bigint);

-- ---- C. the reason is a fixed set ---------------------------------------------------------------------
select tests.as_user(tests.uid(1291));
select tests.eq('availability: free-text reason rejected',
  public.enqueue_media_availability_refresh('ANIME', 1290001, 'pin-me-' || repeat('x', 500))->>'error', 'invalid_reason');
select tests.eq('availability: relation-only reason rejected',
  public.enqueue_media_availability_refresh('ANIME', 1290001, 'discover_primary')->>'error', 'invalid_reason');
select tests.raises('relation: free-text reason rejected',
  $q$select public.enqueue_media_relation_refresh('ANIME', 1290001, 'pin-me')$q$, '%Unsupported reason%');
select tests.raises('relation: availability-only reason rejected',
  $q$select public.enqueue_media_relation_refresh('ANIME', 1290001, 'user_tap')$q$, '%Unsupported reason%');
select tests.raises('relation: bad media type still 22023',
  $q$select public.enqueue_media_relation_refresh('GAME', 1290001, 'detail_open')$q$, '%Unsupported media type%');
select tests.reset();
select tests.ok('rejected reasons left no trace',
  not exists (select 1 from public.provider_availability_refresh_state where request_reason like 'pin-me%' or request_reason = 'discover_primary')
  and not exists (select 1 from public.media_relation_refresh_queue where reason in ('pin-me', 'user_tap')));

-- ---- D. in-progress rows are never reset -------------------------------------------------------------
update public.media_relation_refresh_queue
   set status = 'processing', last_attempt_at = now() - interval '1 minute', retry_count = 2, reason = 'detail_open'
 where media_type = 'MANGA' and media_id = 1290002;
select tests.as_user(tests.uid(1291));
select public.enqueue_media_relation_refresh('MANGA', 1290002, 'discover_primary');
select tests.reset();
select tests.eq('relation: a processing row is untouched (status, reason, retry_count, last_attempt_at kept)',
  (select status || '/' || reason || '/' || retry_count || '/' || (last_attempt_at is not null)::text
   from public.media_relation_refresh_queue where media_type = 'MANGA' and media_id = 1290002),
  'processing/detail_open/2/true');
update public.media_relation_refresh_queue set status = 'ok' where media_type = 'MANGA' and media_id = 1290002;
select tests.as_user(tests.uid(1291));
select public.enqueue_media_relation_refresh('MANGA', 1290002, 'discover_primary');
select tests.reset();
select tests.eq('relation: a finished row is re-queued as before',
  (select status || '/' || reason from public.media_relation_refresh_queue where media_type = 'MANGA' and media_id = 1290002),
  'pending/discover_primary');

-- availability: a pending row that already holds a priority reason is not re-pinned
update public.provider_availability_refresh_state
   set next_refresh_at = now() + interval '3 hours', last_requested_at = now() - interval '2 hours', request_reason = 'detail_open', status = 'pending'
 where media_type = 'ANIME' and media_id = 1290001;
create temp table t129_state on commit drop as
  select next_refresh_at, last_requested_at from public.provider_availability_refresh_state where media_type = 'ANIME' and media_id = 1290001;
select tests.as_user(tests.uid(1291));
select tests.ok('availability: repeat call on a pending priority row still reports success',
  (public.enqueue_media_availability_refresh('ANIME', 1290001, 'user_tap')->>'success')::boolean);
select tests.reset();
select tests.ok('availability: the pending priority row was not re-pinned (times and reason kept)',
  (select p.next_refresh_at = s.next_refresh_at and p.last_requested_at = s.last_requested_at and p.request_reason = 'detail_open'
   from public.provider_availability_refresh_state p, t129_state s where p.media_type = 'ANIME' and p.media_id = 1290001));
-- an 'ok' row is queued again (normal refresh request), and a low-priority pending row can be upgraded
update public.provider_availability_refresh_state set status = 'ok', request_reason = 'scheduled', next_refresh_at = now() + interval '3 hours'
 where media_type = 'ANIME' and media_id = 1290001;
select tests.as_user(tests.uid(1291));
select public.enqueue_media_availability_refresh('ANIME', 1290001, 'detail_open');
select tests.reset();
select tests.eq('availability: an ok row is queued again with the requested reason',
  (select status || '/' || request_reason from public.provider_availability_refresh_state where media_type = 'ANIME' and media_id = 1290001),
  'pending/detail_open');

-- ---- E. per-user rate limit: 30 per 5 minutes per function ----------------------------------------
select tests.as_user(tests.uid(1292));
create temp table t129_rl on commit drop as
  select n, public.enqueue_media_availability_refresh('ANIME', 1290001, 'on_demand') as r from generate_series(1, 32) n;
select tests.eq('availability: 30 allowed, calls 31 and 32 rate_limited',
  (select count(*) filter (where r->>'error' = 'rate_limited') from t129_rl), 2::bigint);
select tests.ok('availability: the limited reply carries retry_after_s',
  (select (r->>'retry_after_s')::int between 1 and 300 from t129_rl where n = 32));
select tests.ok('availability: the first 30 succeeded',
  (select bool_and((r->>'success')::boolean) from t129_rl where n <= 30));
select tests.reset();

-- relation: over-limit calls are silent no-ops that write nothing
update public.media_relation_refresh_queue set status = 'ok', reason = 'on_demand' where media_type = 'ANIME' and media_id = 1290001;
select tests.as_user(tests.uid(1292));
do $$
begin
  for i in 1..30 loop perform public.enqueue_media_relation_refresh('ANIME', 1290001, 'detail_open'); end loop;
end $$;
select tests.reset();
update public.media_relation_refresh_queue set status = 'ok' where media_type = 'ANIME' and media_id = 1290001;
select tests.as_user(tests.uid(1292));
select public.enqueue_media_relation_refresh('ANIME', 1290001, 'detail_open');
select tests.reset();
select tests.eq('relation: call 31 in the window changed nothing',
  (select status from public.media_relation_refresh_queue where media_type = 'ANIME' and media_id = 1290001), 'ok');
select tests.as_user(tests.uid(1291));
select public.enqueue_media_relation_refresh('ANIME', 1290001, 'detail_open');
select tests.reset();
select tests.eq('relation: another user has their own bucket',
  (select status from public.media_relation_refresh_queue where media_type = 'ANIME' and media_id = 1290001), 'pending');

-- ---- F. grants ------------------------------------------------------------------------------------------
select tests.ok('availability: authenticated + service_role execute; anon and PUBLIC do not',
  has_function_privilege('authenticated', 'public.enqueue_media_availability_refresh(text,integer,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.enqueue_media_availability_refresh(text,integer,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.enqueue_media_availability_refresh(text,integer,text)', 'EXECUTE'));
select tests.ok('relation: authenticated + service_role execute; anon does not',
  has_function_privilege('authenticated', 'public.enqueue_media_relation_refresh(text,integer,text)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.enqueue_media_relation_refresh(text,integer,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.enqueue_media_relation_refresh(text,integer,text)', 'EXECUTE'));
select tests.as_anon();
select tests.denied('anon cannot call the relation enqueue',
  $q$select public.enqueue_media_relation_refresh('ANIME', 1290001, 'detail_open')$q$);
select tests.reset();
select tests.ok('both are SECURITY DEFINER with search_path = public, extensions',
  (select bool_and(p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c = 'search_path=public, extensions'))
   from pg_proc p where p.oid in ('public.enqueue_media_availability_refresh(text,integer,text)'::regprocedure,
                                  'public.enqueue_media_relation_refresh(text,integer,text)'::regprocedure)));

rollback;
