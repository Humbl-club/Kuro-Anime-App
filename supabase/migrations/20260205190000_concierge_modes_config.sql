-- Concierge modes:
-- Add pre-defined "modes" (curated rails) for vibe routing.
-- These are used by the `concierge-recommend` Edge Function to pick up to 2 modes
-- deterministically (fast/cheap) before any optional LLM narration.

begin;

-- Store modes inside the existing single-row concierge_config JSON so we can tune without redeploy.
-- Modes are intentionally small + declarative.
update public.concierge_config
set config = jsonb_set(
  config,
  '{modes}',
  jsonb_build_array(
    jsonb_build_object(
      'id','premium_comedy_grownup',
      'title','Premium Comedy (grown-up)',
      'synonyms', jsonb_build_array('funny but not childish','grown up comedy','adult humor','smart comedy','comedy premium','funny premium','witzig aber nicht kindisch'),
      'required_genres', jsonb_build_array('Comedy'),
      'min_score', 75,
      'min_popularity', 3500,
      'exclude_genres', jsonb_build_array('Kids'),
      'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
    ),
    jsonb_build_object(
      'id','premium_action',
      'title','Premium Action',
      'synonyms', jsonb_build_array('hype action','action premium','best action','sakuga','fight scenes','shounen but premium'),
      'required_genres', jsonb_build_array('Action'),
      'min_score', 75,
      'min_popularity', 3500,
      'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
    ),
    jsonb_build_object(
      'id','cozy_comfort',
      'title','Cozy / Comfort',
      'synonyms', jsonb_build_array('cozy','comfort','chill','relax','gemütlich','healing','iyashikei'),
      'required_genres', jsonb_build_array('Slice of Life'),
      'min_score', 70,
      'min_popularity', 1200,
      'exclude_formats', jsonb_build_array('MUSIC')
    ),
    jsonb_build_object(
      'id','dark_serious',
      'title','Dark / Serious',
      'synonyms', jsonb_build_array('dark','serious','mature','grown up','not childish','thriller','psychological','mind game'),
      'required_genres', jsonb_build_array('Drama','Thriller','Psychological','Mystery'),
      'min_score', 78,
      'min_popularity', 2500,
      'exclude_genres', jsonb_build_array('Kids'),
      'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
    ),
    jsonb_build_object(
      'id','classics_expanded',
      'title','Classics (expanded)',
      'synonyms', jsonb_build_array('classic','classics','must watch','essentials','greatest of all time','goat'),
      'classic_year_max', 2012,
      'min_score', 80,
      'min_popularity', 1500,
      'exclude_genres', jsonb_build_array('Kids'),
      'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
    ),
    jsonb_build_object(
      'id','hidden_gems',
      'title','Hidden Gems',
      'synonyms', jsonb_build_array('hidden gems','underrated','less known','something new','new to me','surprise me'),
      'min_score', 78,
      'max_popularity', 45000,
      'exclude_genres', jsonb_build_array('Kids'),
      'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
    )
  ),
  true
)
where id = true;

commit;

