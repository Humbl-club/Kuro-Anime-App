-- ============================================================
-- CLUBS FOUNDATION MIGRATION
-- Creates the 7 core club tables, invite-code helper function,
-- indexes on all foreign keys, and updated_at triggers.
--
-- RLS is enabled on every table; policies are added in a
-- separate migration (clubs_rls_policies).
--
-- IMPORTANT — user_id type mismatch:
--   Club tables use  user_id UUID REFERENCES auth.users(id)
--   Legacy tables    anime_user_lists.user_id / manga_user_lists.user_id are TEXT
--   Any joins between club_members and user-list tables MUST cast:
--     cm.user_id::text = aul.user_id
--   This mismatch exists because the original schema predates typed auth
--   integration. A future migration may unify them.
-- ============================================================

begin;

-- ==========================================================
-- 0. HELPER: generate_invite_code()
--    8-char case-sensitive alphanumeric (a-zA-Z0-9 = 62 chars)
--    62^8 ≈ 218 trillion combinations
-- ==========================================================

CREATE OR REPLACE FUNCTION public.generate_invite_code(p_length int DEFAULT 8)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  _alphabet text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  _code text := '';
  _i int;
BEGIN
  FOR _i IN 1..p_length LOOP
    _code := _code || substr(_alphabet, floor(random() * 62 + 1)::int, 1);
  END LOOP;
  RETURN _code;
END;
$$;

-- ==========================================================
-- 1. clubs
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.clubs (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text        NOT NULL CHECK (char_length(name) <= 80),
  description   text        CHECK (char_length(description) <= 500),
  created_by    uuid        NOT NULL REFERENCES auth.users(id),
  invite_code   text        UNIQUE NOT NULL DEFAULT public.generate_invite_code(),
  invite_expires_at  timestamptz,
  invite_max_uses    int,
  invite_use_count   int     NOT NULL DEFAULT 0,
  sharing_level text        NOT NULL DEFAULT 'status'
                            CHECK (sharing_level IN ('private', 'status', 'progress')),
  max_members   int         NOT NULL DEFAULT 20,
  is_archived   boolean     NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Indexes (spec 2.1)
CREATE INDEX IF NOT EXISTS idx_clubs_invite_code ON public.clubs(invite_code);
CREATE INDEX IF NOT EXISTS idx_clubs_created_by  ON public.clubs(created_by);

-- ==========================================================
-- 2. club_members
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.club_members (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id       uuid        NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  -- user_id is UUID here; see top-of-file comment about TEXT mismatch with user lists
  user_id       uuid        NOT NULL REFERENCES auth.users(id),
  role          text        NOT NULL DEFAULT 'member'
                            CHECK (role IN ('owner', 'admin', 'member')),
  sharing_level text        CHECK (sharing_level IN ('private', 'status', 'progress')),
  joined_at     timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (club_id, user_id)
);

-- Indexes (spec 2.2)
CREATE INDEX IF NOT EXISTS idx_club_members_user ON public.club_members(user_id);
CREATE INDEX IF NOT EXISTS idx_club_members_club ON public.club_members(club_id);

-- ==========================================================
-- 3. club_rails
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.club_rails (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id       uuid        NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  title         text        NOT NULL CHECK (char_length(title) <= 120),
  description   text        CHECK (char_length(description) <= 500),
  created_by    uuid        NOT NULL REFERENCES auth.users(id),
  is_locked     boolean     NOT NULL DEFAULT false,
  sort_order    int         NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Index (spec 2.3)
CREATE INDEX IF NOT EXISTS idx_club_rails_club_sort ON public.club_rails(club_id, sort_order);

-- ==========================================================
-- 4. club_rail_items
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.club_rail_items (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  rail_id       uuid        NOT NULL REFERENCES public.club_rails(id) ON DELETE CASCADE,
  media_type    text        NOT NULL CHECK (media_type IN ('ANIME', 'MANGA')),
  media_id      int         NOT NULL,
  -- added_by is UUID; see top-of-file comment about TEXT mismatch with user lists
  added_by      uuid        NOT NULL REFERENCES auth.users(id),
  sort_order    int         NOT NULL DEFAULT 0,
  note          text        CHECK (char_length(note) <= 280),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (rail_id, media_type, media_id)
);

-- Index (spec 2.4)
CREATE INDEX IF NOT EXISTS idx_club_rail_items_rail_sort ON public.club_rail_items(rail_id, sort_order);

-- ==========================================================
-- 5. club_polls
--    NOTE: No is_active column. Use closes_at + is_closed for
--    open/closed state (devils-advocate M4).
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.club_polls (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id       uuid        NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  question      text        NOT NULL CHECK (char_length(question) <= 200),
  created_by    uuid        NOT NULL REFERENCES auth.users(id),
  closes_at     timestamptz,
  is_closed     boolean     NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Index (spec 2.5)
CREATE INDEX IF NOT EXISTS idx_club_polls_club_created ON public.club_polls(club_id, created_at DESC);

-- ==========================================================
-- 6. club_poll_options
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.club_poll_options (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id       uuid        NOT NULL REFERENCES public.club_polls(id) ON DELETE CASCADE,
  label         text        NOT NULL CHECK (char_length(label) <= 120),
  media_type    text        CHECK (media_type IN ('ANIME', 'MANGA')),
  media_id      int,
  sort_order    int         NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Index on FK
CREATE INDEX IF NOT EXISTS idx_club_poll_options_poll ON public.club_poll_options(poll_id);

-- ==========================================================
-- 7. club_votes
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.club_votes (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id       uuid        NOT NULL REFERENCES public.club_polls(id) ON DELETE CASCADE,
  option_id     uuid        NOT NULL REFERENCES public.club_poll_options(id) ON DELETE CASCADE,
  -- user_id is UUID; see top-of-file comment about TEXT mismatch with user lists
  user_id       uuid        NOT NULL REFERENCES auth.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (poll_id, user_id)
);

-- Indexes on FKs
CREATE INDEX IF NOT EXISTS idx_club_votes_option  ON public.club_votes(option_id);
CREATE INDEX IF NOT EXISTS idx_club_votes_poll    ON public.club_votes(poll_id);
CREATE INDEX IF NOT EXISTS idx_club_votes_user    ON public.club_votes(user_id);

-- ==========================================================
-- 8. UPDATED_AT TRIGGERS
--    Reuses public.set_updated_at() created in concierge_core migration.
-- ==========================================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'clubs_set_updated_at') THEN
    CREATE TRIGGER clubs_set_updated_at
      BEFORE UPDATE ON public.clubs
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'club_members_set_updated_at') THEN
    CREATE TRIGGER club_members_set_updated_at
      BEFORE UPDATE ON public.club_members
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'club_rails_set_updated_at') THEN
    CREATE TRIGGER club_rails_set_updated_at
      BEFORE UPDATE ON public.club_rails
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'club_rail_items_set_updated_at') THEN
    CREATE TRIGGER club_rail_items_set_updated_at
      BEFORE UPDATE ON public.club_rail_items
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'club_polls_set_updated_at') THEN
    CREATE TRIGGER club_polls_set_updated_at
      BEFORE UPDATE ON public.club_polls
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

-- club_poll_options has no updated_at (append-only per spec)
-- club_votes has no updated_at (append-only per spec)

-- ==========================================================
-- 9. ENABLE ROW LEVEL SECURITY
--    Policies will be added in a separate migration.
-- ==========================================================

ALTER TABLE public.clubs             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_members      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_rails        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_rail_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_polls        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.club_votes        ENABLE ROW LEVEL SECURITY;

commit;
