-- 40_streaming_and_taste.sql  --  (d) user_streaming_services + taste tables: owner isolation
-- Taste objects created by migrations that do NOT replay in this fixture
-- (taste_tag_stats ... 20260731060000) are reported BLOCKED by the runner's
-- requirement manifest below, not faked.
-- @requires table public.user_streaming_services
-- @requires table public.streaming_services
-- @requires table public.user_taste_profiles
-- @requires table public.taste_signal_events
-- @requires table public.taste_import_context
-- @requires table public.taste_profile_recompute_queue
-- @requires function public.save_user_streaming_services(text[])
-- @requires-for "taste_tag_stats owner isolation (taste_tag_stats_select_own; created by 20260731060000, recovery: production-equivalent schema)" table public.taste_tag_stats
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2);
select tests.eq('streaming_services catalog is seeded by migrations', (select count(*) >= 2 from public.streaming_services), true);
select slug as svc_a from public.streaming_services order by slug limit 1 \gset
select slug as svc_b from public.streaming_services order by slug offset 1 limit 1 \gset

-- ============================ user_streaming_services ========================
select tests.as_user(tests.uid(1));
select tests.eq('owner saves services through the RPC',
  (public.save_user_streaming_services(array[:'svc_a', :'svc_b'])) ->> 'inserted', '2');
select tests.eq('owner reads own 2 rows', (select count(*) from public.user_streaming_services), 2::bigint);
select tests.eq('owner deletes one own row directly', tests.affected(format($q$delete from public.user_streaming_services where service=%L$q$, :'svc_b')), 1::bigint);
select tests.denied('owner cannot insert a row for another user',
  format($q$insert into public.user_streaming_services (user_id, service) values (%L, %L)$q$, tests.uid(2), :'svc_a'));
select tests.eq('no UPDATE policy: owner UPDATE of own row affects 0 rows (table is insert/delete only)',
  tests.affected(format($q$update public.user_streaming_services set service=%L where user_id=auth.uid()$q$, :'svc_b')), 0::bigint);

select tests.as_user(tests.uid(2));
select tests.eq('user 2 reads 0 of user 1 rows', (select count(*) from public.user_streaming_services), 0::bigint);
select tests.eq('user 2 DELETE of user 1 rows affects 0', tests.affected($q$delete from public.user_streaming_services$q$), 0::bigint);
select tests.denied('user 2 cannot insert for user 1',
  format($q$insert into public.user_streaming_services (user_id, service) values (%L, %L)$q$, tests.uid(1), :'svc_b'));
select tests.eq('user 2 RPC only touches own rows (does not delete user 1''s)',
  (public.save_user_streaming_services(array[:'svc_b'])) ->> 'deleted', '0');
select tests.as_anon();
select tests.eq('anon reads 0 rows', (select count(*) from public.user_streaming_services), 0::bigint);
select tests.eq('anon RPC returns unauthenticated', (public.save_user_streaming_services(array[:'svc_a'])) ->> 'error', 'unauthenticated');
select tests.reset();
select tests.eq('readback: user 1 still has exactly svc_a', (select count(*) from public.user_streaming_services where user_id = tests.uid(1) and service = :'svc_a'), 1::bigint);

-- ============================ user_taste_profiles ============================
select tests.reset();
insert into public.user_taste_profiles (user_id, vector) values (tests.uid(1), '{"k":1}'::jsonb);
insert into public.user_taste_profiles (user_id, vector) values (tests.uid(2), '{"k":2}'::jsonb);
select tests.as_user(tests.uid(1));
select tests.eq('owner reads exactly own taste profile', (select count(*) from public.user_taste_profiles), 1::bigint);
select tests.eq('owner reads own vector', (select vector ->> 'k' from public.user_taste_profiles), '1');
select tests.eq('owner updates own taste profile', tests.affected($q$update public.user_taste_profiles set vector='{"k":9}' where user_id = auth.uid()$q$), 1::bigint);
select tests.eq('owner UPDATE of user 2 profile affects 0 rows', tests.affected(format($q$update public.user_taste_profiles set vector='{"k":0}' where user_id=%L$q$, tests.uid(2))), 0::bigint);
select tests.eq('owner DELETE of user 2 profile affects 0 rows', tests.affected(format($q$delete from public.user_taste_profiles where user_id=%L$q$, tests.uid(2))), 0::bigint);
select tests.denied('owner cannot insert a profile for user 2',
  format($q$insert into public.user_taste_profiles (user_id, vector) values (%L, '{}')$q$, tests.uid(3)));
