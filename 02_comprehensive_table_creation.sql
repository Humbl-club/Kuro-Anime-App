-- ============================================
-- COMPREHENSIVE TABLE CREATION SCRIPT
-- Optimal structure with internal IDs + external references
-- ============================================

-- ============================================
-- 1. ANIME TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE anime (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Basic Info
    title_english TEXT,
    title_romaji TEXT,
    title_native TEXT,
    title_synonyms TEXT[],
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    cover_image_color TEXT,
    banner_image TEXT,
    
    -- Anime-specific
    format TEXT, -- 'TV', 'MOVIE', 'OVA', 'ONA', 'SPECIAL'
    status TEXT, -- 'FINISHED', 'RELEASING', 'NOT_YET_RELEASED'
    description TEXT,
    description_normalized TEXT,
    
    -- Episodes
    episodes INTEGER,
    duration INTEGER, -- minutes per episode
    total_duration INTEGER, -- total runtime in minutes
    season TEXT, -- 'SPRING', 'SUMMER', 'FALL', 'WINTER'
    season_year INTEGER,
    
    -- Airing schedule
    next_episode_number INTEGER,
    next_airing_at TIMESTAMP WITH TIME ZONE,
    
    -- Dates
    start_date_year INTEGER,
    start_date_month INTEGER,
    start_date_day INTEGER,
    end_date_year INTEGER,
    end_date_month INTEGER,
    end_date_day INTEGER,
    
    -- Ratings
    average_score INTEGER,
    mean_score INTEGER,
    popularity INTEGER,
    trending INTEGER,
    favourites INTEGER,
    
    -- Content
    genres TEXT[],
    source TEXT,
    country_of_origin TEXT,
    is_adult BOOLEAN DEFAULT false,
    age_rating TEXT,
    
    -- External links
    site_url TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at_anilist TIMESTAMP WITH TIME ZONE
);

-- ============================================
-- 2. MANGA TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE manga (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Basic Info
    title_english TEXT,
    title_romaji TEXT,
    title_native TEXT,
    title_synonyms TEXT[],
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    cover_image_color TEXT,
    banner_image TEXT,
    
    -- Manga-specific
    format TEXT, -- 'MANGA', 'NOVEL', 'ONE_SHOT', 'DOUJINSHI', 'MANHWA', 'MANHUA'
    status TEXT, -- 'FINISHED', 'RELEASING', 'NOT_YET_RELEASED', 'HIATUS'
    description TEXT,
    description_normalized TEXT,
    
    -- Chapters/Volumes
    chapters INTEGER,
    volumes INTEGER,
    
    -- Chapter schedule
    next_chapter_number INTEGER,
    next_chapter_at TIMESTAMP WITH TIME ZONE,
    
    -- Dates
    start_date_year INTEGER,
    start_date_month INTEGER,
    start_date_day INTEGER,
    end_date_year INTEGER,
    end_date_month INTEGER,
    end_date_day INTEGER,
    
    -- Ratings
    average_score INTEGER,
    mean_score INTEGER,
    popularity INTEGER,
    trending INTEGER,
    favourites INTEGER,
    
    -- Content
    genres TEXT[],
    source TEXT,
    country_of_origin TEXT,
    is_adult BOOLEAN DEFAULT false,
    age_rating TEXT,
    
    -- External links
    site_url TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at_anilist TIMESTAMP WITH TIME ZONE
);

