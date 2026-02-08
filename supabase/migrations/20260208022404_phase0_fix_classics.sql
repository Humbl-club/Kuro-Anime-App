-- Phase 0 Migration 5: Fix classics rail
-- Add missing cornerstone classics that should be in the top tier.
-- Idempotent via ON CONFLICT DO NOTHING.

-- Add Akira (1988, score 79, THE defining anime film)
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note, created_at, updated_at)
VALUES ('classics_anime', 'ANIME', 47, 81, 'Cornerstone classic - the film that defined anime in the West', now(), now())
ON CONFLICT DO NOTHING;

-- Add Galaxy Express 999 (1978, score 75, Leiji Matsumoto masterpiece)
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note, created_at, updated_at)
VALUES ('classics_anime', 'ANIME', 1491, 82, 'Cornerstone classic - Leiji Matsumoto space opera', now(), now())
ON CONFLICT DO NOTHING;

-- Add Macross: Do You Remember Love? (1984, score 77, definitive mecha movie)
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note, created_at, updated_at)
VALUES ('classics_anime', 'ANIME', 1089, 83, 'Cornerstone classic - the definitive Macross experience', now(), now())
ON CONFLICT DO NOTHING;

-- Add Rurouni Kenshin (1996, score 79, classic shounen)
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note, created_at, updated_at)
VALUES ('classics_anime', 'ANIME', 45, 84, 'Cornerstone classic - essential 90s shounen', now(), now())
ON CONFLICT DO NOTHING;

-- Now re-rank classics to promote these cornerstone titles higher
-- Akira should be top 15, Galaxy Express ~30, Macross ~35, Rurouni ~40
-- We'll shift existing items to make room

-- First, bump existing items at ranks 10+ up by 1 to make room for Akira at 10
UPDATE curated_rail_items
SET rank = rank + 1, updated_at = now()
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND rank >= 10 AND anilist_id != 47;

-- Place Akira at rank 10
UPDATE curated_rail_items
SET rank = 10, updated_at = now()
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND anilist_id = 47;

-- Bump existing items at ranks 31+ up by 1 for Galaxy Express
UPDATE curated_rail_items
SET rank = rank + 1, updated_at = now()
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND rank >= 31 AND anilist_id NOT IN (47, 1491);

-- Place Galaxy Express 999 at rank 31
UPDATE curated_rail_items
SET rank = 31, updated_at = now()
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND anilist_id = 1491;

-- Bump existing items at ranks 36+ up by 1 for Macross
UPDATE curated_rail_items
SET rank = rank + 1, updated_at = now()
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND rank >= 36 AND anilist_id NOT IN (47, 1491, 1089);

-- Place Macross DYRL at rank 36
UPDATE curated_rail_items
SET rank = 36, updated_at = now()
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND anilist_id = 1089;

-- Bump existing items at ranks 42+ up by 1 for Rurouni Kenshin
UPDATE curated_rail_items
SET rank = rank + 1, updated_at = now()
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND rank >= 42 AND anilist_id NOT IN (47, 1491, 1089, 45);

-- Place Rurouni Kenshin at rank 42
UPDATE curated_rail_items
SET rank = 42, updated_at = now()
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND anilist_id = 45;

-- Final re-rank to close any gaps (sequential 1..N)
WITH ranked AS (
  SELECT rail_id, media_type, anilist_id,
         ROW_NUMBER() OVER (PARTITION BY rail_id, media_type ORDER BY rank) as new_rank
  FROM curated_rail_items
  WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
)
UPDATE curated_rail_items cri
SET rank = r.new_rank,
    updated_at = now()
FROM ranked r
WHERE cri.rail_id = r.rail_id
  AND cri.media_type = r.media_type
  AND cri.anilist_id = r.anilist_id
  AND cri.rank != r.new_rank;
