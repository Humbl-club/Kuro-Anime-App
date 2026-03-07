BEGIN;

CREATE TABLE IF NOT EXISTS public.media_relations (
  id bigserial PRIMARY KEY,
  from_media_type text NOT NULL CHECK (from_media_type IN ('ANIME', 'MANGA')),
  from_media_id int NOT NULL,
  relation_type text NOT NULL CHECK (relation_type IN ('SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF')),
  to_media_type text NOT NULL CHECK (to_media_type IN ('ANIME', 'MANGA')),
  to_media_id int NOT NULL,
  source text NOT NULL DEFAULT 'anilist',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (from_media_type, from_media_id, relation_type, to_media_type, to_media_id, source)
);

CREATE INDEX IF NOT EXISTS idx_media_relations_from
  ON public.media_relations (from_media_type, from_media_id);

CREATE INDEX IF NOT EXISTS idx_media_relations_to
  ON public.media_relations (to_media_type, to_media_id);

ALTER TABLE public.media_relations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'media_relations'
      AND policyname = 'media_relations_select_all'
  ) THEN
    CREATE POLICY media_relations_select_all
      ON public.media_relations
      FOR SELECT
      USING (true);
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'set_updated_at')
     AND NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'media_relations_set_updated_at') THEN
    CREATE TRIGGER media_relations_set_updated_at
      BEFORE UPDATE ON public.media_relations
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_media_ladder(
  p_media_type text,
  p_media_id int
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  normalized_media_type text := upper(trim(COALESCE(p_media_type, '')));
BEGIN
  IF normalized_media_type NOT IN ('ANIME', 'MANGA') THEN
    RAISE EXCEPTION 'Unsupported media type for ladder: %', p_media_type
      USING ERRCODE = '22023';
  END IF;

  RETURN (
    WITH relation_rows AS (
      SELECT
        upper(mr.relation_type) AS relation_type,
        upper(mr.to_media_type) AS media_type,
        mr.to_media_id AS media_id,
        COALESCE(a.title_english, a.title_romaji, m.title_english, m.title_romaji, 'Unknown') AS title,
        COALESCE(a.cover_image_large, m.cover_image_large) AS cover_image,
        COALESCE(a.season_year, m.start_date_year) AS year,
        COALESCE(a.format, m.format) AS format,
        CASE
          WHEN COALESCE(a.average_score, m.average_score) IS NULL THEN NULL
          ELSE round((COALESCE(a.average_score, m.average_score)::numeric) / 10.0, 1)
        END AS rating,
        COALESCE(a.popularity, m.popularity, 0) AS popularity
      FROM public.media_relations mr
      LEFT JOIN public.anime a
        ON upper(mr.to_media_type) = 'ANIME'
       AND a.id = mr.to_media_id
      LEFT JOIN public.manga m
        ON upper(mr.to_media_type) = 'MANGA'
       AND m.id = mr.to_media_id
      WHERE upper(mr.from_media_type) = normalized_media_type
        AND mr.from_media_id = p_media_id
        AND upper(mr.relation_type) IN ('SOURCE', 'ADAPTATION', 'PREQUEL', 'SEQUEL', 'SIDE_STORY', 'SPIN_OFF')
        AND (
          (
            upper(mr.to_media_type) = 'ANIME'
            AND a.id IS NOT NULL
            AND COALESCE(a.is_adult, false) = false
            AND NOT COALESCE('Hentai' = ANY(a.genres), false)
            AND NOT COALESCE('Ecchi' = ANY(a.genres), false)
          )
          OR
          (
            upper(mr.to_media_type) = 'MANGA'
            AND m.id IS NOT NULL
            AND COALESCE(m.is_adult, false) = false
            AND NOT COALESCE('Hentai' = ANY(m.genres), false)
            AND NOT COALESCE('Ecchi' = ANY(m.genres), false)
          )
        )
    )
    SELECT jsonb_build_object(
      'source_material',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'media_type', rr.media_type,
            'media_id', rr.media_id,
            'title', rr.title,
            'cover_image', rr.cover_image,
            'year', rr.year,
            'format', rr.format,
            'rating', rr.rating
          )
          ORDER BY COALESCE(rr.rating, 0) DESC, rr.popularity DESC, rr.year DESC NULLS LAST, rr.media_id ASC
        )
        FROM relation_rows rr
        WHERE rr.relation_type = 'SOURCE'
      ), '[]'::jsonb),
      'adaptations',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'media_type', rr.media_type,
            'media_id', rr.media_id,
            'title', rr.title,
            'cover_image', rr.cover_image,
            'year', rr.year,
            'format', rr.format,
            'rating', rr.rating
          )
          ORDER BY COALESCE(rr.rating, 0) DESC, rr.popularity DESC, rr.year DESC NULLS LAST, rr.media_id ASC
        )
        FROM relation_rows rr
        WHERE rr.relation_type = 'ADAPTATION'
      ), '[]'::jsonb),
      'prequels',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'media_type', rr.media_type,
            'media_id', rr.media_id,
            'title', rr.title,
            'cover_image', rr.cover_image,
            'year', rr.year,
            'format', rr.format,
            'rating', rr.rating
          )
          ORDER BY rr.year ASC NULLS LAST, COALESCE(rr.rating, 0) DESC, rr.popularity DESC, rr.media_id ASC
        )
        FROM relation_rows rr
        WHERE rr.relation_type = 'PREQUEL'
      ), '[]'::jsonb),
      'sequels',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'media_type', rr.media_type,
            'media_id', rr.media_id,
            'title', rr.title,
            'cover_image', rr.cover_image,
            'year', rr.year,
            'format', rr.format,
            'rating', rr.rating
          )
          ORDER BY rr.year ASC NULLS LAST, COALESCE(rr.rating, 0) DESC, rr.popularity DESC, rr.media_id ASC
        )
        FROM relation_rows rr
        WHERE rr.relation_type = 'SEQUEL'
      ), '[]'::jsonb),
      'side_stories',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'media_type', rr.media_type,
            'media_id', rr.media_id,
            'title', rr.title,
            'cover_image', rr.cover_image,
            'year', rr.year,
            'format', rr.format,
            'rating', rr.rating
          )
          ORDER BY rr.year ASC NULLS LAST, COALESCE(rr.rating, 0) DESC, rr.popularity DESC, rr.media_id ASC
        )
        FROM relation_rows rr
        WHERE rr.relation_type = 'SIDE_STORY'
      ), '[]'::jsonb),
      'spin_offs',
      COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'media_type', rr.media_type,
            'media_id', rr.media_id,
            'title', rr.title,
            'cover_image', rr.cover_image,
            'year', rr.year,
            'format', rr.format,
            'rating', rr.rating
          )
          ORDER BY rr.year ASC NULLS LAST, COALESCE(rr.rating, 0) DESC, rr.popularity DESC, rr.media_id ASC
        )
        FROM relation_rows rr
        WHERE rr.relation_type = 'SPIN_OFF'
      ), '[]'::jsonb)
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_media_ladder(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_media_ladder(text, int) TO anon, authenticated, service_role;

COMMIT;
