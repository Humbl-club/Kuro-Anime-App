-- ============================================================================
-- delete_account_prereqs.sql -- READ-ONLY prerequisite checklist for the hardened
-- account deletion and the prepared club / list migrations (F45, F40, F41, F16, F37).
--
-- NEVER run this against production without an explicit, recorded approval for a
-- READ-ONLY check. It changes nothing: the whole script runs in one
-- `READ ONLY` transaction with statement/lock timeouts and ends with ROLLBACK.
-- It REFUSES (exit 3, nothing queried) unless BOTH variables are given and the
-- connected database name equals the approved one:
--
--   psql "<approved target connection>" -X -v ON_ERROR_STOP=1 \
--        -v approved_target=<expected current_database()> \
--        -v approval_ref=<approval record id> \
--        -f supabase/tests/prerequisites/delete_account_prereqs.sql
--
-- Output: one table, one row per check: check | status | observed | expected.
--   PASS  prerequisite satisfied
--   FAIL  must be fixed (explicit grant/schema change, prepared separately) BEFORE the
--         new delete-account function or the prepared migrations are deployed
--   TODO  a prepared migration is not deployed yet (expected before deployment)
--   INFO  evidence for a human decision (counts, current definitions)
-- Exercised locally against the throwaway fixture only (see supabase/tests/README.md).
-- ============================================================================
\set ON_ERROR_STOP on

\if :{?approved_target}
\else
\echo 'REFUSED: pass -v approved_target=<current_database() of the approved target> and -v approval_ref=<approval record>.'
do $$ begin raise exception 'REFUSED: no approved target given; nothing was queried'; end $$;
\endif
\if :{?approval_ref}
\else
\echo 'REFUSED: pass -v approval_ref=<approval record> (who approved this read-only check on which target).'
do $$ begin raise exception 'REFUSED: no approval reference given; nothing was queried'; end $$;
\endif

begin transaction isolation level repeatable read read only;
set local statement_timeout = '15s';
set local lock_timeout = '2s';
set local idle_in_transaction_session_timeout = '60s';

select (current_database() = :'approved_target') as target_matches \gset
\if :target_matches
\else
\echo 'REFUSED: the connected database is not the approved target.'
do $$ begin raise exception 'REFUSED: connected database does not match approved_target'; end $$;
\endif

\echo '== approved read-only check on' :'approved_target' 'approval' :'approval_ref'
select current_database() as database, current_user as connected_as,
       current_setting('transaction_read_only') as read_only, now() as checked_at;

-- optional objects are branched with psql \if (a missing relation cannot be referenced)
select to_regclass('storage.buckets') is not null as has_storage_buckets,
       to_regclass('public.user_lists') is not null as has_user_lists,
       to_regclass('public.account_deletion_barriers') is not null as has_barriers \gset

