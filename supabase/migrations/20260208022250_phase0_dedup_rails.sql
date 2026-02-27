-- Phase 0 Migration 3: Deduplicate rails by removing shared items from less-specific rails
-- Idempotent: DELETE WHERE only removes rows that exist.

-- ========================================
-- ANIME DEDUP
-- ========================================

-- 1. Remove from premium_picks what's already in gateway
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'gateway_anime' AND media_type = 'ANIME'
);

-- 2. Remove from premium_picks what's already in dark_serious
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'dark_serious_anime' AND media_type = 'ANIME'
);

-- 3. Remove from premium_picks what's already in premium_action
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'premium_action_anime' AND media_type = 'ANIME'
);

-- 4. Remove from premium_picks what's already in classics
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
);

-- 5. Remove pre-2005 classics from gateway (keep essential gateway titles)
DELETE FROM curated_rail_items
WHERE rail_id = 'gateway_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT cri.anilist_id FROM curated_rail_items cri
  JOIN anime a ON cri.anilist_id = a.anilist_id
  WHERE cri.rail_id = 'classics_anime' AND cri.media_type = 'ANIME'
  AND a.season_year < 2005
)
AND anilist_id NOT IN (
  1, 5114, 20, 1535, 16498, 21, 11061, 30, 9253, 1575, 269, 5081
);

-- 6. Remove from premium_comedy what's already in cozy_comfort
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_comedy_grownup_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'cozy_comfort_anime' AND media_type = 'ANIME'
);

-- 7. Remove from premium_comedy what's already in romcom
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_comedy_grownup_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'romcom_anime' AND media_type = 'ANIME'
);

-- 8. Remove from short_one_season what's already in gateway
DELETE FROM curated_rail_items
WHERE rail_id = 'short_one_season_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'gateway_anime' AND media_type = 'ANIME'
);

-- 9. Remove from short_one_season what's already in premium_picks
DELETE FROM curated_rail_items
WHERE rail_id = 'short_one_season_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
);

-- 10. Remove from short_one_season what's already in premium_action
DELETE FROM curated_rail_items
WHERE rail_id = 'short_one_season_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'premium_action_anime' AND media_type = 'ANIME'
);

-- 11. Remove from fantasy_non_isekai what's already in premium_action
DELETE FROM curated_rail_items
WHERE rail_id = 'fantasy_non_isekai_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'premium_action_anime' AND media_type = 'ANIME'
);

-- 12. Remove from fantasy_non_isekai what's already in gateway
DELETE FROM curated_rail_items
WHERE rail_id = 'fantasy_non_isekai_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'gateway_anime' AND media_type = 'ANIME'
);

-- 13. Remove pre-2005 classics from dark_serious
DELETE FROM curated_rail_items
WHERE rail_id = 'dark_serious_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  SELECT cri.anilist_id FROM curated_rail_items cri
  JOIN anime a ON cri.anilist_id = a.anilist_id
  WHERE cri.rail_id = 'classics_anime' AND cri.media_type = 'ANIME'
  AND a.season_year < 2005
);

-- ========================================
-- MANGA DEDUP
-- ========================================

-- 1. Remove from premium_picks_manga what's already in gateway_manga (94%!)
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'gateway_manga' AND media_type = 'MANGA'
);

-- 2. Remove from premium_picks_manga what's already in dark_serious_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'dark_serious_manga' AND media_type = 'MANGA'
);

-- 3. Remove from premium_picks_manga what's already in classics_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'classics_manga' AND media_type = 'MANGA'
);

-- 4. Remove from premium_picks_manga what's already in premium_action_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'premium_action_manga' AND media_type = 'MANGA'
);

-- 5. Remove pre-2005 classics from gateway_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'gateway_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT cri.anilist_id FROM curated_rail_items cri
  JOIN manga m ON cri.anilist_id = m.anilist_id
  WHERE cri.rail_id = 'classics_manga' AND cri.media_type = 'MANGA'
  AND m.start_date_year < 2005
);

-- 6. Remove pre-2005 classics from dark_serious_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'dark_serious_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT cri.anilist_id FROM curated_rail_items cri
  JOIN manga m ON cri.anilist_id = m.anilist_id
  WHERE cri.rail_id = 'classics_manga' AND cri.media_type = 'MANGA'
  AND m.start_date_year < 2005
);

-- 7. Remove from premium_comedy_grownup_manga what's already in romcom_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_comedy_grownup_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'romcom_manga' AND media_type = 'MANGA'
);

-- 8. Remove from premium_comedy_grownup_manga what's already in cozy_comfort_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_comedy_grownup_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'cozy_comfort_manga' AND media_type = 'MANGA'
);

-- 9. Remove from premium_action_manga what's already in gateway_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_action_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'gateway_manga' AND media_type = 'MANGA'
);

-- 10. Remove from cozy_comfort_manga what's already in romcom_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'cozy_comfort_manga' AND media_type = 'MANGA'
AND anilist_id IN (
  SELECT anilist_id FROM curated_rail_items
  WHERE rail_id = 'romcom_manga' AND media_type = 'MANGA'
);;
