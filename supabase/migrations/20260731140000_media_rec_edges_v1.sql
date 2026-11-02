-- Realm Graph Stage 3a: AniList community recommendation edges (probationary)
-- Spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md §7
--
-- "Users who liked X also recommend Y" edges imported in bulk from AniList by
-- scripts/import_anilist_rec_edges.js. Probationary association data: nothing in
-- the app consumes these edges until the evaluation harness (precision@10 of raw
-- edges vs realm-gated graph vs edges∩gate) proves they earn a place. We read
-- their data; we don't inherit their taste.
--
-- media ids are Kuro-internal (anime.id / manga.id), matching media_relations.

BEGIN;

-- ============================================================
-- 1. TABLE
-- ============================================================

CREATE TABLE public.media_rec_edges (
  from_media_type text        NOT NULL CHECK (from_media_type IN ('ANIME', 'MANGA')),
  from_media_id   integer     NOT NULL,
  to_media_type   text        NOT NULL CHECK (to_media_type IN ('ANIME', 'MANGA')),
  to_media_id     integer     NOT NULL,
  rating          integer     NOT NULL DEFAULT 0,
  source          text        NOT NULL DEFAULT 'anilist',
  imported_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (from_media_type, from_media_id, to_media_type, to_media_id)
);

CREATE INDEX idx_media_rec_edges_from_rating
  ON public.media_rec_edges (from_media_type, from_media_id, rating DESC);

-- ============================================================
-- 2. RLS
-- ============================================================

ALTER TABLE public.media_rec_edges ENABLE ROW LEVEL SECURITY;

-- Public read: edges are non-personal catalog metadata, same posture as media_relations.
CREATE POLICY "media_rec_edges_select_all" ON public.media_rec_edges
  FOR SELECT
  USING (true);

-- Writes only via upsert_rec_edges() (SECURITY DEFINER): no INSERT/UPDATE/DELETE
-- policies, so RLS default-deny covers direct writes from client roles.

-- ============================================================
-- 3. RPC: bulk upsert (rate-limited)
-- ============================================================

CREATE OR REPLACE FUNCTION public.upsert_rec_edges(p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _hits     int;
  _affected int;
  _row      jsonb;
BEGIN
  -- Rate limit: 200 calls per hour per user. service_role calls carry no uid,
  -- so they share one global bucket. Probationary grant: authenticated callers
  -- are accepted for the import window; this may be revoked to service_role-only
  -- once the bulk import completes.
  _hits := public.rate_limit_hit(
    'rec_edges_upsert:' || COALESCE(auth.uid()::text, 'service_role'),
    3600
  );
  IF _hits > 200 THEN
    RAISE EXCEPTION 'RATE_LIMITED' USING ERRCODE = 'P0001';
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_ROWS: expected a jsonb array' USING ERRCODE = 'P0001';
  END IF;
  IF jsonb_array_length(p_rows) > 500 THEN
    RAISE EXCEPTION 'TOO_MANY_ROWS: max 500 rows per call' USING ERRCODE = 'P0001';
  END IF;

  FOR _row IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    IF jsonb_typeof(_row) <> 'object' THEN
      RAISE EXCEPTION 'INVALID_ROW: each row must be an object' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(_row->>'from_media_type', '') NOT IN ('ANIME', 'MANGA')
       OR COALESCE(_row->>'to_media_type', '') NOT IN ('ANIME', 'MANGA') THEN
      RAISE EXCEPTION 'INVALID_MEDIA_TYPE' USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_typeof(_row->'from_media_id') <> 'number'
       OR jsonb_typeof(_row->'to_media_id') <> 'number'
       OR (_row->>'from_media_id')::numeric < 1
       OR (_row->>'to_media_id')::numeric < 1
       OR (_row->>'from_media_id')::numeric <> floor((_row->>'from_media_id')::numeric)
       OR (_row->>'to_media_id')::numeric <> floor((_row->>'to_media_id')::numeric)
       OR (_row->>'from_media_id')::numeric > 2147483647
       OR (_row->>'to_media_id')::numeric > 2147483647 THEN
      RAISE EXCEPTION 'INVALID_MEDIA_ID: ids must be positive integers' USING ERRCODE = 'P0001';
    END IF;
    IF _row->'rating' IS NOT NULL AND _row->'rating' <> 'null'::jsonb THEN
      IF jsonb_typeof(_row->'rating') <> 'number'
         OR (_row->>'rating')::numeric < 0
         OR (_row->>'rating')::numeric > 100000
         OR (_row->>'rating')::numeric <> floor((_row->>'rating')::numeric) THEN
        RAISE EXCEPTION 'INVALID_RATING: rating must be an integer 0..100000' USING ERRCODE = 'P0001';
      END IF;
    END IF;
  END LOOP;

  -- DISTINCT ON collapses duplicate edges inside one batch (keeps the highest
  -- rating, matching the ON CONFLICT greatest() merge below).
  INSERT INTO public.media_rec_edges (from_media_type, from_media_id, to_media_type, to_media_id, rating, source)
  SELECT DISTINCT ON (r.from_media_type, r.from_media_id, r.to_media_type, r.to_media_id)
    r.from_media_type, r.from_media_id, r.to_media_type, r.to_media_id, r.rating, r.source
  FROM (
    SELECT
      _e->>'from_media_type'                            AS from_media_type,
      (_e->>'from_media_id')::integer                   AS from_media_id,
      _e->>'to_media_type'                              AS to_media_type,
      (_e->>'to_media_id')::integer                     AS to_media_id,
      COALESCE((_e->>'rating')::integer, 0)             AS rating,
      COALESCE(NULLIF(TRIM(_e->>'source'), ''), 'anilist') AS source
    FROM jsonb_array_elements(p_rows) AS _e
  ) r
  ORDER BY r.from_media_type, r.from_media_id, r.to_media_type, r.to_media_id, r.rating DESC
  ON CONFLICT (from_media_type, from_media_id, to_media_type, to_media_id)
  DO UPDATE SET rating = greatest(excluded.rating, media_rec_edges.rating);

  GET DIAGNOSTICS _affected = ROW_COUNT;
  RETURN _affected;
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_rec_edges(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.upsert_rec_edges(jsonb) TO authenticated, service_role;

COMMIT;
