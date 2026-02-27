
-- 1B: Drop unused FTS/trigram indexes superseded by title_search MV,
-- duplicate genre indexes, and unused sort-by-creation indexes.
-- Total ~55 MB freed. PKs, unique constraints, FK indexes kept.

DROP INDEX IF EXISTS idx_anime_search_tsv;
DROP INDEX IF EXISTS idx_manga_search_tsv;
DROP INDEX IF EXISTS idx_anime_title_trgm;
DROP INDEX IF EXISTS idx_manga_title_trgm;
DROP INDEX IF EXISTS idx_anime_title_fts;
DROP INDEX IF EXISTS idx_manga_title_fts;
DROP INDEX IF EXISTS idx_anime_description_fts;
DROP INDEX IF EXISTS idx_manga_description_fts;
DROP INDEX IF EXISTS idx_manga_genres;
DROP INDEX IF EXISTS idx_manga_genres_gin;
DROP INDEX IF EXISTS idx_anime_created_id;
DROP INDEX IF EXISTS idx_manga_created_id;

-- 1C: Merge duplicate DELETE policies on club_members into a single OR policy.

DROP POLICY IF EXISTS club_members_delete_self ON club_members;
DROP POLICY IF EXISTS club_members_delete_admin ON club_members;

CREATE POLICY club_members_delete_self_or_admin ON club_members
  FOR DELETE
  USING (
    user_id = (SELECT auth.uid())
    OR public.is_club_admin_or_owner(club_id)
  );

-- 1E: Mirror pipeline health check function.
-- Returns JSONB with run stats and alerting info.
-- Read-only, no side effects.

CREATE OR REPLACE FUNCTION check_mirror_health(
  p_lookback_hours INT DEFAULT 24,
  p_max_consecutive_failures INT DEFAULT 3
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  result JSONB;
  v_total INT;
  v_errors INT;
  v_skipped INT;
  v_success INT;
  v_consecutive_failures INT := 0;
  v_last_success TIMESTAMPTZ;
  rec RECORD;
BEGIN
  -- Aggregate stats for the lookback window
  SELECT
    count(*),
    count(*) FILTER (WHERE status = 'error'),
    count(*) FILTER (WHERE status = 'skipped'),
    count(*) FILTER (WHERE status = 'success')
  INTO v_total, v_errors, v_skipped, v_success
  FROM mirror_runs
  WHERE started_at >= now() - (p_lookback_hours || ' hours')::interval;

  -- Last successful run
  SELECT max(finished_at) INTO v_last_success
  FROM mirror_runs
  WHERE status = 'success';

  -- Count consecutive recent failures (most recent first)
  FOR rec IN
    SELECT status
    FROM mirror_runs
    ORDER BY started_at DESC
    LIMIT 20
  LOOP
    IF rec.status = 'error' THEN
      v_consecutive_failures := v_consecutive_failures + 1;
    ELSE
      EXIT;
    END IF;
  END LOOP;

  result := jsonb_build_object(
    'lookback_hours', p_lookback_hours,
    'total_runs', v_total,
    'errors', v_errors,
    'skipped', v_skipped,
    'success', v_success,
    'consecutive_failures', v_consecutive_failures,
    'alert', v_consecutive_failures >= p_max_consecutive_failures,
    'last_success', v_last_success
  );

  RETURN result;
END;
$$;
;
