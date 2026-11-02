-- ============================================================================
-- Import Apply / Undo as database transactions (findings F08-F13, ruling P2-R2)
--
-- STATUS: PREPARED, NOT APPLIED TO PRODUCTION. Deployment needs a separate,
--         explicit human approval. This file lives in supabase/prepared-migrations/
--         so no push can deploy it by accident; the lead registers it in
--         supabase/tests/pending_migrations.txt. After approval, `git mv` it into
--         supabase/migrations/ BEFORE deploying the new concierge-apply /
--         concierge-undo edge functions (they call the RPCs below).
--
-- Problem (reproduced against the real handlers, see the modularity contract):
--   the edge functions wrote list rows, journal rows and the session status as
--   separate PostgREST calls and ignored the journal / finalisation errors (F10,
--   F11); a mixed outcome left an undoable write behind a `failed` session (F12);
--   Undo upserted the before-image over later edits and over later deletions
--   (F08, F09) and marked a half-failed Undo `cancelled` (F13).
--
-- Fix: the database owns ONE transaction per Apply and ONE per Undo.
--   apply_import_session(p_user_id, p_session_id, p_idempotency_key, p_items)
--     - p_items are items ALREADY validated and planned by concierge-apply
--       (apply_plan.ts owns validation, clamping, the status vocabulary and which
--       fields are written). Per item:
--         media_type 'ANIME'|'MANGA', media_id int > 0, import_action add|update|skip,
--         expected        null = no check; an object = the row must exist and every
--                         key (list_type / progress) must still equal the stored
--                         value (compare-and-set under the row lock), else conflict,
--         insert_values   the columns written when the row does not exist,
--         update_values   the columns written when it does (only keys present
--                         change; list_type / progress / rating / notes only),
--         journal         {raw, parsed, candidates, confidence} descriptive fields.
--     - accepted list writes, their journal rows (before image AND after image),
--       the session row and its draft -> applied|failed transition commit together
--       or not at all. A list write that violates a table constraint (class 22/23)
--       is an item error: rolled back to the item's savepoint and journaled; it does
--       not abort the batch (partial outcome). Any journal or session error aborts
--       the whole call.
--     - idempotency: (user_id, idempotency_key) is unique; a call with a key that
--       already has a session returns that session's stored outcome
--       (`replayed: true`) and writes nothing. A concurrent duplicate waits on the
--       unique index and then replays.
--     - import-origin taste semantics: taste_import_context is set for the user to
--       this session INSIDE the transaction and deleted before commit, so exactly
--       this transaction's list writes are marked is_import / import_session_id by
--       the taste_capture triggers (never visible to other transactions).
--   undo_import_session(p_user_id, p_session_id)
--     - only the caller's most recent `applied` session (a `partial` Apply is
--       `applied`); per journaled applied item, under the row lock: compares the
--       CURRENT row with the journaled after image field by field; an add whose row
--       is unchanged is deleted; an update reverts only the fields still equal to
--       what the import wrote; a later edit keeps its value and a later deletion
--       stays deleted, both reported in `skipped`
--       (reason edited_since_import | deleted_since_import). Revert writes are
--       marked import-origin like Apply's. The session becomes `cancelled` only after
--       every item resolved; any error rolls everything back and the session stays
--       `applied` (retryable). An already-undone session is reported as such.
--   Both: SECURITY DEFINER, SET search_path = public, extensions, EXECUTE only for
--   service_role (the edge handler derives p_user_id from the verified JWT and
--   never from the request body).
--
-- Lock order (review R2): every list write fires taste_capture, which takes the
--   user's taste_profile_recompute_queue row lock until commit. A manual edit of the
--   same user takes (its list row -> queue row). Writing row 1 and THEN locking row 2
--   would cross that order and deadlock with a manual edit of row 2 (reproduced; the
--   user's own save could be the victim). Both functions therefore lock EVERY existing
--   target row of the batch first (anime_user_lists then manga_user_lists, ascending
--   media id) BEFORE the first write; a manual UPDATE of one of those rows then waits
--   for the batch and applies on top of it. NOT a total closure: a concurrent manual
--   INSERT of the same NEW title from a second client can still cycle (the Apply's
--   insert waits on that uncommitted row while holding the queue row); PostgreSQL
--   resolves it as 40P01 (or 40001), which is HTTP 500 retryable for the Apply, or an
--   error for that insert. Same-user Applies/Undos serialise on the
--   taste_import_context row.
--
-- Mixed deploy window (review A3): the still-deployed old concierge-apply writes the
--   same one-row-per-user taste_import_context through begin_taste_import_context; a
--   new RPC call during an in-flight old Apply overwrites and then deletes that row, so
--   the old Apply's remaining writes lose import origin. Deploy order is therefore:
--   this migration, then concierge-apply AND concierge-undo together.
--
-- Schema (additive): import_session_items.after_values jsonb,
--   import_session_items.reverted_at timestamptz, import_sessions.idempotency_key
--   text + partial unique index per user. Journals written before this migration
--   (no after_values) stay undoable: their after image is action.after.
--
-- Read-only pre-checks on the target before deploying:
--   select column_name from information_schema.columns
--    where table_schema = 'public' and table_name in ('import_sessions', 'import_session_items')
--    order by table_name, column_name;          -- after_values / reverted_at / idempotency_key absent
--   select to_regclass('public.taste_import_context');                   -- not null
--   select pg_get_functiondef('public.check_concierge_rate_limit(text,text,integer,integer,integer)'::regprocedure);
--   select count(*) from public.import_sessions;                          -- index build size (30-day retention)
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, CREATE ... IF NOT EXISTS, CREATE OR REPLACE.
-- Rollback (if the new edge functions are not deployed): drop the three functions;
--   the columns and index are inert for the old edge functions.
-- ============================================================================

do $$
begin
  if to_regclass('public.import_sessions') is null
     or to_regclass('public.import_session_items') is null
     or to_regclass('public.anime_user_lists') is null
     or to_regclass('public.manga_user_lists') is null
     or to_regclass('public.taste_import_context') is null then
    raise exception 'import_apply_undo_transactions: a prerequisite table is missing (import_sessions, import_session_items, anime_user_lists, manga_user_lists, taste_import_context)';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'import_session_items' and column_name = 'previous_values'
  ) then
    raise exception 'import_apply_undo_transactions: import_session_items.previous_values missing (20260209135229_import_reconciliation)';
  end if;
