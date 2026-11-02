-- 93_contact_messages.sql
-- Prepared 20261102100000_contact_messages.sql (NOT deployed): the contact form table is service
-- role only. anon and authenticated (own JWT, even for a row carrying their own user_id) can
-- neither SELECT, INSERT, UPDATE nor DELETE; the purge function is not callable by them; the
-- purge deletes exactly the rows older than 12 months; the daily cron job is registered once;
-- account deletion unlinks (SET NULL) instead of blocking or deleting.
-- No @requires: the table and function are the subject under test (absence must FAIL).
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(931), tests.make_user(932);

-- ===================== 1. posture (catalog) ==================================
select tests.ok('RLS is enabled on contact_messages',
  (select relrowsecurity from pg_class where oid = 'public.contact_messages'::regclass));
select tests.eq('no RLS policies at all (service role only)',
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'contact_messages'), 0::bigint);
select tests.ok('anon/authenticated hold no table privilege; service_role holds all four',
  not has_table_privilege('anon', 'public.contact_messages', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.contact_messages', 'select,insert,update,delete')
  and has_table_privilege('service_role', 'public.contact_messages', 'select')
  and has_table_privilege('service_role', 'public.contact_messages', 'insert')
  and has_table_privilege('service_role', 'public.contact_messages', 'update')
  and has_table_privilege('service_role', 'public.contact_messages', 'delete'));
select tests.ok('purge function: no EXECUTE for anon/authenticated/PUBLIC; service_role has it; search_path pinned',
  not has_function_privilege('anon', 'public.purge_contact_messages_v1()', 'execute')
  and not has_function_privilege('authenticated', 'public.purge_contact_messages_v1()', 'execute')
  and not exists (select 1 from information_schema.routine_privileges
                  where routine_schema = 'public' and routine_name = 'purge_contact_messages_v1' and grantee = 'PUBLIC')
  and has_function_privilege('service_role', 'public.purge_contact_messages_v1()', 'execute')
  and exists (select 1 from pg_proc where oid = 'public.purge_contact_messages_v1()'::regprocedure
              and proconfig @> array['search_path=public, extensions']));
select tests.eq('exactly one daily retention cron job with the purge command',
  (select string_agg(schedule || ' | ' || command, '; ') from cron.job where jobname = 'contact-messages-retention'),
  '50 4 * * * | select public.purge_contact_messages_v1();');
select tests.eq('user_id FK to auth.users is ON DELETE SET NULL',
  (select confdeltype::text from pg_constraint
   where conrelid = 'public.contact_messages'::regclass and contype = 'f'
     and confrelid = 'auth.users'::regclass), 'n');

-- ===================== 2. seed as service role ===============================
select tests.reset();
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
insert into public.contact_messages (id, created_at, source, topic, email, message, user_id)
values ('c0000000-0000-4000-8000-000000000001', now() - interval '13 months', 'web', 'general', 'old@tests.invalid', 'old', null),
       ('c0000000-0000-4000-8000-000000000002', now() - interval '11 months', 'app', 'support', 'user931@tests.invalid', 'mine', tests.uid(931)),
       ('c0000000-0000-4000-8000-000000000003', now(), 'web', 'privacy', 'new@tests.invalid', 'new', null);
select tests.eq('service_role reads every row', tests.rowcount('select 1 from public.contact_messages'), 3::bigint);
select tests.reset();

-- ===================== 3. anon ===============================================
select tests.as_anon();
select tests.denied('anon cannot SELECT', $q$select count(*) from public.contact_messages$q$);
select tests.denied('anon cannot INSERT',
  $q$insert into public.contact_messages (source, topic, email, message) values ('web','general','a@tests.invalid','hi')$q$);
select tests.denied('anon cannot UPDATE', $q$update public.contact_messages set status = 'handled'$q$);
select tests.denied('anon cannot DELETE', $q$delete from public.contact_messages$q$);
select tests.denied('anon cannot run the purge', $q$select public.purge_contact_messages_v1()$q$);
select tests.reset();

-- ===================== 4. authenticated (even for its own row) ===============
select tests.as_user(tests.uid(931));
select tests.denied('authenticated cannot SELECT (not even its own message)',
  $q$select count(*) from public.contact_messages where user_id = auth.uid()$q$);
select tests.denied('authenticated cannot INSERT (not even with its own user_id)',
  $q$insert into public.contact_messages (source, topic, email, message, user_id) values ('app','general','user931@tests.invalid','hi', auth.uid())$q$);
select tests.denied('authenticated cannot UPDATE its own message',
  $q$update public.contact_messages set message = 'changed' where user_id = auth.uid()$q$);
select tests.denied('authenticated cannot DELETE', $q$delete from public.contact_messages$q$);
select tests.denied('authenticated cannot run the purge', $q$select public.purge_contact_messages_v1()$q$);
select tests.reset();

-- ===================== 5. constraints (service role) =========================
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select tests.raises('topic outside the enum is rejected',
  $q$insert into public.contact_messages (source, topic, email, message) values ('web','spam','a@tests.invalid','hi')$q$, '%check constraint%');
select tests.raises('source outside the enum is rejected',
  $q$insert into public.contact_messages (source, topic, email, message) values ('api','general','a@tests.invalid','hi')$q$, '%check constraint%');
select tests.raises('malformed email is rejected',
  $q$insert into public.contact_messages (source, topic, email, message) values ('web','general','not-an-email','hi')$q$, '%check constraint%');
select tests.raises('empty message is rejected',
  $q$insert into public.contact_messages (source, topic, email, message) values ('web','general','a@tests.invalid','')$q$, '%check constraint%');
select tests.raises('message over 4000 characters is rejected',
  $q$insert into public.contact_messages (source, topic, email, message) values ('web','general','a@tests.invalid', repeat('x', 4001))$q$, '%check constraint%');
select tests.eq('message of exactly 4000 characters is accepted',
  tests.affected($q$insert into public.contact_messages (source, topic, email, message, created_at) values ('web','other','b@tests.invalid', repeat('x', 4000), now())$q$), 1::bigint);
select tests.raises('status outside new/handled is rejected',
  $q$update public.contact_messages set status = 'archived' where id = 'c0000000-0000-4000-8000-000000000003'$q$, '%check constraint%');

-- ===================== 6. purge ==============================================
select tests.eq('purge deletes exactly the row older than 12 months', public.purge_contact_messages_v1(), 1);
select tests.eq('the 11-month and new rows survive the purge',
  (select string_agg(id::text, ',' order by id) from public.contact_messages where id::text like 'c0000000-%'),
  'c0000000-0000-4000-8000-000000000002,c0000000-0000-4000-8000-000000000003');
select tests.eq('a second purge deletes nothing', public.purge_contact_messages_v1(), 0);
select tests.reset();

-- ===================== 7. account deletion unlinks ===========================
delete from auth.users where id = tests.uid(931);  -- stands in for GoTrue's admin deletion (superuser)
select tests.eq('account deletion keeps the message but clears user_id (SET NULL)',
  (select coalesce(user_id::text, 'null') from public.contact_messages where id = 'c0000000-0000-4000-8000-000000000002'),
  'null');

-- ===================== 8. limiter buckets contact-submit relies on ===========
-- contact-submit calls check_concierge_rate_limit only as anon (callerClient(null)) with an
-- explicit key in p_ip, so auth.uid() adds no implicit bucket; kinds keep the counters apart.
select tests.ok('fixture: check_concierge_rate_limit exists',
  to_regprocedure('public.check_concierge_rate_limit(text,text,integer,integer,integer)') is not null);
select tests.as_anon();
create temp table _rl on commit drop as
  select n, public.check_concierge_rate_limit('contact', 'contact:t93-ip', 3600, 5, 5) as r
  from generate_series(1, 6) n;
select tests.eq('anon, explicit key: five allowed per hour, the sixth denied',
  (select string_agg((r->>'allowed'), ',' order by n) from _rl), 'true,true,true,true,true,false');
select tests.eq('anon caller adds no user bucket (user_hits is null)',
  (select count(*) from _rl where r->>'user_hits' is not null), 0::bigint);
select tests.ok('the same key under another kind is a separate counter (contact_app_ip, 30/h)',
  (public.check_concierge_rate_limit('contact_app_ip', 'contact:t93-ip', 3600, 30, 30)->>'allowed')::boolean
  and (public.check_concierge_rate_limit('contact_app_ip', 'contact:t93-ip', 3600, 30, 30)->>'ip_hits')::int = 2);
select tests.ok('global ceiling key counts across callers',
  (public.check_concierge_rate_limit('contact_global', 'contact:global', 3600, 200, 200)->>'ip_hits')::int = 1
  and (public.check_concierge_rate_limit('contact_global', 'contact:global', 3600, 200, 200)->>'ip_hits')::int = 2);
select tests.reset();

rollback;
