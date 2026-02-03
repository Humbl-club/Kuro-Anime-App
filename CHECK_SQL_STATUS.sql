-- ============================================
-- RUN THIS IN SUPABASE SQL EDITOR TO CHECK STATUS
-- ============================================

-- Check 1: Has user_id been migrated to TEXT?
SELECT 
    table_name,
    column_name, 
    data_type,
    CASE 
        WHEN data_type IN ('text', 'character varying') THEN '✅ MIGRATED'
        WHEN data_type = 'integer' THEN '❌ NOT MIGRATED - RUN 12_fix_user_id_type.sql'
        ELSE '⚠️ UNEXPECTED TYPE'
    END as status
FROM information_schema.columns 
WHERE table_name IN ('anime_user_lists', 'manga_user_lists')
  AND column_name = 'user_id';

-- Check 2: Does user_airing_next view exist?
SELECT 
    'user_airing_next' as object_name,
    'VIEW' as object_type,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ EXISTS'
        ELSE '❌ MISSING - RUN 10_create_user_airing_next_view.sql'
    END as status
FROM information_schema.views 
WHERE table_name = 'user_airing_next';

-- Check 3: Does airing_next RPC exist?
SELECT 
    'airing_next' as object_name,
    'FUNCTION' as object_type,
    CASE 
        WHEN COUNT(*) > 0 THEN '✅ EXISTS'
        ELSE '❌ MISSING - RUN 11_airing_next_rpc.sql'
    END as status
FROM information_schema.routines 
WHERE routine_name = 'airing_next';

-- Summary
SELECT 
    '============================================' as summary,
    'COPY RESULTS ABOVE AND SEND TO ME' as instruction,
    '============================================' as summary2;