with
req_tables(t) as (
  values ('anime_user_lists'), ('manga_user_lists'), ('anime_comments'), ('manga_comments'), ('profiles'),
         ('club_analytics'), ('concierge_events'), ('discover_rail_impressions'), ('rag_retrieval_feedback'),
         ('concierge_runs'), ('clubs'), ('club_members'), ('club_votes'), ('club_rail_item_reactions')
),
text_user_tables(t) as (values ('anime_user_lists'), ('manga_user_lists'), ('anime_comments'), ('manga_comments')),
service_delete(t) as (values ('anime_user_lists'), ('manga_user_lists'), ('anime_comments'), ('manga_comments'), ('profiles')),
fk as (
  select c.conrelid::regclass::text as tbl, c.confdeltype
    from pg_constraint c where c.contype = 'f' and c.confrelid = 'auth.users'::regclass
),
checks(ord, check_name, status, observed, expected) as (
  select 10, 'table exists: ' || t,
         case when to_regclass('public.' || t) is not null then 'PASS' else 'FAIL' end,
         coalesce((select relkind::text from pg_class where oid = to_regclass('public.' || t)), 'missing'), 'r'
    from req_tables
  union all
  select 20, 'user_id column type: ' || t,
         case when (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
                     where a.attrelid = to_regclass('public.' || t) and a.attname = 'user_id' and not a.attisdropped) = 'text'
              then 'PASS' else 'FAIL' end,
         coalesce((select format_type(a.atttypid, a.atttypmod) from pg_attribute a
                    where a.attrelid = to_regclass('public.' || t) and a.attname = 'user_id' and not a.attisdropped), 'missing'),
         'text (delete-account deletes both id spellings)'
    from text_user_tables
  union all
  select 30, 'service_role DELETE on ' || t,
         case when to_regclass('public.' || t) is not null and has_table_privilege('service_role', 'public.' || t, 'DELETE') then 'PASS' else 'FAIL' end,
         case when to_regclass('public.' || t) is null then 'table missing'
              else has_table_privilege('service_role', 'public.' || t, 'DELETE')::text end, 'true'
    from service_delete
  union all
  select 40, 'service_role bypasses RLS',
         case when (select rolbypassrls from pg_roles where rolname = 'service_role') then 'PASS' else 'FAIL' end,
         coalesce((select rolbypassrls::text from pg_roles where rolname = 'service_role'), 'role missing'), 'true'
  union all
  select 50, 'FK to auth.users never blocks the auth deletion (no NO ACTION / RESTRICT)',
         case when not exists (select 1 from fk where confdeltype in ('a', 'r')) then 'PASS' else 'FAIL' end,
         coalesce((select string_agg(tbl, ', ') from fk where confdeltype in ('a', 'r')), 'none'), 'none'
  union all
  select 55, 'migration/function owner can read auth.users (begin_account_deletion purge and the club signal / lifecycle triggers run as the owner)',
         case when (select proowner from pg_proc where oid = to_regprocedure('public.delete_user_concierge_data(text)')) is not null
               and has_schema_privilege((select proowner from pg_proc where oid = to_regprocedure('public.delete_user_concierge_data(text)')), 'auth', 'USAGE')
               and has_table_privilege((select proowner from pg_proc where oid = to_regprocedure('public.delete_user_concierge_data(text)')), 'auth.users', 'SELECT')
              then 'PASS' else 'FAIL' end,
         coalesce((select pg_get_userbyid(proowner) from pg_proc where oid = to_regprocedure('public.delete_user_concierge_data(text)')), 'owner unknown'),
         'owner of the existing DEFINER functions has USAGE on auth and SELECT on auth.users'
  union all
  select 60, 'delete_user_concierge_data(text) exists, SECURITY DEFINER, authenticated may EXECUTE',
         case when to_regprocedure('public.delete_user_concierge_data(text)') is not null
               and (select prosecdef from pg_proc where oid = to_regprocedure('public.delete_user_concierge_data(text)'))
               and has_function_privilege('authenticated', 'public.delete_user_concierge_data(text)', 'EXECUTE')
              then 'PASS' else 'FAIL' end,
         coalesce((select prosecdef::text from pg_proc where oid = to_regprocedure('public.delete_user_concierge_data(text)')), 'missing'),
         'true'
  union all
  select 61, 'delete_user_concierge_data latest body (20260806020000: discover_rail_impressions)',
         case when (select position('discover_rail_impressions' in prosrc) > 0 from pg_proc
                     where oid = to_regprocedure('public.delete_user_concierge_data(text)')) then 'PASS' else 'FAIL' end,
         'body contains discover_rail_impressions', 'true'
  union all
  select 70, 'prepared ' || f || ' deployed',
         case when to_regprocedure(f) is not null then 'PASS' else 'TODO' end,
         case when to_regprocedure(f) is not null then 'present' else 'absent' end, 'present after approved deployment'
    from (values ('public.begin_account_deletion(uuid)'), ('public.delete_account_club_memberships(uuid)'),
                 ('public.remove_club_member(uuid,uuid)'), ('public.restore_club_member(uuid,uuid)')) v(f)
  union all
  select 71, 'barrier triggers (account_deletion_barrier) on the 10 guarded tables',
         case when (select count(*) from pg_trigger where tgname = 'account_deletion_barrier' and not tgisinternal) = 10
              then 'PASS' else 'TODO' end,
         (select count(*)::text from pg_trigger where tgname = 'account_deletion_barrier' and not tgisinternal), '10'
  union all
  select 80, 'club raw SELECT policies (F34): no member-wide policy left',
         case when exists (select 1 from pg_policies where schemaname = 'public'
                             and policyname in ('club_votes_select_member', 'club_reactions_select_member', 'club_members_select_member'))
              then 'TODO' else 'PASS' end,
         coalesce((select string_agg(tablename || '.' || policyname, ', ') from pg_policies
                    where schemaname = 'public' and tablename in ('club_members', 'club_votes', 'club_rail_item_reactions') and cmd = 'SELECT'), 'none'),
         'club_members_select_own, club_votes_select_own, club_reactions_select_own'
  union all
  select 81, 'fetch_club_bundle is SECURITY DEFINER with search_path public, extensions (F36)',
         case when (select prosecdef and proconfig @> array['search_path=public, extensions'] from pg_proc
                     where oid = to_regprocedure('public.fetch_club_bundle(uuid)')) then 'PASS' else 'TODO' end,
         coalesce((select prosecdef::text || ' ' || coalesce(array_to_string(proconfig, ','), '') from pg_proc
                    where oid = to_regprocedure('public.fetch_club_bundle(uuid)')), 'missing'), 'true search_path=public, extensions'
  union all
  select 90, 'PUBLIC (grantee 0) holds no privilege on club tables (F41)',
         case when exists (select 1 from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                            where c.relnamespace = 'public'::regnamespace and c.relname like 'club%' and c.relkind = 'r' and a.grantee = 0)
              then 'FAIL' else 'PASS' end,
         coalesce((select string_agg(distinct c.relname || ':' || a.privilege_type, ', ')
                     from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                    where c.relnamespace = 'public'::regnamespace and c.relname like 'club%' and c.relkind = 'r' and a.grantee = 0), 'none'), 'none'
  union all
  select 91, 'authenticated cannot UPDATE club_members.role (F41 20261005120000)',
         case when has_column_privilege('authenticated', 'public.club_members', 'role', 'UPDATE') then 'TODO' else 'PASS' end,
         has_column_privilege('authenticated', 'public.club_members', 'role', 'UPDATE')::text, 'false'
  union all
  select 92, 'club_rails INSERT is owner/admin only (F41 20261005120100)',
         case when exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'club_rails' and policyname = 'club_rails_insert_member')
              then 'TODO' else 'PASS' end,
         coalesce((select string_agg(policyname, ', ') from pg_policies where schemaname = 'public' and tablename = 'club_rails' and cmd = 'INSERT'), 'none'),
         'club_rails_insert_admin'
  union all
  select 93, 'toggle_comment_reaction checks shares_club_with (F41 20261005120200)',
         case when (select position('shares_club_with' in prosrc) > 0 from pg_proc where oid = to_regprocedure('public.toggle_comment_reaction(uuid,text)'))
              then 'PASS' else 'TODO' end,
         'body contains shares_club_with', 'true'
  union all
  select 100, 'F16: non-canonical (not lower-case) user_id rows in anime_user_lists',
         case when (select count(*) from public.anime_user_lists where user_id <> lower(user_id)) = 0 then 'PASS' else 'INFO' end,
         (select count(*)::text from public.anime_user_lists where user_id <> lower(user_id)), '0 (else review the opt-in backfill)'
  union all
  select 101, 'F16: non-canonical user_id rows in manga_user_lists',
         case when (select count(*) from public.manga_user_lists where user_id <> lower(user_id)) = 0 then 'PASS' else 'INFO' end,
         (select count(*)::text from public.manga_user_lists where user_id <> lower(user_id)), '0 (else review the opt-in backfill)'
  union all
  select 102, 'F16: case collisions (non-canonical row whose canonical twin exists)',
         case when (select count(*) from public.anime_user_lists u join public.anime_user_lists c
                      on c.user_id = lower(u.user_id) and c.anime_id = u.anime_id and c.id <> u.id where u.user_id <> lower(u.user_id))
                 + (select count(*) from public.manga_user_lists u join public.manga_user_lists c
                      on c.user_id = lower(u.user_id) and c.manga_id = u.manga_id and c.id <> u.id where u.user_id <> lower(u.user_id)) = 0
              then 'PASS' else 'INFO' end,
         ((select count(*) from public.anime_user_lists u join public.anime_user_lists c
             on c.user_id = lower(u.user_id) and c.anime_id = u.anime_id and c.id <> u.id where u.user_id <> lower(u.user_id))
        + (select count(*) from public.manga_user_lists u join public.manga_user_lists c
             on c.user_id = lower(u.user_id) and c.manga_id = u.manga_id and c.id <> u.id where u.user_id <> lower(u.user_id)))::text,
         '0 (else an explicit keep_newest decision)'
  union all
  select 103, 'F16: effective list policies', 'INFO',
         coalesce((select string_agg(tablename || '.' || policyname || ' ' || cmd || ' ' || coalesce(qual, '') , ' | ')
                     from pg_policies where schemaname = 'public' and tablename in ('anime_user_lists', 'manga_user_lists')), 'none'),
         'auth.uid()::text = user_id (captured)'
  union all
  select 110, 'F37/F39: existing empty clubs (orphans) awaiting a separate cleanup decision',
         case when (select count(*) from public.clubs c where not exists (select 1 from public.club_members m where m.club_id = c.id)) = 0
              then 'PASS' else 'INFO' end,
         (select count(*)::text from public.clubs c where not exists (select 1 from public.club_members m where m.club_id = c.id)), '0'
  union all
  select 111, 'F37: clubs with members but no owner',
         case when (select count(*) from public.clubs c
                     where exists (select 1 from public.club_members m where m.club_id = c.id)
                       and not exists (select 1 from public.club_members m where m.club_id = c.id and m.role = 'owner')) = 0
              then 'PASS' else 'INFO' end,
         (select count(*)::text from public.clubs c
           where exists (select 1 from public.club_members m where m.club_id = c.id)
             and not exists (select 1 from public.club_members m where m.club_id = c.id and m.role = 'owner')), '0'
)
select check_name as "check", status, observed, expected from checks order by ord, check_name;

