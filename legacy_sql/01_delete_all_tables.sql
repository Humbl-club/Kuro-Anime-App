-- ============================================
-- DELETE ALL TABLES SCRIPT
-- Clean slate for comprehensive rebuild
-- ============================================

-- Drop all tables in correct order (respecting foreign key constraints)

-- User interaction tables first
DROP TABLE IF EXISTS anime_user_lists CASCADE;
DROP TABLE IF EXISTS manga_user_lists CASCADE;
DROP TABLE IF EXISTS anime_comments CASCADE;
DROP TABLE IF EXISTS manga_comments CASCADE;

-- Relationship tables
DROP TABLE IF EXISTS anime_characters CASCADE;
DROP TABLE IF EXISTS manga_characters CASCADE;
DROP TABLE IF EXISTS anime_studios CASCADE;
DROP TABLE IF EXISTS manga_studios CASCADE;
DROP TABLE IF EXISTS anime_authors CASCADE;
DROP TABLE IF EXISTS manga_authors CASCADE;
DROP TABLE IF EXISTS anime_staff CASCADE;
DROP TABLE IF EXISTS manga_staff CASCADE;
DROP TABLE IF EXISTS anime_tags CASCADE;
DROP TABLE IF EXISTS manga_tags CASCADE;

-- Episode/Chapter/Volume tables
DROP TABLE IF EXISTS episodes CASCADE;
DROP TABLE IF EXISTS chapters CASCADE;
DROP TABLE IF EXISTS volumes CASCADE;

-- Core entity tables
DROP TABLE IF EXISTS characters CASCADE;
DROP TABLE IF EXISTS studios CASCADE;
DROP TABLE IF EXISTS authors CASCADE;
DROP TABLE IF EXISTS staff CASCADE;
DROP TABLE IF EXISTS tags CASCADE;

-- Main media tables
DROP TABLE IF EXISTS anime CASCADE;
DROP TABLE IF EXISTS manga CASCADE;

-- Legacy tables (if they exist)
DROP TABLE IF EXISTS user_lists CASCADE;
DROP TABLE IF EXISTS streaming_links CASCADE;
DROP TABLE IF EXISTS reading_links CASCADE;
DROP TABLE IF EXISTS anime_relations CASCADE;
DROP TABLE IF EXISTS recommendations CASCADE;
DROP TABLE IF EXISTS rankings CASCADE;
DROP TABLE IF EXISTS score_distribution CASCADE;

-- Drop any views
DROP VIEW IF EXISTS popular_anime CASCADE;
DROP VIEW IF EXISTS popular_manga CASCADE;
DROP VIEW IF EXISTS currently_airing_anime CASCADE;

-- Drop any functions
DROP FUNCTION IF EXISTS find_anime_by_ids CASCADE;
DROP FUNCTION IF EXISTS update_updated_at_column CASCADE;

-- Drop any triggers
DROP TRIGGER IF EXISTS update_anime_updated_at ON anime;
DROP TRIGGER IF EXISTS update_manga_updated_at ON manga;
DROP TRIGGER IF EXISTS update_episodes_updated_at ON episodes;
DROP TRIGGER IF EXISTS update_chapters_updated_at ON chapters;
DROP TRIGGER IF EXISTS update_volumes_updated_at ON volumes;
DROP TRIGGER IF EXISTS update_characters_updated_at ON characters;
DROP TRIGGER IF EXISTS update_studios_updated_at ON studios;
DROP TRIGGER IF EXISTS update_authors_updated_at ON authors;
DROP TRIGGER IF EXISTS update_staff_updated_at ON staff;
DROP TRIGGER IF EXISTS update_tags_updated_at ON tags;

-- Drop any sequences
DROP SEQUENCE IF EXISTS anime_id_seq CASCADE;
DROP SEQUENCE IF EXISTS manga_id_seq CASCADE;
DROP SEQUENCE IF EXISTS episodes_id_seq CASCADE;
DROP SEQUENCE IF EXISTS chapters_id_seq CASCADE;
DROP SEQUENCE IF EXISTS volumes_id_seq CASCADE;
DROP SEQUENCE IF EXISTS characters_id_seq CASCADE;
DROP SEQUENCE IF EXISTS studios_id_seq CASCADE;
DROP SEQUENCE IF EXISTS authors_id_seq CASCADE;
DROP SEQUENCE IF EXISTS staff_id_seq CASCADE;
DROP SEQUENCE IF EXISTS tags_id_seq CASCADE;

-- Drop any custom types
DROP TYPE IF EXISTS list_type CASCADE;
DROP TYPE IF EXISTS media_type CASCADE;

-- Reset any extensions (if needed)
-- DROP EXTENSION IF EXISTS "uuid-ossp" CASCADE;

-- Verify all tables are dropped
SELECT 
    schemaname,
    tablename 
FROM pg_tables 
WHERE schemaname = 'public' 
    AND tablename NOT IN ('spatial_ref_sys', 'geography_columns', 'geometry_columns')
ORDER BY tablename;

-- If any tables remain, they will be listed above
-- If no output, all tables have been successfully dropped

