CREATE OR REPLACE FUNCTION public.undo_import_session(p_user_id uuid, p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$

