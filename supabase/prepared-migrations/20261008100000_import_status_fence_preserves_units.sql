-- Forward-only repair: preserve exact tracking through legacy Apply and Undo.
-- Existing migration identities and deployed history remain unchanged.
-- All replacements are atomic; ownership, admission/row locks and service ACLs
-- are retained. No historical session backfill is performed.
begin;

create or replace function public._apply_progress_mutations_for_user(
  p_user text,
  p_mutations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user text := p_user;
  v_item jsonb;
  v_results jsonb := '[]'::jsonb;
  v_mutation uuid;
  v_medium text;
  v_media_id integer;
  v_lifecycle uuid;
  v_unit uuid;
  v_base bigint;
  v_position integer;
  v_label text;
  v_status text;
  v_hash text;
  v_canonical text;
  v_receipt public.mutation_receipts%rowtype;
  v_revision bigint;
  v_lifecycle_row uuid;
  v_progress integer;
  v_notes text;
  v_rating integer;
  v_list_type text;
  v_found boolean;
  v_outcome text;
  v_tombstone boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user,0));
  if v_user is null or btrim(v_user) = '' then
    raise exception 'UNAUTHENTICATED';
  end if;
  if p_mutations is null or jsonb_typeof(p_mutations) <> 'array' then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if jsonb_array_length(p_mutations) > 50 then
    raise exception 'BATCH_TOO_LARGE';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(p_mutations) as t(value)
    order by t.value->>'medium', (t.value->>'media_id'), t.value->>'mutation_id'
  loop
    begin
      v_mutation := (v_item->>'mutation_id')::uuid;
      v_medium := v_item->>'medium';
      v_media_id := (v_item->>'media_id')::integer;
      v_lifecycle := (v_item->>'lifecycle_id')::uuid;
      v_base := (v_item->>'base_revision')::bigint;
      v_position := (v_item->>'position')::integer;
      v_label := v_item->>'position_label';
      v_status := v_item->>'status';
      if v_item->>'unit_id' is null or v_item->>'unit_id' = '' then
        v_unit := null;
      else
        v_unit := (v_item->>'unit_id')::uuid;
      end if;
    exception when others then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_item->>'mutation_id', 'outcome', 'invalid_target'
      ));
      continue;
    end;

    if v_mutation is null or v_media_id is null or v_lifecycle is null
       or v_medium is null or v_medium not in ('anime', 'manga') or v_base is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_position is not null and v_position < 0 then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_position is null and v_status is null and v_label is null then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;
    if v_status is not null and v_status not in ('WATCHING', 'READING', 'PLANNING', 'COMPLETED', 'DROPPED', 'PAUSED') then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;

    v_found := false;
    if v_medium = 'anime' then
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id
      for update;
      v_found := found;
    else
      select server_revision, lifecycle_id, progress, notes, rating, list_type
        into v_revision, v_lifecycle_row, v_progress, v_notes, v_rating, v_list_type
      from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id
      for update;
      v_found := found;
    end if;

    v_canonical := jsonb_build_object(
      'medium', v_medium, 'media_id', v_media_id, 'lifecycle_id', v_lifecycle,
      'base_revision', v_base, 'unit_id', v_unit, 'position', v_item->'position',
      'position_label', v_item->'position_label', 'status', v_item->'status',
      'has_position',v_item ? 'position','has_unit_id',v_item ? 'unit_id',
      'has_position_label',v_item ? 'position_label','has_status',v_item ? 'status'
    )::text;
    v_hash := encode(digest(v_canonical, 'sha256'), 'hex');

    select * into v_receipt
    from public.mutation_receipts
    where user_id = v_user and mutation_id = v_mutation;

    if v_receipt.mutation_id is not null then
      v_outcome := case when v_receipt.request_hash <> v_hash then 'rejected_payload'
        when v_receipt.outcome in ('applied','already_applied') then 'already_applied' else v_receipt.outcome end;
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', v_outcome,
        'server_revision', v_receipt.server_revision,
        'position', v_receipt.position
      ));
      continue;
    end if;

    select exists (
      select 1 from public.list_entry_tombstones t
      where t.user_id = v_user and t.medium = v_medium and t.media_id = v_media_id
        and t.lifecycle_id = v_lifecycle
    ) into v_tombstone;

    if v_tombstone or (v_found and v_lifecycle_row is distinct from v_lifecycle) then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'removed_entry'
      ));
      continue;
    end if;

    if not v_found then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation, 'outcome', 'invalid_target'
      ));
      continue;
    end if;

    if v_revision is distinct from v_base then
      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'mutation_id', v_mutation,
        'outcome', 'conflict',
        'server_revision', v_revision,
        'position', v_progress,
        'notes', v_notes,
        'rating', v_rating,
        'status', v_list_type
      ));
      continue;
    end if;

    if v_unit is not null and not exists (
      select 1 from public.catalogue_units u where u.id = v_unit and u.medium = v_medium
        and ((v_medium = 'anime' and u.anime_id = v_media_id)
          or (v_medium = 'manga' and u.manga_id = v_media_id))
    ) then
      v_results := v_results || jsonb_build_array(jsonb_build_object('mutation_id', v_mutation, 'outcome', 'invalid_target'));
      continue;
    end if;
    -- Missing position is retained only after hashing/replay lookup of the immutable body.
    v_position := coalesce(v_position, v_progress, 0);

    if v_medium = 'anime' then
      if v_label is not null and v_label !~ '^[0-9]+$' then
        update public.anime_user_lists
          set progress = v_position,
              progress_label = v_label,
              unit_id = case when v_item ? 'unit_id' then v_unit else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and anime_id = v_media_id;
      else
        update public.anime_user_lists
          set progress = v_position,
              progress_label = case when v_item ? 'position_label' then v_label when v_item ? 'position' then null else progress_label end,
              unit_id = case when v_item ? 'unit_id' then v_unit when v_item ? 'position' then null else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and anime_id = v_media_id;
      end if;
      select server_revision, progress into v_revision, v_progress
      from public.anime_user_lists
      where user_id = v_user and anime_id = v_media_id;
    else
      if v_label is not null and v_label !~ '^[0-9]+$' then
        update public.manga_user_lists
          set progress = v_position,
              progress_label = v_label,
              unit_id = case when v_item ? 'unit_id' then v_unit else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and manga_id = v_media_id;
      else
        update public.manga_user_lists
          set progress = v_position,
              progress_label = case when v_item ? 'position_label' then v_label when v_item ? 'position' then null else progress_label end,
              unit_id = case when v_item ? 'unit_id' then v_unit when v_item ? 'position' then null else unit_id end,
              list_type = coalesce(v_status, list_type)
        where user_id = v_user and manga_id = v_media_id;
      end if;
      select server_revision, progress into v_revision, v_progress
      from public.manga_user_lists
      where user_id = v_user and manga_id = v_media_id;
    end if;

    insert into public.mutation_receipts
      (user_id, mutation_id, request_hash, outcome, medium, media_id, server_revision, position)
    values
      (v_user, v_mutation, v_hash, 'applied', v_medium, v_media_id, v_revision, v_progress);

    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'mutation_id', v_mutation,
      'outcome', 'applied',
      'server_revision', v_revision,
      'position', v_progress
    ));
  end loop;

  return jsonb_build_object('items', v_results);
