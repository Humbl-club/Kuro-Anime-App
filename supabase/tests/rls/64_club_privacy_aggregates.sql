-- 64_club_privacy_aggregates.sql  --  F34 + F36 together (policy P2-R1)
--
-- Contract under test (prepared, NOT deployed):
--   supabase/prepared-migrations/20261005150000_club_membership_lifecycle_and_privacy.sql
--   * RAW: club_votes / club_rail_item_reactions / club_members show a member ONLY their
--     own rows (any sharing level). Other members' metadata reaches the app only through
--     the authorized bundle RPCs, which apply the sharing_level and <3-member rules.
--   * AGGREGATES: fetch_club_bundle / fetch_club_bundle_loading are SECURITY DEFINER with
--     an explicit membership check, search_path = public, extensions and EXECUTE for
--     `authenticated` only; counts are correct across members, departed members are
--     excluded, and per-member detail follows each member's EFFECTIVE level
--     (least(club, own)): status >= 1, progress >= 2. No rating/notes ever leave the RPC.
-- Raw access and aggregate output are asserted TOGETHER for private / status / progress
-- clubs and a 2-member club, all as role `authenticated` through the real RPCs.
-- @requires table public.clubs
-- @requires table public.club_members
-- @requires table public.club_rails
-- @requires table public.club_rail_items
-- @requires table public.club_rail_item_reactions
-- @requires table public.club_polls
-- @requires table public.club_poll_options
-- @requires table public.club_votes
-- @requires table public.anime_user_lists
-- @requires table public.profiles
-- @requires function public.create_club(text,text,text)
-- @requires function public.join_club(text)
-- @requires function public.leave_club(uuid)
-- @requires function public.fetch_club_bundle(uuid)
-- @requires function public.fetch_club_bundle_loading(uuid)
-- @requires function public.create_club_rail(uuid,text,text)
-- @requires function public.add_club_rail_item(uuid,text,integer,text)
-- @requires function public.create_club_poll(uuid,text,text[],timestamptz)
-- @requires function public.cast_club_vote(uuid,uuid)
-- @requires function public.toggle_club_reaction(uuid,text)
\set ON_ERROR_STOP on
\o /dev/null
begin;

select tests.make_user(1), tests.make_user(2), tests.make_user(3), tests.make_user(4),
       tests.make_user(5), tests.make_user(6);
insert into public.anime (id) values (646464);

-- list rows: every user tracks the item (rating/notes must never leave the RPC)
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, notes) values
  (tests.uid(1)::text, 646464, 'WATCHING',  3, 7, 'secret-note-1'),
  (tests.uid(2)::text, 646464, 'COMPLETED', 12, 9, 'secret-note-2'),
  (tests.uid(3)::text, 646464, 'WATCHING',  7, 6, 'secret-note-3'),
  (tests.uid(4)::text, 646464, 'DROPPED',   1, 2, 'secret-note-4'),
  (tests.uid(5)::text, 646464, 'PAUSED',    2, 5, 'secret-note-5');

-- ---- clubs (all through the real RPCs) --------------------------------------
-- P private: 1 (owner), 2, 3, 4
select tests.as_user(tests.uid(1));
select (public.create_club('Private P', null, 'private')) ->> 'club_id' as p_club \gset
select invite_code as p_code from public.clubs where id = :'p_club' \gset
select (public.create_club_rail(:'p_club', 'P rail', null)) ->> 'rail_id' as p_rail \gset
select (public.add_club_rail_item(:'p_rail', 'ANIME', 646464, null)) ->> 'item_id' as p_item \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'p_code');
select tests.as_user(tests.uid(3)); select public.join_club(:'p_code');
select tests.as_user(tests.uid(4)); select public.join_club(:'p_code');
select tests.as_user(tests.uid(2));
select (public.create_club_poll(:'p_club', 'Next?', array['A','B'], null)) ->> 'poll_id' as p_poll \gset
select id as p_opt_a from public.club_poll_options where poll_id = :'p_poll' and label = 'A' \gset
select id as p_opt_b from public.club_poll_options where poll_id = :'p_poll' and label = 'B' \gset
select tests.as_user(tests.uid(1)); select public.cast_club_vote(:'p_poll', :'p_opt_a'); select public.toggle_club_reaction(:'p_item', 'fire');
select tests.as_user(tests.uid(3)); select public.cast_club_vote(:'p_poll', :'p_opt_b'); select public.toggle_club_reaction(:'p_item', 'heart');
select tests.as_user(tests.uid(2)); select public.cast_club_vote(:'p_poll', :'p_opt_a'); select public.toggle_club_reaction(:'p_item', 'fire');

