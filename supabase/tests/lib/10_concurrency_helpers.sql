-- ============================================================================
-- 10_concurrency_helpers.sql -- two-session interleaving helpers (throwaway DB only)
--
-- Loaded by scripts/db/run_local_db_tests.sh into a FRESH clone of the fixture
-- database for every file in supabase/tests/concurrency/ (those files COMMIT, so
-- they never share a database with each other or with supabase/tests/rls/).
--
-- Each actor is a real, separate PostgreSQL backend opened with dblink to the
-- same throwaway database over the runner's unix socket (the runner passes the
-- connection string as psql variable :conn). The psql session itself is only the
-- orchestrator: it never holds the locks under test, it starts actor statements
-- (actor_exec = send + wait; actor_send alone for a statement expected to block) and
-- waits on OBSERVABLE STATE (pg_locks / dblink_is_busy), never on a fixed sleep.
-- ============================================================================
\set ON_ERROR_STOP on

-- dblink lives in `tests` unless the template database already has it in another schema
-- (another test file may have created it); the helpers below call it unqualified with
-- search_path = tests, extensions, public, so either placement works.
create extension if not exists dblink with schema tests;

-- Open an actor session `name` acting as a fresh, idle backend.
create or replace function tests.actor_open(name text, conninfo text) returns int
language plpgsql set search_path = tests, extensions, public as $$
declare pid int;
begin
  perform dblink_connect(name, conninfo);
  select p into pid from dblink(name, 'select pg_backend_pid()') as t(p int);
  return pid;
end $$;

-- Start one statement asynchronously in actor `name` (it may block on a lock).
-- The statement must return at most one row with at most one column (a command
-- such as BEGIN/COMMIT yields its status string).
create or replace function tests.actor_send(name text, stmt text) returns void
language plpgsql set search_path = tests, extensions, public as $$
begin
  if dblink_send_query(name, stmt) <> 1 then
    raise exception 'HARNESS: dblink_send_query failed for actor % (%)', name, dblink_error_message(name);
  end if;
end $$;

-- State-based wait: return once backend `pid` is waiting for a lock that is not
-- granted (pg_locks is a live view, unlike the per-transaction pg_stat_activity
-- snapshot). Fails the test after `timeout_ms` instead of hanging.
create or replace function tests.wait_lock_wait(pid int, timeout_ms int default 15000) returns text
language plpgsql set search_path = tests, extensions, public as $$
declare
  started timestamptz := clock_timestamp();
  kind text;
begin
  loop
    select string_agg(distinct l.locktype, ',') into kind
      from pg_locks l where l.pid = wait_lock_wait.pid and not l.granted;
    if kind is not null then
      return kind;
    end if;
    if clock_timestamp() - started > make_interval(secs => timeout_ms / 1000.0) then
      raise exception 'TEST FAIL: backend % never started waiting for a lock within % ms', pid, timeout_ms;
    end if;
    perform pg_sleep(0.005);
  end loop;
end $$;

-- State-based wait for an asynchronous actor statement to finish; returns its
-- single text value, '' for no row, or 'ERROR: <message>'. Drains the result
-- queue so the actor connection can be reused.
create or replace function tests.actor_result(name text, timeout_ms int default 15000) returns text
language plpgsql set search_path = tests, extensions, public as $$
declare
  started timestamptz := clock_timestamp();
  v text;
  got boolean := false;
  msg text;
begin
  while dblink_is_busy(name) = 1 loop
    if clock_timestamp() - started > make_interval(secs => timeout_ms / 1000.0) then
      raise exception 'TEST FAIL: actor % did not finish within % ms', name, timeout_ms;
    end if;
    perform pg_sleep(0.005);
  end loop;
  for v in select r from dblink_get_result(name, false) as t(r text) loop
    got := true;
    exit;
  end loop;
  msg := dblink_error_message(name);
  -- drain: one more call returns the empty set that frees the connection
  perform 1 from dblink_get_result(name, false) as t(r text);
  if msg is not null and msg <> 'OK' and msg <> '' then
    return 'ERROR: ' || btrim(regexp_replace(msg, '^ERROR:\s*', ''), E' \n');
  end if;
  return case when got then coalesce(v, '') else '' end;
end $$;

-- Run one statement in actor `name` and wait for it: returns its single text
-- value / command status, or 'ERROR: <message>' (never raises, so a test can
-- assert on a refusal). Use actor_send + wait_lock_wait for a statement that is
-- expected to block.
create or replace function tests.actor_exec(name text, stmt text, timeout_ms int default 15000) returns text
language plpgsql set search_path = tests, extensions, public as $$
begin
  perform tests.actor_send(name, stmt);
  return tests.actor_result(name, timeout_ms);
end $$;

create or replace function tests.actor_close(name text) returns void
language plpgsql set search_path = tests, extensions, public as $$
begin
  perform dblink_disconnect(name);
end $$;