\if :has_storage_buckets
select 'storage bucket "media" exists' as "check",
       case when exists (select 1 from storage.buckets where id = 'media') then 'PASS' else 'FAIL' end as status,
       coalesce((select id || ' public=' || public::text from storage.buckets where id = 'media'), 'missing') as observed,
       'media (delete-account purges media/<userId>/...)' as expected;
\else
select 'storage bucket "media" exists' as "check", 'FAIL' as status, 'storage.buckets not visible' as observed, 'media' as expected;
\endif

\if :has_user_lists
select 'F40: public.user_lists is a view with security_invoker' as "check",
       case when c.relkind = 'v'
             and (c.reloptions @> array['security_invoker=true'] or c.reloptions @> array['security_invoker=on'])
            then 'PASS' else 'FAIL' end as status,
       'relkind=' || c.relkind || ' reloptions=' || coalesce(array_to_string(c.reloptions, ','), '{}')
         || ' anon_select=' || has_table_privilege('anon', 'public.user_lists', 'SELECT')::text as observed,
       'v, security_invoker=on (20261005170000); anon_select is informational (reads 0 rows under invoker)' as expected
  from pg_class c where c.oid = 'public.user_lists'::regclass;
\else
select 'F40: public.user_lists' as "check", 'INFO' as status, 'view does not exist (nothing can leak; its callers would fail)' as observed,
       'exists with security_invoker' as expected;
\endif

\if :has_barriers
select 'F38: pending (unfinished) account deletions' as "check", 'INFO' as status,
       (select count(*)::text from public.account_deletion_barriers b where exists (select 1 from auth.users u where u.id = b.user_id)) as observed,
       'users whose deletion started but did not finish (they retry)' as expected;
\endif

rollback;