end;
$$;

create or replace function public._fence_set_progress_status(
  p_user text,
  p_medium text,
  p_media_id integer,
  p_mutation_id uuid,
  p_progress integer,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_lifecycle uuid;
  v_revision bigint;
  v_mutation jsonb;
  v_result jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user,0));
  if p_user is null or p_medium is null or p_media_id is null or p_mutation_id is null then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_PAYLOAD';
  end if;
  if p_progress is null and p_status is null then
    raise exception 'INVALID_PAYLOAD';
  end if;

  if p_medium = 'anime' then
    select lifecycle_id, server_revision
      into v_lifecycle, v_revision
    from public.anime_user_lists
    where user_id = p_user and anime_id = p_media_id
    for update;
  else
    select lifecycle_id, server_revision
      into v_lifecycle, v_revision
    from public.manga_user_lists
    where user_id = p_user and manga_id = p_media_id
    for update;
  end if;
  if v_lifecycle is null then
    raise exception 'INVALID_TARGET';
  end if;

  -- Omitted progress is not an integer progress write: keep selected units and
  -- exact labels. Explicit zero remains an intentional progress write.
  v_mutation := jsonb_build_object(
    'mutation_id', p_mutation_id, 'medium', p_medium, 'media_id', p_media_id,
    'lifecycle_id', v_lifecycle, 'base_revision', v_revision
  );
  if p_progress is not null then
    v_mutation := v_mutation || jsonb_build_object('position', p_progress);
  end if;
  if p_status is not null then
    v_mutation := v_mutation || jsonb_build_object('status', p_status);
  end if;
  v_result := public._apply_progress_mutations_for_user(p_user, jsonb_build_array(v_mutation));
  return v_result -> 'items' -> 0;
