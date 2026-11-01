-- 50_account_deletion_fk_and_rpc.sql  --  (e) delete-account relevance
--   1. which user-owning relations reference auth.users with ON DELETE CASCADE /
--      SET NULL / nothing (characterization: any change fails and forces review)
--   2. delete_user_concierge_data authorization (caller must equal p_user_id)
--   3. emulate the edge function's order on the fixture (supabase/functions/delete-account):
--      begin_account_deletion (service role: write barrier), delete_account_club_memberships
--      (service role: the shared club lifecycle), the RPC as the user, the explicit
--      TEXT-table deletes (both id spellings), then DELETE FROM auth.users (the superuser
--      session stands in for GoTrue's admin delete -- label: NOT Supabase Auth), and read
--      back what survives.
-- Fixture caveat: delete_user_concierge_data here is the 20260305153000 body;
-- the newer 20260806020000 body does not replay in this fixture.
-- @requires table public.anime_user_lists
-- @requires table public.manga_user_lists
-- @requires table public.anime_comments
-- @requires table public.manga_comments
-- @requires table public.club_analytics
-- @requires table public.concierge_events
-- @requires table public.discover_rail_impressions
-- @requires table public.rag_retrieval_feedback
-- @requires table public.user_taste_profiles
-- @requires table public.outbound_link_events
-- @requires function public.delete_user_concierge_data(text)
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
-- @requires-for "latest delete_user_concierge_data body (20260806020000 adds discover_rail_impressions; that file does not replay, the fixture holds the 20260305153000 body; recovery: production-equivalent schema)" function-body public.delete_user_concierge_data(text) discover_rail_impressions
\set ON_ERROR_STOP on
\o /dev/null
begin;

-- ===================== 1. FK delete rules (catalog) ==========================
create temp table _fk on commit drop as
select c.conrelid::regclass::text as tbl, a.attname::text as col,
       case c.confdeltype when 'c' then 'CASCADE' when 'n' then 'SET NULL' when 'a' then 'NO ACTION'
                          when 'r' then 'RESTRICT' when 'd' then 'SET DEFAULT' end as rule
from pg_constraint c
join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
where c.contype = 'f' and c.confrelid = 'auth.users'::regclass;

select tests.eq('every FK to auth.users is CASCADE or SET NULL (none NO ACTION/RESTRICT that would block auth deletion)',
  (select count(*) from _fk where rule not in ('CASCADE','SET NULL')), 0::bigint);

-- 2026-11-01: the six account_user_id/user_id FKs added by the series/import foundation
-- (20261007040000, live since 2026-10-08) and feature_flag_overrides (20261007120000,
-- prepared) are CASCADE by design: those rows are per-account state removed with the account.
-- feature_flag_overrides comes from a still-pending file: it is expected only when present, so
-- the --exclude-pending (deployed-chain) run does not fail this test for an unrelated reason.
select tests.eq('CASCADE set is the reviewed one',
  (select string_agg(tbl || '.' || col, ', ' order by tbl, col) from _fk where rule = 'CASCADE'),
  'club_member_blocks.user_id, club_members.user_id, club_membership_signals.user_id, club_messages.user_id, club_rail_item_reactions.user_id, club_votes.user_id, concierge_mode_cache.user_id, concierge_parse_feedback.user_id, '
  || case when to_regclass('public.feature_flag_overrides') is not null then 'feature_flag_overrides.user_id, ' else '' end
  || 'home_publications.account_user_id, import_sessions.user_id, library_import_jobs.user_id, list_entry_tombstones.account_user_id, llm_daily_usage.user_id, mutation_receipts.account_user_id, outbound_link_events.user_id, profiles.id, taste_import_context.user_id, taste_profile_recompute_queue.user_id, taste_signal_events.user_id, title_aliases.user_id, title_comment_reactions.user_id, title_comments.user_id, user_series_intent.account_user_id, user_streaming_services.user_id, user_taste_profiles.user_id');
select tests.eq('SET NULL set is the reviewed one',
  (select string_agg(tbl || '.' || col, ', ' order by tbl, col) from _fk where rule = 'SET NULL'),
  'club_member_blocks.blocked_by, club_polls.created_by, club_rail_items.added_by, club_rails.created_by, clubs.created_by, concierge_runs.user_id');

-- user-identifying columns with NO foreign key to auth.users (no cascade on account deletion).
-- account_deletion_barriers.user_id is deliberately FK-free: the barrier must outlive the
-- auth user so a still-valid JWT cannot write afterwards (bounded retention, 51_...sql).
create temp table _nofk on commit drop as
select c.relname::text as tbl, a.attname::text as col, format_type(a.atttypid, a.atttypmod) as typ
from pg_class c
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
where c.relkind = 'r'
  and a.attname in ('user_id','created_by','added_by','owner_id')
  and not exists (select 1 from pg_constraint k
                  where k.conrelid = c.oid and k.contype = 'f' and k.confrelid = 'auth.users'::regclass
                    and a.attnum = any (k.conkey));
select tests.eq('user-keyed columns WITHOUT a cascade (must be cleaned explicitly on account deletion)',
  (select string_agg(tbl || '.' || col || ' (' || typ || ')', ', ' order by tbl, col) from _nofk),
  -- 2026-11-01: home_publications, list_entry_tombstones, mutation_receipts and
  -- user_series_intent (20261007040000, live) keep a TEXT user_id for list joins; their
  -- rows cascade through account_user_id (uuid FK, CASCADE, asserted above and in 96_...).
  'account_deletion_barriers.user_id (uuid), anime_comments.user_id (text), anime_user_lists.user_id (text), club_analytics.user_id (uuid), concierge_events.user_id (text), discover_rail_impressions.user_id (text), home_publications.user_id (text), list_entry_tombstones.user_id (text), manga_comments.user_id (text), manga_user_lists.user_id (text), mutation_receipts.user_id (text), rag_retrieval_feedback.user_id (text), user_series_intent.user_id (text)');

-- ===================== 2. RPC authorization ==================================
select tests.make_user(1), tests.make_user(2);
select tests.as_user(tests.uid(2));
select tests.eq('RPC refuses a caller deleting someone else''s data (forbidden)',
  (public.delete_user_concierge_data(tests.uid(1)::text)) ->> 'error', 'forbidden');
select tests.as_anon();
select tests.eq('RPC refuses anon (unauthenticated)', (public.delete_user_concierge_data(tests.uid(1)::text)) ->> 'error', 'unauthenticated');
select tests.as_user(tests.uid(2));
select tests.eq('RPC rejects a non-uuid id for the caller as forbidden (id must equal auth.uid()::text)',
  (public.delete_user_concierge_data('not-a-uuid')) ->> 'error', 'forbidden');
select tests.reset();

-- ===================== 3. emulate the deletion order =========================
-- victim = user 1.  Seed rows in every relevant relation as the superuser session.
insert into public.anime (id) values (424242);
insert into public.manga (id) values (424242);
insert into public.anime_user_lists (user_id, anime_id, list_type) values (tests.uid(1)::text, 424242, 'WATCHING');
insert into public.manga_user_lists (user_id, manga_id, list_type) values (tests.uid(1)::text, 424242, 'READING');
insert into public.anime_comments (anime_id, user_id, comment) values (424242, tests.uid(1)::text, 'legacy comment');
insert into public.manga_comments (manga_id, user_id, comment) values (424242, tests.uid(1)::text, 'legacy comment');
insert into public.club_analytics (user_id, event_type) values (tests.uid(1), 'test');
insert into public.concierge_events (user_id, event_name, language, market) values (tests.uid(1)::text, 'e', 'en', 'de');
insert into public.discover_rail_impressions (user_id, rail_key, media_type, media_id) values (tests.uid(1)::text, 'k', 'anime', 424242);
insert into public.rag_retrieval_feedback (user_id, query, locale, accepted) values (tests.uid(1)::text, 'q', 'en', true);
insert into public.user_taste_profiles (user_id, vector) values (tests.uid(1), '{}');
insert into public.title_comments (user_id, media_type, media_id, text) values (tests.uid(1), 'ANIME', 424242, 'c');
insert into public.outbound_link_events (user_id, media_type, media_id, link_kind, provider) values (tests.uid(1), 'ANIME', 424242, 'watch', 'p');

-- club "solo": user 1 is the only member.  club "shared": user 1 owns it, user 2 is a member.
select tests.as_user(tests.uid(1));
select (public.create_club('Solo club', null, 'status')) ->> 'club_id' as solo \gset
select (public.create_club('Shared club', null, 'status')) ->> 'club_id' as shared \gset
select invite_code as shared_code from public.clubs where id = :'shared' \gset
select (public.create_club_rail(:'solo', 'solo rail', null)) ->> 'rail_id' as solo_rail \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'shared_code');
-- a historical UPPER-case spelling of the victim's id in a TEXT table (F16; the comment
-- tables have no canonical-case trigger): the cleanup must remove it too
select tests.reset();
insert into public.anime_comments (anime_id, user_id, comment) values (424242, upper(tests.uid(1)::text), 'upper-case legacy comment');

