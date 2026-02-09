-- ============================================================
-- CLUBS RLS POLICIES
-- Adds Row Level Security policies for all 7 club tables.
--
-- Depends on: 20260209200000_clubs_foundation.sql (tables + RLS enabled)
--
-- Design:
--   - Two SECURITY DEFINER helper functions avoid infinite recursion
--     when policies on club_members need to query club_members itself.
--   - All policies are idempotent (DO $$ EXCEPTION WHEN duplicate_object).
--   - club_members INSERT is intentionally omitted for the 'authenticated'
--     role; membership is managed via SECURITY DEFINER RPCs (create_club,
--     join_club) that insert directly as the DB owner.
-- ============================================================

begin;

-- ==========================================================
-- 0. HELPER FUNCTIONS
--    SECURITY DEFINER so they bypass RLS on club_members.
--    STABLE because they only read data.
-- ==========================================================

CREATE OR REPLACE FUNCTION public.is_club_member(p_club_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_club_admin_or_owner(p_club_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id
      AND user_id = auth.uid()
      AND role IN ('owner', 'admin')
  );
$$;

-- Internal helper: check if caller is the club owner (not admin).
CREATE OR REPLACE FUNCTION public.is_club_owner(p_club_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_members
    WHERE club_id = p_club_id
      AND user_id = auth.uid()
      AND role = 'owner'
  );
$$;

-- ==========================================================
-- 1. clubs
--    SELECT  -> member of the club
--    INSERT  -> any authenticated user (becomes owner via RPC)
--    UPDATE  -> owner only
--    DELETE  -> owner only
-- ==========================================================

DO $$ BEGIN
  CREATE POLICY "clubs_select_member"
    ON public.clubs FOR SELECT TO authenticated
    USING (public.is_club_member(id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "clubs_insert_authenticated"
    ON public.clubs FOR INSERT TO authenticated
    WITH CHECK (created_by = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "clubs_update_owner"
    ON public.clubs FOR UPDATE TO authenticated
    USING (public.is_club_owner(id))
    WITH CHECK (public.is_club_owner(id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "clubs_delete_owner"
    ON public.clubs FOR DELETE TO authenticated
    USING (public.is_club_owner(id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ==========================================================
-- 2. club_members
--    SELECT  -> member of the same club
--    INSERT  -> NO direct policy for authenticated; managed via
--              SECURITY DEFINER RPCs (create_club, join_club)
--    UPDATE  -> own row only (sharing_level changes)
--    DELETE  -> own row (leave) OR owner/admin can remove others
-- ==========================================================

DO $$ BEGIN
  CREATE POLICY "club_members_select_member"
    ON public.club_members FOR SELECT TO authenticated
    USING (public.is_club_member(club_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Members can update only their own row (e.g. sharing_level).
DO $$ BEGIN
  CREATE POLICY "club_members_update_self"
    ON public.club_members FOR UPDATE TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Members can delete their own row (leave club).
DO $$ BEGIN
  CREATE POLICY "club_members_delete_self"
    ON public.club_members FOR DELETE TO authenticated
    USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Owner/admin can remove other members.
DO $$ BEGIN
  CREATE POLICY "club_members_delete_admin"
    ON public.club_members FOR DELETE TO authenticated
    USING (public.is_club_admin_or_owner(club_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ==========================================================
-- 3. club_rails
--    SELECT  -> club member
--    INSERT  -> club member (any member can create a rail)
--    UPDATE  -> admin/owner only
--    DELETE  -> admin/owner only
-- ==========================================================

DO $$ BEGIN
  CREATE POLICY "club_rails_select_member"
    ON public.club_rails FOR SELECT TO authenticated
    USING (public.is_club_member(club_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_rails_insert_member"
    ON public.club_rails FOR INSERT TO authenticated
    WITH CHECK (
      public.is_club_member(club_id)
      AND created_by = auth.uid()
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_rails_update_admin"
    ON public.club_rails FOR UPDATE TO authenticated
    USING (public.is_club_admin_or_owner(club_id))
    WITH CHECK (public.is_club_admin_or_owner(club_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_rails_delete_admin"
    ON public.club_rails FOR DELETE TO authenticated
    USING (public.is_club_admin_or_owner(club_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ==========================================================
-- 4. club_rail_items
--    SELECT  -> club member (via rail -> club)
--    INSERT  -> club member (application-level lock check via RPC;
--              RLS allows any member, locked-rail enforcement is in
--              the add_rail_item RPC)
--    UPDATE  -> adder or admin/owner
--    DELETE  -> adder or admin/owner
--
--    NOTE: club_id is not on this table; we join through club_rails.
-- ==========================================================

DO $$ BEGIN
  CREATE POLICY "club_rail_items_select_member"
    ON public.club_rail_items FOR SELECT TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.club_rails cr
        WHERE cr.id = rail_id
          AND public.is_club_member(cr.club_id)
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_rail_items_insert_member"
    ON public.club_rail_items FOR INSERT TO authenticated
    WITH CHECK (
      added_by = auth.uid()
      AND EXISTS (
        SELECT 1 FROM public.club_rails cr
        WHERE cr.id = rail_id
          AND public.is_club_member(cr.club_id)
          AND cr.is_locked = false
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_rail_items_delete_adder_or_admin"
    ON public.club_rail_items FOR DELETE TO authenticated
    USING (
      added_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.club_rails cr
        WHERE cr.id = rail_id
          AND public.is_club_admin_or_owner(cr.club_id)
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ==========================================================
-- 5. club_polls
--    SELECT  -> club member
--    INSERT  -> club member
--    UPDATE  -> creator or admin/owner (e.g. close poll)
--    DELETE  -> creator or admin/owner
-- ==========================================================

DO $$ BEGIN
  CREATE POLICY "club_polls_select_member"
    ON public.club_polls FOR SELECT TO authenticated
    USING (public.is_club_member(club_id));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_polls_insert_member"
    ON public.club_polls FOR INSERT TO authenticated
    WITH CHECK (
      public.is_club_member(club_id)
      AND created_by = auth.uid()
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_polls_update_creator_or_admin"
    ON public.club_polls FOR UPDATE TO authenticated
    USING (
      created_by = auth.uid()
      OR public.is_club_admin_or_owner(club_id)
    )
    WITH CHECK (
      created_by = auth.uid()
      OR public.is_club_admin_or_owner(club_id)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_polls_delete_creator_or_admin"
    ON public.club_polls FOR DELETE TO authenticated
    USING (
      created_by = auth.uid()
      OR public.is_club_admin_or_owner(club_id)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ==========================================================
-- 6. club_poll_options
--    SELECT  -> club member (via poll -> club)
--    INSERT  -> poll creator only
--    DELETE  -> poll creator only
--    (no UPDATE -- options are immutable once created)
-- ==========================================================

DO $$ BEGIN
  CREATE POLICY "club_poll_options_select_member"
    ON public.club_poll_options FOR SELECT TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.club_polls cp
        WHERE cp.id = poll_id
          AND public.is_club_member(cp.club_id)
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_poll_options_insert_creator"
    ON public.club_poll_options FOR INSERT TO authenticated
    WITH CHECK (
      EXISTS (
        SELECT 1 FROM public.club_polls cp
        WHERE cp.id = poll_id
          AND cp.created_by = auth.uid()
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_poll_options_delete_creator"
    ON public.club_poll_options FOR DELETE TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.club_polls cp
        WHERE cp.id = poll_id
          AND cp.created_by = auth.uid()
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ==========================================================
-- 7. club_votes
--    SELECT  -> club member (via poll -> club)
--    INSERT  -> club member, poll must not be closed
--              (UNIQUE(poll_id, user_id) enforces one-vote-per-poll)
--    DELETE  -> own vote only
--    (no UPDATE -- delete+reinsert to change vote)
-- ==========================================================

DO $$ BEGIN
  CREATE POLICY "club_votes_select_member"
    ON public.club_votes FOR SELECT TO authenticated
    USING (
      EXISTS (
        SELECT 1 FROM public.club_polls cp
        WHERE cp.id = poll_id
          AND public.is_club_member(cp.club_id)
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_votes_insert_member"
    ON public.club_votes FOR INSERT TO authenticated
    WITH CHECK (
      user_id = auth.uid()
      AND EXISTS (
        SELECT 1 FROM public.club_polls cp
        WHERE cp.id = poll_id
          AND public.is_club_member(cp.club_id)
          AND cp.is_closed = false
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "club_votes_delete_self"
    ON public.club_votes FOR DELETE TO authenticated
    USING (user_id = auth.uid());
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

commit;
