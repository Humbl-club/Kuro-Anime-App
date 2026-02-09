-- Import reconciliation: add columns for action type and previous state snapshot.
--
-- The existing "action" column is jsonb storing {table, key, before, after}.
-- We add "import_action" for the reconciliation action type (add/update/skip)
-- and "previous_values" for a clean snapshot of the pre-import user-list row.

begin;

ALTER TABLE public.import_session_items
  ADD COLUMN IF NOT EXISTS import_action text NOT NULL DEFAULT 'add'
    CHECK (import_action IN ('add', 'update', 'skip'));

ALTER TABLE public.import_session_items
  ADD COLUMN IF NOT EXISTS previous_values jsonb;

commit;
