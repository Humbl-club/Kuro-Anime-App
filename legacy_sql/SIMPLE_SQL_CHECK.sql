-- Simple check - Run each query ONE AT A TIME

-- Query 1: Check user_id type (copy and run this first)
SELECT column_name, data_type
FROM information_schema.columns 
WHERE table_name = 'anime_user_lists' AND column_name = 'user_id';

-- Expected: 
-- If shows "integer" → SQL NOT run yet
-- If shows "text" or "character varying" → SQL already run ✅