end;
$$;

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
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user_id::text,0));
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
                                  'notes', l.notes, 'verdict', l.verdict,
                                  'unit_id', l.unit_id, 'progress_label', l.progress_label, 'lifecycle_id', l.lifecycle_id)
          into v_cur
        from public.anime_user_lists l
        where l.user_id = v_uid and l.anime_id = v_media_id
        for update;
      else
        select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                  'notes', l.notes, 'verdict', l.verdict,
                                  'unit_id', l.unit_id, 'progress_label', l.progress_label, 'lifecycle_id', l.lifecycle_id)
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
                                           'notes', notes, 'verdict', verdict,
                                           'unit_id', unit_id, 'progress_label', progress_label, 'lifecycle_id', lifecycle_id)
                into v_written;
            else
              insert into public.manga_user_lists (user_id, manga_id, list_type, progress, rating, notes)
              values (v_uid, v_media_id, v_values ->> 'list_type', coalesce((v_values ->> 'progress')::integer, 0),
                      (v_values ->> 'rating')::integer, v_values ->> 'notes')
              on conflict (user_id, manga_id) do nothing
              returning jsonb_build_object('list_type', list_type, 'progress', progress, 'rating', rating,
                                           'notes', notes, 'verdict', verdict,
                                           'unit_id', unit_id, 'progress_label', progress_label, 'lifecycle_id', lifecycle_id)
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
            -- Progress/status go through the series receipt fence. Notes/rating stay
            -- direct writes and still advance server_revision via their triggers.
            if v_values ? 'progress' or v_values ? 'list_type' then
              perform public._fence_set_progress_status(
                v_uid,
                case v_type when 'ANIME' then 'anime' else 'manga' end,
                v_media_id,
                public._import_mutation_id('apply', v_session_id, v_type, v_media_id),
                case when v_values ? 'progress' then (v_values ->> 'progress')::integer end,
                case when v_values ? 'list_type' then v_values ->> 'list_type' end
              );
            end if;
            if v_values ? 'rating' or v_values ? 'notes' then
              if v_type = 'ANIME' then
                update public.anime_user_lists l set
                  rating = case when v_values ? 'rating' then (v_values ->> 'rating')::integer else l.rating end,
                  notes  = case when v_values ? 'notes' then v_values ->> 'notes' else l.notes end
                where l.user_id = v_uid and l.anime_id = v_media_id;
              else
                update public.manga_user_lists l set
                  rating = case when v_values ? 'rating' then (v_values ->> 'rating')::integer else l.rating end,
                  notes  = case when v_values ? 'notes' then v_values ->> 'notes' else l.notes end
                where l.user_id = v_uid and l.manga_id = v_media_id;
              end if;
            end if;
            if v_type = 'ANIME' then
              select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                       'notes', l.notes, 'verdict', l.verdict,
                                  'unit_id', l.unit_id, 'progress_label', l.progress_label, 'lifecycle_id', l.lifecycle_id)
                into v_written
              from public.anime_user_lists l
              where l.user_id = v_uid and l.anime_id = v_media_id;
            else
              select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                       'notes', l.notes, 'verdict', l.verdict,
                                  'unit_id', l.unit_id, 'progress_label', l.progress_label, 'lifecycle_id', l.lifecycle_id)
                into v_written
              from public.manga_user_lists l
              where l.user_id = v_uid and l.manga_id = v_media_id;
            end if;
            -- an update journals only the fields it wrote, as stored
            select coalesce(jsonb_object_agg(k.key, v_written -> k.key), '{}'::jsonb)
              into v_after
            from jsonb_object_keys(v_written) as k(key)
            where (k.key in ('list_type', 'progress', 'rating', 'notes') and v_values ? k.key)
               or (v_values ? 'progress' and k.key in ('unit_id', 'progress_label'))
               or k.key = 'lifecycle_id';
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
  v_restore jsonb;
  v_restore_result jsonb;
  v_precise boolean;
