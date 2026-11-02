-- ============================================================================
-- Account deletion: database-enforced write barrier (F38)
--
-- STATUS: PREPARED, NOT APPLIED TO PRODUCTION. Deployment needs a separate, explicit
--   human approval; the lead registers it in supabase/tests/pending_migrations.txt. It
--   lives in supabase/prepared-migrations/ so no push can deploy it by accident.
--   Deploy order: 20261005140000 -> 20261005150000 -> new delete-account function.
--
-- Problem (reproduced in the fixture, evidence 90_review_deletion_interleaving.sql):
--   the delete-account function deletes the legacy TEXT-keyed rows, and a request that
--   is still authenticated can write a new row afterwards; deleting auth.users does not
--   cascade into those tables, so the row survives the "successful" deletion. A
--   notes-only update of a surviving row works as well.
--
-- Mechanism:
--   * begin_account_deletion(user) (service role only) takes the user's EXCLUSIVE
--     transaction-level advisory lock and records a barrier row (idempotent). Taking the
--     exclusive lock waits for every in-flight writer of that user to finish, so no
--     write can commit after the barrier without the cleanup seeing it.
--   * every INSERT/UPDATE of a user-keyed row that the auth.users cascade would NOT
--     remove takes the same user's SHARED advisory lock in a BEFORE trigger and is
--     refused once a barrier exists (42501, message ACCOUNT_DELETION_IN_PROGRESS). That
--     covers the user's own JWT and service-role writers acting for the user (imports).
--     Guarded tables (the complete set of user-keyed columns without an auth.users
--     CASCADE, plus two special cases):
--       anime_user_lists, manga_user_lists, anime_comments, manga_comments (TEXT, no FK)
--       club_analytics, concierge_events, discover_rail_impressions, rag_retrieval_feedback (no FK)
--       concierge_runs (FK is ON DELETE SET NULL: a late run would survive anonymized)
--       club_members (INSERT only: no new membership during deletion, so the club
--                     lifecycle that runs after the barrier sees every membership)
--     Tables whose user FK CASCADEs need no barrier: a row written before the auth
--     deletion is cascaded by it, a row written after it fails the FK.
--   * DELETE is never blocked (cleanup and retries proceed).
--   * Storage uploads are not table triggers. The media INSERT and UPDATE policies
--     call public.account_deletion_storage_guard(), which takes the same shared
--     advisory lock and then refuses the write when a barrier exists. An upload
--     already inside its INSERT waits for begin_account_deletion's exclusive lock,
--     then sees the barrier and fails. The edge function purges the bucket prefix
--     only after that transaction has committed, then lists again and refuses
--     success if anything remains. Service-role catalog writes bypass these policies.
--     Public catalog objects are not stored under a user-id folder, so this guard
--     does not apply to them.
--   * Isolation: proven for READ COMMITTED (PostgREST's and the edge functions' mode):
--     each statement of the trigger function takes a new snapshot after the lock wait.
--   * The barrier has NO foreign key: it must outlive the auth user, because an access
--     token stays valid until it expires (Supabase allows at most 7 days). Retention is
--     bounded: begin_account_deletion purges barriers older than 7 days whose auth user
--     is gone. A barrier of a user who still exists (an interrupted deletion) is kept
--     until a retry completes; that user cannot write until then, by design.
--
-- Lock order (deadlock freedom): user advisory lock BEFORE any club row lock, in every
--   path (join_club takes the guard first, 20261005150000; the deletion takes the user
--   lock, then club rows in club_id order).
--
-- Production parity / prerequisites (read-only, before deploying; also in
-- supabase/tests/prerequisites/delete_account_prereqs.sql):
--   select to_regclass('public.' || t) from unnest(array['anime_user_lists','manga_user_lists',
--     'anime_comments','manga_comments','club_analytics','concierge_events',
--     'discover_rail_impressions','rag_retrieval_feedback','concierge_runs','club_members']) t;
--   (every table must exist: a missing one makes this file fail loudly, on purpose)
-- Rollback (re-opens F38 and F88): restore the previous media INSERT/UPDATE policies
--   without account_deletion_storage_guard, drop that function, drop the ten
--   account_deletion_barrier triggers, then drop begin_account_deletion,
--   account_deletion_write_barrier, _account_write_guard, _account_deletion_lock_key,
--   and table account_deletion_barriers.
-- ============================================================================

create table if not exists public.account_deletion_barriers (
  user_id    uuid primary key,
  started_at timestamptz not null default now()
);
comment on table public.account_deletion_barriers is
  'F38 write barrier: a row means the account deletion of user_id has started; guarded user-keyed writes for that user are refused. No FK on purpose (outlives the auth user for the JWT lifetime); purged by begin_account_deletion after 7 days once the auth user is gone. Service role only.';
alter table public.account_deletion_barriers enable row level security;
-- no policies: end users can neither read nor write; the service role bypasses RLS
revoke all on table public.account_deletion_barriers from public, anon, authenticated;
grant select, insert, delete on table public.account_deletion_barriers to service_role;

