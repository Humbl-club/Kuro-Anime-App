-- Forward lifecycle repair for the integrated series foundation. Prepared only.
-- Auth foreign keys validate existing ownership; orphaned data aborts this migration
-- for explicit review rather than being silently purged or rewritten.
BEGIN;
ALTER TABLE public.library_import_jobs
    ADD CONSTRAINT library_import_jobs_auth_owner
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

DO $$
DECLARE relation_name text;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY[
        'user_series_intent', 'home_publications', 'mutation_receipts', 'list_entry_tombstones'
    ] LOOP
        EXECUTE format('ALTER TABLE public.%I ADD COLUMN account_user_id uuid GENERATED ALWAYS AS (user_id::uuid) STORED', relation_name);
        EXECUTE format('ALTER TABLE public.%I ADD CONSTRAINT %I FOREIGN KEY (account_user_id) REFERENCES auth.users(id) ON DELETE CASCADE',
            relation_name, relation_name || '_auth_owner');
        EXECUTE format('CREATE INDEX %I ON public.%I(account_user_id)',
            relation_name || '_auth_owner_idx', relation_name);
    END LOOP;
END;
$$;

CREATE FUNCTION public.series_account_write_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions AS $$
DECLARE owner_text text := to_jsonb(NEW)->>'user_id'; owner_id uuid;
BEGIN
    BEGIN
        owner_id := owner_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'INVALID_ACCOUNT' USING ERRCODE = '42501';
    END;
    IF owner_id IS NULL THEN
        RAISE EXCEPTION 'INVALID_ACCOUNT' USING ERRCODE = '42501';
    END IF;
    -- Reuse the existing deletion lock and committed barrier. Old JWT validity
    -- cannot admit writes while account deletion is in progress.
    PERFORM public._account_write_guard(owner_id::text);
    -- Hold the live owner until this transaction ends. GoTrue deletion either
    -- waits and cascades this write, or finishes first and this write is refused.
    PERFORM 1 FROM auth.users WHERE id = owner_id FOR KEY SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ACCOUNT_DELETION_IN_PROGRESS' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.series_account_write_guard() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE relation_name text;
BEGIN
    FOREACH relation_name IN ARRAY ARRAY[
        'library_import_jobs', 'user_series_intent', 'mutation_receipts'
    ] LOOP
        EXECUTE format('CREATE TRIGGER series_account_write_guard BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.series_account_write_guard()', relation_name);
    END LOOP;
END;
$$;
-- Tombstones and Home publications have no client write grants. Internal list
-- deletion may write them after the deletion barrier; guarding that cleanup
-- would prevent deletion itself. Their validated auth FK still prevents orphan
-- creation and cascades the internal cleanup records with the deleted account.
COMMIT;