begin
  perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||p_user_id::text,0));
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
    where e.key in ('list_type', 'progress', 'rating', 'notes', 'verdict', 'unit_id', 'progress_label', 'lifecycle_id');
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
                                'notes', l.notes, 'verdict', l.verdict,
                                  'unit_id', l.unit_id, 'progress_label', l.progress_label, 'lifecycle_id', l.lifecycle_id)
        into v_cur
      from public.anime_user_lists l
      where l.user_id = v_uid and l.anime_id = v_media_id
      for update;
    else
      select jsonb_build_object('list_type', l.list_type, 'progress', l.progress, 'rating', l.rating,
                                'notes', l.notes, 'verdict', l.verdict,
                                  'unit_id', l.unit_id, 'progress_label', l.progress_label, 'lifecycle_id', l.lifecycle_id)
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

    -- New snapshots bind Undo to the entry lifetime that Apply actually wrote.
    -- Historical snapshots have no such proof; do not infer one from equal fields
    -- or an absence of tombstones (pre-foundation removals were not recorded).
    if not (v_after ? 'lifecycle_id') or jsonb_typeof(v_after -> 'lifecycle_id') <> 'string' then
      v_skipped := jsonb_build_array((v_ident || jsonb_build_object(
        'reason', 'legacy_lifecycle_unavailable'))) || v_skipped;
      continue;
    elsif (v_cur -> 'lifecycle_id') is distinct from (v_after -> 'lifecycle_id') then
      v_skipped := jsonb_build_array((v_ident || jsonb_build_object(
        'reason', 'removed_since_import'))) || v_skipped;
      continue;
    end if;

    select coalesce(array_agg(e.key order by e.key), '{}') into v_changed
    from jsonb_each(v_after) e
    where (v_cur -> e.key) is distinct from e.value;

    if v_before is null then
      -- Older journals cannot prove that a current precise selection was absent.
      if not (v_after ? 'unit_id' and v_after ? 'progress_label')
         and (v_cur ->> 'unit_id' is not null or v_cur ->> 'progress_label' is not null) then
        v_changed := v_changed || array['unit_id', 'progress_label'];
      end if;
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
          when 'rating'    then coalesce(jsonb_typeof(v_before -> 'rating'), 'null') = 'null'
                                or (jsonb_typeof(v_before -> 'rating') = 'number'
                                    and (v_before ->> 'rating') ~ '^([1-9]|10)$')
          when 'notes'     then coalesce(jsonb_typeof(v_before -> 'notes'), 'null') in ('null', 'string')
        end, false) as ok
      ) r
      where e.key in ('list_type', 'rating', 'notes')
        and (v_cur -> e.key) is not distinct from e.value;
      -- Progress, selected unit and exact label form one tracking value. Do not
      -- partially undo it when any component was edited after Apply.
      if v_after ? 'progress' then
        v_precise := v_after ? 'unit_id' and v_after ? 'progress_label'
                     and v_before ? 'unit_id' and v_before ? 'progress_label';
        if v_precise and exists (
          select 1 from unnest(array['progress', 'unit_id', 'progress_label']) k
          where (v_cur -> k) is distinct from (v_after -> k)
        ) then
          v_changed := v_changed || array['progress', 'unit_id', 'progress_label'];
        elsif not v_precise and (v_cur ->> 'unit_id' is not null or v_cur ->> 'progress_label' is not null
                                  or v_after ? 'unit_id' or v_after ? 'progress_label') then
          -- A legacy journal has no exact before-image. Preserve a newer precise
          -- selection while still allowing independent status/notes/rating Undo.
          v_changed := v_changed || array['progress', 'unit_id', 'progress_label'];
          v_warnings := jsonb_build_array((v_ident || jsonb_build_object(
            'reason', 'legacy_precision_unavailable'))) || v_warnings;
        elsif (v_cur -> 'progress') is not distinct from (v_after -> 'progress') then
          if coalesce(jsonb_typeof(v_before -> 'progress') = 'number'
                      and (v_before ->> 'progress') ~ '^[0-9]{1,9}$', false)
             and (not v_precise or (
               jsonb_typeof(v_before -> 'progress_label') in ('null', 'string')
               and (jsonb_typeof(v_before -> 'unit_id') = 'null' or (
                 jsonb_typeof(v_before -> 'unit_id') = 'string'
                 and (v_before ->> 'unit_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                 and exists (select 1 from public.catalogue_units u
                   where u.id::text = lower(v_before ->> 'unit_id')
                     and u.medium = case v_type when 'ANIME' then 'anime' else 'manga' end
                     and (case v_type when 'ANIME' then u.anime_id else u.manga_id end) = v_media_id)
               ))
             )) then
            v_revert := v_revert || case when v_precise
              then array['progress', 'unit_id', 'progress_label'] else array['progress'] end;
          else
            v_unrestorable := v_unrestorable || array['progress', 'unit_id', 'progress_label'];
          end if;
        end if;
      end if;
      if cardinality(v_unrestorable) > 0 then
        v_warnings := jsonb_build_array((v_ident || jsonb_build_object('reason', 'unrestorable_before_value',
                                                                   'fields', to_jsonb(v_unrestorable)))) || v_warnings;
      end if;
      if cardinality(v_revert) > 0 then
        if 'progress' = any(v_revert) or 'list_type' = any(v_revert) then
          -- Use the authoritative writer once: one revision and one receipt for
          -- the coupled restoration, with no intermediate integer-only state.
          if v_type = 'ANIME' then
            select jsonb_build_object('lifecycle_id', lifecycle_id, 'base_revision', server_revision)
              into v_restore from public.anime_user_lists
              where user_id = v_uid and anime_id = v_media_id;
          else
            select jsonb_build_object('lifecycle_id', lifecycle_id, 'base_revision', server_revision)
              into v_restore from public.manga_user_lists
              where user_id = v_uid and manga_id = v_media_id;
          end if;
          v_restore := v_restore || jsonb_build_object(
            'mutation_id', public._import_mutation_id('undo', p_session_id, v_type, v_media_id),
            'medium', case v_type when 'ANIME' then 'anime' else 'manga' end, 'media_id', v_media_id);
          if 'progress' = any(v_revert) then
            v_restore := v_restore || jsonb_build_object('position', v_before -> 'progress');
          end if;
          if 'unit_id' = any(v_revert) then
            v_restore := v_restore || jsonb_build_object(
              'unit_id', v_before -> 'unit_id', 'position_label', v_before -> 'progress_label');
          end if;
          if 'list_type' = any(v_revert) then
            v_restore := v_restore || jsonb_build_object('status', v_before -> 'list_type');
          end if;
          v_restore_result := public._apply_progress_mutations_for_user(v_uid, jsonb_build_array(v_restore));
          if v_restore_result -> 'items' -> 0 ->> 'outcome' not in ('applied', 'already_applied') then
            raise exception 'undo_import_session: tracking restoration rejected';
          end if;
        end if;
        if 'rating' = any(v_revert) or 'notes' = any(v_revert) then
          if v_type = 'ANIME' then
            update public.anime_user_lists l set
              rating = case when 'rating' = any(v_revert) then (v_before ->> 'rating')::integer else l.rating end,
              notes  = case when 'notes' = any(v_revert) then v_before ->> 'notes' else l.notes end
            where l.user_id = v_uid and l.anime_id = v_media_id;
          else
            update public.manga_user_lists l set
              rating = case when 'rating' = any(v_revert) then (v_before ->> 'rating')::integer else l.rating end,
              notes  = case when 'notes' = any(v_revert) then v_before ->> 'notes' else l.notes end
            where l.user_id = v_uid and l.manga_id = v_media_id;
          end if;
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

revoke all on function public._apply_progress_mutations_for_user(text, jsonb) from public, anon, authenticated;
revoke all on function public._fence_set_progress_status(text, text, integer, uuid, integer, text) from public, anon, authenticated;
revoke all on function public.apply_import_session(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.undo_import_session(uuid, uuid) from public, anon, authenticated;
grant execute on function public._apply_progress_mutations_for_user(text, jsonb) to service_role;
grant execute on function public._fence_set_progress_status(text, text, integer, uuid, integer, text) to service_role;
grant execute on function public.apply_import_session(uuid, uuid, text, jsonb) to service_role;
grant execute on function public.undo_import_session(uuid, uuid) to service_role;
commit;