-- One advisory key per user (namespaced, case-insensitive so every spelling of the id
-- serializes on the same lock).
create or replace function public._account_deletion_lock_key(p_user text)
returns bigint
language sql
immutable
set search_path = public, extensions
as $$
  select hashtextextended('kuro.account_deletion:' || lower(btrim(p_user)), 0)
$$;
revoke all on function public._account_deletion_lock_key(text) from public, anon, authenticated;

-- Writer side: shared lock for the rest of the writer's transaction, then refuse when a
-- barrier exists. Ids that are not uuids cannot belong to an auth user: nothing to guard.
create or replace function public._account_write_guard(p_user text)
returns void
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_text text := lower(btrim(p_user));
begin
  if v_text is null
     or v_text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return;
  end if;
  perform pg_advisory_xact_lock_shared(public._account_deletion_lock_key(v_text));
  -- new statement => new snapshot (READ COMMITTED): sees a barrier committed while waiting
  if exists (select 1 from public.account_deletion_barriers where user_id = v_text::uuid) then
    raise exception 'ACCOUNT_DELETION_IN_PROGRESS'
      using errcode = '42501',
            hint = 'ACCOUNT_DELETION_IN_PROGRESS',
            detail = 'this account is being deleted; no new data is accepted for it';
  end if;
end;
$$;
revoke all on function public._account_write_guard(text) from public, anon, authenticated;

-- Trigger adapter: TG_ARGV[0] names the user column (uuid or text).
create or replace function public.account_deletion_write_barrier()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform public._account_write_guard(to_jsonb(new) ->> tg_argv[0]);
  return new;
end;
$$;
revoke all on function public.account_deletion_write_barrier() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['anime_user_lists','manga_user_lists','anime_comments','manga_comments',
                           'club_analytics','concierge_events','discover_rail_impressions',
                           'rag_retrieval_feedback','concierge_runs']
  loop
    execute format('drop trigger if exists account_deletion_barrier on public.%I', t);
    execute format('create trigger account_deletion_barrier before insert or update on public.%I
                      for each row execute function public.account_deletion_write_barrier(%L)', t, 'user_id');
  end loop;
  drop trigger if exists account_deletion_barrier on public.club_members;
  create trigger account_deletion_barrier before insert on public.club_members
    for each row execute function public.account_deletion_write_barrier('user_id');
end $$;

-- Deletion side (service role only; the delete-account edge function passes the
-- JWT-verified user id, never a request-body value).
create or replace function public.begin_account_deletion(p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_started timestamptz;
begin
  if p_user_id is null then
    raise exception 'INVALID_USER_ID' using errcode = '22023';
  end if;
  -- waits for every in-flight guarded write of this user (they hold the shared lock)
  perform pg_advisory_xact_lock(public._account_deletion_lock_key(p_user_id::text));
  insert into public.account_deletion_barriers (user_id) values (p_user_id)
    on conflict (user_id) do nothing;
  select started_at into v_started from public.account_deletion_barriers where user_id = p_user_id;

  -- bounded retention of finished deletions (no cron needed)
  delete from public.account_deletion_barriers b
   where b.started_at < now() - interval '7 days'
     and b.user_id <> p_user_id
     and not exists (select 1 from auth.users u where u.id = b.user_id);

  return jsonb_build_object('success', true, 'started_at', v_started);
end;
$$;
comment on function public.begin_account_deletion(uuid) is
  'F38: start (or resume) the account deletion of p_user_id: exclusive per-user lock + barrier row; idempotent. Service role only (delete-account edge function, JWT-derived id).';
revoke all on function public.begin_account_deletion(uuid) from public, anon, authenticated;
grant execute on function public.begin_account_deletion(uuid) to service_role;

-- Storage has no row trigger. The policy calls this during the object INSERT, so it
-- serializes with begin_account_deletion on the same advisory lock. A false result
-- fails the policy; the exception makes the refusal explicit.
create or replace function public.account_deletion_storage_guard()
returns boolean
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return false;
  end if;
  perform pg_advisory_xact_lock_shared(public._account_deletion_lock_key(v_user::text));
  if exists (select 1 from public.account_deletion_barriers where user_id = v_user) then
    raise exception 'ACCOUNT_DELETION_IN_PROGRESS'
      using errcode = '42501',
            hint = 'ACCOUNT_DELETION_IN_PROGRESS',
            detail = 'this account is being deleted; no new files are accepted for it';
  end if;
  return true;
end;
$$;
comment on function public.account_deletion_storage_guard() is
  'F88: shared deletion lock plus barrier check for storage.objects policies. Authenticated uploads only; service role bypasses RLS.';
revoke all on function public.account_deletion_storage_guard() from public;
grant execute on function public.account_deletion_storage_guard() to authenticated;

-- Permissive policies are OR-ed, so the guard has to be inside the existing policy,
-- not a second policy beside it.
drop policy if exists "Authenticated users can upload media" on storage.objects;
create policy "Authenticated users can upload media" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.account_deletion_storage_guard()
  );

drop policy if exists "Authenticated users can update own media" on storage.objects;
create policy "Authenticated users can update own media" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'media'
    and (select auth.uid())::text = owner_id
    and public.account_deletion_storage_guard()
  )
  with check (
    bucket_id = 'media'
    and (select auth.uid())::text = owner_id
    and public.account_deletion_storage_guard()
  );
