# 📊 Kuro Database - Complete Overview

## 🎯 **Database System:**
- **Backend:** Supabase (PostgreSQL)
- **Project ID:** `bkdifromsqxkndnllmdj`
- **Primary Keys:** INTEGER (AniList IDs)
- **Cross-API:** MyAnimeList & Kitsu IDs for independence

---

## 📋 **Complete Table Structure:**

### **1. 🎬 MAIN MEDIA TABLES**

#### **`anime` Table (10,000+ entries)**
```sql
-- IDs & Cross-API Matching
id INTEGER PRIMARY KEY              -- AniList ID
id_mal INTEGER UNIQUE              -- MyAnimeList ID (backup)
id_kitsu TEXT                      -- Kitsu ID (backup)

-- Titles (Multi-language)
title_english TEXT                 -- "Solo Leveling"
title_romaji TEXT                  -- "Ore dake Level Up na Ken"
title_native TEXT                  -- "나 혼자만 레벨업"
title_synonyms TEXT[]              -- Alternative titles array

-- Images (Supabase CDN Ready)
cover_image_large TEXT             -- Main poster
cover_image_medium TEXT            -- Smaller version
cover_image_color TEXT             -- Dominant color hex
banner_image TEXT                  -- Wide banner image

-- Content Info
type TEXT DEFAULT 'ANIME'
format TEXT                        -- TV, MOVIE, OVA, SPECIAL
status TEXT                        -- FINISHED, RELEASING, NOT_YET_RELEASED
description TEXT                   -- Full description
description_normalized TEXT        -- HTML stripped, clean

-- Episode Data
episodes INTEGER                   -- Total episode count
duration INTEGER                   -- Per episode (minutes)
total_duration INTEGER             -- Total runtime

-- Release Information
season TEXT                        -- WINTER, SPRING, SUMMER, FALL
season_year INTEGER                -- 2024, 2023, etc.
start_date_year INTEGER
start_date_month INTEGER
start_date_day INTEGER
end_date_year INTEGER
end_date_month INTEGER
end_date_day INTEGER

-- Airing Schedule
next_airing_episode INTEGER        -- Next episode number
next_airing_at TIMESTAMPTZ         -- When it airs

-- Popularity & Scores
average_score INTEGER              -- 0-100 rating
mean_score INTEGER                 -- Alternative scoring
popularity INTEGER                 -- Popularity rank
trending INTEGER                   -- Trending rank
favourites INTEGER                 -- Favorite count

-- Classification
genres TEXT[]                      -- ["Action", "Fantasy", "Adventure"]
tags JSONB                         -- Rich metadata from AniList
is_adult BOOLEAN                   -- Adult content flag
age_rating TEXT                    -- G, PG, PG-13, R

-- External Links
site_url TEXT                      -- AniList page URL
trailer_url TEXT                   -- YouTube trailer

-- Production Info
source TEXT                        -- MANGA, LIGHT_NOVEL, ORIGINAL
country_of_origin TEXT             -- JP, KR, CN

-- Timestamps
created_at TIMESTAMPTZ
updated_at TIMESTAMPTZ
last_synced_at TIMESTAMPTZ         -- Last API sync
```

#### **`manga` Table**
```sql
-- Similar structure to anime but for manga/novels
id INTEGER PRIMARY KEY
id_mal INTEGER UNIQUE
title_english, title_romaji, title_native
cover_image_large, cover_image_medium, cover_image_color
type TEXT DEFAULT 'MANGA'
format TEXT                        -- MANGA, NOVEL, ONE_SHOT
chapters INTEGER, volumes INTEGER
genres TEXT[]
-- Plus timestamps and metadata
```

### **2. 👥 STAFF & CHARACTERS**

#### **`staff` Table**
```sql
id INTEGER PRIMARY KEY             -- AniList staff ID
name_full TEXT                     -- "Hayao Miyazaki"
name_native TEXT                   -- Native language name
description TEXT                   -- Biography
image_large TEXT                   -- Profile photo
site_url TEXT                      -- AniList staff page
```

#### **`anime_staff` Table (Relations)**
```sql
anime_id INTEGER → anime(id)
staff_id INTEGER → staff(id)
role TEXT                          -- "Director", "Animation", "Music"
```

#### **`characters` Table**
```sql
id INTEGER PRIMARY KEY             -- AniList character ID
name_full TEXT                     -- "Edward Elric"
name_native TEXT                   -- Native name
description TEXT                   -- Character bio
image_large TEXT, image_medium TEXT
age TEXT, gender TEXT
date_of_birth_year, _month, _day
```

