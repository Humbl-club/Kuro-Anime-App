-- ============================================
-- CREATE UNIFIED VIEW: user_lists
-- Bridges anime_user_lists and manga_user_lists into a single shape expected by the app
-- ============================================

CREATE OR REPLACE VIEW public.user_lists AS
SELECT
  aul.id AS id,
  aul.user_id::text AS user_id,
  aul.anime_id AS media_id,
  'anime'::text AS media_type,
  aul.list_type AS status,
  aul.progress AS progress,
  NULL::integer AS progress_volumes,
  CASE WHEN aul.rating IS NULL THEN NULL ELSE aul.rating * 10 END AS score,
  aul.notes AS notes,
  NULL::timestamp with time zone AS started_at,
  NULL::timestamp with time zone AS completed_at,
  FALSE AS private,
  aul.created_at AS created_at,
  aul.updated_at AS updated_at
FROM public.anime_user_lists aul
UNION ALL
SELECT
  mul.id AS id,
  mul.user_id::text AS user_id,
  mul.manga_id AS media_id,
  'manga'::text AS media_type,
  mul.list_type AS status,
  mul.progress AS progress,
  NULL::integer AS progress_volumes,
  CASE WHEN mul.rating IS NULL THEN NULL ELSE mul.rating * 10 END AS score,
  mul.notes AS notes,
  NULL::timestamp with time zone AS started_at,
  NULL::timestamp with time zone AS completed_at,
  FALSE AS private,
  mul.created_at AS created_at,
  mul.updated_at AS updated_at
FROM public.manga_user_lists mul;

-- Optional helper indexes on the view via materialized pattern could be added if needed.

