CREATE OR REPLACE FUNCTION public.apply_import_session(p_user_id uuid, p_session_id uuid, p_idempotency_key text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$

