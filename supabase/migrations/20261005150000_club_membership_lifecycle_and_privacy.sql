-- ============================================================================
-- Clubs: one membership lifecycle + private raw rows + authorized aggregates
-- (F34, F35, F36, F37, F39; club policy P2-R1 in
--  docs/plans/2026-10-05-modularity-completion-contracts.md section 4)
--
-- STATUS: PREPARED, NOT APPLIED TO PRODUCTION. Deployment needs a separate, explicit
--   human approval; the lead registers it in supabase/tests/pending_migrations.txt.
--   Requires 20261005140000_account_deletion_write_barrier.sql (applied first).
--
-- What changes
--   F34 raw privacy: club_members / club_votes / club_rail_item_reactions SELECT is own
--       rows only (a member still reads their own row/vote/reaction while a member).
--       Other members' metadata reaches the app only through the bundle RPCs, which
--       already apply the private / <3-member rules.
--   F36 aggregates: fetch_club_bundle and fetch_club_bundle_loading become SECURITY
--       DEFINER with an explicit is_club_member() caller check, search_path = public,
--       extensions and EXECUTE for `authenticated` only. Response shapes are unchanged.
--       Per-member detail follows each member's EFFECTIVE level least(club, own):
--       status >= 1, progress >= 2 (the INVOKER body gated progress on the CLUB level,
--       which would have exposed the progress of a member who downgraded to status).
--       No rating / notes / updated list fields beyond status/progress/updated_at.
--       Cross-member item counts: none below 3 members (member_status_counts = null:
--       the pre-existing `_tracking_count` branch also covered 2-member clubs, where a
--       count over the one other member identifies them; it was never observable
--       before because INVOKER + list RLS made it 0); private clubs with >= 3 members
--       keep the anonymous `_tracking_count` (docs/clubs-spec.md: private = "anonymous
--       contribution to counts"); status/progress clubs count only members at
--       effective rank >= 1, so a member who opted down to private is never counted.
--   F35 removal vs leave: removal of ANOTHER member is the owner/admin RPC
--       remove_club_member() (no new screen; the app has no removal UI today). Before,
--       removal was a direct table DELETE by an owner/admin; with own-row SELECT such a
--       DELETE cannot see the row any more, so the table DELETE policy is narrowed to
--       one's own non-owner row (= leaving). Every deletion of a membership by another
--       authenticated user records a block (trigger); join_club refuses a blocked user
--       with REMOVED_FROM_CLUB until restore_club_member (owner/admin) lifts it.
--       Voluntary leave (leave_club, or deleting one's own non-owner row) records no
--       block, so a still-valid invite works. Departed members' votes and reactions
--       are EXCLUDED from current-member counts (rows kept, not deleted; they count again
--       if the person rejoins).
--   F37/F39 one lifecycle: _club_member_depart() is the single function leave_club and
--       account deletion use: lock the club row, remove the membership, then
--       _club_settle(): transfer ownership (oldest admin, else oldest member; members
--       being deleted last) or delete a club left with no members, re-checked in a new
--       statement under the lock. join_club takes the same club row lock first and
--       refuses an empty club, so a join can neither be cascaded away by a stale
--       emptiness decision nor resurrect an orphan. The owner row can no longer be
--       deleted through the table API (only through the lifecycle). An AFTER DELETE
--       trigger settles a club whose owner row disappears by any other path (e.g. an
--       auth user deleted from the dashboard: FK cascade).
--   delete_account_club_memberships(user) (service role): the account-deletion step;
--       requires the barrier of 20261005140000, then runs the lifecycle for every
--       membership in club_id order. The global orphan sweep of the old edge function is
--       gone: deletion never touches clubs unrelated to the deleting user.
--
-- Error codes (MESSAGE carries the code, HINT repeats it): REMOVED_FROM_CLUB (join_club),
--   NOT_ADMIN / NOT_A_MEMBER / CANNOT_REMOVE_SELF (remove_club_member), NOT_ADMIN
--   (restore_club_member), DELETION_NOT_STARTED / INVALID_USER_ID
--   (delete_account_club_memberships); all existing codes unchanged.
--
-- Production parity (read-only, before deploying; see
-- supabase/tests/prerequisites/delete_account_prereqs.sql):
--   select policyname, cmd, roles, qual from pg_policies where schemaname = 'public'
--    and tablename in ('club_members','club_votes','club_rail_item_reactions');
--   select p.oid::regprocedure, prosecdef, proconfig from pg_proc p
--    where p.oid in ('public.fetch_club_bundle(uuid)'::regprocedure, 'public.join_club(text)'::regprocedure,
--                    'public.leave_club(uuid)'::regprocedure);
--   -- existing orphans (created_by null, no members), for the separate cleanup decision:
--   select count(*) from public.clubs c where not exists (select 1 from public.club_members m where m.club_id = c.id);
-- Rollback: restore the three *_select_member policies and club_members_delete_self_or_admin
--   (dropping club_members_delete_self) from 20260209201000 / 20260216214047, re-run the
--   previous function bodies
--   (fetch_club_bundle 20260317110000, fetch_club_bundle_loading 20260318104000,
--   join_club 20260218141754, leave_club 20260209202000), drop the trigger
--   club_members_lifecycle, the functions added here and table club_member_blocks.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- F35: removal blocks
-- ---------------------------------------------------------------------------
create table if not exists public.club_member_blocks (
  club_id    uuid not null references public.clubs(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  blocked_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (club_id, user_id)
);
comment on table public.club_member_blocks is
  'F35: a member removed by an owner/admin cannot rejoin through join_club until restore_club_member. Written only by the club_members lifecycle trigger; owner/admin read.';
alter table public.club_member_blocks enable row level security;
drop policy if exists club_member_blocks_select_admin on public.club_member_blocks;
create policy club_member_blocks_select_admin on public.club_member_blocks
  for select to authenticated using (public.is_club_admin_or_owner(club_id));
revoke all on table public.club_member_blocks from public, anon, authenticated;
grant select on table public.club_member_blocks to authenticated;
grant all on table public.club_member_blocks to service_role;

-- ---------------------------------------------------------------------------
-- F37/F39: the lifecycle
-- ---------------------------------------------------------------------------
-- Settle a club under its row lock: delete it when no member is left, otherwise make
-- sure it has an owner. Idempotent; 'gone' when the club no longer exists.
create or replace function public._club_settle(p_club_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_successor uuid;
begin
  perform 1 from public.clubs where id = p_club_id for update;
  if not found then
    return 'gone';
  end if;
  -- new statements under the lock: they see every committed membership
  if not exists (select 1 from public.club_members where club_id = p_club_id) then
    delete from public.clubs c
     where c.id = p_club_id
       and not exists (select 1 from public.club_members m where m.club_id = c.id);
    return 'deleted';
  end if;
  if exists (select 1 from public.club_members where club_id = p_club_id and role = 'owner') then
    return 'owned';
  end if;
  -- oldest admin, else oldest member; members whose account deletion is running last.
  -- FOR UPDATE skips a candidate deleted concurrently (its own leave/removal).
  select m.user_id into v_successor
    from public.club_members m
   where m.club_id = p_club_id
   order by exists (select 1 from public.account_deletion_barriers b where b.user_id = m.user_id),
            (m.role = 'admin') desc, m.joined_at, m.user_id
   limit 1
   for update of m;
  if v_successor is null then
    delete from public.clubs c
     where c.id = p_club_id
       and not exists (select 1 from public.club_members m where m.club_id = c.id);
    return 'deleted';
  end if;
  update public.club_members set role = 'owner'
   where club_id = p_club_id and user_id = v_successor;
  return 'transferred';
end;
$$;
revoke all on function public._club_settle(uuid) from public, anon, authenticated;

-- THE membership lifecycle shared by leave_club and account deletion.
create or replace function public._club_member_depart(p_club_id uuid, p_user_id uuid, p_reason text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  v_role text;
  v_deleted boolean;
begin
  if p_reason not in ('left', 'account_deleted') then
    raise exception 'INVALID_REASON' using errcode = '22023';
  end if;
  -- club row lock first (same order as join_club), then the membership
  perform 1 from public.clubs where id = p_club_id for update;
  if not found then
    return jsonb_build_object('club_id', p_club_id, 'outcome', 'club_gone', 'club_deleted', false);
  end if;
  delete from public.club_members
   where club_id = p_club_id and user_id = p_user_id
  returning role into v_role;
  if v_role is null then
    return jsonb_build_object('club_id', p_club_id, 'outcome', 'not_a_member', 'club_deleted', false);
  end if;
  perform public._club_settle(p_club_id);
  v_deleted := not exists (select 1 from public.clubs where id = p_club_id);
  return jsonb_build_object(
    'club_id', p_club_id,
    'outcome', p_reason,
    'previous_role', v_role,
    'club_deleted', v_deleted,
    'owner', (select user_id from public.club_members where club_id = p_club_id and role = 'owner'));
end;
$$;
revoke all on function public._club_member_depart(uuid, uuid, text) from public, anon, authenticated;

-- Any deletion of a membership row: block on removal by another user, settle when the
-- owner row went away (covers the auth.users FK cascade and any future path).
create or replace function public.club_members_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not exists (select 1 from public.clubs where id = old.club_id) then
    return null;   -- club deleted (cascade): nothing to block or settle
  end if;
  if v_actor is not null and v_actor <> old.user_id then
    insert into public.club_member_blocks (club_id, user_id, blocked_by)
    values (old.club_id, old.user_id, v_actor)
    on conflict (club_id, user_id) do update set blocked_by = excluded.blocked_by, created_at = now();
  end if;
  if old.role = 'owner' then
    perform public._club_settle(old.club_id);
  end if;
  return null;
end;
$$;
revoke all on function public.club_members_lifecycle() from public, anon, authenticated;

drop trigger if exists club_members_lifecycle on public.club_members;
create trigger club_members_lifecycle
  after delete on public.club_members
  for each row execute function public.club_members_lifecycle();

-- Table-API DELETE: only one's OWN non-owner row (= leaving). With own-row SELECT
-- (below) a DELETE of another member's row could never see it anyway, so removal of
-- others is the explicit owner/admin RPC remove_club_member(); the owner row changes
-- only through the lifecycle (leave_club / account deletion).
drop policy if exists club_members_delete_self_or_admin on public.club_members;
drop policy if exists club_members_delete_self on public.club_members;
create policy club_members_delete_self on public.club_members
  for delete to authenticated
  using (user_id = (select auth.uid()) and role <> 'owner');

-- ---------------------------------------------------------------------------
-- F34: raw per-user rows are own-row only
-- ---------------------------------------------------------------------------
drop policy if exists club_members_select_member on public.club_members;
drop policy if exists club_members_select_own on public.club_members;
create policy club_members_select_own on public.club_members
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists club_votes_select_member on public.club_votes;
drop policy if exists club_votes_select_own on public.club_votes;
create policy club_votes_select_own on public.club_votes
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and exists (select 1 from public.club_polls cp
                 where cp.id = club_votes.poll_id and public.is_club_member(cp.club_id))
  );

drop policy if exists club_reactions_select_member on public.club_rail_item_reactions;
drop policy if exists club_reactions_select_own on public.club_rail_item_reactions;
create policy club_reactions_select_own on public.club_rail_item_reactions
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and exists (select 1 from public.club_rail_items cri
                  join public.club_rails cr on cr.id = cri.rail_id
                 where cri.id = club_rail_item_reactions.rail_item_id and public.is_club_member(cr.club_id))
  );

-- ---------------------------------------------------------------------------
-- F36: authorized aggregates (shape unchanged)
-- ---------------------------------------------------------------------------
create or replace function public.fetch_club_bundle(p_club_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
DECLARE
  _uid uuid;
  _club record;
  _my_membership record;
  _my_effective_level text;
  _club_sharing_rank int;
  _member_count int;
  _members jsonb;
  _rails jsonb;
  _polls jsonb;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Explicit caller authorization: this function reads every member's rows.
  IF NOT public.is_club_member(p_club_id) THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  SELECT cm.role, cm.sharing_level, cm.joined_at
  INTO _my_membership
  FROM public.club_members cm
  WHERE cm.club_id = p_club_id AND cm.user_id = _uid;

  IF _my_membership IS NULL THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  SELECT c.id, c.name, c.description, c.sharing_level, c.max_members,
         c.is_archived, c.invite_code, c.created_at
  INTO _club
  FROM public.clubs c
  WHERE c.id = p_club_id;

  IF _club IS NULL THEN
    RAISE EXCEPTION 'CLUB_NOT_FOUND' USING ERRCODE = 'P0001';
  END IF;

  _my_effective_level := CASE
    WHEN _my_membership.sharing_level IS NULL THEN _club.sharing_level
    WHEN public.sharing_level_rank(_my_membership.sharing_level) < public.sharing_level_rank(_club.sharing_level)
      THEN _my_membership.sharing_level
    ELSE _club.sharing_level
  END;

  _club_sharing_rank := public.sharing_level_rank(_club.sharing_level);

  -- current members only
  SELECT count(*) INTO _member_count FROM public.club_members WHERE club_id = p_club_id;

  -- MEMBERS: private club or fewer than 3 members -> only the caller
  IF _club_sharing_rank = 0 OR _member_count < 3 THEN
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id AND cm.user_id = _uid
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  ELSE
    SELECT jsonb_agg(jsonb_build_object(
      'user_id', member_rows.user_id,
      'role', member_rows.role,
      'sharing_level', member_rows.sharing_level,
      'joined_at', member_rows.joined_at,
      'display_name', member_rows.display_name
    ) ORDER BY member_rows.joined_at, member_rows.user_id)
    INTO _members
    FROM (
      SELECT
        cm.user_id,
        cm.role,
        COALESCE(cm.sharing_level, _club.sharing_level) AS sharing_level,
        cm.joined_at,
        nullif(trim(coalesce(p.display_name, '')), '') AS display_name
      FROM public.club_members cm
      LEFT JOIN public.profiles p ON p.id = cm.user_id
      WHERE cm.club_id = p_club_id
      ORDER BY cm.joined_at, cm.user_id
      LIMIT 50
    ) member_rows;
  END IF;

  _members := COALESCE(_members, '[]'::jsonb);

  -- RAILS + ITEMS with media join + per-item aggregates + reactions
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'title', r.title,
      'description', r.description,
      'is_locked', r.is_locked,
      'sort_order', r.sort_order,
      'created_by', r.created_by,
      'items', COALESCE(r.items, '[]'::jsonb)
    ) ORDER BY r.sort_order, r.id
  ), '[]'::jsonb)
  INTO _rails
  FROM (
    SELECT
      cr.id, cr.title, cr.description, cr.is_locked, cr.sort_order, cr.created_by,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', enriched.item_id,
            'media_type', enriched.media_type,
            'media_id', enriched.media_id,
            'sort_order', enriched.sort_order,
            'note', enriched.note,
            'added_by', enriched.added_by,
            'title_display', enriched.title_display,
            'cover_image_medium', enriched.cover_image_medium,
            'average_score', enriched.average_score,
            'year', enriched.year,
            'format', enriched.format,
            'episode_count', enriched.episode_count,
            'chapter_count', enriched.chapter_count,
            'my_status', enriched.my_status,
            'my_progress', enriched.my_progress,
            'my_rating', enriched.my_rating,
            'member_status_counts', enriched.member_status_counts,
            'member_statuses', enriched.member_statuses,
            'reactions', enriched.reactions,
            'my_reactions', enriched.my_reactions
          ) ORDER BY enriched.sort_order, enriched.item_id
        )
        FROM (
          SELECT
            cri.id AS item_id,
            cri.media_type,
            cri.media_id,
            cri.sort_order,
            cri.note,
            cri.added_by,
            COALESCE(
              CASE WHEN cri.media_type = 'ANIME' THEN COALESCE(a.title_english, a.title_romaji)
                   WHEN cri.media_type = 'MANGA' THEN COALESCE(m.title_english, m.title_romaji)
              END, 'Unknown'
            ) AS title_display,
            CASE WHEN cri.media_type = 'ANIME' THEN a.cover_image_medium
                 WHEN cri.media_type = 'MANGA' THEN m.cover_image_medium
            END AS cover_image_medium,
            CASE WHEN cri.media_type = 'ANIME' THEN a.average_score
                 WHEN cri.media_type = 'MANGA' THEN m.average_score
            END AS average_score,
            CASE WHEN cri.media_type = 'ANIME' THEN a.season_year
                 WHEN cri.media_type = 'MANGA' THEN m.start_date_year
            END AS year,
            CASE WHEN cri.media_type = 'ANIME' THEN a.format
                 WHEN cri.media_type = 'MANGA' THEN m.format
            END AS format,
            CASE WHEN cri.media_type = 'ANIME' THEN a.episodes ELSE NULL END AS episode_count,
            CASE WHEN cri.media_type = 'MANGA' THEN m.chapters ELSE NULL END AS chapter_count,
            -- Caller's own status/progress/rating
            COALESCE(my_aul.list_type, my_mul.list_type) AS my_status,
            COALESCE(my_aul.progress, my_mul.progress) AS my_progress,
            COALESCE(my_aul.rating, my_mul.rating) AS my_rating,
            -- Aggregate status counts across CURRENT club members
            CASE
              -- Fewer than 3 members: no cross-member aggregate at all (H1 "only own data";
              -- a count over one other member would identify that person).
              WHEN _member_count < 3 THEN NULL
              WHEN _club_sharing_rank = 0 THEN
                -- private club (>= 3 members, so >= 2 others): anonymous count of the OTHER
                -- members who track the item; every member's effective level is private here,
                -- which docs/clubs-spec.md defines as "anonymous contribution to counts"
                jsonb_build_object('_tracking_count', (
                  SELECT count(*)
                  FROM public.club_members cm2
                  WHERE cm2.club_id = p_club_id
                    AND cm2.user_id != _uid
                    AND (
                      CASE WHEN cri.media_type = 'ANIME' THEN
                        EXISTS (SELECT 1 FROM public.anime_user_lists aul2
                                WHERE aul2.user_id = cm2.user_id::text AND aul2.anime_id = cri.media_id)
                      WHEN cri.media_type = 'MANGA' THEN
                        EXISTS (SELECT 1 FROM public.manga_user_lists mul2
                                WHERE mul2.user_id = cm2.user_id::text AND mul2.manga_id = cri.media_id)
                      END
                    )
                ))
              ELSE
                (
                  SELECT COALESCE(jsonb_object_agg(sa.list_type, sa.cnt), '{}'::jsonb)
                  FROM (
                    SELECT ul.list_type, count(*) AS cnt
                    FROM public.club_members cm3
                    JOIN LATERAL (
                      SELECT CASE
                        WHEN cm3.sharing_level IS NULL THEN _club_sharing_rank
                        WHEN public.sharing_level_rank(cm3.sharing_level) < _club_sharing_rank
                          THEN public.sharing_level_rank(cm3.sharing_level)
                        ELSE _club_sharing_rank
                      END AS eff_rank
                    ) eff ON true
                    LEFT JOIN LATERAL (
                      SELECT aul3.list_type FROM public.anime_user_lists aul3
                      WHERE cri.media_type = 'ANIME' AND aul3.user_id = cm3.user_id::text AND aul3.anime_id = cri.media_id
                      UNION ALL
                      SELECT mul3.list_type FROM public.manga_user_lists mul3
                      WHERE cri.media_type = 'MANGA' AND mul3.user_id = cm3.user_id::text AND mul3.manga_id = cri.media_id
                    ) ul ON true
                    WHERE cm3.club_id = p_club_id AND eff.eff_rank >= 1 AND ul.list_type IS NOT NULL
                    GROUP BY ul.list_type
                  ) sa
                )
            END AS member_status_counts,
            -- Per-member status: effective rank >= 1; progress only at effective rank >= 2
            CASE
              WHEN _member_count < 3 OR _club_sharing_rank = 0 THEN NULL
              ELSE (
                SELECT jsonb_agg(jsonb_build_object(
                  'user_id', ms.user_id,
                  'display_name', ms.display_name,
                  'status', ms.list_type,
                  'progress', CASE WHEN ms.eff_rank >= 2 THEN ms.progress ELSE NULL END,
                  'updated_at', ms.updated_at
                ) ORDER BY ms.updated_at DESC NULLS LAST, ms.user_id)
                FROM (
                  SELECT cm4.user_id, nullif(trim(coalesce(p4.display_name, '')), '') AS display_name,
                         ul4.list_type, ul4.progress, ul4.updated_at, eff4.eff_rank
                  FROM public.club_members cm4
                  LEFT JOIN public.profiles p4 ON p4.id = cm4.user_id
                  JOIN LATERAL (
                    SELECT CASE
                      WHEN cm4.sharing_level IS NULL THEN _club_sharing_rank
                      WHEN public.sharing_level_rank(cm4.sharing_level) < _club_sharing_rank
                        THEN public.sharing_level_rank(cm4.sharing_level)
                      ELSE _club_sharing_rank
                    END AS eff_rank
                  ) eff4 ON true
                  LEFT JOIN LATERAL (
                    SELECT aul4.list_type, aul4.progress, aul4.updated_at FROM public.anime_user_lists aul4
                    WHERE cri.media_type = 'ANIME' AND aul4.user_id = cm4.user_id::text AND aul4.anime_id = cri.media_id
                    UNION ALL
                    SELECT mul4.list_type, mul4.progress, mul4.updated_at FROM public.manga_user_lists mul4
                    WHERE cri.media_type = 'MANGA' AND mul4.user_id = cm4.user_id::text AND mul4.manga_id = cri.media_id
                  ) ul4 ON true
                  WHERE cm4.club_id = p_club_id AND eff4.eff_rank >= 1 AND ul4.list_type IS NOT NULL
                ) ms
              )
            END AS member_statuses,
            -- Reactions of CURRENT members: anonymous aggregate counts {fire: 3, heart: 1}
            (
              SELECT COALESCE(jsonb_object_agg(rc.emoji, rc.cnt), '{}'::jsonb)
              FROM (
                SELECT r2.emoji, count(*) AS cnt
                FROM public.club_rail_item_reactions r2
                JOIN public.club_members rm ON rm.club_id = p_club_id AND rm.user_id = r2.user_id
                WHERE r2.rail_item_id = cri.id
                GROUP BY r2.emoji
              ) rc
            ) AS reactions,
            -- My reactions: ["fire", "heart"]
            (
              SELECT COALESCE(jsonb_agg(r3.emoji), '[]'::jsonb)
              FROM public.club_rail_item_reactions r3
              WHERE r3.rail_item_id = cri.id AND r3.user_id = _uid
            ) AS my_reactions
          FROM public.club_rail_items cri
          LEFT JOIN public.anime a ON cri.media_type = 'ANIME' AND a.id = cri.media_id
          LEFT JOIN public.manga m ON cri.media_type = 'MANGA' AND m.id = cri.media_id
          LEFT JOIN public.anime_user_lists my_aul
            ON cri.media_type = 'ANIME' AND my_aul.user_id = _uid::text AND my_aul.anime_id = cri.media_id
          LEFT JOIN public.manga_user_lists my_mul
            ON cri.media_type = 'MANGA' AND my_mul.user_id = _uid::text AND my_mul.manga_id = cri.media_id
          WHERE cri.rail_id = cr.id
          ORDER BY cri.sort_order, cri.id
          LIMIT 50
        ) enriched
      ) AS items
    FROM public.club_rails cr
    WHERE cr.club_id = p_club_id
  ) r;

  -- POLLS + OPTIONS + VOTE COUNTS (current members' votes)
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'question', p.question,
      'is_closed', p.is_closed,
      'closes_at', p.closes_at,
      'created_by', p.created_by,
      'created_at', p.created_at,
      'options', COALESCE(p.options, '[]'::jsonb),
      'my_vote_option_id', p.my_vote_option_id
    ) ORDER BY p.is_closed ASC, p.created_at DESC, p.id DESC
  ), '[]'::jsonb)
  INTO _polls
  FROM (
    SELECT
      cp.id, cp.question, cp.is_closed, cp.closes_at, cp.created_by, cp.created_at,
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', option_rows.id,
            'label', option_rows.label,
            'media_type', option_rows.media_type,
            'media_id', option_rows.media_id,
            'sort_order', option_rows.sort_order,
            'vote_count', option_rows.vote_count
          ) ORDER BY option_rows.sort_order, option_rows.id
        )
        FROM (
          SELECT
            cpo.id,
            cpo.label,
            cpo.media_type,
            cpo.media_id,
            cpo.sort_order,
            COALESCE(vc.vote_count, 0)::int AS vote_count
          FROM public.club_poll_options cpo
          LEFT JOIN (
            SELECT cv.option_id, count(*) AS vote_count
            FROM public.club_votes cv
            JOIN public.club_members vm ON vm.club_id = p_club_id AND vm.user_id = cv.user_id
            WHERE cv.poll_id = cp.id
            GROUP BY cv.option_id
          ) vc ON vc.option_id = cpo.id
          WHERE cpo.poll_id = cp.id
        ) option_rows
      ) AS options,
      (
        SELECT cv2.option_id
        FROM public.club_votes cv2
        WHERE cv2.poll_id = cp.id AND cv2.user_id = _uid
        LIMIT 1
      ) AS my_vote_option_id
    FROM public.club_polls cp
    WHERE cp.club_id = p_club_id
    ORDER BY cp.is_closed ASC, cp.created_at DESC, cp.id DESC
    LIMIT 20
  ) p;

  RETURN jsonb_build_object(
    'club', jsonb_build_object(
      'id', _club.id,
      'name', _club.name,
      'description', _club.description,
      'sharing_level', _club.sharing_level,
      'max_members', _club.max_members,
      'is_archived', _club.is_archived,
      'invite_code', CASE WHEN _my_membership.role IN ('owner', 'admin') THEN _club.invite_code ELSE NULL END,
      'created_at', _club.created_at
    ),
    'members', _members,
    'my_role', _my_membership.role,
    'my_sharing_level', _my_effective_level,
    'rails', _rails,
    'polls', _polls,
    'member_count', _member_count
  );
