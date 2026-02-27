-- Concierge modes v2:
-- - Canonical small set (deterministic router)
-- - Add rail_id for pinned Classics/Gateway rails
-- - Add router_llm tuning knobs

begin;
update public.concierge_config
set config =
  jsonb_set(
    jsonb_set(
      config,
      '{modes}',
      jsonb_build_array(
        jsonb_build_object(
          'id','premium_picks',
          'title','Premium Picks',
          'synonyms', jsonb_build_array('something good','recommend something','surprise me','premium','best','top tier'),
          'min_score', 75,
          'min_popularity', 2500,
          'exclude_genres', jsonb_build_array('Kids'),
          'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
        ),
        jsonb_build_object(
          'id','gateway_start_here',
          'title','Start Here',
          'synonyms', jsonb_build_array('first anime','first manga','where do i start','getting into anime','getting into manga','anime anfangen','manga anfangen'),
          'rail_id', jsonb_build_object('anime','gateway_anime','manga','gateway_manga')
        ),
        jsonb_build_object(
          'id','premium_action',
          'title','Premium Action',
          'synonyms', jsonb_build_array('action','hype action','action premium','best action','sakuga','fight scenes'),
          'required_genres', jsonb_build_array('Action'),
          'min_score', 75,
          'min_popularity', 3500,
          'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
        ),
        jsonb_build_object(
          'id','premium_comedy_grownup',
          'title','Premium Comedy (grown-up)',
          'synonyms', jsonb_build_array('funny but not childish','grown up comedy','adult humor','smart comedy','witzig aber nicht kindisch'),
          'required_genres', jsonb_build_array('Comedy'),
          'min_score', 75,
          'min_popularity', 3500,
          'exclude_genres', jsonb_build_array('Kids'),
          'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
        ),
        jsonb_build_object(
          'id','cozy_comfort',
          'title','Cozy / Comfort',
          'synonyms', jsonb_build_array('cozy','comfort','chill','relax','healing','iyashikei','gemütlich'),
          'required_genres', jsonb_build_array('Slice of Life'),
          'min_score', 70,
          'min_popularity', 1200,
          'exclude_formats', jsonb_build_array('MUSIC')
        ),
        jsonb_build_object(
          'id','dark_serious',
          'title','Dark / Serious',
          'synonyms', jsonb_build_array('dark','serious','mature','grown up','not childish','psychological','thriller','mind game'),
          'required_genres', jsonb_build_array('Drama','Thriller','Psychological','Mystery'),
          'min_score', 78,
          'min_popularity', 2500,
          'exclude_genres', jsonb_build_array('Kids'),
          'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
        ),
        jsonb_build_object(
          'id','hidden_gems',
          'title','Hidden Gems',
          'synonyms', jsonb_build_array('hidden gems','underrated','less known','something new','new to me'),
          'min_score', 78,
          'max_popularity', 45000,
          'exclude_genres', jsonb_build_array('Kids'),
          'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
        ),
        jsonb_build_object(
          'id','classics_expanded',
          'title','Classics (expanded)',
          'synonyms', jsonb_build_array('classic','classics','must watch','essentials','goat','greatest of all time'),
          'rail_id', jsonb_build_object('anime','classics_anime','manga','classics_manga'),
          'classic_year_max', 2012,
          'min_score', 80,
          'min_popularity', 1500,
          'exclude_genres', jsonb_build_array('Kids'),
          'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
        )
      ),
      true
    ),
    '{router_llm}',
    jsonb_build_object(
      'enabled', false,
      'min_confidence', 0.45,
      'min_top_score', 2,
      'max_tokens', 80,
      'cache_ttl_days', 30
    ),
    true
  )
where id = true;
commit;
