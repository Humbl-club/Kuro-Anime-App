-- ============================================================================
-- 00_test_helpers.sql -- test-only helper schema `tests` (throwaway DB only)
--
-- Identity switching mirrors what PostgREST does for a user request:
--   SET LOCAL ROLE authenticated  +  set_config('request.jwt.claims', <json>, true)
-- so auth.uid() resolves exactly as in Supabase and RLS is evaluated for a
-- NON-superuser, NON-BYPASSRLS role.  The service_role / postgres session is
-- used ONLY to seed fixture rows and to read back catalogs, never to judge
-- user access.
--
-- Assertions RAISE EXCEPTION on mismatch (psql runs with ON_ERROR_STOP, so the
-- run fails) and RAISE NOTICE 'TEST ok|BLOCKED|FINDING: ...' lines that the
-- runner counts.
-- ============================================================================
\set ON_ERROR_STOP on

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Deterministic user ids: tests.uid(1) = abcdef00-0000-4000-8000-000000000001
-- (hex LETTERS on purpose, so upper()/lower() case-variant checks are meaningful)
create or replace function tests.uid(n integer) returns uuid
language sql immutable as $$
  select ('abcdef00-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
$$;

-- Seed an auth.users row (run as the superuser session, i.e. after tests.reset()).
create or replace function tests.make_user(n integer) returns uuid
language plpgsql as $$
begin
  insert into auth.users (id, aud, role, email)
  values (tests.uid(n), 'authenticated', 'authenticated', 'user' || n || '@tests.invalid')
  on conflict (id) do nothing;
  -- Supabase has an auth.users trigger creating the profile; the stub auth schema has none.
  if to_regclass('public.profiles') is not null then
    insert into public.profiles (id, display_name) values (tests.uid(n), 'User ' || n)
    on conflict (id) do nothing;
  end if;
  return tests.uid(n);
end $$;

-- Back to the session (superuser) identity with no JWT claims.
create or replace function tests.reset() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Act as an authenticated end user (PostgREST path).
create or replace function tests.as_user(p_uid uuid) returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated', 'aud', 'authenticated')::text, true);
  set local role authenticated;
end $$;

-- Act as the anonymous API role (publishable key, no user).
create or replace function tests.as_anon() returns void
language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  set local role anon;
end $$;

-- ---- assertions -------------------------------------------------------------

create or replace function tests.ok(label text, cond boolean) returns void
language plpgsql as $$
begin
  if cond is distinct from true then
    raise exception 'TEST FAIL: %', label;
  end if;
  raise notice 'TEST ok: %', label;
end $$;

create or replace function tests.eq(label text, actual anyelement, expected anyelement) returns void
language plpgsql as $$
begin
  if actual is distinct from expected then
    raise exception 'TEST FAIL: % (expected %, got %)', label, expected, actual;
  end if;
  raise notice 'TEST ok: %', label;
end $$;

-- Rows a query returns for the CURRENT role (RLS applies).
create or replace function tests.rowcount(q text) returns bigint
language plpgsql as $$
declare n bigint;
begin
  execute 'select count(*) from (' || q || ') s' into n;
  return n;
end $$;

-- Run a DML statement for the CURRENT role and return rows affected
-- (RLS hides rows from UPDATE/DELETE silently, so 0 means "not visible").
create or replace function tests.affected(stmt text) returns bigint
language plpgsql as $$
declare n bigint;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end $$;

-- Statement must fail with insufficient_privilege (42501: RLS WITH CHECK violation
-- or missing GRANT).  Any OTHER error is re-raised so a test cannot pass for the
-- wrong reason (FK, NOT NULL, typo...).
create or replace function tests.denied(label text, stmt text) returns void
language plpgsql as $$
begin
  begin
    execute stmt;
  exception when insufficient_privilege then
    raise notice 'TEST ok: % (denied: %)', label, sqlerrm;
    return;
  end;
  raise exception 'TEST FAIL: % (statement was ALLOWED, expected 42501)', label;
end $$;

-- Statement must raise an exception whose message matches `like_pattern`
-- (used for RPCs that raise typed errors such as NOT_A_MEMBER).
create or replace function tests.raises(label text, stmt text, like_pattern text) returns void
language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if sqlerrm like like_pattern then
      raise notice 'TEST ok: % (raised: %)', label, sqlerrm;
      return;
    end if;
    raise exception 'TEST FAIL: % (raised "%" which does not match "%")', label, sqlerrm, like_pattern;
  end;
  raise exception 'TEST FAIL: % (no error raised, expected "%")', label, like_pattern;
end $$;

-- Like tests.raises, and additionally the structured DETAIL must equal
-- `expected_detail` (club/social RPCs put machine-readable codes in DETAIL).
create or replace function tests.raises_detail(label text, stmt text, like_pattern text, expected_detail text)
returns void
language plpgsql as $$
declare d text;
begin
  begin
    execute stmt;
  exception when others then
    get stacked diagnostics d = pg_exception_detail;
    if sqlerrm like like_pattern and d is not distinct from expected_detail then
      raise notice 'TEST ok: % (raised: % / detail: %)', label, sqlerrm, d;
      return;
    end if;
    raise exception 'TEST FAIL: % (raised "%" detail "%", expected "%" detail "%")', label, sqlerrm, d, like_pattern, expected_detail;
  end;
  raise exception 'TEST FAIL: % (no error raised, expected "%")', label, like_pattern;
end $$;

-- Evaluate a scalar SQL expression for the CURRENT role and return it as text,
-- or 'ERROR: <message>' if it raises (so a test can assert on either outcome
-- without aborting the transaction).
create or replace function tests.try_scalar(expr text) returns text
language plpgsql as $$
declare r text;
begin
  execute 'select (' || expr || ')::text' into r;
  return r;
exception when others then
  return 'ERROR: ' || sqlerrm;
end $$;

-- Documented-limitation markers (counted by the runner, never failures).
create or replace function tests.blocked(label text, reason text) returns void
language plpgsql as $$
begin
  raise notice 'TEST BLOCKED: % -- %', label, reason;
end $$;

-- A separate evidence layer, never a passing assertion or a missing SQL object.
-- Release qualification must exercise these through real deployed services.
create or replace function tests.requires_live(label text, reason text) returns void
language plpgsql set search_path = public, extensions as $$
begin
  raise notice 'TEST LIVE REQUIRED: % -- %', label, reason;
end $$;

create or replace function tests.finding(label text, detail text) returns void
language plpgsql as $$
begin
  raise notice 'TEST FINDING: % -- %', label, detail;
end $$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