END;
$function$;
comment on function public.fetch_club_bundle(uuid) is
  'Authorized club aggregate (F34/F36, 20261005150000): SECURITY DEFINER; caller must be a member; private/<3-member rules for member lists and statuses; no cross-member item counts below 3 members; per-member status at effective rank >= 1, progress at >= 2; votes/reactions of current members only. Shape unchanged.';
revoke all on function public.fetch_club_bundle(uuid) from public, anon, service_role;
grant execute on function public.fetch_club_bundle(uuid) to authenticated;

create or replace function public.fetch_club_bundle_loading(p_club_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
declare
  _uid uuid;
  _club record;
  _my_membership record;
  _my_effective_level text;
  _club_sharing_rank int;
  _member_count int;
  _rail_count int;
  _poll_count int;
  _last_activity_at timestamptz;
  _activity_preview text;
  _bundle_state text;
  _bundle_visibility text;
begin
  _uid := auth.uid();
  if _uid is null then
    raise exception 'UNAUTHENTICATED' using errcode = 'P0001';
  end if;

  if not public.is_club_member(p_club_id) then
    raise exception 'NOT_A_MEMBER' using errcode = 'P0001';
  end if;

  select cm.role, cm.sharing_level, cm.joined_at
  into _my_membership
  from public.club_members cm
  where cm.club_id = p_club_id and cm.user_id = _uid;

  if _my_membership is null then
    raise exception 'NOT_A_MEMBER' using errcode = 'P0001';
  end if;

  select c.id, c.name, c.description, c.sharing_level, c.max_members,
         c.is_archived, c.invite_code, c.created_at
  into _club
  from public.clubs c
  where c.id = p_club_id;

  if _club is null then
    raise exception 'CLUB_NOT_FOUND' using errcode = 'P0001';
  end if;

  _my_effective_level := case
    when _my_membership.sharing_level is null then _club.sharing_level
    when public.sharing_level_rank(_my_membership.sharing_level) < public.sharing_level_rank(_club.sharing_level)
      then _my_membership.sharing_level
    else _club.sharing_level
  end;

  _club_sharing_rank := public.sharing_level_rank(_club.sharing_level);
  select count(*) into _member_count from public.club_members where club_id = p_club_id;
  select count(*) into _rail_count from public.club_rails where club_id = p_club_id;
  select count(*) into _poll_count from public.club_polls where club_id = p_club_id;

  select greatest(
    (select max(cri.created_at) from public.club_rail_items cri
     join public.club_rails cr on cr.id = cri.rail_id
     where cr.club_id = p_club_id),
    (select max(cp.created_at) from public.club_polls cp where cp.club_id = p_club_id),
    (select max(cv.created_at) from public.club_votes cv
     join public.club_polls cp2 on cp2.id = cv.poll_id
     where cp2.club_id = p_club_id)
  )
  into _last_activity_at;

  select case
    when latest.source = 'item' then 'Added: ' || left(latest.label, 40)
    when latest.source = 'poll' then 'Poll: ' || left(latest.label, 40)
    when latest.source = 'vote' then 'Vote on: ' || left(latest.label, 40)
    else null
  end
  into _activity_preview
  from (
    select 'item' as source,
           coalesce(a.title_english, a.title_romaji, m.title_english, m.title_romaji, 'Unknown') as label,
           cri2.created_at as ts
    from public.club_rail_items cri2
    join public.club_rails cr2 on cr2.id = cri2.rail_id
    left join public.anime a on cri2.media_type = 'ANIME' and a.id = cri2.media_id
    left join public.manga m on cri2.media_type = 'MANGA' and m.id = cri2.media_id
    where cr2.club_id = p_club_id
    union all
    select 'poll' as source, cp3.question as label, cp3.created_at as ts
    from public.club_polls cp3
    where cp3.club_id = p_club_id
    union all
    select 'vote' as source, cp4.question as label, cv2.created_at as ts
    from public.club_votes cv2
    join public.club_polls cp4 on cp4.id = cv2.poll_id
    where cp4.club_id = p_club_id
    order by ts desc
    limit 1
  ) latest;

  _bundle_state := case
    when _club.is_archived then 'archived'
    when _last_activity_at is null then 'loading'
    when _rail_count = 0 and _poll_count = 0 then 'loading'
    else 'ready'
  end;
  _bundle_visibility := case when _club.is_archived then 'hidden' else 'visible' end;

  return jsonb_build_object(
    'club', jsonb_build_object(
      'id', _club.id,
      'name', _club.name,
      'description', _club.description,
      'sharing_level', _club.sharing_level,
      'max_members', _club.max_members,
      'is_archived', _club.is_archived,
      'invite_code', case when _my_membership.role in ('owner', 'admin') then _club.invite_code else null end,
      'created_at', _club.created_at
    ),
    'members', '[]'::jsonb,
    'my_role', _my_membership.role,
    'my_sharing_level', _my_effective_level,
    'rails', '[]'::jsonb,
    'polls', '[]'::jsonb,
    'member_count', _member_count,
    'rail_count', _rail_count,
    'poll_count', _poll_count,
    'last_activity_at', _last_activity_at,
    'activity_preview', _activity_preview,
    'loading_state', jsonb_build_object(
      'state', _bundle_state,
      'visibility', _bundle_visibility
    )
  );
end;
$function$;
revoke all on function public.fetch_club_bundle_loading(uuid) from public, anon, service_role;
grant execute on function public.fetch_club_bundle_loading(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- join / leave / restore
-- ---------------------------------------------------------------------------
create or replace function public.join_club(p_invite_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
DECLARE
  _uid uuid;
  _club record;
  _member_count int;
  _rate_hits int;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  -- Account deletion barrier FIRST (lock order: user advisory lock, then club row).
  PERFORM public._account_write_guard(_uid::text);

  -- Rate limit: max 10 join attempts per user per minute (60s window)
  _rate_hits := public.rate_limit_hit('club_join:' || _uid::text, 60);
  IF _rate_hits > 10 THEN
    RAISE EXCEPTION 'RATE_LIMITED: too many join attempts, try again later' USING ERRCODE = 'P0001';
  END IF;

  -- Lock the club row: serializes with the membership lifecycle (leave, account
  -- deletion, empty-club cleanup) and with concurrent joins (member cap).
  SELECT c.id, c.name, c.invite_expires_at, c.invite_max_uses,
         c.invite_use_count, c.max_members, c.is_archived
  INTO _club
  FROM public.clubs c
  WHERE c.invite_code = p_invite_code
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVALID_CODE' USING ERRCODE = 'P0001';
  END IF;

  IF _club.is_archived THEN
    RAISE EXCEPTION 'CLUB_ARCHIVED' USING ERRCODE = 'P0001';
  END IF;

  IF _club.invite_expires_at IS NOT NULL AND _club.invite_expires_at < now() THEN
    RAISE EXCEPTION 'CODE_EXPIRED' USING ERRCODE = 'P0001';
  END IF;

  IF _club.invite_max_uses IS NOT NULL AND _club.invite_use_count >= _club.invite_max_uses THEN
    RAISE EXCEPTION 'CODE_EXHAUSTED' USING ERRCODE = 'P0001';
  END IF;

  -- An empty club is an orphan: never resurrect it (reported like an unknown code).
  IF NOT EXISTS (SELECT 1 FROM public.club_members WHERE club_id = _club.id) THEN
    RAISE EXCEPTION 'INVALID_CODE' USING ERRCODE = 'P0001';
  END IF;

  -- F35: removed by an owner/admin -> refused until restored.
  IF EXISTS (SELECT 1 FROM public.club_member_blocks WHERE club_id = _club.id AND user_id = _uid) THEN
    RAISE EXCEPTION 'REMOVED_FROM_CLUB' USING ERRCODE = 'P0001', HINT = 'REMOVED_FROM_CLUB';
  END IF;

  IF EXISTS (SELECT 1 FROM public.club_members WHERE club_id = _club.id AND user_id = _uid) THEN
    RAISE EXCEPTION 'ALREADY_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*) INTO _member_count FROM public.club_members WHERE club_id = _club.id;
  IF _member_count >= _club.max_members THEN
    RAISE EXCEPTION 'CLUB_FULL' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.club_members (club_id, user_id, role, sharing_level)
  VALUES (_club.id, _uid, 'member', NULL);

  UPDATE public.clubs SET invite_use_count = invite_use_count + 1 WHERE id = _club.id;

  RETURN jsonb_build_object(
    'club_id', _club.id,
    'club_name', _club.name,
    'role', 'member'
  );
END;
$function$;
revoke all on function public.join_club(text) from public, anon;
grant execute on function public.join_club(text) to authenticated;

create or replace function public.leave_club(p_club_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
DECLARE
  _uid uuid;
  _result jsonb;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;

  _result := public._club_member_depart(p_club_id, _uid, 'left');
  IF _result ->> 'outcome' IN ('not_a_member', 'club_gone') THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$function$;
revoke all on function public.leave_club(uuid) from public, anon;
grant execute on function public.leave_club(uuid) to authenticated;

-- F35 removal: owner/admin removes another, non-owner member (an admin cannot remove the
-- owner or another admin). The club_members_lifecycle trigger records the block.
create or replace function public.remove_club_member(p_club_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
DECLARE
  _uid uuid;
  _my_role text;
  _target_role text;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;
  IF p_user_id IS NULL OR p_user_id = _uid THEN
    RAISE EXCEPTION 'CANNOT_REMOVE_SELF' USING ERRCODE = 'P0001', HINT = 'CANNOT_REMOVE_SELF';
  END IF;
  -- same lock order as every membership change: club row first
  PERFORM 1 FROM public.clubs WHERE id = p_club_id FOR UPDATE;
  SELECT role INTO _my_role FROM public.club_members WHERE club_id = p_club_id AND user_id = _uid;
  IF _my_role IS NULL OR _my_role NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = 'P0001', HINT = 'NOT_ADMIN';
  END IF;
  SELECT role INTO _target_role FROM public.club_members WHERE club_id = p_club_id AND user_id = p_user_id;
  IF _target_role IS NULL THEN
    RAISE EXCEPTION 'NOT_A_MEMBER' USING ERRCODE = 'P0001';
  END IF;
  IF _target_role = 'owner' OR (_target_role = 'admin' AND _my_role <> 'owner') THEN
    RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = 'P0001', HINT = 'NOT_ADMIN';
  END IF;
  DELETE FROM public.club_members WHERE club_id = p_club_id AND user_id = p_user_id;
  RETURN jsonb_build_object('success', true, 'removed', true);
END;
$function$;
comment on function public.remove_club_member(uuid, uuid) is
  'F35: owner/admin removes a non-owner member (admins cannot remove admins); records a block so join_club refuses the person until restore_club_member.';
revoke all on function public.remove_club_member(uuid, uuid) from public, anon;
grant execute on function public.remove_club_member(uuid, uuid) to authenticated;

create or replace function public.restore_club_member(p_club_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $function$
DECLARE
  _uid uuid;
  _n int;
BEGIN
  _uid := auth.uid();
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED' USING ERRCODE = 'P0001';
  END IF;
  IF NOT public.is_club_admin_or_owner(p_club_id) THEN
    RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = 'P0001', HINT = 'NOT_ADMIN';
  END IF;
  DELETE FROM public.club_member_blocks WHERE club_id = p_club_id AND user_id = p_user_id;
  GET DIAGNOSTICS _n = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'restored', _n > 0);
END;
$function$;
comment on function public.restore_club_member(uuid, uuid) is
  'F35: owner/admin lifts the removal block of p_user_id; the person can then rejoin with a valid invite code (membership is not re-created here).';
revoke all on function public.restore_club_member(uuid, uuid) from public, anon;
grant execute on function public.restore_club_member(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- account deletion: the club step (service role only)
-- ---------------------------------------------------------------------------
create or replace function public.delete_account_club_memberships(p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, extensions
as $function$
declare
  v_club uuid;
  v_r jsonb;
  v_removed int := 0;
  v_deleted int := 0;
  v_transferred int := 0;
begin
  if p_user_id is null then
    raise exception 'INVALID_USER_ID' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(public._account_deletion_lock_key(p_user_id::text));
  if not exists (select 1 from public.account_deletion_barriers where user_id = p_user_id) then
    raise exception 'DELETION_NOT_STARTED' using errcode = 'P0001', hint = 'DELETION_NOT_STARTED';
  end if;
  for v_club in
    select club_id from public.club_members where user_id = p_user_id order by club_id
  loop
    v_r := public._club_member_depart(v_club, p_user_id, 'account_deleted');
    if v_r ->> 'outcome' = 'account_deleted' then
      v_removed := v_removed + 1;
      if (v_r ->> 'club_deleted')::boolean then
        v_deleted := v_deleted + 1;
      elsif v_r ->> 'previous_role' = 'owner' then
        v_transferred := v_transferred + 1;
      end if;
    end if;
  end loop;
  return jsonb_build_object(
    'success', true,
    'memberships_removed', v_removed,
    'clubs_deleted', v_deleted,
    'ownership_transferred', v_transferred);
end;
$function$;
comment on function public.delete_account_club_memberships(uuid) is
  'F37: account-deletion club step; runs the shared lifecycle (_club_member_depart) for every membership of p_user_id after begin_account_deletion. Retry-safe. Service role only.';
revoke all on function public.delete_account_club_memberships(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_club_memberships(uuid) to service_role;
