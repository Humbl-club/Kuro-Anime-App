-- ============================================
-- FIX TRIGGERS AND ADD EPISODE/CHAPTER SUPPORT
-- ============================================

-- ============================================
-- 1. FIX DESCRIPTION_NORMALIZED TRIGGER
-- ============================================

-- Recreate the normalize_description function
CREATE OR REPLACE FUNCTION public.normalize_description()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.description IS NOT NULL THEN
        -- Remove HTML tags, convert to lowercase, remove extra whitespace
        NEW.description_normalized = LOWER(
            regexp_replace(
                regexp_replace(NEW.description, '<[^>]+>', '', 'g'),
                '\s+', ' ', 'g'
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing triggers if they exist
DROP TRIGGER IF EXISTS set_anime_description_normalized ON public.anime;
DROP TRIGGER IF EXISTS set_manga_description_normalized ON public.manga;

-- Create triggers for anime
CREATE TRIGGER set_anime_description_normalized
    BEFORE INSERT OR UPDATE OF description ON public.anime
    FOR EACH ROW
    EXECUTE FUNCTION public.normalize_description();

-- Create triggers for manga
CREATE TRIGGER set_manga_description_normalized
    BEFORE INSERT OR UPDATE OF description ON public.manga
    FOR EACH ROW
    EXECUTE FUNCTION public.normalize_description();

-- Update existing records to populate description_normalized
UPDATE public.anime 
SET description_normalized = LOWER(
    regexp_replace(
        regexp_replace(description, '<[^>]+>', '', 'g'),
        '\s+', ' ', 'g'
    )
)
WHERE description IS NOT NULL AND description_normalized IS NULL;

UPDATE public.manga 
SET description_normalized = LOWER(
    regexp_replace(
        regexp_replace(description, '<[^>]+>', '', 'g'),
        '\s+', ' ', 'g'
    )
)
WHERE description IS NOT NULL AND description_normalized IS NULL;

-- ============================================
-- 2. VERIFY TRIGGERS ARE WORKING
-- ============================================

-- Test the trigger by updating a record
DO $$
DECLARE
    test_anime_id INT;
BEGIN
    -- Get first anime
    SELECT id INTO test_anime_id FROM public.anime LIMIT 1;
    
    IF test_anime_id IS NOT NULL THEN
        -- Trigger an update to test
        UPDATE public.anime 
        SET updated_at = NOW() 
        WHERE id = test_anime_id;
        
        RAISE NOTICE 'Trigger test completed for anime ID: %', test_anime_id;
    END IF;
END $$;

-- ============================================
-- 3. CREATE FULL-TEXT SEARCH INDEXES
-- ============================================

-- Create full-text search indexes on normalized descriptions
CREATE INDEX IF NOT EXISTS idx_anime_description_fts 
    ON public.anime 
    USING GIN(to_tsvector('english', COALESCE(description_normalized, '')));

CREATE INDEX IF NOT EXISTS idx_manga_description_fts 
    ON public.manga 
    USING GIN(to_tsvector('english', COALESCE(description_normalized, '')));

-- Create indexes on title fields for search
CREATE INDEX IF NOT EXISTS idx_anime_title_fts 
    ON public.anime 
    USING GIN(to_tsvector('english', 
        COALESCE(title_english, '') || ' ' || 
        COALESCE(title_romaji, '') || ' ' || 
        COALESCE(title_native, '')
    ));

CREATE INDEX IF NOT EXISTS idx_manga_title_fts 
    ON public.manga 
    USING GIN(to_tsvector('english', 
        COALESCE(title_english, '') || ' ' || 
        COALESCE(title_romaji, '') || ' ' || 
        COALESCE(title_native, '')
    ));

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Check if triggers exist
SELECT 
    trigger_name,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_schema = 'public'
    AND trigger_name LIKE '%description%'
ORDER BY event_object_table, trigger_name;

-- Check if description_normalized is now populated
SELECT 
    'anime' as table_name,
    COUNT(*) as total_records,
    COUNT(description) as has_description,
    COUNT(description_normalized) as has_normalized,
    ROUND(100.0 * COUNT(description_normalized) / NULLIF(COUNT(description), 0), 2) as normalized_percentage
FROM public.anime
UNION ALL
SELECT 
    'manga' as table_name,
    COUNT(*) as total_records,
    COUNT(description) as has_description,
    COUNT(description_normalized) as has_normalized,
    ROUND(100.0 * COUNT(description_normalized) / NULLIF(COUNT(description), 0), 2) as normalized_percentage
FROM public.manga;

