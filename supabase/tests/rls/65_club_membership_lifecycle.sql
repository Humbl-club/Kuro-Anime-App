-- 65_club_membership_lifecycle.sql  --  F35 removal vs leave, F37 account-deletion club
-- lifecycle, F39 orphan join (single-session parts; the two-session interleavings are in
-- supabase/tests/concurrency/91_club_lifecycle_join_race.sql)
--
-- Contract under test (prepared, NOT deployed):
--   20261005140000_account_deletion_write_barrier.sql   (barrier the lifecycle requires)
--   20261005150000_club_membership_lifecycle_and_privacy.sql
--   * owner/admin removal of ANOTHER member inserts a block: join_club refuses that user
--     (REMOVED_FROM_CLUB) until an owner/admin calls restore_club_member; voluntary leave
--     (leave_club or deleting one's own non-owner row) adds no block, so a still-valid
--     invite works.
--   * the owner row is never deleted through the table API: ownership changes only through
--     the one lifecycle function (leave_club / account deletion), which transfers to the
--     oldest admin, else the oldest member, and deletes a club left with no members.
--   * an empty (orphaned) club can never be joined again.
-- @requires table public.clubs
-- @requires table public.club_members
-- @requires table public.club_rails
-- @requires table public.club_rail_items
-- @requires table public.club_polls
-- @requires table public.club_votes
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
-- @requires function public.leave_club(uuid)
-- @requires function public.fetch_club_bundle(uuid)
-- @requires function public.create_club_rail(uuid,text,text)
-- @requires function public.add_club_rail_item(uuid,text,integer,text)
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3), tests.make_user(4),
       tests.make_user(5), tests.make_user(6), tests.make_user(7), tests.make_user(8);
insert into public.anime (id) values (656565), (656566);

select tests.as_user(tests.uid(1));
select (public.create_club('Lifecycle L', null, 'status')) ->> 'club_id' as l_club \gset
select invite_code as l_code from public.clubs where id = :'l_club' \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'l_code');
select tests.as_user(tests.uid(3)); select public.join_club(:'l_code');
select tests.as_user(tests.uid(4)); select public.join_club(:'l_code');

-- ==========================================================================
-- F35 removal is sticky until restored
-- ==========================================================================
select tests.as_user(tests.uid(1));
select tests.eq('a direct table DELETE of another member''s row cannot see it (0 rows)',
  tests.affected(format($q$delete from public.club_members where club_id = %L and user_id = %L$q$, :'l_club', tests.uid(4))), 0::bigint);
select tests.eq('owner removes member 4 through remove_club_member', (public.remove_club_member(:'l_club', tests.uid(4))) ->> 'removed', 'true');
select tests.eq('removal recorded a block for (club, member 4), visible to the owner',
  (select count(*) from public.club_member_blocks where club_id = :'l_club' and user_id = tests.uid(4)), 1::bigint);
select tests.as_user(tests.uid(4));
select tests.raises('F35: removed member cannot rejoin with the still-valid invite code',
  format($q$select public.join_club(%L)$q$, :'l_code'), '%REMOVED_FROM_CLUB%');
select tests.eq('removed member cannot read block rows', (select count(*) from public.club_member_blocks), 0::bigint);
select tests.as_user(tests.uid(2));
select tests.eq('plain member cannot read block rows', (select count(*) from public.club_member_blocks), 0::bigint);
select tests.raises('plain member cannot remove anyone (NOT_ADMIN)',
  format($q$select public.remove_club_member(%L, %L)$q$, :'l_club', tests.uid(3)), '%NOT_ADMIN%');
select tests.raises('plain member cannot restore a removed member (NOT_ADMIN)',
  format($q$select public.restore_club_member(%L, %L)$q$, :'l_club', tests.uid(4)), '%NOT_ADMIN%');
select tests.denied('nobody writes block rows through the table API',
  format($q$delete from public.club_member_blocks where club_id = %L$q$, :'l_club'));
select tests.as_user(tests.uid(1));
select tests.eq('owner restores member 4', (public.restore_club_member(:'l_club', tests.uid(4))) ->> 'restored', 'true');
select tests.eq('restoring again is a no-op', (public.restore_club_member(:'l_club', tests.uid(4))) ->> 'restored', 'false');
select tests.as_user(tests.uid(4));
select tests.eq('F35: restored member rejoins with a valid invite code', (public.join_club(:'l_code')) ->> 'club_id', :'l_club');

-- admin removal (admin role set by the superuser: there is no promote RPC)
select tests.reset();
update public.club_members set role = 'admin' where club_id = :'l_club' and user_id = tests.uid(2);
select tests.as_user(tests.uid(2));
select tests.eq('admin removes plain member 3', (public.remove_club_member(:'l_club', tests.uid(3))) ->> 'removed', 'true');
select tests.as_user(tests.uid(3));
select tests.raises('F35: member removed by an admin cannot rejoin', format($q$select public.join_club(%L)$q$, :'l_code'), '%REMOVED_FROM_CLUB%');
select tests.as_user(tests.uid(2));
select tests.eq('admin restores member 3', (public.restore_club_member(:'l_club', tests.uid(3))) ->> 'restored', 'true');
select tests.as_user(tests.uid(3)); select public.join_club(:'l_code');

