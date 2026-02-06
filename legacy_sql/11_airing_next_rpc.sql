-- ============================================
-- OPTIONAL: RPC to fetch the caller's upcoming airings within N days
-- Uses auth.uid() for scoping; SECURITY INVOKER respects RLS
-- Requires: 12_fix_user_id_type.sql must be run FIRST
-- ============================================

CREATE OR REPLACE FUNCTION public.airing_next(days integer DEFAULT 7)
RETURNS TABLE(
  anime_id int,
  title_english text,
  title_romaji text,
  next_episode_number int,
  next_airing_at timestamptz,
  list_type text,
  progress int
) AS $$
  SELECT
    a.id,
    a.title_english,
    a.title_romaji,
    a.next_episode_number,
    a.next_airing_at,
    aul.list_type,
    aul.progress
  FROM public.anime a
  JOIN public.anime_user_lists aul ON aul.anime_id = a.id
  WHERE aul.user_id = auth.uid()::text  -- Matches TEXT user_id
    AND a.next_airing_at IS NOT NULL
    AND a.next_airing_at BETWEEN now() AND (now() + (days || ' days')::interval)
  ORDER BY a.next_airing_at ASC
  LIMIT 500;
$$ LANGUAGE sql SECURITY INVOKER STABLE;

-- Notes:
-- - SECURITY INVOKER: Executes with caller's permissions (respects RLS)
-- - STABLE: Query result doesn't change within transaction (optimization)
-- - Returns up to 500 upcoming episodes within specified days window
-- - Ordered by airing date (soonest first)

-- Usage example:
-- SELECT * FROM airing_next(7);  -- Next 7 days
-- SELECT * FROM airing_next(1);  -- Next 24 hours
