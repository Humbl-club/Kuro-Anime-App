-- ============================================
-- CREATE USER-SCOPED UPCOMING AIRINGS VIEW (ANIME)
-- Only includes titles saved by a user, with a future next_airing_at
-- Requires: 12_fix_user_id_type.sql must be run FIRST
-- ============================================

CREATE OR REPLACE VIEW public.user_airing_next AS
SELECT
  aul.user_id        AS user_id,           -- TEXT (after migration)
  a.id               AS anime_id,          -- anime PK
  a.title_english    AS title_english,
  a.title_romaji     AS title_romaji,
  a.next_episode_number AS next_episode_number,
  a.next_airing_at   AS next_airing_at,
  aul.list_type      AS list_type,         -- WATCHING, COMPLETED, etc.
  aul.progress       AS progress,          -- Episodes watched
  aul.updated_at     AS list_updated_at
FROM public.anime_user_lists aul
JOIN public.anime a ON a.id = aul.anime_id
WHERE a.next_airing_at IS NOT NULL
  AND a.next_airing_at > now()
ORDER BY a.next_airing_at ASC;

-- Notes:
-- - RLS applies on underlying tables
-- - Client should filter: WHERE user_id = auth.uid()::text
-- - Can add additional filters for date windows (e.g., next 7 days)
-- - Ordered by airing date (soonest first)

-- Verification query (optional):
-- SELECT * FROM user_airing_next WHERE user_id = auth.uid()::text LIMIT 5;
