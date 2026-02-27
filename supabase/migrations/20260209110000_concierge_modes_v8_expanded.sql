-- Concierge modes v8: add 6 new vibe modes (mecha, mystery_detective,
-- music_performance, historical, school_coming_of_age, shoujo_josei).
-- Rails are seeded by: 20260209120000_new_vibe_rails.sql

begin;
update public.concierge_config
set config = jsonb_set(
  config,
  '{modes}',
  (config->'modes') || '[
    {
      "id": "mecha",
      "title": "Mecha",
      "synonyms": ["mecha","giant robot","gundam","evangelion","code geass","roboter","riesenroboter","giant robots","mech"],
      "required_genres": ["Mecha"],
      "min_score": 72,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT","SPECIAL","MUSIC"],
      "rail_id": { "anime": "mecha_anime", "manga": "mecha_manga" }
    },
    {
      "id": "mystery_detective",
      "title": "Mystery & Detective",
      "synonyms": ["mystery","detective","whodunit","case","deduction","krimi","detektiv","raetsel","who did it","crime","suspense"],
      "required_genres": ["Mystery"],
      "min_score": 76,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT","SPECIAL","MUSIC"],
      "rail_id": { "anime": "mystery_detective_anime", "manga": "mystery_detective_manga" }
    },
    {
      "id": "music_performance",
      "title": "Music & Performance",
      "synonyms": ["music anime","band","idol","concert","k-on","your lie in april","musik","konzert","musik anime","instrument"],
      "required_genres": ["Music"],
      "min_score": 70,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT","SPECIAL","MUSIC"],
      "rail_id": { "anime": "music_performance_anime", "manga": "music_performance_manga" }
    },
    {
      "id": "historical",
      "title": "Historical & Period",
      "synonyms": ["historical","period","samurai","war","vinland","kingdom","historisch","samurai","mittelalter","sengoku","edo","period drama"],
      "min_score": 76,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT","SPECIAL","MUSIC"],
      "rail_id": { "anime": "historical_anime", "manga": "historical_manga" }
    },
    {
      "id": "school_coming_of_age",
      "title": "School & Coming of Age",
      "synonyms": ["school","high school","campus","coming of age","youth","schule","gymnasium","jugend","school life","teen","student"],
      "min_score": 74,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT","SPECIAL","MUSIC"],
      "rail_id": { "anime": "school_anime", "manga": "school_manga" }
    },
    {
      "id": "shoujo_josei",
      "title": "Shoujo & Josei",
      "synonyms": ["shoujo","josei","for women","girls manga","woman protagonist","fuer frauen","maedchen","mahou shoujo","magical girl","reverse harem"],
      "min_score": 72,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT","SPECIAL","MUSIC"],
      "rail_id": { "anime": "shoujo_josei_anime", "manga": "shoujo_josei_manga" }
    }
  ]'::jsonb,
  true
)
where id = true;
commit;