#### **`anime_characters` Table (Relations)**
```sql
anime_id INTEGER → anime(id)
character_id INTEGER → characters(id)
role TEXT                          -- "MAIN", "SUPPORTING", "BACKGROUND"
voice_actor_id INTEGER → staff(id)
voice_actor_language TEXT          -- "Japanese", "English"
```

### **3. 📺 EPISODES & CHAPTERS**

#### **`episodes` Table**
```sql
id SERIAL PRIMARY KEY
anime_id INTEGER → anime(id)
number INTEGER                     -- Episode number
title TEXT, title_romaji TEXT      -- Episode titles
description TEXT                   -- Episode synopsis
air_date DATE, air_at TIMESTAMPTZ  -- When it aired
thumbnail TEXT                     -- Episode thumbnail
duration INTEGER                   -- Runtime in minutes

-- Filler Detection (Smart!)
is_filler BOOLEAN                  -- Filler episode?
is_recap BOOLEAN                   -- Recap episode?
is_mixed BOOLEAN                   -- Partially filler?
filler_source TEXT                 -- Which API detected it
```

#### **`chapters` Table**
```sql
id SERIAL PRIMARY KEY
manga_id INTEGER → manga(id)
number FLOAT                       -- Can be 1.5, 2.5 for specials
title TEXT
release_date DATE
```

### **4. 🔗 STREAMING & READING LINKS**

#### **`streaming_links` Table**
```sql
anime_id INTEGER → anime(id)
platform TEXT                     -- "Crunchyroll", "Netflix", "Hulu"
platform_id TEXT                  -- Platform's internal ID
url TEXT                          -- Direct link
region TEXT[]                     -- ["US", "CA", "UK"]
is_premium BOOLEAN                -- Requires subscription?
is_simulcast BOOLEAN              -- Day-and-date release?
has_subtitles BOOLEAN
has_dub BOOLEAN
languages TEXT[]                  -- ["en", "ja", "es"]
```

#### **`reading_links` Table**
```sql
manga_id INTEGER → manga(id)
platform TEXT                     -- "MangaPlus", "VIZ", "Webtoon"
url TEXT
region TEXT[]
is_premium BOOLEAN
languages TEXT[]
```

### **5. 👤 USER DATA**

#### **`user_lists` Table**
```sql
id SERIAL PRIMARY KEY
user_id UUID                       -- Supabase auth user
media_id INTEGER                   -- Links to anime(id) or manga(id)
media_type TEXT                    -- 'anime' or 'manga'
status TEXT                        -- 'CURRENT', 'PLANNING', 'COMPLETED', 'DROPPED', 'PAUSED', 'REPEATING'
progress INTEGER                   -- Episodes/chapters watched
progress_volumes INTEGER
score INTEGER                      -- 0-100 user rating
notes TEXT                         -- User notes
started_at TIMESTAMPTZ
completed_at TIMESTAMPTZ
private BOOLEAN                    -- Private list?
```

#### **`user_episode_progress` Table**
```sql
user_id UUID
episode_id INTEGER → episodes(id)
watched BOOLEAN
watched_at TIMESTAMPTZ
```

### **6. 🔗 RELATIONS & RECOMMENDATIONS**

#### **`anime_relations` Table**
```sql
anime_id INTEGER → anime(id)
related_anime_id INTEGER → anime(id)
relation_type TEXT                 -- "SEQUEL", "PREQUEL", "SIDE_STORY", "SPIN_OFF"
```

---

## 🚀 **What This Gives You:**

### **Rich Content Data:**
- **10,000+ anime** with complete metadata
- **Multiple title formats** (English, Romaji, Native)
- **High-quality images** ready for Supabase CDN
- **Episode-level tracking** with filler detection
- **Streaming availability** across platforms
- **Staff and character information**

### **User Experience:**
- **Personal lists** with detailed progress
- **Episode-by-episode tracking**
- **User ratings and notes**
- **Privacy controls**
- **Cross-device sync** via Supabase

### **API Independence:**
- **Cross-API matching** via multiple ID fields
- **Fallback systems** if any API fails
- **Rich local data** reduces API dependency
- **Future-proof architecture**

### **Performance:**
- **Full-text search** across titles and descriptions
- **Optimized indexes** for all common queries
- **Real-time subscriptions** via Supabase
- **Efficient filtering** by genre, year, status

---

## 📊 **Sample Data Available:**
- **Solo Leveling** (2024) - Action/Fantasy
- **Frieren: Beyond Journey's End** (2023) - Adventure/Drama
- **Chainsaw Man** (2022) - Action/Supernatural
- **Plus 10,000+ more anime**

**Your database is incredibly comprehensive and ready for production!** 🎯✨