-- ============================================
-- 3. EPISODES TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE episodes (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Episode info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Airing info
    air_date DATE,
    air_at TIMESTAMP WITH TIME ZONE,
    thumbnail TEXT,
    duration INTEGER, -- minutes
    
    -- Episode metadata
    is_filler BOOLEAN DEFAULT false,
    is_recap BOOLEAN DEFAULT false,
    is_mixed BOOLEAN DEFAULT false,
    filler_source TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 4. CHAPTERS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE chapters (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Chapter info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Release info
    release_date DATE,
    release_at TIMESTAMP WITH TIME ZONE,
    thumbnail TEXT,
    pages INTEGER,
    
    -- Chapter metadata
    is_side_story BOOLEAN DEFAULT false,
    is_extra BOOLEAN DEFAULT false,
    is_omake BOOLEAN DEFAULT false,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 5. VOLUMES TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE volumes (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Volume info
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    
    -- Visual
    cover_image_large TEXT,
    cover_image_medium TEXT,
    
    -- Release info
    release_date DATE,
    release_at TIMESTAMP WITH TIME ZONE,
    pages INTEGER,
    
    -- Volume metadata
    isbn TEXT,
    price_jpy INTEGER,
    price_usd DECIMAL(10,2),
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 6. CHARACTERS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE characters (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Character info
    name_full TEXT,
    name_native TEXT,
    name_alternative TEXT[],
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Character details
    description TEXT,
    gender TEXT, -- 'Male', 'Female', 'Non-binary', 'Unknown'
    age INTEGER,
    birthday DATE,
    blood_type TEXT, -- 'A', 'B', 'AB', 'O', 'Unknown'
    
    -- Physical attributes
    height INTEGER, -- cm
    weight INTEGER, -- kg
    hair_color TEXT,
    eye_color TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 7. STUDIOS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE studios (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Studio info
    name TEXT NOT NULL,
    name_romaji TEXT,
    name_native TEXT,
    
    -- Studio details
    description TEXT,
    is_animation_studio BOOLEAN DEFAULT false,
    is_producer BOOLEAN DEFAULT false,
    is_licensor BOOLEAN DEFAULT false,
    
    -- External
    site_url TEXT,
    favourites INTEGER DEFAULT 0,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 8. AUTHORS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE authors (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Author info
    name_full TEXT,
    name_native TEXT,
    name_romaji TEXT,
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Author details
    description TEXT,
    birth_date DATE,
    death_date DATE,
    hometown TEXT,
    blood_type TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 9. STAFF TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE staff (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    
    -- Staff info
    name_full TEXT,
    name_native TEXT,
    name_romaji TEXT,
    
    -- Visual
    image_large TEXT,
    image_medium TEXT,
    
    -- Staff details
    description TEXT,
    primary_occupations TEXT[], -- ['Director', 'Writer', 'Music', 'Character Design']
    birth_date DATE,
    death_date DATE,
    hometown TEXT,
    blood_type TEXT,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 10. TAGS TABLE (Internal ID + External References)
-- ============================================
CREATE TABLE tags (
    id SERIAL PRIMARY KEY, -- INTERNAL ID (your control)
    
    -- External API References (for sync only)
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    
    -- Tag info
    name TEXT NOT NULL,
    name_romaji TEXT,
    name_native TEXT,
    description TEXT,
    
    -- Tag metadata
    category TEXT, -- 'Genre', 'Theme', 'Demographic', 'Content'
    is_general_spoiler BOOLEAN DEFAULT false,
    is_media_spoiler BOOLEAN DEFAULT false,
    is_adult BOOLEAN DEFAULT false,
    rank INTEGER DEFAULT 0,
    
    -- System
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 11. RELATIONSHIP TABLES (All use INTERNAL IDs)
-- ============================================

-- Anime-Character relationship
CREATE TABLE anime_characters (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Main', 'Supporting', 'Background'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, character_id)
);

-- Manga-Character relationship
CREATE TABLE manga_characters (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    character_id INTEGER REFERENCES characters(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Main', 'Supporting', 'Background'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, character_id)
);

-- Anime-Studio relationship
CREATE TABLE anime_studios (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    studio_id INTEGER REFERENCES studios(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Animation', 'Production', 'Licensor'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, studio_id)
);

-- Manga-Author relationship
CREATE TABLE manga_authors (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    author_id INTEGER REFERENCES authors(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Story', 'Art', 'Story & Art', 'Supervision'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, author_id)
);

-- Anime-Staff relationship
CREATE TABLE anime_staff (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    staff_id INTEGER REFERENCES staff(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Director', 'Writer', 'Music', 'Character Design'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, staff_id)
);

-- Manga-Staff relationship
CREATE TABLE manga_staff (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    staff_id INTEGER REFERENCES staff(id) ON DELETE CASCADE, -- INTERNAL reference
    role TEXT, -- 'Editor', 'Publisher', 'Translator'
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, staff_id)
);

-- Anime-Tag relationship
CREATE TABLE anime_tags (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE, -- INTERNAL reference
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, tag_id)
);

-- Manga-Tag relationship
CREATE TABLE manga_tags (
    id SERIAL PRIMARY KEY, -- Auto-increment for relationship ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    tag_id INTEGER REFERENCES tags(id) ON DELETE CASCADE, -- INTERNAL reference
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, tag_id)
);

-- ============================================
-- 12. USER INTERACTION TABLES (All use INTERNAL IDs)
-- ============================================

-- Anime user lists
CREATE TABLE anime_user_lists (
    id SERIAL PRIMARY KEY, -- Auto-increment for user list entry ID
    user_id INTEGER NOT NULL, -- Your user system ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    list_type TEXT NOT NULL, -- 'WATCHING', 'COMPLETED', 'PLANNING', 'DROPPED', 'PAUSED'
    progress INTEGER DEFAULT 0, -- episodes watched
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, anime_id)
);

-- Manga user lists
CREATE TABLE manga_user_lists (
    id SERIAL PRIMARY KEY, -- Auto-increment for user list entry ID
    user_id INTEGER NOT NULL, -- Your user system ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    list_type TEXT NOT NULL, -- 'READING', 'COMPLETED', 'PLANNING', 'DROPPED', 'PAUSED'
    progress INTEGER DEFAULT 0, -- chapters read
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, manga_id)
);

-- Anime comments
CREATE TABLE anime_comments (
    id SERIAL PRIMARY KEY, -- Auto-increment for comment ID
    anime_id INTEGER REFERENCES anime(id) ON DELETE CASCADE, -- INTERNAL reference
    user_id INTEGER NOT NULL, -- Your user system ID
    comment TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    is_spoiler BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Manga comments
CREATE TABLE manga_comments (
    id SERIAL PRIMARY KEY, -- Auto-increment for comment ID
    manga_id INTEGER REFERENCES manga(id) ON DELETE CASCADE, -- INTERNAL reference
    user_id INTEGER NOT NULL, -- Your user system ID
    comment TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    is_spoiler BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 13. PERFORMANCE INDEXES
-- ============================================

-- Primary entity indexes (INTERNAL IDs)
CREATE INDEX idx_anime_id ON anime(id);
CREATE INDEX idx_manga_id ON manga(id);
CREATE INDEX idx_episodes_id ON episodes(id);
CREATE INDEX idx_chapters_id ON chapters(id);
CREATE INDEX idx_volumes_id ON volumes(id);
CREATE INDEX idx_characters_id ON characters(id);
CREATE INDEX idx_studios_id ON studios(id);
CREATE INDEX idx_authors_id ON authors(id);
CREATE INDEX idx_staff_id ON staff(id);
CREATE INDEX idx_tags_id ON tags(id);

-- External ID indexes (for sync)
CREATE INDEX idx_anime_anilist_id ON anime(anilist_id);
CREATE INDEX idx_anime_mal_id ON anime(mal_id);
CREATE INDEX idx_manga_anilist_id ON manga(anilist_id);
CREATE INDEX idx_manga_mal_id ON manga(mal_id);
CREATE INDEX idx_characters_anilist_id ON characters(anilist_id);
CREATE INDEX idx_characters_mal_id ON characters(mal_id);
CREATE INDEX idx_studios_anilist_id ON studios(anilist_id);
CREATE INDEX idx_studios_mal_id ON studios(mal_id);
CREATE INDEX idx_authors_anilist_id ON authors(anilist_id);
CREATE INDEX idx_authors_mal_id ON authors(mal_id);
CREATE INDEX idx_staff_anilist_id ON staff(anilist_id);
CREATE INDEX idx_staff_mal_id ON staff(mal_id);
CREATE INDEX idx_tags_anilist_id ON tags(anilist_id);
CREATE INDEX idx_tags_mal_id ON tags(mal_id);

-- Content indexes
CREATE INDEX idx_anime_title_english ON anime(title_english);
CREATE INDEX idx_anime_title_romaji ON anime(title_romaji);
CREATE INDEX idx_anime_status ON anime(status);
CREATE INDEX idx_anime_popularity ON anime(popularity DESC);
CREATE INDEX idx_anime_average_score ON anime(average_score DESC);
CREATE INDEX idx_anime_genres ON anime USING GIN(genres);
CREATE INDEX idx_anime_season_year ON anime(season_year);
CREATE INDEX idx_anime_next_airing ON anime(next_airing_at);

CREATE INDEX idx_manga_title_english ON manga(title_english);
CREATE INDEX idx_manga_title_romaji ON manga(title_romaji);
CREATE INDEX idx_manga_status ON manga(status);
CREATE INDEX idx_manga_popularity ON manga(popularity DESC);
CREATE INDEX idx_manga_average_score ON manga(average_score DESC);
CREATE INDEX idx_manga_genres ON manga USING GIN(genres);
CREATE INDEX idx_manga_next_chapter ON manga(next_chapter_at);

-- Relationship indexes (INTERNAL IDs)
CREATE INDEX idx_anime_characters_anime_id ON anime_characters(anime_id);
CREATE INDEX idx_anime_characters_character_id ON anime_characters(character_id);
CREATE INDEX idx_manga_characters_manga_id ON manga_characters(manga_id);
CREATE INDEX idx_manga_characters_character_id ON manga_characters(character_id);
CREATE INDEX idx_anime_studios_anime_id ON anime_studios(anime_id);
CREATE INDEX idx_anime_studios_studio_id ON anime_studios(studio_id);
CREATE INDEX idx_manga_authors_manga_id ON manga_authors(manga_id);
CREATE INDEX idx_manga_authors_author_id ON manga_authors(author_id);
CREATE INDEX idx_anime_staff_anime_id ON anime_staff(anime_id);
CREATE INDEX idx_anime_staff_staff_id ON anime_staff(staff_id);
CREATE INDEX idx_manga_staff_manga_id ON manga_staff(manga_id);
CREATE INDEX idx_manga_staff_staff_id ON manga_staff(staff_id);
CREATE INDEX idx_anime_tags_anime_id ON anime_tags(anime_id);
CREATE INDEX idx_anime_tags_tag_id ON anime_tags(tag_id);
CREATE INDEX idx_manga_tags_manga_id ON manga_tags(manga_id);
CREATE INDEX idx_manga_tags_tag_id ON manga_tags(tag_id);

-- User interaction indexes
CREATE INDEX idx_anime_user_lists_user_id ON anime_user_lists(user_id);
CREATE INDEX idx_anime_user_lists_anime_id ON anime_user_lists(anime_id);
CREATE INDEX idx_anime_user_lists_list_type ON anime_user_lists(list_type);
CREATE INDEX idx_manga_user_lists_user_id ON manga_user_lists(user_id);
CREATE INDEX idx_manga_user_lists_manga_id ON manga_user_lists(manga_id);
CREATE INDEX idx_manga_user_lists_list_type ON manga_user_lists(list_type);
CREATE INDEX idx_anime_comments_anime_id ON anime_comments(anime_id);
CREATE INDEX idx_anime_comments_user_id ON anime_comments(user_id);
CREATE INDEX idx_manga_comments_manga_id ON manga_comments(manga_id);
CREATE INDEX idx_manga_comments_user_id ON manga_comments(user_id);

-- ============================================
-- 14. AUTO-UPDATE TRIGGERS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for all tables
CREATE TRIGGER update_anime_updated_at BEFORE UPDATE ON anime FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_manga_updated_at BEFORE UPDATE ON manga FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_episodes_updated_at BEFORE UPDATE ON episodes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_chapters_updated_at BEFORE UPDATE ON chapters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_volumes_updated_at BEFORE UPDATE ON volumes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_characters_updated_at BEFORE UPDATE ON characters FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_studios_updated_at BEFORE UPDATE ON studios FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_authors_updated_at BEFORE UPDATE ON authors FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_staff_updated_at BEFORE UPDATE ON staff FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_tags_updated_at BEFORE UPDATE ON tags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 15. ROW LEVEL SECURITY (RLS)
-- ============================================

-- Enable RLS on all tables
ALTER TABLE anime ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga ENABLE ROW LEVEL SECURITY;
ALTER TABLE episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE chapters ENABLE ROW LEVEL SECURITY;
ALTER TABLE volumes ENABLE ROW LEVEL SECURITY;
ALTER TABLE characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE anime_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE manga_comments ENABLE ROW LEVEL SECURITY;

-- Create policies for public read access
CREATE POLICY "Public read access" ON anime FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga FOR SELECT USING (true);
CREATE POLICY "Public read access" ON episodes FOR SELECT USING (true);
CREATE POLICY "Public read access" ON chapters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON volumes FOR SELECT USING (true);
CREATE POLICY "Public read access" ON characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON studios FOR SELECT USING (true);
CREATE POLICY "Public read access" ON authors FOR SELECT USING (true);
CREATE POLICY "Public read access" ON staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON tags FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_characters FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_studios FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_authors FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_staff FOR SELECT USING (true);
CREATE POLICY "Public read access" ON anime_tags FOR SELECT USING (true);
CREATE POLICY "Public read access" ON manga_tags FOR SELECT USING (true);

-- User-specific policies for user lists and comments
CREATE POLICY "Users can manage their own lists" ON anime_user_lists USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own lists" ON manga_user_lists USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own comments" ON anime_comments USING (auth.uid()::text = user_id::text);
CREATE POLICY "Users can manage their own comments" ON manga_comments USING (auth.uid()::text = user_id::text);

-- ============================================
-- 16. VERIFICATION
-- ============================================

-- Verify all tables were created
SELECT 
    schemaname,
    tablename,
    tableowner
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY tablename;

-- Verify all indexes were created
SELECT 
    schemaname,
    tablename,
    indexname
FROM pg_indexes 
WHERE schemaname = 'public' 
ORDER BY tablename, indexname;

-- Verify all triggers were created
SELECT 
    trigger_name,
    event_object_table,
    action_timing,
    event_manipulation
FROM information_schema.triggers 
WHERE trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