end $$;

alter table public.import_session_items
  add column if not exists after_values jsonb,
  add column if not exists reverted_at timestamptz;

comment on column public.import_session_items.after_values is
  'Values the import wrote: the full tracked row for an insert, only the written fields for an update. Undo compares the current row with it.';
comment on column public.import_session_items.reverted_at is
  'Set when Undo reverted this item (deleted or restored at least one field).';

alter table public.import_sessions
  add column if not exists idempotency_key text;

alter table public.import_sessions drop constraint if exists import_sessions_idempotency_key_len;
alter table public.import_sessions add constraint import_sessions_idempotency_key_len
  check (idempotency_key is null or char_length(idempotency_key) between 1 and 128);

create unique index if not exists import_sessions_user_idempotency_key_uidx
  on public.import_sessions (user_id, idempotency_key)
  where idempotency_key is not null;

-- ---------------------------------------------------------------------------
-- Outcome of an Apply session, built from its journal (the first response and
-- every replay use this one function, so a replay returns the same outcome).
-- ---------------------------------------------------------------------------
create or replace function public._import_apply_outcome(p_session_id uuid, p_replayed boolean)
returns jsonb
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with items as (
    select i.*,
           case when coalesce(i.action ->> 'ordinal', '') ~ '^[0-9]{1,9}$' then (i.action ->> 'ordinal')::integer else 0 end as ord,
           -- same identity rule as the item guard and the Undo journal guard (1..2147483647)
           jsonb_build_object('mediaType', i.chosen ->> 'mediaType',
                              'mediaId', case when coalesce(i.chosen ->> 'mediaId', '') ~ '^[1-9][0-9]{0,9}$'
                                              then case when (i.chosen ->> 'mediaId')::bigint <= 2147483647
                                                        then (i.chosen ->> 'mediaId')::integer end
                                         end) as ident
    from public.import_session_items i
    where i.session_id = p_session_id
  )
  select jsonb_build_object(
    'session_id', p_session_id,
    'replayed', coalesce(p_replayed, false),
    'applied', coalesce((
      select jsonb_agg(ident || jsonb_build_object('status', after_values ->> 'list_type', 'action', import_action)
                       order by ord, created_at, id)
      from items where state = 'applied'), '[]'::jsonb),
    'skipped', coalesce((
      select jsonb_agg(ident order by ord, created_at, id)
      from items where state = 'skipped'), '[]'::jsonb),
    'conflicts', coalesce((
      select jsonb_agg(ident || jsonb_build_object('error', error) order by ord, created_at, id)
      from items where state = 'error' and action ->> 'outcome' = 'conflict'), '[]'::jsonb),
    'errors', coalesce((
      select jsonb_agg(ident || jsonb_build_object('error', error) order by ord, created_at, id)
      from items where state = 'error' and coalesce(action ->> 'outcome', 'error') <> 'conflict'), '[]'::jsonb),
    'undoable', exists (select 1 from public.import_sessions s where s.id = p_session_id and s.status = 'applied')
                and exists (select 1 from items where state = 'applied' and reverted_at is null)
  );
