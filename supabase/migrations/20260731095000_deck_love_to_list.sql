-- DECK LOVE -> COLLECTION 2026-07-31: CALLS TO ME (deck 'love') also lands in
-- the user's Collection as PLANNING ("want to watch/read"). Taste signals
-- alone are visible nowhere in the app; loved titles must be. Apply after
-- 20260731090000. One recreated function, nothing else.
--
-- record_taste_deck_signal: byte-identical to 090000 except one new block —
-- on p_action = 'love', AFTER the taste_signal_events insert, the title is
-- inserted into the caller's list (anime_user_lists / manga_user_lists by
-- p_media_type) with list_type = 'PLANNING' (the literal the list triggers
-- match on; list_type carries no DB CHECK constraint — the value set lives in
-- the legacy table comment and the trigger code), user_id = v_uid::text
-- (TEXT column), progress = 0 (NOT NULL, default 0 — set explicitly).
--   * ON CONFLICT (user_id, media_id) DO NOTHING: a love on a title that is
--     already listed — WATCHING, COMPLETED, anything — changes NOTHING in the
--     list. Status / progress / rating are never overwritten; no row is
--     inserted, so the list trigger does not fire either.
--   * INTERPLAY (deliberate): when the insert does land, the
--     taste_capture_list_mutation trigger (20260730160000) ALSO emits
--     planned_add (+0.10) — a deck love nets +0.65 across two events
--     (deck_love 0.55 + planned_add 0.10). Not suppressed: a love genuinely
--     is a stronger signal than a bare planned add.
--   * No double recompute bookkeeping: the existing enqueue below covers the
--     profile refresh; the trigger's own enqueue upserts the same per-user
--     queue row — harmless, left as-is on purpose.
--   * FAILURE ISOLATION: the taste event is the primary write. The list
--     insert runs inside EXCEPTION WHEN OTHERS so a list hiccup (FK drift,
--     trigger error, RLS change) can never fail the signal recording.
--   * Mind changes: love -> pass/retract removes the deck signal but KEEPS
--     the PLANNING row — the Collection is the user's visible memory of the
--     love; removing it is a deliberate user action in the app, not a deck
--     side effect.

-- ---------------------------------------------------------------------------
-- 1) record_taste_deck_signal: 090000 form + love -> PLANNING list insert
-- ---------------------------------------------------------------------------
drop function if exists public.record_taste_deck_signal(text, integer, text);

