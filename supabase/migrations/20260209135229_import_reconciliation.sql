ALTER TABLE public.import_session_items
  ADD COLUMN IF NOT EXISTS import_action text NOT NULL DEFAULT 'add'
    CHECK (import_action IN ('add', 'update', 'skip'));

ALTER TABLE public.import_session_items
  ADD COLUMN IF NOT EXISTS previous_values jsonb;;
