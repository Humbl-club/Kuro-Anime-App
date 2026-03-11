BEGIN;

-- Add source_author_name to primary_source, total_franchise_count, and
-- alternate_adaptation_summary to the get_media_ladder response.

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
        COALESCE(a.popularity, m.popularity, 0) AS popularity,
        CASE COALESCE(a.format, m.format, '')
          WHEN 'TV' THEN 0
          WHEN 'MOVIE' THEN 1
          WHEN 'ONA' THEN 2
          WHEN 'OVA' THEN 3
          WHEN 'TV_SHORT' THEN 4
          WHEN 'SPECIAL' THEN 6
          WHEN 'MUSIC' THEN 7
          ELSE 5
        END AS format_priority
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
    ),
    source_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'SOURCE'
      ORDER BY COALESCE(rating, 0) DESC, popularity DESC, year DESC NULLS LAST, media_id ASC
    ),
    adaptation_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'ADAPTATION'
      ORDER BY format_priority ASC, COALESCE(rating, 0) DESC, popularity DESC, year DESC NULLS LAST, media_id ASC
    ),
    prequel_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'PREQUEL'
      ORDER BY year ASC NULLS LAST, COALESCE(rating, 0) DESC, popularity DESC, media_id ASC
    ),
    sequel_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'SEQUEL'
      ORDER BY year ASC NULLS LAST, COALESCE(rating, 0) DESC, popularity DESC, media_id ASC
    ),
    side_story_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'SIDE_STORY'
      ORDER BY year ASC NULLS LAST, COALESCE(rating, 0) DESC, popularity DESC, media_id ASC
    ),
    spin_off_rows AS (
      SELECT * FROM relation_rows
      WHERE relation_type = 'SPIN_OFF'
      ORDER BY year ASC NULLS LAST, COALESCE(rating, 0) DESC, popularity DESC, media_id ASC
    ),
    curated AS (
      SELECT
        EXISTS (SELECT 1 FROM source_rows) AS has_source,
        EXISTS (SELECT 1 FROM adaptation_rows) AS has_adaptation,
        EXISTS (SELECT 1 FROM prequel_rows) OR EXISTS (SELECT 1 FROM sequel_rows) AS has_chronology,
        EXISTS (SELECT 1 FROM side_story_rows) OR EXISTS (SELECT 1 FROM spin_off_rows) AS has_companions
    ),
    primary_source AS (
      SELECT
        media_type, media_id, title, cover_image, year, format, rating,
        'Original source'::text AS reason_label
      FROM source_rows
      LIMIT 1
    ),
    -- Resolve author name for the primary source when it lives in the manga table
    -- (covers both MANGA and NOVEL formats since light novels are stored as manga).
    source_author AS (
      SELECT au.name_full
      FROM primary_source ps
      JOIN public.manga_authors ma ON ma.manga_id = ps.media_id
      JOIN public.authors au ON au.id = ma.author_id
      WHERE ps.media_type = 'MANGA'
      ORDER BY
        CASE WHEN lower(COALESCE(ma.role, '')) IN ('story', 'original creator', 'story & art', 'original story') THEN 0 ELSE 1 END,
        ma.author_id ASC
      LIMIT 1
    ),
    primary_adaptation AS (
      SELECT
        media_type, media_id, title, cover_image, year, format, rating,
        'Most relevant adaptation'::text AS reason_label
      FROM adaptation_rows
      LIMIT 1
    ),
    entry_point AS (
      SELECT * FROM (
        SELECT media_type, media_id, title, cover_image, year, format, rating, 'Best starting point'::text AS reason_label, 1 AS priority
        FROM prequel_rows
        LIMIT 1
      ) q
      UNION ALL
      SELECT * FROM (
        SELECT media_type, media_id, title, cover_image, year, format, rating, 'Best starting point'::text AS reason_label, 2 AS priority
        FROM source_rows
        LIMIT 1
      ) q
      UNION ALL
      SELECT * FROM (
        SELECT media_type, media_id, title, cover_image, year, format, rating, 'Best starting point'::text AS reason_label, 3 AS priority
        FROM adaptation_rows
        LIMIT 1
      ) q
      ORDER BY priority
      LIMIT 1
    ),
    next_step AS (
      SELECT * FROM (
        SELECT media_type, media_id, title, cover_image, year, format, rating, 'Direct continuation'::text AS reason_label, 1 AS priority
        FROM sequel_rows
        LIMIT 1
      ) q
      UNION ALL
      SELECT * FROM (
        SELECT pa.media_type, pa.media_id, pa.title, pa.cover_image, pa.year, pa.format, pa.rating, pa.reason_label, 2 AS priority
        FROM primary_adaptation pa
        WHERE NOT EXISTS (
          SELECT 1 FROM entry_point ep
          WHERE ep.media_type = pa.media_type AND ep.media_id = pa.media_id
        )
      ) q
      UNION ALL
      SELECT * FROM (
        SELECT ps.media_type, ps.media_id, ps.title, ps.cover_image, ps.year, ps.format, ps.rating, ps.reason_label, 3 AS priority
        FROM primary_source ps
        WHERE NOT EXISTS (
          SELECT 1 FROM entry_point ep
          WHERE ep.media_type = ps.media_type AND ep.media_id = ps.media_id
        )
      ) q
      ORDER BY priority
      LIMIT 1
    ),
    -- First adaptation that is NOT the current item, for prose summary
    alt_adaptation AS (
      SELECT year, format
      FROM adaptation_rows
      WHERE NOT (media_type = normalized_media_type AND media_id = p_media_id)
      LIMIT 1
    )
    SELECT jsonb_build_object(
      'source_material',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM source_rows rr
      ), '[]'::jsonb),
      'adaptations',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM adaptation_rows rr
      ), '[]'::jsonb),
      'prequels',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM prequel_rows rr
      ), '[]'::jsonb),
      'sequels',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM sequel_rows rr
      ), '[]'::jsonb),
      'side_stories',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM side_story_rows rr
      ), '[]'::jsonb),
      'spin_offs',
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'media_type', rr.media_type,
          'media_id', rr.media_id,
          'title', rr.title,
          'cover_image', rr.cover_image,
          'year', rr.year,
          'format', rr.format,
          'rating', rr.rating
        ))
        FROM spin_off_rows rr
      ), '[]'::jsonb),
      'entry_point', (SELECT to_jsonb(ep) - 'priority' FROM entry_point ep),
      'next_step', (SELECT to_jsonb(ns) - 'priority' FROM next_step ns),
      'primary_source', (
        SELECT to_jsonb(ps) || jsonb_build_object(
          'source_author_name', (SELECT sa.name_full FROM source_author sa)
        )
        FROM primary_source ps
      ),
      'primary_adaptation', (SELECT to_jsonb(pa) FROM primary_adaptation pa),
      'coverage_status', (
        SELECT CASE
          WHEN (has_source::int + has_adaptation::int + has_chronology::int) >= 2 THEN 'strong'
          WHEN has_source OR has_adaptation OR has_chronology THEN 'partial'
          WHEN has_companions THEN 'minimal'
          ELSE 'minimal'
        END
        FROM curated
      ),
      'franchise_note', (
        SELECT CASE
          WHEN (has_source::int + has_adaptation::int + has_chronology::int) >= 2 AND has_source THEN 'Start with the source, then follow the main adaptation path.'
          WHEN (has_source::int + has_adaptation::int + has_chronology::int) >= 2 AND has_adaptation THEN 'Kuro found the clearest adaptation path for this title.'
          WHEN has_source OR has_adaptation OR has_chronology OR has_companions THEN 'Kuro found a partial path through this franchise.'
          ELSE NULL
        END
        FROM curated
      ),
      'total_franchise_count', (
        SELECT (SELECT count(*) FROM relation_rows) + 1
      ),
      'alternate_adaptation_summary', (
        SELECT
          CASE
            WHEN aa.year IS NOT NULL AND aa.format IS NOT NULL THEN
              aa.year::text || ' ' || lower(aa.format) || ' series'
            WHEN aa.year IS NOT NULL THEN
              aa.year::text || ' adaptation'
            WHEN aa.format IS NOT NULL THEN
              lower(aa.format) || ' series'
            ELSE NULL
          END
        FROM alt_adaptation aa
      )
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_media_ladder(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_media_ladder(text, int) TO anon, authenticated, service_role;

COMMIT;
