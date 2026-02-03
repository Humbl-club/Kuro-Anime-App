APPENDIX SQL Table Definitions (Columns)
========================================

anime
- id SERIAL PK
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- kitsu_id INTEGER UNIQUE
- title_english TEXT
- title_romaji TEXT
- title_native TEXT
- title_synonyms TEXT[]
- cover_image_large TEXT
- cover_image_medium TEXT
- cover_image_color TEXT
- banner_image TEXT
- format TEXT
- status TEXT
- description TEXT
- description_normalized TEXT
- episodes INTEGER
- duration INTEGER
- total_duration INTEGER
- season TEXT
- season_year INTEGER
- next_episode_number INTEGER
- next_airing_at TIMESTAMP WITH TIME ZONE
- start_date_year INTEGER
- start_date_month INTEGER
- start_date_day INTEGER
- end_date_year INTEGER
- end_date_month INTEGER
- end_date_day INTEGER
- average_score INTEGER
- mean_score INTEGER
- popularity INTEGER
- trending INTEGER
- favourites INTEGER
- genres TEXT[]
- source TEXT
- country_of_origin TEXT
- is_adult BOOLEAN DEFAULT false
- age_rating TEXT
- site_url TEXT
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()
- last_synced_at TIMESTAMPTZ DEFAULT now()
- updated_at_anilist TIMESTAMPTZ

manga
- id SERIAL PK
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- kitsu_id INTEGER UNIQUE
- title_english TEXT
- title_romaji TEXT
- title_native TEXT
- title_synonyms TEXT[]
- cover_image_large TEXT
- cover_image_medium TEXT
- cover_image_color TEXT
- banner_image TEXT
- format TEXT
- status TEXT
- description TEXT
- description_normalized TEXT
- chapters INTEGER
- volumes INTEGER
- next_chapter_number INTEGER
- next_chapter_at TIMESTAMPTZ
- start_date_year INTEGER
- start_date_month INTEGER
- start_date_day INTEGER
- end_date_year INTEGER
- end_date_month INTEGER
- end_date_day INTEGER
- average_score INTEGER
- mean_score INTEGER
- popularity INTEGER
- trending INTEGER
- favourites INTEGER
- genres TEXT[]
- source TEXT
- country_of_origin TEXT
- is_adult BOOLEAN DEFAULT false
- age_rating TEXT
- site_url TEXT
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()
- last_synced_at TIMESTAMPTZ DEFAULT now()
- updated_at_anilist TIMESTAMPTZ

episodes
- id SERIAL PK
- anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- number INTEGER NOT NULL
- title TEXT
- title_romaji TEXT
- description TEXT
- air_date DATE
- air_at TIMESTAMPTZ
- thumbnail TEXT
- duration INTEGER
- is_filler BOOLEAN DEFAULT false
- is_recap BOOLEAN DEFAULT false
- is_mixed BOOLEAN DEFAULT false
- filler_source TEXT
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()

chapters
- id SERIAL PK
- manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- number INTEGER NOT NULL
- title TEXT
- title_romaji TEXT
- description TEXT
- release_date DATE
- release_at TIMESTAMPTZ
- thumbnail TEXT
- pages INTEGER
- is_side_story BOOLEAN DEFAULT false
- is_extra BOOLEAN DEFAULT false
- is_omake BOOLEAN DEFAULT false
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()

volumes
- id SERIAL PK
- manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- number INTEGER NOT NULL
- title TEXT
- title_romaji TEXT
- description TEXT
- cover_image_large TEXT
- cover_image_medium TEXT
- release_date DATE
- release_at TIMESTAMPTZ
- pages INTEGER
- isbn TEXT
- price_jpy INTEGER
- price_usd DECIMAL(10,2)
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()

characters
- id SERIAL PK
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- kitsu_id INTEGER UNIQUE
- name_full TEXT
- name_native TEXT
- name_alternative TEXT[]
- image_large TEXT
- image_medium TEXT
- description TEXT
- gender TEXT
- age INTEGER
- birthday DATE
- blood_type TEXT
- height INTEGER
- weight INTEGER
- hair_color TEXT
- eye_color TEXT
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()

studios
- id SERIAL PK
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- kitsu_id INTEGER UNIQUE
- name TEXT NOT NULL
- name_romaji TEXT
- name_native TEXT
- description TEXT
- is_animation_studio BOOLEAN DEFAULT false
- is_producer BOOLEAN DEFAULT false
- is_licensor BOOLEAN DEFAULT false
- site_url TEXT
- favourites INTEGER DEFAULT 0
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()

authors
- id SERIAL PK
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- kitsu_id INTEGER UNIQUE
- name_full TEXT
- name_romaji TEXT
- name_native TEXT
- image_large TEXT
- image_medium TEXT
- description TEXT
- primary_occupations TEXT[]
- site_url TEXT
- favourites INTEGER DEFAULT 0
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()

staff
- id SERIAL PK
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- kitsu_id INTEGER UNIQUE
- name_full TEXT
- name_romaji TEXT
- name_native TEXT
- image_large TEXT
- image_medium TEXT
- description TEXT
- primary_occupations TEXT[]
- site_url TEXT
- favourites INTEGER DEFAULT 0
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()

tags
- id SERIAL PK
- anilist_id INTEGER UNIQUE
- mal_id INTEGER UNIQUE
- kitsu_id INTEGER UNIQUE
- name TEXT NOT NULL
- name_romaji TEXT
- name_native TEXT
- description TEXT
- category TEXT
- is_general_spoiler BOOLEAN DEFAULT false
- is_media_spoiler BOOLEAN DEFAULT false
- is_adult BOOLEAN DEFAULT false
- rank INTEGER DEFAULT 0
- created_at TIMESTAMPTZ DEFAULT now()
- updated_at TIMESTAMPTZ DEFAULT now()

Relationship Tables (columns)
- anime_characters: id, anime_id, character_id, role, role_notes, created_at (UNIQUE(anime_id, character_id))
- manga_characters: id, manga_id, character_id, role, role_notes, created_at (UNIQUE(manga_id, character_id))
- anime_studios: id, anime_id, studio_id, role, role_notes, created_at (UNIQUE(anime_id, studio_id))
- manga_authors: id, manga_id, author_id, role, role_notes, created_at (UNIQUE(manga_id, author_id))
- anime_staff: id, anime_id, staff_id, role, role_notes, created_at (UNIQUE(anime_id, staff_id))
- manga_staff: id, manga_id, staff_id, role, role_notes, created_at (UNIQUE(manga_id, staff_id))
- anime_tags: id, anime_id, tag_id, rank, created_at (UNIQUE(anime_id, tag_id))
- manga_tags: id, manga_id, tag_id, rank, created_at (UNIQUE(manga_id, tag_id))

User Interaction Tables
- anime_user_lists: id, user_id, anime_id, list_type, progress, rating, notes, created_at, updated_at (UNIQUE(user_id, anime_id))
- manga_user_lists: id, user_id, manga_id, list_type, progress, rating, notes, created_at, updated_at (UNIQUE(user_id, manga_id))
- anime_comments: id, anime_id, user_id, comment, rating, is_spoiler, created_at, updated_at
- manga_comments: id, manga_id, user_id, comment, rating, is_spoiler, created_at, updated_at

Views & Cursors
- user_lists view (08_create_user_lists_view.sql): normalized union of anime_user_lists and manga_user_lists with unified columns (id, user_id, media_id, media_type, status, progress, progress_volumes, score, notes, started_at, completed_at, private, created_at, updated_at)
- import_state (09_import_state.sql): media_type PK, last_page, updated_at

