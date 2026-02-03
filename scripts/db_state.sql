-- DB State Snapshot Queries
-- Run in Supabase SQL Editor or via psql against your project.

-- Basic entity counts
SELECT 'anime' AS table, COUNT(*) AS rows FROM anime
UNION ALL SELECT 'manga', COUNT(*) FROM manga
UNION ALL SELECT 'episodes', COUNT(*) FROM episodes
UNION ALL SELECT 'chapters', COUNT(*) FROM chapters
UNION ALL SELECT 'volumes', COUNT(*) FROM volumes
UNION ALL SELECT 'characters', COUNT(*) FROM characters
UNION ALL SELECT 'studios', COUNT(*) FROM studios
UNION ALL SELECT 'authors', COUNT(*) FROM authors
UNION ALL SELECT 'staff', COUNT(*) FROM staff
UNION ALL SELECT 'tags', COUNT(*) FROM tags
UNION ALL SELECT 'anime_characters', COUNT(*) FROM anime_characters
UNION ALL SELECT 'manga_characters', COUNT(*) FROM manga_characters
UNION ALL SELECT 'anime_studios', COUNT(*) FROM anime_studios
UNION ALL SELECT 'manga_authors', COUNT(*) FROM manga_authors
UNION ALL SELECT 'anime_staff', COUNT(*) FROM anime_staff
UNION ALL SELECT 'manga_staff', COUNT(*) FROM manga_staff
UNION ALL SELECT 'anime_tags', COUNT(*) FROM anime_tags
UNION ALL SELECT 'manga_tags', COUNT(*) FROM manga_tags
UNION ALL SELECT 'anime_user_lists', COUNT(*) FROM anime_user_lists
UNION ALL SELECT 'manga_user_lists', COUNT(*) FROM manga_user_lists
UNION ALL SELECT 'anime_comments', COUNT(*) FROM anime_comments
UNION ALL SELECT 'manga_comments', COUNT(*) FROM manga_comments
ORDER BY table;

-- Airing windows
SELECT 'airing_next_24h' AS metric, COUNT(*) AS value
FROM anime
WHERE next_airing_at BETWEEN now() AND now() + interval '24 hours';

SELECT 'airing_with_timestamp' AS metric, COUNT(*) AS value
FROM anime
WHERE next_airing_at IS NOT NULL;

-- Next chapter fields (expect low/null)
SELECT 'manga_next_chapter_known' AS metric, COUNT(*) AS value
FROM manga
WHERE next_chapter_at IS NOT NULL OR next_chapter_number IS NOT NULL;

-- Mirrored image coverage (Storage public URLs)
SELECT 'anime_cover_medium_storage' AS metric, COUNT(*) AS value
FROM anime WHERE cover_image_medium LIKE '%/storage/v1/object/public/%';

SELECT 'manga_cover_medium_storage' AS metric, COUNT(*) AS value
FROM manga WHERE cover_image_medium LIKE '%/storage/v1/object/public/%';

SELECT 'characters_image_storage' AS metric, COUNT(*) AS value
FROM characters WHERE image_large LIKE '%/storage/v1/object/public/%';

SELECT 'staff_image_storage' AS metric, COUNT(*) AS value
FROM staff WHERE image_large LIKE '%/storage/v1/object/public/%';

-- Remaining remote images (rough estimate)
SELECT 'anime_cover_medium_remote' AS metric, COUNT(*) AS value
FROM anime WHERE cover_image_medium ~* '^(http|https)://' AND cover_image_medium NOT LIKE '%/storage/v1/object/public/%';

SELECT 'manga_cover_medium_remote' AS metric, COUNT(*) AS value
FROM manga WHERE cover_image_medium ~* '^(http|https)://' AND cover_image_medium NOT LIKE '%/storage/v1/object/public/%';

-- User list breakdowns
SELECT 'anime_user_lists_by_type' AS metric, list_type, COUNT(*) AS value
FROM anime_user_lists GROUP BY list_type ORDER BY value DESC;

SELECT 'manga_user_lists_by_type' AS metric, list_type, COUNT(*) AS value
FROM manga_user_lists GROUP BY list_type ORDER BY value DESC;

-- Total public tables (sanity)
SELECT 'public_tables' AS metric, COUNT(*) AS value
FROM information_schema.tables WHERE table_schema = 'public';