create function public.record_taste_deck_signal(
  p_media_type text,
  p_media_id integer,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_media_type text := upper(trim(coalesce(p_media_type, '')));
  v_action text := lower(trim(coalesce(p_action, '')));
  v_event_type text;
  v_strength real;
  v_deleted integer := 0;
  v_prior_event_type text;
  v_day_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if v_media_type not in ('ANIME', 'MANGA') then
    raise exception 'unsupported media type: %', p_media_type using errcode = '22023';
  end if;
  if p_media_id is null then
    raise exception 'media_id required' using errcode = '22023';
  end if;
  if v_action not in ('love', 'known', 'skip', 'pass', 'retract') then
    raise exception 'unsupported deck action: %', p_action using errcode = '22023';
  end if;

  -- Rate limit: max 300 deck events per user per rolling 24h (inserts only);
  -- passes share the same budget. Checked before the dedupe delete so a
  -- limited user keeps their prior signal.
  if v_action <> 'retract' then
    select count(*) into v_day_count
    from public.taste_signal_events
    where user_id = v_uid
      and event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
      and created_at > now() - interval '1 day';
    if v_day_count >= 300 then
      raise exception 'taste deck signal rate limit exceeded'
        using errcode = 'P0001', detail = 'RATE_LIMITED';
    end if;
  end if;

  -- One deck signal per user/media: drop the prior deck_* event first so a
  -- changed mind replaces instead of stacking. Non-deck events are untouched.
  -- The prior event type is captured so its taste_tag_stats deltas can be
  -- reversed (retract = "undo the last action on this title").
  with d as (
    delete from public.taste_signal_events
    where user_id = v_uid
      and media_type = v_media_type
      and media_id = p_media_id
      and event_type in ('deck_love', 'deck_known', 'deck_skip', 'deck_pass')
    returning event_type
  )
  select count(*), max(d.event_type)
    into v_deleted, v_prior_event_type
  from d;

  if v_prior_event_type is not null then
    perform public._taste_deck_apply_tag_stats(
      v_uid, v_media_type, p_media_id, replace(v_prior_event_type, 'deck_', ''), -1
    );
    -- Zero-row cleanup (hotfix P3): a retract/replacement that cancels the
    -- last delta leaves an empty posterior; drop rows at alpha = beta = 0.
    delete from public.taste_tag_stats s
    where s.user_id = v_uid
      and s.alpha = 0
      and s.beta = 0
      and s.tag_key in (
        select k.tag_key
        from public._taste_deck_title_tag_keys(v_media_type, p_media_id) k
      );
  end if;

  if v_action = 'retract' then
    if v_deleted > 0 then
      perform public._taste_enqueue_recompute(v_uid, 'deck_retract');
    end if;
    return jsonb_build_object(
      'ok', true,
      'action', 'retract',
      'media_type', v_media_type,
      'media_id', case when v_deleted > 0 then p_media_id else null end,
      'deleted', v_deleted
    );
  end if;

  v_event_type := case v_action
    when 'love' then 'deck_love'
    when 'known' then 'deck_known'
    when 'skip' then 'deck_skip'
    when 'pass' then 'deck_pass'
  end;
  v_strength := case v_action
    when 'love' then 0.55
    when 'known' then 0.25
    when 'skip' then -0.45
    when 'pass' then 0.00
  end;

  insert into public.taste_signal_events (
    user_id, media_id, media_type, event_type, event_strength,
    signal_value, source_transition, is_import
  ) values (
    v_uid, p_media_id, v_media_type, v_event_type, v_strength,
    jsonb_build_object('action', v_action),
    jsonb_build_object('source', 'taste_deck'),
    false
  );

  -- CALLS TO ME lands in the Collection: a deck love also lists the title as
  -- PLANNING (the only new behavior vs 090000). ON CONFLICT DO NOTHING: an
  -- existing list row (any status) is left untouched — status, progress and
  -- rating are never overwritten. When the insert lands, the
  -- taste_capture_list_mutation trigger ALSO emits planned_add (+0.10), so a
  -- deck love nets +0.65 across two events — deliberate, do not suppress.
  -- The taste event above is the primary write: any list-insert failure must
  -- never fail the signal recording, hence the exception guard. The recompute
  -- enqueue below already covers the profile refresh; the trigger's own
  -- enqueue upserts the same queue row harmlessly (not duplicated logic).
  if v_action = 'love' then
    begin
      if v_media_type = 'ANIME' then
        insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
        values (v_uid::text, p_media_id, 'PLANNING', 0)
        on conflict (user_id, anime_id) do nothing;
      else
        insert into public.manga_user_lists (user_id, manga_id, list_type, progress)
        values (v_uid::text, p_media_id, 'PLANNING', 0)
        on conflict (user_id, manga_id) do nothing;
      end if;
    exception
      when others then
        null; -- list hiccup swallowed: the deck_love event already recorded
    end;
  end if;

  -- Beta-posterior maintenance for the explore UCB (a no-op for 'pass' via the
  -- explicit guard in _taste_deck_apply_tag_stats).
  perform public._taste_deck_apply_tag_stats(v_uid, v_media_type, p_media_id, v_action, 1);

  -- Mirror _taste_emit_event: every inserted signal enqueues a profile
  -- recompute — EXCEPT a pure pass, which changes nothing in the profile
  -- (strength 0, excluded from recompute). A pass that REPLACED a scored
  -- signal (love/known/skip) must enqueue so the profile drops that title.
  if v_action = 'pass' then
    if v_prior_event_type is not null and v_prior_event_type <> 'deck_pass' then
      perform public._taste_enqueue_recompute(v_uid, v_event_type);
    end if;
  else
    perform public._taste_enqueue_recompute(v_uid, v_event_type);
  end if;

  return jsonb_build_object(
    'ok', true,
    'action', v_action,
    'event_type', v_event_type,
    'event_strength', v_strength,
    'media_type', v_media_type,
    'media_id', p_media_id,
    'replaced_prior', v_deleted > 0
  );
end;
$$;

revoke all on function public.record_taste_deck_signal(text, integer, text) from public;
grant execute on function public.record_taste_deck_signal(text, integer, text) to authenticated, service_role;
