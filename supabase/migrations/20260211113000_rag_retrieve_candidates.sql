-- ============================================================
-- RAG retrieval RPC
-- Provides lexical candidate retrieval across title, alias and tags.
-- Used by edge function: concierge-retrieve-assist.
-- ============================================================

begin;

-- Function return shape changed (adds entity_id). Drop old signature first
-- to avoid "cannot change return type of existing function" on projects that
-- already have the previous version.
drop function if exists public.rag_retrieve_candidates(text, text, int, int, text, text[], int);

CREATE OR REPLACE FUNCTION public.rag_retrieve_candidates(
  p_query text,
  p_media_type text DEFAULT NULL,
  p_year_min int DEFAULT NULL,
  p_year_max int DEFAULT NULL,
  p_format text DEFAULT NULL,
  p_excluded_genres text[] DEFAULT '{}',
  p_limit int DEFAULT 10
)
RETURNS TABLE (
  entity_id uuid,
  anilist_id int,
  media_type text,
  canonical_title text,
  year int,
  final_score numeric,
  popularity int,
  match_source text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
WITH q AS (
  SELECT
    greatest(1, least(coalesce(p_limit, 10), 25)) AS lim,
    trim(lower(coalesce(p_query, ''))) AS query
),
base AS (
  SELECT
    e.id,
    e.anilist_id,
    e.media_type,
    e.canonical_title,
    e.year,
    e.format,
    e.popularity,
    e.normalized_title
  FROM public.rag_entity_index e
  CROSS JOIN q
  WHERE
    q.query <> ''
    AND (p_media_type IS NULL OR e.media_type = p_media_type)
    AND (p_year_min IS NULL OR e.year IS NULL OR e.year >= p_year_min)
    AND (p_year_max IS NULL OR e.year IS NULL OR e.year <= p_year_max)
    AND (p_format IS NULL OR upper(coalesce(e.format, '')) = upper(p_format))
    AND NOT EXISTS (
      SELECT 1
      FROM public.rag_entity_tags t
      WHERE
        t.entity_id = e.id
        AND t.tag_group = 'genre'
        AND t.normalized_tag = ANY (coalesce(p_excluded_genres, '{}'::text[]))
    )
),
alias_score AS (
  SELECT
    b.id,
    max(similarity(a.normalized_alias, q.query)) AS sim
  FROM base b
  JOIN public.rag_entity_aliases a ON a.entity_id = b.id
  CROSS JOIN q
  WHERE a.normalized_alias % q.query
  GROUP BY b.id
),
title_score AS (
  SELECT
    b.id,
    similarity(b.normalized_title, q.query) AS sim
  FROM base b
  CROSS JOIN q
  WHERE b.normalized_title % q.query
),
tag_score AS (
  SELECT
    b.id,
    max(similarity(t.normalized_tag, q.query)) AS sim
  FROM base b
  JOIN public.rag_entity_tags t ON t.entity_id = b.id
  CROSS JOIN q
  WHERE t.normalized_tag % q.query
  GROUP BY b.id
),
scored AS (
  SELECT
    b.*,
    coalesce(a.sim, 0) AS alias_sim,
    coalesce(ts.sim, 0) AS title_sim,
    coalesce(g.sim, 0) AS tag_sim,
    (
      coalesce(a.sim, 0) * 0.55 +
      coalesce(ts.sim, 0) * 0.35 +
      coalesce(g.sim, 0) * 0.10 +
      least(coalesce(b.popularity, 0)::numeric / 500000.0, 0.05)
    ) AS weighted
  FROM base b
  LEFT JOIN alias_score a ON a.id = b.id
  LEFT JOIN title_score ts ON ts.id = b.id
  LEFT JOIN tag_score g ON g.id = b.id
  WHERE coalesce(a.sim, 0) > 0 OR coalesce(ts.sim, 0) > 0 OR coalesce(g.sim, 0) > 0
)
SELECT
  s.id AS entity_id,
  s.anilist_id,
  s.media_type,
  s.canonical_title,
  s.year,
  round(s.weighted::numeric, 6) AS final_score,
  s.popularity,
  CASE
    WHEN s.alias_sim >= s.title_sim AND s.alias_sim >= s.tag_sim THEN 'alias'
    WHEN s.title_sim >= s.tag_sim THEN 'title'
    ELSE 'tag'
  END AS match_source
FROM scored s
ORDER BY s.weighted DESC, s.popularity DESC NULLS LAST
LIMIT (SELECT lim FROM q);
$$;

GRANT EXECUTE ON FUNCTION public.rag_retrieve_candidates(text, text, int, int, text, text[], int)
  TO anon, authenticated, service_role;

comment on function public.rag_retrieve_candidates(text, text, int, int, text, text[], int)
  is 'Lexical retrieval for concierge RAG assist using title/alias/tag trigram similarity.';

commit;
