-- Fix 5 RLS policies missing initplan optimization on club_messages and club_rail_item_reactions
-- Replace auth.uid() with (SELECT auth.uid()) to enable initplan caching

BEGIN;

-- ============================================================
-- club_messages: 3 policies
-- ============================================================

-- 1. club_messages_select_member (SELECT)
DROP POLICY IF EXISTS club_messages_select_member ON public.club_messages;
CREATE POLICY club_messages_select_member ON public.club_messages
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM club_members cm
      WHERE cm.club_id = club_messages.club_id
        AND cm.user_id = (SELECT auth.uid())
    )
  );

-- 2. club_messages_insert_member (INSERT)
DROP POLICY IF EXISTS club_messages_insert_member ON public.club_messages;
CREATE POLICY club_messages_insert_member ON public.club_messages
  FOR INSERT
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
      SELECT 1
      FROM club_members cm
      WHERE cm.club_id = club_messages.club_id
        AND cm.user_id = (SELECT auth.uid())
    )
  );

-- 3. club_messages_delete_own (DELETE)
DROP POLICY IF EXISTS club_messages_delete_own ON public.club_messages;
CREATE POLICY club_messages_delete_own ON public.club_messages
  FOR DELETE
  USING (
    (SELECT auth.uid()) = user_id
  );

-- ============================================================
-- club_rail_item_reactions: 2 policies
-- ============================================================

-- 4. club_reactions_insert_member (INSERT)
DROP POLICY IF EXISTS club_reactions_insert_member ON public.club_rail_item_reactions;
CREATE POLICY club_reactions_insert_member ON public.club_rail_item_reactions
  FOR INSERT
  WITH CHECK (
    (SELECT auth.uid()) = user_id
    AND EXISTS (
      SELECT 1
      FROM club_rail_items cri
      JOIN club_rails cr ON cri.rail_id = cr.id
      WHERE cri.id = club_rail_item_reactions.rail_item_id
        AND is_club_member(cr.club_id)
    )
  );

-- 5. club_reactions_delete_own (DELETE)
DROP POLICY IF EXISTS club_reactions_delete_own ON public.club_rail_item_reactions;
CREATE POLICY club_reactions_delete_own ON public.club_rail_item_reactions
  FOR DELETE
  USING (
    (SELECT auth.uid()) = user_id
  );

COMMIT;;