-- S status: 1 (owner), 2, 3, 5 ; member 5 downgrades to private (effective rank 0)
select tests.as_user(tests.uid(1));
select (public.create_club('Status S', null, 'status')) ->> 'club_id' as s_club \gset
select invite_code as s_code from public.clubs where id = :'s_club' \gset
select (public.create_club_rail(:'s_club', 'S rail', null)) ->> 'rail_id' as s_rail \gset
select (public.add_club_rail_item(:'s_rail', 'ANIME', 646464, null)) ->> 'item_id' as s_item \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'s_code');
select tests.as_user(tests.uid(3)); select public.join_club(:'s_code');
select tests.as_user(tests.uid(5)); select public.join_club(:'s_code');
select tests.eq('legit: a member downgrades their own sharing level (own row, sharing_level only)',
  tests.affected(format($q$update public.club_members set sharing_level = 'private' where club_id = %L and user_id = auth.uid()$q$, :'s_club')), 1::bigint);

-- G progress: 1 (owner), 2, 3, 4 ; member 4 downgrades to status (effective rank 1)
select tests.as_user(tests.uid(1));
select (public.create_club('Progress G', null, 'progress')) ->> 'club_id' as g_club \gset
select invite_code as g_code from public.clubs where id = :'g_club' \gset
select (public.create_club_rail(:'g_club', 'G rail', null)) ->> 'rail_id' as g_rail \gset
select (public.add_club_rail_item(:'g_rail', 'ANIME', 646464, null)) ->> 'item_id' as g_item \gset
select tests.as_user(tests.uid(2)); select public.join_club(:'g_code');
select tests.as_user(tests.uid(3)); select public.join_club(:'g_code');
select tests.as_user(tests.uid(4)); select public.join_club(:'g_code');
select tests.eq('legit: member 4 downgrades to status in the progress club',
  tests.affected(format($q$update public.club_members set sharing_level = 'status' where club_id = %L and user_id = auth.uid()$q$, :'g_club')), 1::bigint);
select tests.as_user(tests.uid(5)); select public.join_club(:'g_code');
select tests.eq('legit: member 5 opts out (private) in the progress club',
  tests.affected(format($q$update public.club_members set sharing_level = 'private' where club_id = %L and user_id = auth.uid()$q$, :'g_club')), 1::bigint);

-- 2-member clubs at all three levels: 3 (owner, tracks the item) + 2
-- (create_club allows 5 creations per user per hour, so user 1 does not own these)
select tests.as_user(tests.uid(3));
select (public.create_club('Duo D', null, 'progress')) ->> 'club_id' as d_club \gset
select invite_code as d_code from public.clubs where id = :'d_club' \gset
select (public.create_club_rail(:'d_club', 'D rail', null)) ->> 'rail_id' as d_rail \gset
select (public.add_club_rail_item(:'d_rail', 'ANIME', 646464, null)) ->> 'item_id' as d_item \gset
select (public.create_club('Duo DS', null, 'status')) ->> 'club_id' as ds_club \gset
select invite_code as ds_code from public.clubs where id = :'ds_club' \gset
select (public.create_club_rail(:'ds_club', 'DS rail', null)) ->> 'rail_id' as ds_rail \gset
select (public.add_club_rail_item(:'ds_rail', 'ANIME', 646464, null)) ->> 'item_id' as ds_item \gset
select (public.create_club('Duo DP', null, 'private')) ->> 'club_id' as dp_club \gset
select invite_code as dp_code from public.clubs where id = :'dp_club' \gset
select (public.create_club_rail(:'dp_club', 'DP rail', null)) ->> 'rail_id' as dp_rail \gset
select (public.add_club_rail_item(:'dp_rail', 'ANIME', 646464, null)) ->> 'item_id' as dp_item \gset
select tests.as_user(tests.uid(2));
select public.join_club(:'d_code'); select public.join_club(:'ds_code'); select public.join_club(:'dp_code');

-- ==========================================================================
-- RAW table access (F34): own rows only, at every sharing level
-- ==========================================================================
select tests.as_user(tests.uid(2));
select tests.eq('F34 raw (private club): member reads ONLY their own vote row',
  (select count(*) from public.club_votes where poll_id = :'p_poll'), 1::bigint);