-- step 1: the write barrier (service role), then the shared club lifecycle
set local role service_role;
select tests.eq('step 1: begin_account_deletion (barrier)', (public.begin_account_deletion(tests.uid(1))) ->> 'success', 'true');
select tests.eq('step 2: club lifecycle removes both memberships and deletes the solo club now',
  ((public.delete_account_club_memberships(tests.uid(1))) ->> 'clubs_deleted')::int, 1);
select tests.reset();

-- step 3: the RPC, under the user's own JWT
select tests.as_user(tests.uid(1));
select (public.delete_user_concierge_data(auth.uid()::text)) as rpc_result \gset
select tests.eq('RPC reports success for the caller', (:'rpc_result'::jsonb) ->> 'success', 'true');
select tests.reset();
select tests.eq('RPC removed club_analytics', (select count(*) from public.club_analytics where user_id = tests.uid(1)), 0::bigint);
select tests.eq('RPC removed concierge_events', (select count(*) from public.concierge_events where user_id = tests.uid(1)::text), 0::bigint);
select tests.eq('RPC removed rag_retrieval_feedback', (select count(*) from public.rag_retrieval_feedback where user_id = tests.uid(1)::text), 0::bigint);
select tests.eq('RPC removed title_comments', (select count(*) from public.title_comments where user_id = tests.uid(1)), 0::bigint);
select tests.eq('the lifecycle (not the cascade) removed the club memberships', (select count(*) from public.club_members where user_id = tests.uid(1)), 0::bigint);

