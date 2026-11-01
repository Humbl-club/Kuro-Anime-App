-- 92_auth_hardening.sql
-- Prepared 20261101030000_auth_hardening.sql (NOT deployed): check_email_exists(text) is no
-- longer callable by anon or authenticated (account enumeration, D13); service_role keeps it.
-- The function itself comes from 20260225100000 (live): a prerequisite.
-- @requires function public.check_email_exists(text)
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(921);
select tests.ok('privileges: anon, authenticated and PUBLIC have no EXECUTE; service_role has',
  not has_function_privilege('anon', 'public.check_email_exists(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.check_email_exists(text)', 'execute')
  and not exists (select 1 from information_schema.routine_privileges
                  where routine_schema = 'public' and routine_name = 'check_email_exists' and grantee = 'PUBLIC')
  and has_function_privilege('service_role', 'public.check_email_exists(text)', 'execute'));

select tests.as_anon();
select tests.denied('anon cannot probe whether an e-mail has an account',
  $q$select public.check_email_exists('user921@tests.invalid')$q$);
select tests.as_user(tests.uid(921));
select tests.denied('a signed-in user cannot probe other e-mails either',
  $q$select public.check_email_exists('user921@tests.invalid')$q$);
select tests.reset();
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select tests.eq('service_role still gets the answer (function body unchanged)',
  public.check_email_exists('USER921@tests.invalid '), true);
select tests.eq('service_role: unknown e-mail is false', public.check_email_exists('nobody@tests.invalid'), false);
select tests.reset();
rollback;
