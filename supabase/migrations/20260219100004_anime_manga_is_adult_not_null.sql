-- Make is_adult NOT NULL on both anime and manga tables
UPDATE anime SET is_adult = false WHERE is_adult IS NULL;
ALTER TABLE anime ALTER COLUMN is_adult SET DEFAULT false;
ALTER TABLE anime ALTER COLUMN is_adult SET NOT NULL;

UPDATE manga SET is_adult = false WHERE is_adult IS NULL;
ALTER TABLE manga ALTER COLUMN is_adult SET DEFAULT false;
ALTER TABLE manga ALTER COLUMN is_adult SET NOT NULL;
