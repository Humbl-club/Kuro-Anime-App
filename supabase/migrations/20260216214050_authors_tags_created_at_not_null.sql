-- Backfill NULL created_at values and enforce NOT NULL on authors and tags

BEGIN;

-- Backfill authors
UPDATE authors
SET created_at = COALESCE(updated_at, now())
WHERE created_at IS NULL;

-- Backfill tags
UPDATE tags
SET created_at = COALESCE(updated_at, now())
WHERE created_at IS NULL;

-- Enforce NOT NULL
ALTER TABLE authors ALTER COLUMN created_at SET NOT NULL;
ALTER TABLE tags ALTER COLUMN created_at SET NOT NULL;

COMMIT;;
