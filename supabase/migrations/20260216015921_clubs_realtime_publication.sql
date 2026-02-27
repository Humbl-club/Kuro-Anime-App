
-- ============================================================
-- Add club tables to supabase_realtime publication
-- for live updates when rails/polls/votes change.
-- ============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.club_rail_items;
ALTER PUBLICATION supabase_realtime ADD TABLE public.club_polls;
ALTER PUBLICATION supabase_realtime ADD TABLE public.club_votes;
ALTER PUBLICATION supabase_realtime ADD TABLE public.club_rail_item_reactions;
;
