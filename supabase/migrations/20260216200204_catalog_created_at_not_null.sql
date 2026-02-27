
-- Backfill any NULL created_at values, then enforce NOT NULL.
-- Uses COALESCE: created_at → updated_at → now().

DO $$ 
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY['anime','manga','episodes','chapters','volumes','characters','studios','staff'])
  LOOP
    EXECUTE format(
      'UPDATE %I SET created_at = COALESCE(updated_at, now()) WHERE created_at IS NULL',
      tbl
    );
    EXECUTE format(
      'ALTER TABLE %I ALTER COLUMN created_at SET DEFAULT now()',
      tbl
    );
    EXECUTE format(
      'ALTER TABLE %I ALTER COLUMN created_at SET NOT NULL',
      tbl
    );
  END LOOP;
END $$;
;