-- ==========================================================================
-- owner row is only changed through the lifecycle
-- ==========================================================================
select tests.as_user(tests.uid(2));
select tests.eq('admin cannot delete the OWNER row through the table API (0 rows)',
  tests.affected(format($q$delete from public.club_members where club_id = %L and user_id = %L$q$, :'l_club', tests.uid(1))), 0::bigint);
select tests.raises('admin cannot remove the OWNER through the RPC (NOT_ADMIN)',
  format($q$select public.remove_club_member(%L, %L)$q$, :'l_club', tests.uid(1)), '%NOT_ADMIN%');
select tests.raises('nobody removes themself through the RPC (CANNOT_REMOVE_SELF; leave_club is the path)',
  format($q$select public.remove_club_member(%L, auth.uid())$q$, :'l_club'), '%CANNOT_REMOVE_SELF%');
select tests.as_user(tests.uid(1));
select tests.eq('owner cannot delete their own row through the table API (0 rows; leave_club transfers ownership)',
  tests.affected(format($q$delete from public.club_members where club_id = %L and user_id = auth.uid()$q$, :'l_club')), 0::bigint);
select tests.eq('club still has exactly one owner', (select count(*) from public.club_members where club_id = :'l_club' and role = 'owner'), 1::bigint);

-- ==========================================================================
-- F35 voluntary leave is not a block
-- ==========================================================================
select tests.as_user(tests.uid(3));
select tests.eq('member 3 leaves through leave_club', (public.leave_club(:'l_club')) ->> 'success', 'true');
select tests.reset();
select tests.eq('leave records no block', (select count(*) from public.club_member_blocks where club_id = :'l_club' and user_id = tests.uid(3)), 0::bigint);
select tests.as_user(tests.uid(3));
select tests.eq('F35: voluntary leaver rejoins with a still-valid invite code', (public.join_club(:'l_code')) ->> 'club_id', :'l_club');
select tests.eq('a non-owner may still delete their own row (equivalent to leave, 1 row)',
  tests.affected(format($q$delete from public.club_members where club_id = %L and user_id = auth.uid()$q$, :'l_club')), 1::bigint);
select tests.eq('...which is not a block either', (public.join_club(:'l_code')) ->> 'club_id', :'l_club');
select tests.reset();
update public.clubs set invite_expires_at = now() - interval '1 minute' where id = :'l_club';
select tests.as_user(tests.uid(3));
select tests.eq('member 3 leaves again', (public.leave_club(:'l_club')) ->> 'success', 'true');
select tests.raises('a voluntary leaver still needs a VALID code (expired -> CODE_EXPIRED)',
  format($q$select public.join_club(%L)$q$, :'l_code'), '%CODE_EXPIRED%');
select tests.reset();
update public.clubs set invite_expires_at = null where id = :'l_club';

-- ==========================================================================
-- leave_club = the shared lifecycle: transfer to oldest admin, else oldest member
-- ==========================================================================
select tests.reset();
update public.club_members set joined_at = joined_at - interval '1 hour' where club_id = :'l_club' and user_id = tests.uid(4);
select tests.as_user(tests.uid(1));
select tests.eq('owner leaves through leave_club', (public.leave_club(:'l_club')) ->> 'success', 'true');
select tests.reset();
select tests.eq('ownership went to the admin (2) although member 4 joined earlier',
  (select user_id from public.club_members where club_id = :'l_club' and role = 'owner'), tests.uid(2));
select tests.as_user(tests.uid(1));
select tests.raises('a leaver is not blocked but not a member any more', format($q$select public.fetch_club_bundle(%L)$q$, :'l_club'), '%NOT_A_MEMBER%');

-- solo club: the owner leaving deletes it
select tests.as_user(tests.uid(5));
select (public.create_club('Solo leave', null, 'status')) ->> 'club_id' as solo_leave \gset
select tests.eq('solo owner leaves', (public.leave_club(:'solo_leave')) ->> 'success', 'true');
select tests.reset();
select tests.eq('solo club deleted when its last member leaves', (select count(*) from public.clubs where id = :'solo_leave'), 0::bigint);

-- ==========================================================================
-- F39 (single session): an empty club can never be joined again
-- ==========================================================================
select tests.reset();
insert into public.clubs (name, created_by, invite_code, sharing_level) values ('Orphan', null, 'ORPHAN01', 'status') returning id as orphan \gset
select tests.as_user(tests.uid(6));
select tests.raises('F39: an empty (orphaned) club cannot be joined (reported like an invalid code)',
  $q$select public.join_club('ORPHAN01')$q$, '%INVALID_CODE%');
