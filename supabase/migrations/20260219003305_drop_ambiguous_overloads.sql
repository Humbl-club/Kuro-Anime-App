-- Drop older create_club_poll with jsonb (weaker validation, dead code)
-- Swift uses text[] version; edge functions don't call this at all
DROP FUNCTION IF EXISTS public.create_club_poll(uuid, text, jsonb, timestamptz);

-- Drop older recommend_ids_premium without p_focus_tag_ids (ambiguous with newer version)
-- concierge-recommend calls the 5-param version with p_focus_tag_ids
DROP FUNCTION IF EXISTS public.recommend_ids_premium(text, text[], integer, boolean);;