select tests.as_anon();
select tests.eq('anon reads 0 taste profiles', (select count(*) from public.user_taste_profiles), 0::bigint);
select tests.reset();
select tests.eq('readback: user 2 profile intact', (select vector ->> 'k' from public.user_taste_profiles where user_id = tests.uid(2)), '2');

-- ============================ taste_signal_events ============================
insert into public.taste_signal_events (user_id, media_id, media_type, event_type, event_strength)
  values (tests.uid(1), 1, 'ANIME', 'test', 1.0), (tests.uid(2), 1, 'ANIME', 'test', 1.0);
select tests.as_user(tests.uid(1));
select tests.eq('owner reads own signal events only', (select count(*) from public.taste_signal_events), 1::bigint);
select tests.denied('authenticated has no INSERT grant on taste_signal_events (server-written)',
  format($q$insert into public.taste_signal_events (user_id, media_id, media_type, event_type, event_strength) values (%L,2,'ANIME','x',1)$q$, tests.uid(1)));
select tests.denied('authenticated has no DELETE grant on taste_signal_events',
  $q$delete from public.taste_signal_events$q$);
select tests.as_anon();
select tests.eq('anon reads 0 signal events', (select count(*) from public.taste_signal_events), 0::bigint);

-- ============================ taste_import_context ===========================
select tests.reset();
insert into public.import_sessions (id, user_id) values ('11111111-1111-4111-8111-111111111111', tests.uid(1)), ('22222222-2222-4222-8222-222222222222', tests.uid(2));
insert into public.taste_import_context (user_id, session_id, expires_at) values
  (tests.uid(1), '11111111-1111-4111-8111-111111111111', now() + interval '1 hour'),
  (tests.uid(2), '22222222-2222-4222-8222-222222222222', now() + interval '1 hour');
select tests.as_user(tests.uid(1));
select tests.eq('owner reads own import context only', (select count(*) from public.taste_import_context), 1::bigint);
select tests.eq('owner UPDATE of user 2 context affects 0 rows', tests.affected(format($q$update public.taste_import_context set expires_at = now() where user_id=%L$q$, tests.uid(2))), 0::bigint);
select tests.denied('owner cannot insert a context for user 2',
  format($q$insert into public.taste_import_context (user_id, session_id, expires_at) values (%L, %L, now())$q$, tests.uid(2), '11111111-1111-4111-8111-111111111111'));
select tests.as_anon();
select tests.denied('anon has no SELECT grant on taste_import_context', $q$select * from public.taste_import_context$q$);

-- ============================ queue table: no client access ==================
select tests.as_user(tests.uid(1));
select tests.denied('taste_profile_recompute_queue: authenticated has no SELECT grant',
  $q$select * from public.taste_profile_recompute_queue$q$);
select tests.denied('taste_profile_recompute_queue: authenticated has no INSERT grant',
  format($q$insert into public.taste_profile_recompute_queue (user_id) values (%L)$q$, tests.uid(1)));

-- taste_tag_stats: BLOCKED through the requirement manifest in the header (the runner
-- reports the scope; nothing here asserts on the missing table). When the table exists
-- the scope stops being BLOCKED and this marker asks for the missing isolation test.
select tests.reset();
select case when to_regclass('public.taste_tag_stats') is not null
  then tests.finding('taste_tag_stats now exists in the fixture', 'add an owner-isolation test for it') end;

select tests.reset();
rollback;