select tests.reset();
select tests.eq('...and nobody became a member of it', (select count(*) from public.club_members where club_id = :'orphan'), 0::bigint);

-- ==========================================================================
-- F37 account deletion goes through the SAME lifecycle
--   user 6 owns: Solo6 (only member, has a rail) and Shared6 (7 member, 8 admin, 7's item);
--   user 6 is a plain member of club L (owner 2).
-- ==========================================================================
select tests.as_user(tests.uid(6));
select (public.create_club('Solo6', null, 'status')) ->> 'club_id' as solo6 \gset
select (public.create_club_rail(:'solo6', 'solo rail', null)) ->> 'rail_id' as solo6_rail \gset
select (public.create_club('Shared6', null, 'status')) ->> 'club_id' as shared6 \gset
select invite_code as shared6_code from public.clubs where id = :'shared6' \gset
select (public.create_club_rail(:'shared6', 'shared rail', null)) ->> 'rail_id' as shared6_rail \gset
select public.join_club(:'l_code');
select tests.as_user(tests.uid(7)); select public.join_club(:'shared6_code');
select (public.add_club_rail_item(:'shared6_rail', 'ANIME', 656565, 'seven''s pick')) ->> 'item_id' as seven_item \gset
select tests.as_user(tests.uid(8)); select public.join_club(:'shared6_code');
select tests.reset();
update public.club_members set role = 'admin' where club_id = :'shared6' and user_id = tests.uid(8);

-- the service-role RPCs are not callable by end users
select tests.as_user(tests.uid(6));
select tests.denied('end user cannot call delete_account_club_memberships', format($q$select public.delete_account_club_memberships(%L)$q$, tests.uid(6)));
select tests.reset();
set local role service_role;
select tests.raises('club lifecycle for account deletion requires the deletion barrier first (DELETION_NOT_STARTED)',
  format($q$select public.delete_account_club_memberships(%L)$q$, tests.uid(6)), '%DELETION_NOT_STARTED%');
select public.begin_account_deletion(tests.uid(6));
select public.delete_account_club_memberships(tests.uid(6))::text as life6 \gset
select tests.reset();
select tests.eq('F37: solo club of the deleted owner is deleted now (not left for a later sweep)',
  (select count(*) from public.clubs where id = :'solo6'), 0::bigint);
select tests.eq('F37: ...with its rail', (select count(*) from public.club_rails where id = :'solo6_rail'), 0::bigint);
select tests.eq('F37: shared club survives', (select count(*) from public.clubs where id = :'shared6'), 1::bigint);
select tests.eq('F37: shared club ownership went to the admin (8)',
  (select user_id from public.club_members where club_id = :'shared6' and role = 'owner'), tests.uid(8));
select tests.eq('F37: other members'' content is preserved (7''s rail item)',
  (select count(*) from public.club_rail_items where id = :'seven_item'), 1::bigint);
select tests.eq('F37: the deleted user holds no membership anywhere', (select count(*) from public.club_members where user_id = tests.uid(6)), 0::bigint);
select tests.eq('F37: club L (owner 2) is untouched apart from the departure',
  (select user_id from public.club_members where club_id = :'l_club' and role = 'owner'), tests.uid(2));
select tests.eq('F37: lifecycle reports what it did',
  ((:'life6')::jsonb ->> 'memberships_removed')::int || '/' || ((:'life6')::jsonb ->> 'clubs_deleted')::int, '3/1');
set local role service_role;
select tests.eq('retry after completion is a no-op', ((public.delete_account_club_memberships(tests.uid(6))) ->> 'memberships_removed')::int, 0);
select tests.reset();
delete from auth.users where id = tests.uid(6);
select tests.eq('F37: auth deletion afterwards leaves the shared club owned', (select count(*) from public.club_members where club_id = :'shared6' and role = 'owner'), 1::bigint);

-- ==========================================================================
-- safety net: an auth user deleted OUTSIDE the edge function (dashboard / admin API)
-- still triggers the same settlement through the club_members cascade
-- ==========================================================================
select tests.as_user(tests.uid(7));
select (public.create_club('Solo7', null, 'status')) ->> 'club_id' as solo7 \gset
select (public.create_club('Shared7', null, 'status')) ->> 'club_id' as shared7 \gset
select invite_code as shared7_code from public.clubs where id = :'shared7' \gset
select tests.as_user(tests.uid(5)); select public.join_club(:'shared7_code');
select tests.reset();
delete from auth.users where id = tests.uid(7);
select tests.eq('safety net: solo club of a cascaded owner is deleted', (select count(*) from public.clubs where id = :'solo7'), 0::bigint);
select tests.eq('safety net: shared club gets a new owner (5)',
  (select user_id from public.club_members where club_id = :'shared7' and role = 'owner'), tests.uid(5));

select tests.reset();
rollback;
