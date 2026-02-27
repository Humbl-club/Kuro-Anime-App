-- Tighten 5 club write policies from {public} to {authenticated}
-- Preserves exact same qual/with_check expressions, only changes role

-- 1. club_members_delete_self_or_admin
DROP POLICY IF EXISTS club_members_delete_self_or_admin ON public.club_members;
CREATE POLICY club_members_delete_self_or_admin ON public.club_members
  FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR is_club_admin_or_owner(club_id));

-- 2. club_messages_delete_own
DROP POLICY IF EXISTS club_messages_delete_own ON public.club_messages;
CREATE POLICY club_messages_delete_own ON public.club_messages
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- 3. club_messages_insert_member
DROP POLICY IF EXISTS club_messages_insert_member ON public.club_messages;
CREATE POLICY club_messages_insert_member ON public.club_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM club_members cm
      WHERE cm.club_id = club_messages.club_id AND cm.user_id = auth.uid()
    )
  );

-- 4. club_reactions_delete_own
DROP POLICY IF EXISTS club_reactions_delete_own ON public.club_rail_item_reactions;
CREATE POLICY club_reactions_delete_own ON public.club_rail_item_reactions
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- 5. club_reactions_insert_member
DROP POLICY IF EXISTS club_reactions_insert_member ON public.club_rail_item_reactions;
CREATE POLICY club_reactions_insert_member ON public.club_rail_item_reactions
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM club_rail_items cri
      JOIN club_rails cr ON cri.rail_id = cr.id
      WHERE cri.id = club_rail_item_reactions.rail_item_id AND is_club_member(cr.club_id)
    )
  );;
