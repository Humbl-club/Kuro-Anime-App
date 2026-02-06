-- ============================================
-- Align user_id columns with Supabase auth.uid() (UUID/text)
-- Safely migrate by dropping dependent policies, altering type, then recreating policies.
-- ============================================

BEGIN;

-- Drop dependent policies to allow type change
DROP POLICY IF EXISTS "Users can manage their own lists" ON public.anime_user_lists;
DROP POLICY IF EXISTS "Users can manage their own lists" ON public.manga_user_lists;

-- Alter column type (integer -> text) with NOT NULL constraint
ALTER TABLE public.anime_user_lists
  ALTER COLUMN user_id TYPE text USING user_id::text,
  ALTER COLUMN user_id SET NOT NULL;

ALTER TABLE public.manga_user_lists
  ALTER COLUMN user_id TYPE text USING user_id::text,
  ALTER COLUMN user_id SET NOT NULL;

-- Recreate user-managed policies with text comparison
CREATE POLICY "Users can manage their own lists" ON public.anime_user_lists
  FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can manage their own lists" ON public.manga_user_lists
  FOR ALL
  USING (auth.uid()::text = user_id)
  WITH CHECK (auth.uid()::text = user_id);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_anime_user_lists_user_id ON public.anime_user_lists(user_id);
CREATE INDEX IF NOT EXISTS idx_manga_user_lists_user_id ON public.manga_user_lists(user_id);

-- Verify migration
DO $$
BEGIN
    RAISE NOTICE 'Migration complete. Verifying...';
    RAISE NOTICE 'anime_user_lists.user_id type: %',
        (SELECT data_type FROM information_schema.columns
         WHERE table_name = 'anime_user_lists' AND column_name = 'user_id');
    RAISE NOTICE 'manga_user_lists.user_id type: %',
        (SELECT data_type FROM information_schema.columns
         WHERE table_name = 'manga_user_lists' AND column_name = 'user_id');
END $$;

COMMIT;