select tests.eq('F34 raw (private club): ...and it is their own',
  (select count(*) from public.club_votes where poll_id = :'p_poll' and user_id <> auth.uid()), 0::bigint);
select tests.eq('F34 raw (private club): member reads ONLY their own reaction rows',
  (select count(*) from public.club_rail_item_reactions where rail_item_id = :'p_item' and user_id <> auth.uid()), 0::bigint);
select tests.eq('F34 raw (private club): member reads ONLY their own membership row',
  (select count(*) from public.club_members where club_id = :'p_club'), 1::bigint);
select tests.eq('F34 raw (status club): member reads ONLY their own membership row',
  (select count(*) from public.club_members where club_id = :'s_club'), 1::bigint);
select tests.eq('F34 raw (progress club): member reads ONLY their own membership row',
  (select count(*) from public.club_members where club_id = :'g_club'), 1::bigint);
select tests.eq('F34 raw: other members'' list rows stay invisible (owner-only list policy unchanged)',
  (select count(*) from public.anime_user_lists where anime_id = 646464), 1::bigint);
select tests.as_user(tests.uid(1));
select tests.eq('F34 raw: even the OWNER reads only their own membership row through the table API',
  (select count(*) from public.club_members where club_id = :'p_club'), 1::bigint);
select tests.as_user(tests.uid(6));
select tests.eq('F34 raw: outsider reads 0 votes / reactions / memberships',
  (select count(*) from public.club_votes) + (select count(*) from public.club_rail_item_reactions)
  + (select count(*) from public.club_members), 0::bigint);
select tests.as_anon();
select tests.eq('F34 raw: anon reads 0 votes / reactions / memberships',
  (select count(*) from public.club_votes) + (select count(*) from public.club_rail_item_reactions)
  + (select count(*) from public.club_members), 0::bigint);

