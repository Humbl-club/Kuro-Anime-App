-- Fix P0: Non-optional Swift properties decoding nullable DB columns
-- All columns have defaults and zero null rows — safe to constrain

-- anime
ALTER TABLE anime ALTER COLUMN updated_at SET NOT NULL;

-- manga
ALTER TABLE manga ALTER COLUMN updated_at SET NOT NULL;

-- episodes
ALTER TABLE episodes ALTER COLUMN is_filler SET NOT NULL;
ALTER TABLE episodes ALTER COLUMN is_recap SET NOT NULL;
ALTER TABLE episodes ALTER COLUMN is_mixed SET NOT NULL;
ALTER TABLE episodes ALTER COLUMN updated_at SET NOT NULL;

-- chapters
ALTER TABLE chapters ALTER COLUMN updated_at SET NOT NULL;

-- external_links
ALTER TABLE external_links ALTER COLUMN is_disabled SET NOT NULL;
ALTER TABLE external_links ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE external_links ALTER COLUMN updated_at SET NOT NULL;

-- anime_user_lists
ALTER TABLE anime_user_lists ALTER COLUMN progress SET NOT NULL;
ALTER TABLE anime_user_lists ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE anime_user_lists ALTER COLUMN updated_at SET NOT NULL;

-- manga_user_lists
ALTER TABLE manga_user_lists ALTER COLUMN progress SET NOT NULL;
ALTER TABLE manga_user_lists ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE manga_user_lists ALTER COLUMN updated_at SET NOT NULL;

-- feature_flags
ALTER TABLE feature_flags ALTER COLUMN target_markets SET NOT NULL;
