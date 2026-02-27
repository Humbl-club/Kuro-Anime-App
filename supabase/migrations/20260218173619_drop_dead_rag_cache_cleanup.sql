-- Drop dead rag_cache_cleanup() function
-- The active cron job uses rag_cleanup_expired_cache() instead
-- This function has no callers
DROP FUNCTION IF EXISTS public.rag_cache_cleanup();;
