-- Add user list tables to Realtime publication
-- Fixes silent failure where SupabaseService subscribes to changes
-- but never receives events because tables aren't in the publication
ALTER PUBLICATION supabase_realtime ADD TABLE anime_user_lists, manga_user_lists;;
