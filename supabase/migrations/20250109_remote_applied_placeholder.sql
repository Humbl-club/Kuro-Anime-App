-- Baseline schema migration (historical)
--
-- This version (20250109) exists in the remote Supabase migration history.
-- The original SQL was applied directly to the remote database before
-- migrations were tracked in this repo. Keeping the full SQL here makes
-- the repo self-contained: a new Supabase project can be created from
-- supabase/migrations alone, while existing projects will NOT reapply it
-- because this version is already present in supabase_migrations.
--
-- NOTE: This baseline intentionally includes remote-only objects that
-- production depends on (import_runs/import_locks + lock RPCs, discover
-- materialized views, and the matview refresh cron job).

-- ============================================================
-- FOUNDATION MIGRATION
-- Creates the complete Kuro catalog schema from scratch.
--
-- This migration captures the cumulative effect of the root-level
-- SQL files (02–14) plus remote-only objects (import_runs,
-- import_locks, lock RPCs, materialized views, MV refresh cron)
-- that were applied directly to the remote database before
-- Supabase migration tracking was enabled.
--
-- Idempotency notes:
--   CREATE TABLE IF NOT EXISTS  → true no-op if table exists
--   CREATE INDEX IF NOT EXISTS  → true no-op if index exists
--   ALTER TABLE ADD COLUMN IF NOT EXISTS → true no-op
--   INSERT ... ON CONFLICT DO NOTHING    → true no-op
--   DO $$ EXCEPTION WHEN duplicate_object → true no-op (policies)
--   CREATE OR REPLACE FUNCTION/VIEW → overwrites body (safe if identical)
--   DROP TRIGGER + CREATE TRIGGER   → recreates trigger (safe if identical)
--   CREATE MATERIALIZED VIEW IF NOT EXISTS → true no-op
-- ============================================================

begin;