-- ==========================================================================
-- AGGREGATES (F36 + F34): correct across members, sharing rules per member
-- ==========================================================================
-- private club P, as member 2
select tests.as_user(tests.uid(2));
select public.fetch_club_bundle(:'p_club')::text as pb \gset
select tests.eq('F36 private: member_count is all 4 members', ((:'pb')::jsonb ->> 'member_count')::int, 4);
select tests.eq('F36 private: poll vote counts include all 3 voters',
  (select sum((o ->> 'vote_count')::int) from jsonb_array_elements((:'pb')::jsonb #> '{polls,0,options}') o)::int, 3);
select tests.eq('F36 private: reaction totals are complete anonymous counts',
  (:'pb')::jsonb #> '{rails,0,items,0,reactions}', '{"fire": 2, "heart": 1}'::jsonb);
select tests.eq('F36 private: anonymous tracking count = the 3 OTHER members who track the item',
  (:'pb')::jsonb #> '{rails,0,items,0,member_status_counts}', '{"_tracking_count": 3}'::jsonb);
select tests.ok('F34 private: no per-member statuses', ((:'pb')::jsonb #> '{rails,0,items,0,member_statuses}') = 'null'::jsonb);
select tests.eq('F34 private: members list is only the caller', jsonb_array_length((:'pb')::jsonb -> 'members'), 1);
select tests.eq('F34 private: caller''s own status/progress/rating are returned to the caller',
  (:'pb')::jsonb #>> '{rails,0,items,0,my_status}' || '/' || ((:'pb')::jsonb #>> '{rails,0,items,0,my_progress}') || '/' || ((:'pb')::jsonb #>> '{rails,0,items,0,my_rating}'),
  'COMPLETED/12/9');
select tests.ok('F34 private: no other member''s notes or rating text anywhere in the bundle',
  position('secret-note' in :'pb') = 0);
select tests.eq('F36 loading bundle (private): member_count is all 4 members',
  ((public.fetch_club_bundle_loading(:'p_club')) ->> 'member_count')::int, 4);

-- status club S, as member 2: counts over members with effective rank >= 1 (5 is private)
select public.fetch_club_bundle(:'s_club')::text as sb \gset
select tests.eq('F36 status: per-status counts over status-visible members (1 WATCHING, 2 COMPLETED, 3 WATCHING; 5 private-excluded)',
  (:'sb')::jsonb #> '{rails,0,items,0,member_status_counts}', '{"WATCHING": 2, "COMPLETED": 1}'::jsonb);
select tests.eq('F36 status: member_statuses lists the 3 status-visible members',
  jsonb_array_length((:'sb')::jsonb #> '{rails,0,items,0,member_statuses}'), 3);
select tests.ok('F34 status: the private-downgraded member 5 is absent from member_statuses',
  not exists (select 1 from jsonb_array_elements((:'sb')::jsonb #> '{rails,0,items,0,member_statuses}') e
              where e ->> 'user_id' = tests.uid(5)::text));
select tests.ok('F34 status: no progress numbers at status level',
  not exists (select 1 from jsonb_array_elements((:'sb')::jsonb #> '{rails,0,items,0,member_statuses}') e
              where e -> 'progress' <> 'null'::jsonb));
select tests.ok('F34 status: no anonymous _tracking_count key in a status club (per-status counts only)',
  not (((:'sb')::jsonb #> '{rails,0,items,0,member_status_counts}') ? '_tracking_count'));
select tests.ok('F34 status: member_statuses never carry rating or notes keys',
  not exists (select 1 from jsonb_array_elements((:'sb')::jsonb #> '{rails,0,items,0,member_statuses}') e
              where e ? 'rating' or e ? 'notes'));
select tests.ok('F34 status: no notes anywhere in the bundle', position('secret-note' in :'sb') = 0);

-- progress club G (1, 2, 3, 4 at status, 5 opted out to private), as member 2:
-- progress only for members whose EFFECTIVE rank is 2, nothing at all for member 5
select public.fetch_club_bundle(:'g_club')::text as gb \gset
select tests.eq('F36 progress: per-status counts over the 4 members who share status; opted-out member 5 (PAUSED) is not counted',
  (:'gb')::jsonb #> '{rails,0,items,0,member_status_counts}', '{"WATCHING": 2, "COMPLETED": 1, "DROPPED": 1}'::jsonb);
select tests.eq('F36 progress: member_statuses lists the 4 status-sharing members',
  jsonb_array_length((:'gb')::jsonb #> '{rails,0,items,0,member_statuses}'), 4);
select tests.ok('F34 progress: the opted-out (private) member 5 is absent from member_statuses',
  not exists (select 1 from jsonb_array_elements((:'gb')::jsonb #> '{rails,0,items,0,member_statuses}') e
              where e ->> 'user_id' = tests.uid(5)::text));
select tests.eq('F36 progress: progress visible for a member at effective progress level (member 3: 7)',
  (select e ->> 'progress' from jsonb_array_elements((:'gb')::jsonb #> '{rails,0,items,0,member_statuses}') e
    where e ->> 'user_id' = tests.uid(3)::text), '7');
select tests.ok('F34 progress: member 4 downgraded to status -> status shown, progress withheld',
  exists (select 1 from jsonb_array_elements((:'gb')::jsonb #> '{rails,0,items,0,member_statuses}') e
           where e ->> 'user_id' = tests.uid(4)::text and e ->> 'status' = 'DROPPED' and e -> 'progress' = 'null'::jsonb));
select tests.eq('F36 progress: member list (>=3 members) is complete', jsonb_array_length((:'gb')::jsonb -> 'members'), 5);
select tests.ok('F34 progress: no notes anywhere in the bundle', position('secret-note' in :'gb') = 0);

-- 2-member clubs (progress / status / private), as member 2: ONLY own data. A count over
-- the one other member would identify them (security review); the other member (3) does
-- track the item, so a non-null count here would be that person's tracking.
select public.fetch_club_bundle(:'d_club')::text as db \gset
select public.fetch_club_bundle(:'ds_club')::text as dsb \gset
select public.fetch_club_bundle(:'dp_club')::text as dpb \gset
select tests.ok('k rule (progress duo): no cross-member count that would identify the other member',
  ((:'db')::jsonb #> '{rails,0,items,0,member_status_counts}') = 'null'::jsonb);
select tests.ok('k rule (status duo): no cross-member count', ((:'dsb')::jsonb #> '{rails,0,items,0,member_status_counts}') = 'null'::jsonb);
select tests.ok('k rule (private duo): no cross-member count', ((:'dpb')::jsonb #> '{rails,0,items,0,member_status_counts}') = 'null'::jsonb);
select tests.ok('F34 duo: no per-member statuses below 3 members (all three levels)',
  ((:'db')::jsonb #> '{rails,0,items,0,member_statuses}') = 'null'::jsonb
  and ((:'dsb')::jsonb #> '{rails,0,items,0,member_statuses}') = 'null'::jsonb
  and ((:'dpb')::jsonb #> '{rails,0,items,0,member_statuses}') = 'null'::jsonb);
select tests.eq('F34 duo: members list is only the caller below 3 members', jsonb_array_length((:'db')::jsonb -> 'members'), 1);
select tests.eq('duo: the caller still gets their own status for the item', (:'dpb')::jsonb #>> '{rails,0,items,0,my_status}', 'COMPLETED');
select tests.eq('duo: reaction/vote aggregates keep their shape (empty reactions object)', (:'dpb')::jsonb #> '{rails,0,items,0,reactions}', '{}'::jsonb);

-- ==========================================================================
-- departed members are EXCLUDED from current-member aggregates (rows kept)
-- ==========================================================================
select tests.as_user(tests.uid(3));
select tests.eq('legit: member 3 leaves the private club', (public.leave_club(:'p_club')) ->> 'success', 'true');
select tests.as_user(tests.uid(2));
select public.fetch_club_bundle(:'p_club')::text as pb2 \gset
select tests.eq('departed: member_count drops to 3', ((:'pb2')::jsonb ->> 'member_count')::int, 3);
select tests.eq('departed: the leaver''s vote is excluded from poll counts (3 -> 2)',
  (select sum((o ->> 'vote_count')::int) from jsonb_array_elements((:'pb2')::jsonb #> '{polls,0,options}') o)::int, 2);
select tests.eq('departed: the leaver''s reaction is excluded from totals',
  (:'pb2')::jsonb #> '{rails,0,items,0,reactions}', '{"fire": 2}'::jsonb);
select tests.eq('departed: tracking count covers current other members only (1, 4)',
  (:'pb2')::jsonb #> '{rails,0,items,0,member_status_counts}', '{"_tracking_count": 2}'::jsonb);
select tests.reset();
select tests.eq('departed: the leaver''s vote row is kept (excluded, not deleted)',
  (select count(*) from public.club_votes where poll_id = :'p_poll' and user_id = tests.uid(3)), 1::bigint);

-- ==========================================================================
-- authorization of the aggregate boundary
-- ==========================================================================
select tests.as_user(tests.uid(6));
select tests.raises('outsider: fetch_club_bundle raises NOT_A_MEMBER', format($q$select public.fetch_club_bundle(%L)$q$, :'p_club'), '%NOT_A_MEMBER%');
select tests.raises('outsider: fetch_club_bundle_loading raises NOT_A_MEMBER', format($q$select public.fetch_club_bundle_loading(%L)$q$, :'p_club'), '%NOT_A_MEMBER%');
select tests.as_user(tests.uid(3));
select tests.raises('departed member: fetch_club_bundle raises NOT_A_MEMBER', format($q$select public.fetch_club_bundle(%L)$q$, :'p_club'), '%NOT_A_MEMBER%');
select tests.as_anon();
select tests.denied('anon: no EXECUTE on fetch_club_bundle', format($q$select public.fetch_club_bundle(%L)$q$, :'p_club'));
select tests.denied('anon: no EXECUTE on fetch_club_bundle_loading', format($q$select public.fetch_club_bundle_loading(%L)$q$, :'p_club'));
select tests.reset();
select tests.ok('posture: fetch_club_bundle is SECURITY DEFINER with search_path = public, extensions',
  (select prosecdef and proconfig @> array['search_path=public, extensions'] from pg_proc where oid = 'public.fetch_club_bundle(uuid)'::regprocedure));
select tests.ok('posture: fetch_club_bundle_loading is SECURITY DEFINER with search_path = public, extensions',
  (select prosecdef and proconfig @> array['search_path=public, extensions'] from pg_proc where oid = 'public.fetch_club_bundle_loading(uuid)'::regprocedure));
select tests.ok('posture: no PUBLIC EXECUTE on either bundle',
  not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
               where p.oid in ('public.fetch_club_bundle(uuid)'::regprocedure, 'public.fetch_club_bundle_loading(uuid)'::regprocedure)
                 and a.grantee = 0 and a.privilege_type = 'EXECUTE'));
select tests.ok('posture: authenticated may EXECUTE both bundles',
  has_function_privilege('authenticated', 'public.fetch_club_bundle(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.fetch_club_bundle_loading(uuid)', 'EXECUTE'));

select tests.reset();
rollback;
