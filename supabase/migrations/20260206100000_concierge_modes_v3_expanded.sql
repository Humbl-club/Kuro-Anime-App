-- Concierge modes v3 (expanded):
-- - Keep all 8 existing modes with richer synonyms (incl. German)
-- - Add 6 new modes: short_one_season, movie_night, romance_serious,
--   romcom, fantasy_non_isekai, isekai
-- - Total: 14 modes (within the recommended 20-50 ceiling)

begin;

update public.concierge_config
set config =
  jsonb_set(
    config,
    '{modes}',
    jsonb_build_array(
      -- ── Existing 8 modes (enriched synonyms) ──────────────────

      jsonb_build_object(
        'id','premium_picks',
        'title','Premium Picks',
        'synonyms', jsonb_build_array(
          'something good','recommend something','surprise me','premium','best',
          'top tier','what should i watch','was soll ich schauen','etwas gutes',
          'anything good','just pick something','quality'
        ),
        'min_score', 75,
        'min_popularity', 2500,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      jsonb_build_object(
        'id','gateway_start_here',
        'title','Start Here',
        'synonyms', jsonb_build_array(
          'first anime','first manga','where do i start','getting into anime',
          'getting into manga','anime anfangen','manga anfangen','beginner',
          'new to anime','new to manga','gateway','never watched anime',
          'erstes anime','einstieg'
        ),
        'rail_id', jsonb_build_object('anime','gateway_anime','manga','gateway_manga')
      ),

      jsonb_build_object(
        'id','premium_action',
        'title','Premium Action',
        'synonyms', jsonb_build_array(
          'action','hype action','action premium','best action','sakuga',
          'fight scenes','battle','tournament','shounen','epic fights',
          'adrenaline','kampf','action anime'
        ),
        'required_genres', jsonb_build_array('Action'),
        'min_score', 75,
        'min_popularity', 3500,
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      jsonb_build_object(
        'id','premium_comedy_grownup',
        'title','Premium Comedy (grown-up)',
        'synonyms', jsonb_build_array(
          'funny but not childish','grown up comedy','adult humor','smart comedy',
          'witzig aber nicht kindisch','sitcom','parody','satire','clever humor',
          'erwachsene komödie','comedy for adults'
        ),
        'required_genres', jsonb_build_array('Comedy'),
        'min_score', 75,
        'min_popularity', 3500,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      jsonb_build_object(
        'id','cozy_comfort',
        'title','Cozy / Comfort',
        'synonyms', jsonb_build_array(
          'cozy','comfort','chill','relax','healing','iyashikei','gemütlich',
          'wholesome','feel good','heartwarming','warm','gentle','peaceful',
          'entspannend','wohlfühl'
        ),
        'required_genres', jsonb_build_array('Slice of Life'),
        'min_score', 70,
        'min_popularity', 1200,
        'exclude_formats', jsonb_build_array('MUSIC')
      ),

      jsonb_build_object(
        'id','dark_serious',
        'title','Dark / Serious',
        'synonyms', jsonb_build_array(
          'dark','serious','mature','grown up','not childish','psychological',
          'thriller','mind game','seinen','gore','violent','gritty','brutal',
          'düster','ernst','erwachsen','mind bending'
        ),
        'required_genres', jsonb_build_array('Drama','Thriller','Psychological','Mystery'),
        'min_score', 78,
        'min_popularity', 2500,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      jsonb_build_object(
        'id','hidden_gems',
        'title','Hidden Gems',
        'synonyms', jsonb_build_array(
          'hidden gems','underrated','less known','something new','new to me',
          'overlooked','sleeper','cult','niche','off the beaten path',
          'geheimtipp','unbekannt','unterschätzt'
        ),
        'min_score', 78,
        'max_popularity', 45000,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      jsonb_build_object(
        'id','classics_expanded',
        'title','Classics (expanded)',
        'synonyms', jsonb_build_array(
          'classic','classics','must watch','essentials','goat','greatest of all time',
          'old school','retro','90s anime','80s anime','legendär','klassiker',
          'all time best','iconic'
        ),
        'rail_id', jsonb_build_object('anime','classics_anime','manga','classics_manga'),
        'classic_year_max', 2012,
        'min_score', 80,
        'min_popularity', 1500,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      -- ── 6 new modes ──────────────────────────────────────────

      jsonb_build_object(
        'id','short_one_season',
        'title','Short & Complete',
        'synonyms', jsonb_build_array(
          'short','one season','12 episodes','13 episodes','quick watch',
          'binge','completed','one cour','single season','short anime',
          'kurz','eine staffel','schnell durchschauen'
        ),
        'required_genres', jsonb_build_array(),
        'min_score', 74,
        'min_popularity', 2000,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC','MOVIE','ONA')
      ),

      jsonb_build_object(
        'id','movie_night',
        'title','Movie Night',
        'synonyms', jsonb_build_array(
          'movie','movies','film','anime movie','movie night','filmabend',
          'anime film','feature film','standalone movie','kinofilm'
        ),
        'required_genres', jsonb_build_array(),
        'min_score', 76,
        'min_popularity', 2000,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV','TV_SHORT','SPECIAL','MUSIC','ONA','OVA')
      ),

      jsonb_build_object(
        'id','romance_serious',
        'title','Romance (serious)',
        'synonyms', jsonb_build_array(
          'serious romance','love story','romantic drama','romance drama',
          'emotional romance','bittersweet','liebesgeschichte','ernste romanze',
          'heartbreak','romance not comedy','deep romance'
        ),
        'required_genres', jsonb_build_array('Romance','Drama'),
        'min_score', 74,
        'min_popularity', 2000,
        'exclude_genres', jsonb_build_array('Kids','Comedy'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      jsonb_build_object(
        'id','romcom',
        'title','Romcom',
        'synonyms', jsonb_build_array(
          'romcom','romantic comedy','rom com','funny romance','lighthearted romance',
          'love comedy','romantische komödie','lustige romanze','cute romance',
          'fluffy','sweet romance'
        ),
        'required_genres', jsonb_build_array('Romance','Comedy'),
        'min_score', 72,
        'min_popularity', 2000,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      jsonb_build_object(
        'id','fantasy_non_isekai',
        'title','Fantasy (no isekai)',
        'synonyms', jsonb_build_array(
          'fantasy','high fantasy','swords and sorcery','magic','epic fantasy',
          'fantasy no isekai','traditional fantasy','pure fantasy',
          'klassische fantasy','fantasy ohne isekai'
        ),
        'required_genres', jsonb_build_array('Fantasy'),
        'min_score', 74,
        'min_popularity', 2000,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      ),

      jsonb_build_object(
        'id','isekai',
        'title','Isekai',
        'synonyms', jsonb_build_array(
          'isekai','transported to another world','reincarnated','another world',
          'reborn','other world','parallel world','andere welt','wiedergeboren',
          'summoned to another world','truck-kun'
        ),
        'required_genres', jsonb_build_array('Fantasy','Adventure'),
        'min_score', 72,
        'min_popularity', 2500,
        'exclude_genres', jsonb_build_array('Kids'),
        'exclude_formats', jsonb_build_array('TV_SHORT','SPECIAL','MUSIC')
      )
    ),
    true
  )
where id = true;

commit;
