-- ============================================================================
-- 00_platform_stub.sql  --  STUBS of Supabase platform objects (test fixture)
--
-- THIS IS NOT SUPABASE.  It is the smallest set of stand-ins that lets the
-- repo's migrations parse/apply on a vanilla Homebrew PostgreSQL 17 cluster.
-- It is NOT Supabase Auth (GoTrue), NOT Realtime, NOT Storage, NOT PostgREST,
-- NOT pg_cron / pg_net / vault.  Everything here is a documented stub.
--
-- Applied once, as the cluster superuser, to a THROWAWAY database only
-- (scripts/db/run_local_db_tests.sh refuses to run against anything else).
-- Contains no credentials.
-- ============================================================================
\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- Roles (Supabase shape).  The cluster superuser is `postgres`.
--   anon / authenticated : NOLOGIN, NOBYPASSRLS  (the roles RLS is judged under)
--   service_role         : NOLOGIN, BYPASSRLS    (never used for access tests)
--   authenticator        : login role PostgREST connects as, member of the above
--   supabase_admin       : superuser stand-in so `... OWNER TO supabase_admin` parses
-- Passwords are intentionally NOT set (unix-socket trust auth on a throwaway
-- cluster; there is nothing to log in to remotely).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'supabase_admin') then
    create role supabase_admin superuser login;
  end if;
end $$;
grant anon, authenticated, service_role to authenticator;

-- ---------------------------------------------------------------------------
-- Schemas + extensions that Homebrew PostgreSQL 17 actually ships.
-- Supabase installs extensions into the `extensions` schema; migrations use
-- `SET search_path = public, extensions` and call extensions.similarity().
-- (pgvector is NOT available in Homebrew PG; no migration uses the vector type.)
-- ---------------------------------------------------------------------------
create schema if not exists extensions;
create extension if not exists pg_trgm  with schema extensions;
create extension if not exists pgcrypto with schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;

-- Supabase sets the database-level search_path to "$user", public, extensions so
-- extension objects (e.g. pg_trgm's gin_trgm_ops operator class) resolve
-- unqualified.  Migrations rely on this (20260203171100_concierge_core.sql
-- creates a gin_trgm_ops index with no schema qualification).  Takes effect for
-- new sessions.
do $$
begin
  execute format('alter database %I set search_path = "$user", public, extensions', current_database());
end $$;
grant usage on schema public     to anon, authenticated, service_role;

-- Supabase's default privileges for objects created by migrations (run as
-- `postgres`): every public-schema table/sequence/function is granted to the
-- API roles; RLS (not GRANT) is then the real gate.  Emulated here so the
-- RLS tests judge the same thing PostgREST would.  Migration-level REVOKEs
-- still apply on top, because they run after this.
alter default privileges for role postgres in schema public
  grant all on tables    to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on functions to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- STUB auth schema (NOT GoTrue).  auth.uid()/role()/jwt() read the request
-- claims GUCs the same way Supabase's definitions do, so setting
--   set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true)
-- followed by SET LOCAL ROLE authenticated reproduces the PostgREST path.
-- ---------------------------------------------------------------------------
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  instance_id        uuid,
  id                 uuid primary key,
  aud                varchar(255),
  role               varchar(255),
  email              varchar(255),
  encrypted_password varchar(255),
  email_confirmed_at timestamptz,
  raw_app_meta_data  jsonb,
  raw_user_meta_data jsonb,
  is_anonymous       boolean not null default false,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now()
);
-- Real Supabase: RLS is not enabled on auth.users but API roles have no
-- privileges on it.  Mirror that (service_role / postgres only).
revoke all on auth.users from anon, authenticated;

create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

grant execute on function auth.uid(), auth.role(), auth.jwt()
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- STUB storage schema (NOT Supabase Storage).  Only what policies in the
-- migrations reference: storage.buckets, storage.objects (RLS on, as in
-- Supabase) and storage.foldername().
-- ---------------------------------------------------------------------------
create schema if not exists storage;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists storage.buckets (
  id     text primary key,
  name   text not null,
  public boolean default false
);
create table if not exists storage.objects (
  id        uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name      text,
  owner     uuid,
  owner_id  text,
  metadata  jsonb,
  created_at timestamptz default now()
);
alter table storage.objects enable row level security;
grant all on storage.buckets, storage.objects to anon, authenticated, service_role;