-- step 4: required TEXT-table deletes (service role equivalent = superuser session), both
-- spellings of the id (REQUIRED_TEXT_USER_TABLES + userIdSpellings in delete-account)
select tests.eq('SURVIVOR of RPC alone: anime_comments rows (TEXT user_id, no FK) need the explicit delete',
  (select count(*) from public.anime_comments where lower(user_id) = tests.uid(1)::text), 2::bigint);
delete from public.anime_user_lists where user_id in (tests.uid(1)::text, upper(tests.uid(1)::text));
delete from public.manga_user_lists where user_id in (tests.uid(1)::text, upper(tests.uid(1)::text));
delete from public.anime_comments  where user_id in (tests.uid(1)::text, upper(tests.uid(1)::text));
delete from public.manga_comments  where user_id in (tests.uid(1)::text, upper(tests.uid(1)::text));
delete from public.profiles where id = tests.uid(1);
-- step 6: the auth user (GoTrue stand-in)
delete from auth.users where id = tests.uid(1);

-- read back what is left
select tests.eq('CASCADE worked: user_taste_profiles gone', (select count(*) from public.user_taste_profiles where user_id = tests.uid(1)), 0::bigint);
select tests.eq('CASCADE worked: outbound_link_events gone', (select count(*) from public.outbound_link_events where user_id = tests.uid(1)), 0::bigint);
select tests.eq('no anime/manga comment of the user survives (either spelling)',
  (select count(*) from public.anime_comments where lower(user_id) = tests.uid(1)::text)
  + (select count(*) from public.manga_comments where lower(user_id) = tests.uid(1)::text), 0::bigint);
select tests.eq('no list row of the user survives (either spelling)',
  (select count(*) from public.anime_user_lists where lower(user_id) = tests.uid(1)::text)
  + (select count(*) from public.manga_user_lists where lower(user_id) = tests.uid(1)::text), 0::bigint);

-- discover_rail_impressions is removed only by the LATEST RPC body (20260806020000); in this
-- fixture that scope is BLOCKED by the requirement manifest, so assert only when present
select case when (select position('discover_rail_impressions' in prosrc) > 0 from pg_proc
                   where oid = 'public.delete_user_concierge_data(text)'::regprocedure)
  then tests.eq('latest RPC body: discover_rail_impressions of the user removed',
         (select count(*) from public.discover_rail_impressions where user_id = tests.uid(1)::text), 0::bigint) end;

-- clubs (F37): handled by the deletion itself, not by a later unrelated sweep
select tests.eq('F37: the solo club is gone with its rail',
  (select count(*) from public.clubs where id = :'solo') + (select count(*) from public.club_rails where club_id = :'solo'), 0::bigint);
select tests.eq('F37: no orphan club (no creator, no members) is left behind',
  (select count(*) from public.clubs c where c.created_by is null
     and not exists (select 1 from public.club_members m where m.club_id = c.id)), 0::bigint);
select tests.eq('F37: the shared club has a valid owner (user 2) after the owner''s account is deleted',
  (select user_id from public.club_members where club_id = :'shared' and role = 'owner'), tests.uid(2));

select tests.requires_live('storage objects owned by the user (bucket "media")',
  'Supabase Storage is not part of this fixture; storage.objects is a stub with no owner cascade. Covered only by the delete-account unit tests with a fake storage dependency.');
select tests.requires_live('auth.users deletion by GoTrue / supabase_auth_admin',
  'the fixture deletes from the stub auth.users as superuser; FK cascade behavior is real PostgreSQL, the Auth server is not.');

rollback;
