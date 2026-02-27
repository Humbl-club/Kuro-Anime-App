-- Drop duplicate indexes that duplicate primary key btrees (~19 MB wasted)
-- idx_chapters_id duplicates chapters_pkey
-- idx_episodes_id duplicates episodes_pkey
DROP INDEX IF EXISTS public.idx_chapters_id;
DROP INDEX IF EXISTS public.idx_episodes_id;;