$$;

-- ---------------------------------------------------------------------------
-- Apply: one transaction (list writes + journal + session transition).
-- ---------------------------------------------------------------------------
create or replace function public.apply_import_session(
  p_user_id uuid,
  p_session_id uuid,
  p_idempotency_key text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := p_user_id::text;     -- list tables keep the legacy TEXT user_id (auth.uid()::text)
  v_session_id uuid;
  v_existing uuid;
  v_item jsonb;
  v_ord integer;
  v_type text;
  v_media_id integer;
  v_action text;
  v_table text;
  v_idcol text;
  v_expected jsonb;
  v_values jsonb;
  v_journal jsonb;
  v_cur jsonb;
  v_written jsonb;
  v_prev jsonb;
  v_after jsonb;
  v_outcome text;
  v_error text;
  v_applied integer := 0;
  v_locked bigint;
begin
  if p_user_id is null then
    raise exception 'apply_import_session: p_user_id is required' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 100 then
    raise exception 'apply_import_session: p_items must be an array of 1..100 planned items' using errcode = '22023';
  end if;
  if p_idempotency_key is not null and char_length(p_idempotency_key) not between 1 and 128 then
    raise exception 'apply_import_session: p_idempotency_key must be 1..128 characters' using errcode = '22023';
  end if;

  -- Replay: the same user action (key) never applies twice.
  if p_idempotency_key is not null then
    select s.id into v_existing
    from public.import_sessions s
    where s.user_id = p_user_id and s.idempotency_key = p_idempotency_key;
    if found then
      return public._import_apply_outcome(v_existing, true);
    end if;
  end if;

  v_session_id := coalesce(p_session_id, gen_random_uuid());
  begin
    insert into public.import_sessions (id, user_id, status, source, idempotency_key)
    values (v_session_id, p_user_id, 'draft', 'chat', p_idempotency_key);
  exception when unique_violation then
    -- A concurrent call with the same key committed first (this insert waited on it).
    if p_idempotency_key is null then
      raise;
    end if;
    select s.id into v_existing
    from public.import_sessions s
    where s.user_id = p_user_id and s.idempotency_key = p_idempotency_key;
    if not found then
      raise;
    end if;
    return public._import_apply_outcome(v_existing, true);
  end;

  -- Import origin for the taste_capture triggers, for exactly this transaction.
  insert into public.taste_import_context as c (user_id, session_id, expires_at)
  values (p_user_id, v_session_id, now() + interval '10 minutes')
  on conflict (user_id) do update
    set session_id = excluded.session_id,
        expires_at = excluded.expires_at;

  -- Lock order (see header, review R2): every existing target row of the batch,
  -- anime_user_lists then manga_user_lists, ascending media id, BEFORE the first
  -- write (the first write takes the user's recompute-queue row through taste_capture).
  -- Malformed identities are not cast here; the item loop rejects them.
  select count(*) into v_locked from (
    select 1 from public.anime_user_lists l
    where l.user_id = v_uid
      and l.anime_id in (
        select case when (e ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                    then case when (e ->> 'media_id')::bigint <= 2147483647 then (e ->> 'media_id')::integer end end
        from jsonb_array_elements(p_items) e
        where e ->> 'media_type' = 'ANIME' and e ->> 'import_action' in ('add', 'update')
          and jsonb_typeof(e -> 'media_id') = 'number')
    order by l.anime_id
    for update
  ) locked_anime;
  select count(*) into v_locked from (
    select 1 from public.manga_user_lists l
    where l.user_id = v_uid
      and l.manga_id in (
        select case when (e ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                    then case when (e ->> 'media_id')::bigint <= 2147483647 then (e ->> 'media_id')::integer end end
        from jsonb_array_elements(p_items) e
        where e ->> 'media_type' = 'MANGA' and e ->> 'import_action' in ('add', 'update')
          and jsonb_typeof(e -> 'media_id') = 'number')
    order by l.manga_id
    for update
  ) locked_manga;

  for v_item, v_ord in
    select e.value, e.ordinality::integer
    from jsonb_array_elements(p_items) with ordinality as e(value, ordinality)
    order by e.ordinality
  loop
    v_type := v_item ->> 'media_type';
    v_action := v_item ->> 'import_action';
    if v_type is null or v_type not in ('ANIME', 'MANGA')
       or jsonb_typeof(v_item -> 'media_id') is distinct from 'number'
       or (case when (v_item ->> 'media_id') ~ '^[1-9][0-9]{0,9}$'
                then (v_item ->> 'media_id')::bigint > 2147483647 else true end)
       or v_action is null or v_action not in ('add', 'update', 'skip') then
      raise exception 'apply_import_session: item % is not a planned item (media_type/media_id/import_action)', v_ord
        using errcode = '22023';
    end if;
    v_media_id := (v_item ->> 'media_id')::integer;
    v_table := case v_type when 'ANIME' then 'anime_user_lists' else 'manga_user_lists' end;
    v_idcol := case v_type when 'ANIME' then 'anime_id' else 'manga_id' end;
    v_expected := case when jsonb_typeof(v_item -> 'expected') = 'object' then v_item -> 'expected' end;
    -- Descriptive journal fields are type-checked, never cast blindly: a malformed value is
    -- replaced by its default instead of aborting the Apply.
    v_journal := case when jsonb_typeof(v_item -> 'journal') = 'object' then v_item -> 'journal' else '{}'::jsonb end;
    v_cur := null; v_written := null; v_prev := null; v_after := null; v_outcome := null; v_error := null;

    if v_action = 'skip' then
      v_outcome := 'skipped';
    else
      -- Current row under a row lock (concurrent writers of this row wait for us).
      if v_type = 'ANIME' then
        select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                  'notes', l.notes, 'verdict', l.verdict)
          into v_cur
        from public.anime_user_lists l
        where l.user_id = v_uid and l.anime_id = v_media_id
        for update;
      else
        select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                  'notes', l.notes, 'verdict', l.verdict)
          into v_cur
        from public.manga_user_lists l
        where l.user_id = v_uid and l.manga_id = v_media_id
        for update;
      end if;

      -- Compare-and-set on the state the client reviewed.
      if v_expected is not null then
        if v_cur is null then
          v_outcome := 'conflict';
          v_error := 'Entry no longer exists (deleted since parse)';
        elsif exists (select 1 from jsonb_each(v_expected) e where (v_cur -> e.key) is distinct from e.value) then
          v_outcome := 'conflict';
          v_error := 'State changed since parse — review and retry';
        end if;
      end if;

      if v_outcome is null then
        begin
          if v_cur is null then
            v_values := coalesce(v_item -> 'insert_values', '{}'::jsonb);
            if v_type = 'ANIME' then
              insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, notes)
              values (v_uid, v_media_id, v_values ->> 'list_type', coalesce((v_values ->> 'progress')::integer, 0),
                      (v_values ->> 'rating')::integer, v_values ->> 'notes')
              on conflict (user_id, anime_id) do nothing
              returning jsonb_build_object('list_type', list_type, 'progress', progress, 'rating', rating,
                                           'notes', notes, 'verdict', verdict)
                into v_written;
            else
              insert into public.manga_user_lists (user_id, manga_id, list_type, progress, rating, notes)
              values (v_uid, v_media_id, v_values ->> 'list_type', coalesce((v_values ->> 'progress')::integer, 0),
                      (v_values ->> 'rating')::integer, v_values ->> 'notes')
              on conflict (user_id, manga_id) do nothing
              returning jsonb_build_object('list_type', list_type, 'progress', progress, 'rating', rating,
                                           'notes', notes, 'verdict', verdict)
                into v_written;
            end if;
            if v_written is null then
              -- The row was inserted by another transaction after our read: retry the whole Apply.
              raise exception 'apply_import_session: % % was written concurrently', v_type, v_media_id
                using errcode = '40001';
            end if;
            v_after := v_written;          -- an insert journals the whole tracked row
          else
            v_values := coalesce(v_item -> 'update_values', '{}'::jsonb);
            if v_type = 'ANIME' then
              update public.anime_user_lists l set
                list_type = case when v_values ? 'list_type' then v_values ->> 'list_type' else l.list_type end,
                progress  = case when v_values ? 'progress' then (v_values ->> 'progress')::integer else l.progress end,
                rating    = case when v_values ? 'rating' then (v_values ->> 'rating')::integer else l.rating end,
                notes     = case when v_values ? 'notes' then v_values ->> 'notes' else l.notes end
              where l.user_id = v_uid and l.anime_id = v_media_id
              returning jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                           'notes', l.notes, 'verdict', l.verdict)
                into v_written;
            else
              update public.manga_user_lists l set
                list_type = case when v_values ? 'list_type' then v_values ->> 'list_type' else l.list_type end,
                progress  = case when v_values ? 'progress' then (v_values ->> 'progress')::integer else l.progress end,
                rating    = case when v_values ? 'rating' then (v_values ->> 'rating')::integer else l.rating end,
                notes     = case when v_values ? 'notes' then v_values ->> 'notes' else l.notes end
              where l.user_id = v_uid and l.manga_id = v_media_id
              returning jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                           'notes', l.notes, 'verdict', l.verdict)
                into v_written;
            end if;
            -- an update journals only the fields it wrote, as stored
            select coalesce(jsonb_object_agg(k.key, v_written -> k.key), '{}'::jsonb)
              into v_after
            from jsonb_object_keys(v_values) as k(key)
            where k.key in ('list_type', 'progress', 'rating', 'notes');
            v_prev := v_cur;
          end if;
          v_outcome := 'applied';
          v_applied := v_applied + 1;
        exception when integrity_constraint_violation or data_exception then
          -- This item's data was rejected by the table: item error, batch continues.
          -- A fixed message per SQLSTATE (never schema or constraint names).
          v_outcome := 'error';
          v_error := case when sqlstate = '23503' then 'Unknown title' else 'Value rejected' end;
          v_written := null; v_after := null; v_prev := null;
        end;
      end if;
    end if;

    -- Journal row: REQUIRED (any error here aborts the whole Apply).
    insert into public.import_session_items (
      session_id, raw, parsed, candidates, chosen, action, confidence, state, import_action, error,
      previous_values, after_values
    ) values (
      v_session_id,
      left(case when jsonb_typeof(v_journal -> 'raw') = 'string' then v_journal ->> 'raw'
                else v_type || ':' || v_media_id end, 500),
      case when jsonb_typeof(v_journal -> 'parsed') = 'object' then v_journal -> 'parsed' else '{}'::jsonb end,
      case when jsonb_typeof(v_journal -> 'candidates') = 'array' then v_journal -> 'candidates' else '[]'::jsonb end,
      jsonb_build_object('mediaType', v_type, 'mediaId', v_media_id),
      jsonb_build_object(
        'ordinal', v_ord,
        'outcome', v_outcome,
        'table', case when v_action <> 'skip' then v_table end,
        'key', case when v_action <> 'skip' then jsonb_build_object('user_id', v_uid, v_idcol, v_media_id) end,
        'before', v_cur,
        -- legacy-compatible upsert image (read by the pre-transaction undo during a mixed deploy)
        'after', case when v_outcome = 'applied' then jsonb_build_object('user_id', v_uid, v_idcol, v_media_id) || v_after end
      ),
      case when jsonb_typeof(v_journal -> 'confidence') = 'number' then (v_journal ->> 'confidence')::real else 0 end,
      case v_outcome when 'applied' then 'applied' when 'skipped' then 'skipped' else 'error' end,
      v_action,
      v_error,
      case when v_outcome = 'applied' then v_prev end,
      case when v_outcome = 'applied' then v_after end
    );
  end loop;

  -- Session transition: REQUIRED.
  update public.import_sessions
     set status = case when v_applied > 0 then 'applied' else 'failed' end
   where id = v_session_id and status = 'draft';
  if not found then
    raise exception 'apply_import_session: session % could not be finalized', v_session_id;
  end if;

  delete from public.taste_import_context where user_id = p_user_id and session_id = v_session_id;

  return public._import_apply_outcome(v_session_id, false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Undo: one conditional transaction per session (compare-and-revert).
-- ---------------------------------------------------------------------------
create or replace function public.undo_import_session(p_user_id uuid, p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid text := p_user_id::text;
  v_session record;
  v_latest uuid;
  v_item record;
  v_type text;
  v_media_id integer;
  v_ident jsonb;
  v_after jsonb;
  v_before jsonb;
  v_cur jsonb;
  v_changed text[];
  v_revert text[];
  v_unrestorable text[];
  v_reverted jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_locked bigint;
begin
  if p_user_id is null or p_session_id is null then
    raise exception 'undo_import_session: p_user_id and p_session_id are required' using errcode = '22023';
  end if;

  select s.id, s.user_id, s.status, s.created_at into v_session
  from public.import_sessions s
  where s.id = p_session_id
  for update;
  -- Another user's session is reported exactly like a missing one.
  if not found or v_session.user_id is distinct from p_user_id then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v_session.status = 'cancelled' then
    return jsonb_build_object('result', 'already_undone', 'session_id', p_session_id,
                              'reverted', '[]'::jsonb, 'skipped', '[]'::jsonb, 'warnings', '[]'::jsonb);
  end if;
  if v_session.status <> 'applied'
     or not exists (select 1 from public.import_session_items i where i.session_id = p_session_id and i.state = 'applied') then
    return jsonb_build_object('result', 'not_found');
  end if;

  -- Revert writes are import-origin for the taste_capture triggers (same as Apply).
  -- Also serialises with an in-flight Apply of this user (same context row).
  insert into public.taste_import_context as c (user_id, session_id, expires_at)
  values (p_user_id, p_session_id, now() + interval '10 minutes')
  on conflict (user_id) do update
    set session_id = excluded.session_id,
        expires_at = excluded.expires_at;

  select s.id into v_latest
  from public.import_sessions s
  where s.user_id = p_user_id and s.status = 'applied'
  order by s.created_at desc, s.id desc
  limit 1;
  if v_latest is distinct from p_session_id then
    delete from public.taste_import_context where user_id = p_user_id and session_id = p_session_id;
    return jsonb_build_object('result', 'not_latest');
  end if;

  -- Lock order (see header, review R2): every existing row this Undo may write,
  -- anime_user_lists then manga_user_lists, ascending media id, BEFORE the first write.
  select count(*) into v_locked from (
    select 1 from public.anime_user_lists l
    where l.user_id = v_uid
      and l.anime_id in (
        select case when (i.chosen ->> 'mediaId') ~ '^[1-9][0-9]{0,9}$'
                    then case when (i.chosen ->> 'mediaId')::bigint <= 2147483647 then (i.chosen ->> 'mediaId')::integer end end
        from public.import_session_items i
        where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
          and i.chosen ->> 'mediaType' = 'ANIME')
    order by l.anime_id
    for update
  ) locked_anime;
  select count(*) into v_locked from (
    select 1 from public.manga_user_lists l
    where l.user_id = v_uid
      and l.manga_id in (
        select case when (i.chosen ->> 'mediaId') ~ '^[1-9][0-9]{0,9}$'
                    then case when (i.chosen ->> 'mediaId')::bigint <= 2147483647 then (i.chosen ->> 'mediaId')::integer end end
        from public.import_session_items i
        where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
          and i.chosen ->> 'mediaType' = 'MANGA')
    order by l.manga_id
    for update
  ) locked_manga;

  for v_item in
    select i.id, i.chosen, i.import_action, i.previous_values, i.after_values, i.action
    from public.import_session_items i
    where i.session_id = p_session_id and i.state = 'applied' and i.reverted_at is null
    -- DESCENDING ordinal (review A1): a chain on one title (add then update) unwinds last
    -- write first. Results are prepended, so the response lists items in request order.
    order by case when coalesce(i.action ->> 'ordinal', '') ~ '^[0-9]{1,9}$' then (i.action ->> 'ordinal')::integer else 0 end desc,
             i.created_at desc, i.id desc
  loop
    v_type := v_item.chosen ->> 'mediaType';
    if v_type is null or v_type not in ('ANIME', 'MANGA')
       or (case when coalesce(v_item.chosen ->> 'mediaId', '') ~ '^[1-9][0-9]{0,9}$'
                then (v_item.chosen ->> 'mediaId')::bigint > 2147483647 else true end) then
      v_warnings := jsonb_build_array(jsonb_build_object('id', v_item.id, 'reason', 'invalid_journal_identity')) || v_warnings;
      continue;
    end if;
    v_media_id := (v_item.chosen ->> 'mediaId')::integer;
    v_ident := jsonb_build_object('mediaType', v_type, 'mediaId', v_media_id);

    -- After image: after_values; journals written before 20261005130000 carry it in action.after.
    select jsonb_object_agg(e.key, e.value) into v_after
    from jsonb_each(case
                      when jsonb_typeof(v_item.after_values) = 'object' then v_item.after_values
                      when jsonb_typeof(v_item.action -> 'after') = 'object' then v_item.action -> 'after'
                      else '{}'::jsonb
                    end) e
    where e.key in ('list_type', 'progress', 'rating', 'notes', 'verdict');
    if v_after is null then
      v_warnings := jsonb_build_array((v_ident || jsonb_build_object('reason', 'no_after_image'))) || v_warnings;
      continue;
    end if;
    -- Before image: null means the import created the row.
    v_before := case
                  when jsonb_typeof(v_item.previous_values) = 'object' then v_item.previous_values
                  when jsonb_typeof(v_item.action -> 'before') = 'object' then v_item.action -> 'before'
                end;

    v_cur := null;
    if v_type = 'ANIME' then
      select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                'notes', l.notes, 'verdict', l.verdict)
        into v_cur
      from public.anime_user_lists l
      where l.user_id = v_uid and l.anime_id = v_media_id
      for update;
    else
      select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                'notes', l.notes, 'verdict', l.verdict)
        into v_cur
      from public.manga_user_lists l
      where l.user_id = v_uid and l.manga_id = v_media_id
      for update;
    end if;

    if v_cur is null then
      -- Deleted after the import: stays deleted.
      v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'deleted_since_import'))) || v_skipped;
      continue;
    end if;

    select coalesce(array_agg(e.key order by e.key), '{}') into v_changed
    from jsonb_each(v_after) e
    where (v_cur -> e.key) is distinct from e.value;

    if v_before is null then
      -- The import created the row: delete it only when nothing was changed since.
      if cardinality(v_changed) > 0 then
        v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'edited_since_import', 'fields', to_jsonb(v_changed)))) || v_skipped;
        continue;
      end if;
      if v_type = 'ANIME' then
        delete from public.anime_user_lists where user_id = v_uid and anime_id = v_media_id;
      else
        delete from public.manga_user_lists where user_id = v_uid and manga_id = v_media_id;
      end if;
      v_reverted := jsonb_build_array((v_ident || jsonb_build_object('undoType', 'deleted'))) || v_reverted;
    else
      -- The import changed an existing row: revert each written field still equal to
      -- the after image. The journaled before value is type-checked, never cast blindly:
      -- list_type a string, progress a non-negative integer (a NOT NULL column is never
      -- restored to null), rating null or 1..10, notes null or a string. A field whose
      -- before value is not restorable keeps its value and is reported in warnings.
      select coalesce(array_agg(e.key order by e.key) filter (where r.ok), '{}'),
             coalesce(array_agg(e.key order by e.key) filter (where not r.ok), '{}')
        into v_revert, v_unrestorable
      from jsonb_each(v_after) e
      cross join lateral (
        select coalesce(case e.key
          when 'list_type' then jsonb_typeof(v_before -> 'list_type') = 'string'
          when 'progress'  then jsonb_typeof(v_before -> 'progress') = 'number'
                                and (v_before ->> 'progress') ~ '^[0-9]{1,9}$'
          when 'rating'    then coalesce(jsonb_typeof(v_before -> 'rating'), 'null') = 'null'
                                or (jsonb_typeof(v_before -> 'rating') = 'number'
                                    and (v_before ->> 'rating') ~ '^([1-9]|10)$')
          when 'notes'     then coalesce(jsonb_typeof(v_before -> 'notes'), 'null') in ('null', 'string')
        end, false) as ok
      ) r
      where e.key in ('list_type', 'progress', 'rating', 'notes')
        and (v_cur -> e.key) is not distinct from e.value;
      if cardinality(v_unrestorable) > 0 then
        v_warnings := jsonb_build_array((v_ident || jsonb_build_object('reason', 'unrestorable_before_value',
                                                                   'fields', to_jsonb(v_unrestorable)))) || v_warnings;
      end if;
      if cardinality(v_revert) > 0 then
        if v_type = 'ANIME' then
          update public.anime_user_lists l set
            list_type = case when 'list_type' = any(v_revert) then v_before ->> 'list_type' else l.list_type end,
            progress  = case when 'progress' = any(v_revert) then (v_before ->> 'progress')::integer else l.progress end,
            rating    = case when 'rating' = any(v_revert) then (v_before ->> 'rating')::integer else l.rating end,
            notes     = case when 'notes' = any(v_revert) then v_before ->> 'notes' else l.notes end
          where l.user_id = v_uid and l.anime_id = v_media_id;
        else
          update public.manga_user_lists l set
            list_type = case when 'list_type' = any(v_revert) then v_before ->> 'list_type' else l.list_type end,
            progress  = case when 'progress' = any(v_revert) then (v_before ->> 'progress')::integer else l.progress end,
            rating    = case when 'rating' = any(v_revert) then (v_before ->> 'rating')::integer else l.rating end,
            notes     = case when 'notes' = any(v_revert) then v_before ->> 'notes' else l.notes end
          where l.user_id = v_uid and l.manga_id = v_media_id;
        end if;
        v_reverted := jsonb_build_array((v_ident || jsonb_build_object('undoType', 'restored', 'fields', to_jsonb(v_revert)))) || v_reverted;
      end if;
      if cardinality(v_changed) > 0 then
        v_skipped := jsonb_build_array((v_ident || jsonb_build_object('reason', 'edited_since_import', 'fields', to_jsonb(v_changed)))) || v_skipped;
      end if;
      if cardinality(v_revert) = 0 then
        continue;
      end if;
    end if;

    update public.import_session_items set reverted_at = now() where id = v_item.id;
  end loop;

  update public.import_sessions set status = 'cancelled' where id = p_session_id and status = 'applied';
  if not found then
    raise exception 'undo_import_session: session % changed during undo', p_session_id;
  end if;

  delete from public.taste_import_context where user_id = p_user_id and session_id = p_session_id;

  return jsonb_build_object('result', 'undone', 'session_id', p_session_id,
                            'reverted', v_reverted, 'skipped', v_skipped, 'warnings', v_warnings);
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants: service_role only (Supabase default privileges also grant EXECUTE on
-- new public functions to anon/authenticated, so revoke those explicitly).
-- ---------------------------------------------------------------------------
revoke all on function public._import_apply_outcome(uuid, boolean) from public, anon, authenticated;
revoke all on function public.apply_import_session(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.undo_import_session(uuid, uuid) from public, anon, authenticated;
grant execute on function public.apply_import_session(uuid, uuid, text, jsonb) to service_role;
grant execute on function public.undo_import_session(uuid, uuid) to service_role;