create or replace function storage.foldername(name text) returns text[]
language plpgsql immutable as $$
declare _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1:array_length(_parts, 1) - 1];
end $$;

-- ---------------------------------------------------------------------------
-- STUB realtime publication (membership only; no Realtime server).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- STUB pg_cron: `cron` schema that RECORDS schedule/unschedule/alter_job
-- calls into cron.job and never runs anything.  pg_cron itself is not
-- available in Homebrew PG, so a synthetic pg_extension row is inserted so
-- `create extension if not exists pg_cron` and `pg_extension` probes behave
-- as on Supabase.  Nothing is ever scheduled or executed.
-- ---------------------------------------------------------------------------
create schema if not exists cron;
create table if not exists cron.job (
  jobid    bigserial primary key,
  schedule text not null,
  command  text not null,
  nodename text not null default 'localhost',
  nodeport int  not null default 5432,
  database text not null default current_database(),
  username text not null default current_user,
  active   boolean not null default true,
  jobname  text
);
create unique index if not exists cron_job_jobname_uq on cron.job (jobname) where jobname is not null;

create or replace function cron.schedule(job_name text, schedule text, command text)
returns bigint language plpgsql as $$
declare _id bigint;
begin
  insert into cron.job (jobname, schedule, command) values (job_name, schedule, command)
  on conflict (jobname) where jobname is not null
  do update set schedule = excluded.schedule, command = excluded.command
  returning jobid into _id;
  return _id;
end $$;

create or replace function cron.schedule(schedule text, command text)
returns bigint language plpgsql as $$
declare _id bigint;
begin
  insert into cron.job (schedule, command) values (schedule, command) returning jobid into _id;
  return _id;
end $$;

create or replace function cron.unschedule(job_id bigint) returns boolean
language plpgsql as $$
begin
  delete from cron.job where jobid = job_id;
  return found;
end $$;

create or replace function cron.unschedule(job_name text) returns boolean
language plpgsql as $$
begin
  delete from cron.job where jobname = job_name;
  return found;
end $$;

create or replace function cron.alter_job(
  job_id bigint,
  schedule text default null,
  command text default null,
  database text default null,
  username text default null,
  active boolean default null
) returns void language plpgsql as $$
begin
  update cron.job j set
    schedule = coalesce(alter_job.schedule, j.schedule),
    command  = coalesce(alter_job.command,  j.command),
    active   = coalesce(alter_job.active,   j.active)
  where j.jobid = job_id;
end $$;

-- ---------------------------------------------------------------------------
-- STUB pg_net: `net.http_post` / `net.http_get` are no-ops that return 0.
-- They NEVER open a network connection.  (Migrations embed prod URLs inside
-- cron command strings; with these stubs nothing can ever reach them.)
-- ---------------------------------------------------------------------------
create schema if not exists net;
create or replace function net.http_post(
  url text,
  body jsonb default '{}'::jsonb,
  params jsonb default '{}'::jsonb,
  headers jsonb default '{"Content-Type": "application/json"}'::jsonb,
  timeout_milliseconds integer default 5000
) returns bigint language sql as $$ select 0::bigint $$;

create or replace function net.http_get(
  url text,
  params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb,
  timeout_milliseconds integer default 5000
) returns bigint language sql as $$ select 0::bigint $$;

-- Synthetic pg_extension rows (catalog DML, throwaway DB only).
do $$
declare _nsp oid;
begin
  select oid into _nsp from pg_namespace where nspname = 'cron';
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    insert into pg_extension (oid, extname, extowner, extnamespace, extrelocatable, extversion, extconfig, extcondition)
    values ((select coalesce(max(oid::text::bigint), 90000) + 1 from pg_extension)::oid::oid,
            'pg_cron', (select oid from pg_roles where rolname = 'postgres'), _nsp, false, '0.0-stub', null, null);
  end if;
exception when others then
  raise notice 'could not register synthetic pg_cron extension row (%): create extension pg_cron will fail', sqlerrm;
end $$;