-- ==========================================================
-- 1. CORE MEDIA TABLES
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.anime (
    id SERIAL PRIMARY KEY,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    title_english TEXT,
    title_romaji TEXT,
    title_native TEXT,
    title_synonyms TEXT[],
    cover_image_large TEXT,
    cover_image_medium TEXT,
    cover_image_color TEXT,
    banner_image TEXT,
    format TEXT,
    status TEXT,
    description TEXT,
    description_normalized TEXT,
    episodes INTEGER,
    duration INTEGER,
    total_duration INTEGER,
    season TEXT,
    season_year INTEGER,
    next_episode_number INTEGER,
    next_airing_at TIMESTAMP WITH TIME ZONE,
    start_date_year INTEGER,
    start_date_month INTEGER,
    start_date_day INTEGER,
    end_date_year INTEGER,
    end_date_month INTEGER,
    end_date_day INTEGER,
    average_score INTEGER,
    mean_score INTEGER,
    popularity INTEGER,
    trending INTEGER,
    favourites INTEGER,
    genres TEXT[],
    source TEXT,
    country_of_origin TEXT,
    is_adult BOOLEAN DEFAULT false,
    age_rating TEXT,
    site_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at_anilist TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS public.manga (
    id SERIAL PRIMARY KEY,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    title_english TEXT,
    title_romaji TEXT,
    title_native TEXT,
    title_synonyms TEXT[],
    cover_image_large TEXT,
    cover_image_medium TEXT,
    cover_image_color TEXT,
    banner_image TEXT,
    format TEXT,
    status TEXT,
    description TEXT,
    description_normalized TEXT,
    chapters INTEGER,
    volumes INTEGER,
    next_chapter_number INTEGER,
    next_chapter_at TIMESTAMP WITH TIME ZONE,
    start_date_year INTEGER,
    start_date_month INTEGER,
    start_date_day INTEGER,
    end_date_year INTEGER,
    end_date_month INTEGER,
    end_date_day INTEGER,
    average_score INTEGER,
    mean_score INTEGER,
    popularity INTEGER,
    trending INTEGER,
    favourites INTEGER,
    genres TEXT[],
    source TEXT,
    country_of_origin TEXT,
    is_adult BOOLEAN DEFAULT false,
    age_rating TEXT,
    site_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at_anilist TIMESTAMP WITH TIME ZONE
);

-- ==========================================================
-- 2. EPISODES / CHAPTERS / VOLUMES
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.episodes (
    id SERIAL PRIMARY KEY,
    anime_id INTEGER REFERENCES public.anime(id) ON DELETE CASCADE,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    air_date DATE,
    air_at TIMESTAMP WITH TIME ZONE,
    thumbnail TEXT,
    duration INTEGER,
    is_filler BOOLEAN DEFAULT false,
    is_recap BOOLEAN DEFAULT false,
    is_mixed BOOLEAN DEFAULT false,
    filler_source TEXT,
    stream_url TEXT,
    stream_site TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ensure stream fields exist on pre-existing table (from 13_alter_episodes)
ALTER TABLE public.episodes ADD COLUMN IF NOT EXISTS stream_url TEXT;
ALTER TABLE public.episodes ADD COLUMN IF NOT EXISTS stream_site TEXT;

CREATE TABLE IF NOT EXISTS public.chapters (
    id SERIAL PRIMARY KEY,
    manga_id INTEGER REFERENCES public.manga(id) ON DELETE CASCADE,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    release_date DATE,
    release_at TIMESTAMP WITH TIME ZONE,
    thumbnail TEXT,
    pages INTEGER,
    is_side_story BOOLEAN DEFAULT false,
    is_extra BOOLEAN DEFAULT false,
    is_omake BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.volumes (
    id SERIAL PRIMARY KEY,
    manga_id INTEGER REFERENCES public.manga(id) ON DELETE CASCADE,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    number INTEGER NOT NULL,
    title TEXT,
    title_romaji TEXT,
    description TEXT,
    cover_image_large TEXT,
    cover_image_medium TEXT,
    release_date DATE,
    release_at TIMESTAMP WITH TIME ZONE,
    pages INTEGER,
    isbn TEXT,
    price_jpy INTEGER,
    price_usd DECIMAL(10,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ==========================================================
-- 3. ENTITY TABLES (characters, studios, authors, staff, tags)
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.characters (
    id SERIAL PRIMARY KEY,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    name_full TEXT,
    name_native TEXT,
    name_alternative TEXT[],
    image_large TEXT,
    image_medium TEXT,
    description TEXT,
    gender TEXT,
    age INTEGER,
    birthday DATE,
    blood_type TEXT,
    height INTEGER,
    weight INTEGER,
    hair_color TEXT,
    eye_color TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.studios (
    id SERIAL PRIMARY KEY,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    name TEXT NOT NULL,
    name_romaji TEXT,
    name_native TEXT,
    description TEXT,
    is_animation_studio BOOLEAN DEFAULT false,
    is_producer BOOLEAN DEFAULT false,
    is_licensor BOOLEAN DEFAULT false,
    site_url TEXT,
    favourites INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.authors (
    id SERIAL PRIMARY KEY,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    name_full TEXT,
    name_native TEXT,
    name_romaji TEXT,
    image_large TEXT,
    image_medium TEXT,
    description TEXT,
    birth_date DATE,
    death_date DATE,
    hometown TEXT,
    blood_type TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.staff (
    id SERIAL PRIMARY KEY,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    kitsu_id INTEGER UNIQUE,
    name_full TEXT,
    name_native TEXT,
    name_romaji TEXT,
    image_large TEXT,
    image_medium TEXT,
    description TEXT,
    primary_occupations TEXT[],
    birth_date DATE,
    death_date DATE,
    hometown TEXT,
    blood_type TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tags (
    id SERIAL PRIMARY KEY,
    anilist_id INTEGER UNIQUE,
    mal_id INTEGER UNIQUE,
    name TEXT NOT NULL,
    name_romaji TEXT,
    name_native TEXT,
    description TEXT,
    category TEXT,
    is_general_spoiler BOOLEAN DEFAULT false,
    is_media_spoiler BOOLEAN DEFAULT false,
    is_adult BOOLEAN DEFAULT false,
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ==========================================================
-- 4. RELATIONSHIP (join) TABLES
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.anime_characters (
    id SERIAL PRIMARY KEY,
    anime_id INTEGER REFERENCES public.anime(id) ON DELETE CASCADE,
    character_id INTEGER REFERENCES public.characters(id) ON DELETE CASCADE,
    role TEXT,
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, character_id)
);

CREATE TABLE IF NOT EXISTS public.manga_characters (
    id SERIAL PRIMARY KEY,
    manga_id INTEGER REFERENCES public.manga(id) ON DELETE CASCADE,
    character_id INTEGER REFERENCES public.characters(id) ON DELETE CASCADE,
    role TEXT,
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, character_id)
);

CREATE TABLE IF NOT EXISTS public.anime_studios (
    id SERIAL PRIMARY KEY,
    anime_id INTEGER REFERENCES public.anime(id) ON DELETE CASCADE,
    studio_id INTEGER REFERENCES public.studios(id) ON DELETE CASCADE,
    role TEXT,
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, studio_id)
);

CREATE TABLE IF NOT EXISTS public.manga_authors (
    id SERIAL PRIMARY KEY,
    manga_id INTEGER REFERENCES public.manga(id) ON DELETE CASCADE,
    author_id INTEGER REFERENCES public.authors(id) ON DELETE CASCADE,
    role TEXT,
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, author_id)
);

CREATE TABLE IF NOT EXISTS public.anime_staff (
    id SERIAL PRIMARY KEY,
    anime_id INTEGER REFERENCES public.anime(id) ON DELETE CASCADE,
    staff_id INTEGER REFERENCES public.staff(id) ON DELETE CASCADE,
    role TEXT,
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, staff_id)
);

CREATE TABLE IF NOT EXISTS public.manga_staff (
    id SERIAL PRIMARY KEY,
    manga_id INTEGER REFERENCES public.manga(id) ON DELETE CASCADE,
    staff_id INTEGER REFERENCES public.staff(id) ON DELETE CASCADE,
    role TEXT,
    role_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, staff_id)
);

CREATE TABLE IF NOT EXISTS public.anime_tags (
    id SERIAL PRIMARY KEY,
    anime_id INTEGER REFERENCES public.anime(id) ON DELETE CASCADE,
    tag_id INTEGER REFERENCES public.tags(id) ON DELETE CASCADE,
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(anime_id, tag_id)
);

CREATE TABLE IF NOT EXISTS public.manga_tags (
    id SERIAL PRIMARY KEY,
    manga_id INTEGER REFERENCES public.manga(id) ON DELETE CASCADE,
    tag_id INTEGER REFERENCES public.tags(id) ON DELETE CASCADE,
    rank INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(manga_id, tag_id)
);

-- ==========================================================
-- 5. USER INTERACTION TABLES
--    (user_id is TEXT to match auth.uid()::text from day one)
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.anime_user_lists (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    anime_id INTEGER REFERENCES public.anime(id) ON DELETE CASCADE,
    list_type TEXT NOT NULL,
    progress INTEGER DEFAULT 0,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, anime_id)
);

CREATE TABLE IF NOT EXISTS public.manga_user_lists (
    id SERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    manga_id INTEGER REFERENCES public.manga(id) ON DELETE CASCADE,
    list_type TEXT NOT NULL,
    progress INTEGER DEFAULT 0,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, manga_id)
);

CREATE TABLE IF NOT EXISTS public.anime_comments (
    id SERIAL PRIMARY KEY,
    anime_id INTEGER REFERENCES public.anime(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    comment TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    is_spoiler BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.manga_comments (
    id SERIAL PRIMARY KEY,
    manga_id INTEGER REFERENCES public.manga(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    comment TEXT NOT NULL,
    rating INTEGER CHECK (rating >= 1 AND rating <= 10),
    is_spoiler BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ==========================================================
-- 6. EXTERNAL LINKS TABLE (from 14_create_external_links)
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.external_links (
    id SERIAL PRIMARY KEY,
    media_type TEXT CHECK (media_type IN ('ANIME','MANGA')) NOT NULL,
    media_id INT NOT NULL,
    site TEXT,
    url TEXT NOT NULL,
    language TEXT,
    color TEXT,
    priority INT DEFAULT 999,
    is_disabled BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(media_type, media_id, url)
);

-- ==========================================================
-- 7. IMPORT STATE TABLE (from 09_import_state)
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.import_state (
    media_type TEXT PRIMARY KEY,
    last_page INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

INSERT INTO public.import_state (media_type, last_page)
VALUES ('ANIME', 0)
ON CONFLICT (media_type) DO NOTHING;

INSERT INTO public.import_state (media_type, last_page)
VALUES ('MANGA', 0)
ON CONFLICT (media_type) DO NOTHING;

-- ==========================================================
-- 8. INDEXES
-- ==========================================================

-- External ID indexes (sync lookups)
CREATE INDEX IF NOT EXISTS idx_anime_anilist_id ON public.anime(anilist_id);
CREATE INDEX IF NOT EXISTS idx_anime_mal_id ON public.anime(mal_id);
CREATE INDEX IF NOT EXISTS idx_manga_anilist_id ON public.manga(anilist_id);
CREATE INDEX IF NOT EXISTS idx_manga_mal_id ON public.manga(mal_id);
CREATE INDEX IF NOT EXISTS idx_characters_anilist_id ON public.characters(anilist_id);
CREATE INDEX IF NOT EXISTS idx_characters_mal_id ON public.characters(mal_id);
CREATE INDEX IF NOT EXISTS idx_studios_anilist_id ON public.studios(anilist_id);
CREATE INDEX IF NOT EXISTS idx_studios_mal_id ON public.studios(mal_id);
CREATE INDEX IF NOT EXISTS idx_authors_anilist_id ON public.authors(anilist_id);
CREATE INDEX IF NOT EXISTS idx_authors_mal_id ON public.authors(mal_id);
CREATE INDEX IF NOT EXISTS idx_staff_anilist_id ON public.staff(anilist_id);
CREATE INDEX IF NOT EXISTS idx_staff_mal_id ON public.staff(mal_id);
CREATE INDEX IF NOT EXISTS idx_tags_anilist_id ON public.tags(anilist_id);
CREATE INDEX IF NOT EXISTS idx_tags_mal_id ON public.tags(mal_id);

-- Content indexes
CREATE INDEX IF NOT EXISTS idx_anime_title_english ON public.anime(title_english);
CREATE INDEX IF NOT EXISTS idx_anime_title_romaji ON public.anime(title_romaji);
CREATE INDEX IF NOT EXISTS idx_anime_status ON public.anime(status);
CREATE INDEX IF NOT EXISTS idx_anime_popularity ON public.anime(popularity DESC);
CREATE INDEX IF NOT EXISTS idx_anime_average_score ON public.anime(average_score DESC);
CREATE INDEX IF NOT EXISTS idx_anime_genres ON public.anime USING GIN(genres);
CREATE INDEX IF NOT EXISTS idx_anime_season_year ON public.anime(season_year);
CREATE INDEX IF NOT EXISTS idx_anime_next_airing ON public.anime(next_airing_at);

CREATE INDEX IF NOT EXISTS idx_manga_title_english ON public.manga(title_english);
CREATE INDEX IF NOT EXISTS idx_manga_title_romaji ON public.manga(title_romaji);
CREATE INDEX IF NOT EXISTS idx_manga_status ON public.manga(status);
CREATE INDEX IF NOT EXISTS idx_manga_popularity ON public.manga(popularity DESC);
CREATE INDEX IF NOT EXISTS idx_manga_average_score ON public.manga(average_score DESC);
CREATE INDEX IF NOT EXISTS idx_manga_genres ON public.manga USING GIN(genres);
CREATE INDEX IF NOT EXISTS idx_manga_next_chapter ON public.manga(next_chapter_at);

-- Relationship indexes
CREATE INDEX IF NOT EXISTS idx_anime_characters_anime_id ON public.anime_characters(anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_characters_character_id ON public.anime_characters(character_id);
CREATE INDEX IF NOT EXISTS idx_manga_characters_manga_id ON public.manga_characters(manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_characters_character_id ON public.manga_characters(character_id);
CREATE INDEX IF NOT EXISTS idx_anime_studios_anime_id ON public.anime_studios(anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_studios_studio_id ON public.anime_studios(studio_id);
CREATE INDEX IF NOT EXISTS idx_manga_authors_manga_id ON public.manga_authors(manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_authors_author_id ON public.manga_authors(author_id);
CREATE INDEX IF NOT EXISTS idx_anime_staff_anime_id ON public.anime_staff(anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_staff_staff_id ON public.anime_staff(staff_id);
CREATE INDEX IF NOT EXISTS idx_manga_staff_manga_id ON public.manga_staff(manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_staff_staff_id ON public.manga_staff(staff_id);
CREATE INDEX IF NOT EXISTS idx_anime_tags_anime_id ON public.anime_tags(anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_tags_tag_id ON public.anime_tags(tag_id);
CREATE INDEX IF NOT EXISTS idx_manga_tags_manga_id ON public.manga_tags(manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_tags_tag_id ON public.manga_tags(tag_id);

-- User interaction indexes
CREATE INDEX IF NOT EXISTS idx_anime_user_lists_user_id ON public.anime_user_lists(user_id);
CREATE INDEX IF NOT EXISTS idx_anime_user_lists_anime_id ON public.anime_user_lists(anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_user_lists_list_type ON public.anime_user_lists(list_type);
CREATE INDEX IF NOT EXISTS idx_manga_user_lists_user_id ON public.manga_user_lists(user_id);
CREATE INDEX IF NOT EXISTS idx_manga_user_lists_manga_id ON public.manga_user_lists(manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_user_lists_list_type ON public.manga_user_lists(list_type);
CREATE INDEX IF NOT EXISTS idx_anime_comments_anime_id ON public.anime_comments(anime_id);
CREATE INDEX IF NOT EXISTS idx_anime_comments_user_id ON public.anime_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_manga_comments_manga_id ON public.manga_comments(manga_id);
CREATE INDEX IF NOT EXISTS idx_manga_comments_user_id ON public.manga_comments(user_id);

-- External links index
CREATE INDEX IF NOT EXISTS idx_external_links_media ON public.external_links(media_type, media_id);

-- Full-text search indexes (from 05_fix_triggers_and_episodes)
CREATE INDEX IF NOT EXISTS idx_anime_description_fts
    ON public.anime
    USING GIN(to_tsvector('english', COALESCE(description_normalized, '')));

CREATE INDEX IF NOT EXISTS idx_manga_description_fts
    ON public.manga
    USING GIN(to_tsvector('english', COALESCE(description_normalized, '')));

CREATE INDEX IF NOT EXISTS idx_anime_title_fts
    ON public.anime
    USING GIN(to_tsvector('english',
        COALESCE(title_english, '') || ' ' ||
        COALESCE(title_romaji, '') || ' ' ||
        COALESCE(title_native, '')
    ));

CREATE INDEX IF NOT EXISTS idx_manga_title_fts
    ON public.manga
    USING GIN(to_tsvector('english',
        COALESCE(title_english, '') || ' ' ||
        COALESCE(title_romaji, '') || ' ' ||
        COALESCE(title_native, '')
    ));

-- ==========================================================
-- 9. FUNCTIONS + TRIGGERS
-- ==========================================================

-- updated_at auto-setter
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- description_normalized auto-setter (from 05_fix_triggers)
CREATE OR REPLACE FUNCTION public.normalize_description()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.description IS NOT NULL THEN
        NEW.description_normalized = LOWER(
            regexp_replace(
                regexp_replace(NEW.description, '<[^>]+>', '', 'g'),
                '\s+', ' ', 'g'
            )
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop + recreate triggers (no CREATE OR REPLACE TRIGGER in PG < 14)
DROP TRIGGER IF EXISTS update_anime_updated_at ON public.anime;
CREATE TRIGGER update_anime_updated_at BEFORE UPDATE ON public.anime
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_manga_updated_at ON public.manga;
CREATE TRIGGER update_manga_updated_at BEFORE UPDATE ON public.manga
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_episodes_updated_at ON public.episodes;
CREATE TRIGGER update_episodes_updated_at BEFORE UPDATE ON public.episodes
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_chapters_updated_at ON public.chapters;
CREATE TRIGGER update_chapters_updated_at BEFORE UPDATE ON public.chapters
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_volumes_updated_at ON public.volumes;
CREATE TRIGGER update_volumes_updated_at BEFORE UPDATE ON public.volumes
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_characters_updated_at ON public.characters;
CREATE TRIGGER update_characters_updated_at BEFORE UPDATE ON public.characters
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_studios_updated_at ON public.studios;
CREATE TRIGGER update_studios_updated_at BEFORE UPDATE ON public.studios
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_authors_updated_at ON public.authors;
CREATE TRIGGER update_authors_updated_at BEFORE UPDATE ON public.authors
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_staff_updated_at ON public.staff;
CREATE TRIGGER update_staff_updated_at BEFORE UPDATE ON public.staff
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_tags_updated_at ON public.tags;
CREATE TRIGGER update_tags_updated_at BEFORE UPDATE ON public.tags
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Description normalization triggers
DROP TRIGGER IF EXISTS set_anime_description_normalized ON public.anime;
CREATE TRIGGER set_anime_description_normalized
    BEFORE INSERT OR UPDATE OF description ON public.anime
    FOR EACH ROW EXECUTE FUNCTION public.normalize_description();

DROP TRIGGER IF EXISTS set_manga_description_normalized ON public.manga;
CREATE TRIGGER set_manga_description_normalized
    BEFORE INSERT OR UPDATE OF description ON public.manga
    FOR EACH ROW EXECUTE FUNCTION public.normalize_description();

-- ==========================================================
-- 10. ROW LEVEL SECURITY
-- ==========================================================

ALTER TABLE public.anime ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manga ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chapters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.volumes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anime_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manga_characters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anime_studios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manga_authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anime_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manga_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anime_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manga_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anime_user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manga_user_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.anime_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manga_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.external_links ENABLE ROW LEVEL SECURITY;

-- Public read policies (idempotent via exception guard)
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.anime FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.manga FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.episodes FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.chapters FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.volumes FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.characters FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.studios FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.authors FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.staff FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.tags FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.anime_characters FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.manga_characters FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.anime_studios FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.manga_authors FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.anime_staff FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.manga_staff FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.anime_tags FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.manga_tags FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Public read access" ON public.external_links FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- User-scoped policies (ALL = select+insert+update+delete)
DO $$ BEGIN
    CREATE POLICY "Users can manage their own lists" ON public.anime_user_lists
        FOR ALL USING (auth.uid()::text = user_id) WITH CHECK (auth.uid()::text = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can manage their own lists" ON public.manga_user_lists
        FOR ALL USING (auth.uid()::text = user_id) WITH CHECK (auth.uid()::text = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can manage their own comments" ON public.anime_comments
        FOR ALL USING (auth.uid()::text = user_id) WITH CHECK (auth.uid()::text = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE POLICY "Users can manage their own comments" ON public.manga_comments
        FOR ALL USING (auth.uid()::text = user_id) WITH CHECK (auth.uid()::text = user_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ==========================================================
-- 11. VIEWS (from 08, 10)
-- ==========================================================

-- Unified user_lists view (from 08_create_user_lists_view)
CREATE OR REPLACE VIEW public.user_lists AS
SELECT
    aul.id,
    aul.user_id::text AS user_id,
    aul.anime_id AS media_id,
    'anime'::text AS media_type,
    aul.list_type AS status,
    aul.progress,
    NULL::integer AS progress_volumes,
    CASE WHEN aul.rating IS NULL THEN NULL ELSE aul.rating * 10 END AS score,
    aul.notes,
    NULL::timestamptz AS started_at,
    NULL::timestamptz AS completed_at,
    FALSE AS private,
    aul.created_at,
    aul.updated_at
FROM public.anime_user_lists aul
UNION ALL
SELECT
    mul.id,
    mul.user_id::text AS user_id,
    mul.manga_id AS media_id,
    'manga'::text AS media_type,
    mul.list_type AS status,
    mul.progress,
    NULL::integer AS progress_volumes,
    CASE WHEN mul.rating IS NULL THEN NULL ELSE mul.rating * 10 END AS score,
    mul.notes,
    NULL::timestamptz AS started_at,
    NULL::timestamptz AS completed_at,
    FALSE AS private,
    mul.created_at,
    mul.updated_at
FROM public.manga_user_lists mul;

-- User airing-next view (from 10_create_user_airing_next_view)
CREATE OR REPLACE VIEW public.user_airing_next AS
SELECT
    aul.user_id        AS user_id,
    a.id               AS anime_id,
    a.title_english,
    a.title_romaji,
    a.next_episode_number,
    a.next_airing_at,
    aul.list_type,
    aul.progress,
    aul.updated_at      AS list_updated_at
FROM public.anime_user_lists aul
JOIN public.anime a ON a.id = aul.anime_id
WHERE a.next_airing_at IS NOT NULL
  AND a.next_airing_at > now()
ORDER BY a.next_airing_at ASC;

-- ==========================================================
-- 12. RPC: airing_next (from 11_airing_next_rpc)
-- ==========================================================

CREATE OR REPLACE FUNCTION public.airing_next(days integer DEFAULT 7)
RETURNS TABLE(
    anime_id int,
    title_english text,
    title_romaji text,
    next_episode_number int,
    next_airing_at timestamptz,
    list_type text,
    progress int
) AS $$
    SELECT
        a.id,
        a.title_english,
        a.title_romaji,
        a.next_episode_number,
        a.next_airing_at,
        aul.list_type,
        aul.progress
    FROM public.anime a
    JOIN public.anime_user_lists aul ON aul.anime_id = a.id
    WHERE aul.user_id = auth.uid()::text
      AND a.next_airing_at IS NOT NULL
      AND a.next_airing_at BETWEEN now() AND (now() + (days || ' days')::interval)
    ORDER BY a.next_airing_at ASC
    LIMIT 500;
$$ LANGUAGE sql SECURITY INVOKER STABLE;

-- ==========================================================
-- 13. IMPORT RUNS TABLE (used by bulk-import-anime/manga edge functions)
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.import_runs (
    id BIGSERIAL PRIMARY KEY,
    media_type TEXT,
    run_type TEXT,
    status TEXT NOT NULL DEFAULT 'running',
    payload JSONB,
    results JSONB,
    message TEXT,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at TIMESTAMPTZ,
    duration_ms INTEGER
);

CREATE INDEX IF NOT EXISTS idx_import_runs_started_at
    ON public.import_runs(started_at DESC);

ALTER TABLE public.import_runs ENABLE ROW LEVEL SECURITY;
-- No policies: import telemetry is internal; service-role/DB owner can still write/read.

-- ==========================================================
-- 14. IMPORT LOCKS + RPCs (used by bulk-import + mirror-images)
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.import_locks (
    lock_key TEXT PRIMARY KEY,
    locked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.import_locks ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.acquire_import_lock(
    p_key text,
    p_ttl_seconds integer DEFAULT 1800
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    acquired boolean;
BEGIN
    INSERT INTO public.import_locks (lock_key, locked_at)
    VALUES (p_key, now())
    ON CONFLICT (lock_key) DO UPDATE
      SET locked_at = EXCLUDED.locked_at
      WHERE public.import_locks.locked_at < now() - make_interval(secs => p_ttl_seconds)
    RETURNING true INTO acquired;

    IF acquired IS NULL THEN
      RETURN false;
    END IF;

    RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_import_lock(p_key text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM public.import_locks WHERE lock_key = p_key;
    RETURN FOUND;
END;
$$;

-- ==========================================================
-- 15. MATERIALIZED VIEWS (Discover sections)
--     Refreshed nightly by pg_cron; queried by discover_bundle
--     RPC and directly by the iOS client.
-- ==========================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_anime_trending AS
SELECT * FROM public.anime
WHERE trending IS NOT NULL AND trending > 0;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_anime_top_rated AS
SELECT * FROM public.anime
WHERE average_score IS NOT NULL AND average_score >= 80;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_anime_current_season AS
SELECT * FROM public.anime
WHERE status = 'RELEASING'
  AND season_year IS NOT NULL
  AND season_year >= (extract(year from now())::int - 1);

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_anime_newly_added AS
SELECT * FROM public.anime;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_manga_trending AS
SELECT * FROM public.manga
WHERE trending IS NOT NULL AND trending > 0;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_manga_top_rated AS
SELECT * FROM public.manga
WHERE average_score IS NOT NULL AND average_score >= 80;

CREATE MATERIALIZED VIEW IF NOT EXISTS public.mv_manga_newly_added AS
SELECT * FROM public.manga;

-- Unique indexes for CONCURRENTLY refresh support.
CREATE UNIQUE INDEX IF NOT EXISTS mv_anime_trending_id ON public.mv_anime_trending(id);
CREATE UNIQUE INDEX IF NOT EXISTS mv_anime_top_rated_id ON public.mv_anime_top_rated(id);
CREATE UNIQUE INDEX IF NOT EXISTS mv_anime_current_season_id ON public.mv_anime_current_season(id);
CREATE UNIQUE INDEX IF NOT EXISTS mv_anime_newly_added_id ON public.mv_anime_newly_added(id);
CREATE UNIQUE INDEX IF NOT EXISTS mv_manga_trending_id ON public.mv_manga_trending(id);
CREATE UNIQUE INDEX IF NOT EXISTS mv_manga_top_rated_id ON public.mv_manga_top_rated(id);
CREATE UNIQUE INDEX IF NOT EXISTS mv_manga_newly_added_id ON public.mv_manga_newly_added(id);

-- ==========================================================
-- 16. MV REFRESH CRON (nightly at 03:00 UTC)
--     Requires pg_cron extension (enabled by concierge_ops migration).
-- ==========================================================

-- Best-effort scheduling. If pg_cron isn't available, skip.
DO $$
BEGIN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_cron;
    EXCEPTION WHEN others THEN
      RETURN;
    END;

    -- Match the production job shape: one nightly job that refreshes all discover matviews.
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'kuro-refresh-matviews') THEN
      PERFORM cron.schedule(
        'kuro-refresh-matviews',
        '30 1 * * *',
        $cmd$
        REFRESH MATERIALIZED VIEW public.mv_anime_trending;
        REFRESH MATERIALIZED VIEW public.mv_anime_top_rated;
        REFRESH MATERIALIZED VIEW public.mv_anime_current_season;
        REFRESH MATERIALIZED VIEW public.mv_anime_newly_added;
        REFRESH MATERIALIZED VIEW public.mv_manga_trending;
        REFRESH MATERIALIZED VIEW public.mv_manga_top_rated;
        REFRESH MATERIALIZED VIEW public.mv_manga_newly_added;
        $cmd$
      );
    END IF;
END;
$$;

-- ==========================================================
-- 17. DEFENSIVE FIXES for legacy schema drift
--     (no-op on fresh DB; patches gaps on legacy DB)
-- ==========================================================

-- tags.kitsu_id was in the foundation CREATE TABLE but may be missing
-- on DBs that ran the original 02_comprehensive_table_creation.sql.
ALTER TABLE public.tags ADD COLUMN IF NOT EXISTS kitsu_id INTEGER UNIQUE;

-- anime_comments / manga_comments user_id was INTEGER in the original
-- schema and was never migrated to TEXT by 12_fix_user_id_type.sql
-- (which only fixed user_lists). Fix it here defensively.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'anime_comments'
          AND column_name = 'user_id'
          AND data_type = 'integer'
    ) THEN
        ALTER TABLE public.anime_comments
            ALTER COLUMN user_id TYPE text USING user_id::text;
    END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'manga_comments'
          AND column_name = 'user_id'
          AND data_type = 'integer'
    ) THEN
        ALTER TABLE public.manga_comments
            ALTER COLUMN user_id TYPE text USING user_id::text;
    END IF;
END;
$$;

commit;
