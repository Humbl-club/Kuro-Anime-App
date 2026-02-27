-- Phase 0 Migration 4: Slim rails to target sizes and re-rank
-- Target sizes: gateway 50, classics 80, premium_picks 40, premium_action 50,
-- dark_serious 60, hidden_gems 50, isekai 25, movie_night 60, cozy_comfort 50,
-- romcom 50, romance_serious 50, short_complete 50, fantasy 50, comedy 50
-- For manga: similar targets

-- Delete items ranked beyond target sizes (keeping top N by current rank)
-- Then re-rank remaining items sequentially

-- ========================================
-- ANIME SLIMMING
-- ========================================

-- classics_anime: 197 -> 80
DELETE FROM curated_rail_items
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 79
);

-- cozy_comfort_anime: 148 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'cozy_comfort_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'cozy_comfort_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- hidden_gems_anime: 132 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'hidden_gems_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'hidden_gems_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- movie_night_anime: 118 -> 60
DELETE FROM curated_rail_items
WHERE rail_id = 'movie_night_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'movie_night_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 59
);

-- premium_action_anime: 117 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_action_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'premium_action_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- romance_serious_anime: 107 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'romance_serious_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'romance_serious_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- romcom_anime: 105 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'romcom_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'romcom_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- gateway_anime: 100 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'gateway_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'gateway_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- dark_serious_anime: 68 -> 60
DELETE FROM curated_rail_items
WHERE rail_id = 'dark_serious_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'dark_serious_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 59
);

-- fantasy_non_isekai_anime: 60 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'fantasy_non_isekai_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'fantasy_non_isekai_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- premium_comedy_grownup_anime: 52 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_comedy_grownup_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'premium_comedy_grownup_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- isekai_anime: 26 -> 25
DELETE FROM curated_rail_items
WHERE rail_id = 'isekai_anime' AND media_type = 'ANIME'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'isekai_anime' AND media_type = 'ANIME'
  ORDER BY rank
  LIMIT 1 OFFSET 24
);

-- ========================================
-- MANGA SLIMMING
-- ========================================

-- classics_manga: 177 -> 80
DELETE FROM curated_rail_items
WHERE rail_id = 'classics_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'classics_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 79
);

-- gateway_manga: 121 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'gateway_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'gateway_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- short_one_season_manga: 120 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'short_one_season_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'short_one_season_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- romance_serious_manga: 120 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'romance_serious_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'romance_serious_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- isekai_manga: 120 -> 25
DELETE FROM curated_rail_items
WHERE rail_id = 'isekai_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'isekai_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 24
);

-- fantasy_non_isekai_manga: 120 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'fantasy_non_isekai_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'fantasy_non_isekai_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- hidden_gems_manga: 120 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'hidden_gems_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'hidden_gems_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- romcom_manga: 120 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'romcom_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'romcom_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- dark_serious_manga: 94 -> 60
DELETE FROM curated_rail_items
WHERE rail_id = 'dark_serious_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'dark_serious_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 59
);

-- cozy_comfort_manga: 77 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'cozy_comfort_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'cozy_comfort_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- premium_action_manga: 64 -> 50
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_action_manga' AND media_type = 'MANGA'
AND rank > (
  SELECT rank FROM curated_rail_items
  WHERE rail_id = 'premium_action_manga' AND media_type = 'MANGA'
  ORDER BY rank
  LIMIT 1 OFFSET 49
);

-- premium_comedy_grownup_manga: 45 -> already within target

-- ========================================
-- RE-RANK all rails sequentially (1, 2, 3, ...)
-- ========================================
-- Use a CTE to assign new sequential ranks based on current rank order
WITH ranked AS (
  SELECT rail_id, media_type, anilist_id,
         ROW_NUMBER() OVER (PARTITION BY rail_id, media_type ORDER BY rank) as new_rank
  FROM curated_rail_items
)
UPDATE curated_rail_items cri
SET rank = r.new_rank,
    updated_at = now()
FROM ranked r
WHERE cri.rail_id = r.rail_id
  AND cri.media_type = r.media_type
  AND cri.anilist_id = r.anilist_id
  AND cri.rank != r.new_rank;;
