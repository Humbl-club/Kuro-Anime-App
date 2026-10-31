-- 70_import_apply_undo_transactions.sql  --  Apply / Undo as database transactions (F08-F13, P2-R2)
--
-- Functions under test (PENDING, not deployed): 20261005130000_import_apply_undo_transactions.sql
--   apply_import_session(p_user_id, p_session_id, p_idempotency_key, p_items)
--   undo_import_session(p_user_id, p_session_id)
--   default run           -> PASS (the replay applies every file in supabase/prepared-migrations/)
--   --exclude-pending     -> FAILS at the first "pending migration" precondition (deployed-chain
--                            state: the RPCs and journal columns do not exist)
-- The RPCs are service_role-only; the edge handlers pass the JWT-derived user. Planned items are
-- written here in the shape concierge-apply/apply_plan.ts produces (pinned by its Deno test
-- "planned item wire shape"). Failures are injected with throwaway triggers inside this file's
-- transaction. Section K uses dblink for two real concurrent sessions (committed data, removed at
-- the end); without dblink it is reported BLOCKED, not faked.
\set ON_ERROR_STOP on
\o /dev/null
\set as_service 'select tests.reset(); select set_config(''request.jwt.claims'', ''{"role":"service_role"}'', true); set local role service_role;'
begin;

-- ---- preconditions: the fixture objects this slice depends on (F43) ---------
select tests.ok('fixture: import_sessions exists',        to_regclass('public.import_sessions') is not null);
select tests.ok('fixture: import_session_items exists',   to_regclass('public.import_session_items') is not null);
select tests.ok('fixture: anime_user_lists exists',       to_regclass('public.anime_user_lists') is not null);
select tests.ok('fixture: manga_user_lists exists',       to_regclass('public.manga_user_lists') is not null);
select tests.ok('fixture: taste_import_context exists',   to_regclass('public.taste_import_context') is not null);
select tests.ok('fixture: taste_signal_events exists',    to_regclass('public.taste_signal_events') is not null);
select tests.ok('fixture: check_concierge_rate_limit exists (the limiter both handlers gate on)',
  to_regprocedure('public.check_concierge_rate_limit(text,text,integer,integer,integer)') is not null);
select tests.ok('fixture: taste_capture trigger on anime_user_lists exists',
  exists (select 1 from pg_trigger where tgname = 'taste_capture_anime_user_lists' and not tgisinternal));
select tests.ok('pending migration: apply_import_session exists',
  to_regprocedure('public.apply_import_session(uuid,uuid,text,jsonb)') is not null);
select tests.ok('pending migration: undo_import_session exists',
  to_regprocedure('public.undo_import_session(uuid,uuid)') is not null);
select tests.ok('pending migration: journal columns after_values / reverted_at exist',
  (select count(*) = 2 from information_schema.columns
    where table_schema = 'public' and table_name = 'import_session_items' and column_name in ('after_values', 'reverted_at')));
select tests.ok('pending migration: import_sessions.idempotency_key + partial unique index per user',
  exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'import_sessions'
            and indexname = 'import_sessions_user_idempotency_key_uidx'
            and indexdef like '%UNIQUE%(user_id, idempotency_key)%WHERE (idempotency_key IS NOT NULL)%'));

-- ---- grants and function posture ---------------------------------------------
select tests.ok('grant: anon cannot EXECUTE apply_import_session',
  not has_function_privilege('anon', 'public.apply_import_session(uuid,uuid,text,jsonb)', 'EXECUTE'));
select tests.ok('grant: authenticated cannot EXECUTE apply_import_session',
  not has_function_privilege('authenticated', 'public.apply_import_session(uuid,uuid,text,jsonb)', 'EXECUTE'));
select tests.ok('grant: anon cannot EXECUTE undo_import_session',
  not has_function_privilege('anon', 'public.undo_import_session(uuid,uuid)', 'EXECUTE'));
select tests.ok('grant: authenticated cannot EXECUTE undo_import_session',
  not has_function_privilege('authenticated', 'public.undo_import_session(uuid,uuid)', 'EXECUTE'));
select tests.ok('grant: anon/authenticated cannot EXECUTE the outcome helper',
  not has_function_privilege('anon', 'public._import_apply_outcome(uuid,boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public._import_apply_outcome(uuid,boolean)', 'EXECUTE'));
select tests.ok('grant: service_role can EXECUTE both RPCs',
  has_function_privilege('service_role', 'public.apply_import_session(uuid,uuid,text,jsonb)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.undo_import_session(uuid,uuid)', 'EXECUTE'));
select tests.ok('posture: both RPCs are SECURITY DEFINER with search_path = public, extensions',
  (select bool_and(p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, extensions%')
     from pg_proc p
    where p.oid in ('public.apply_import_session(uuid,uuid,text,jsonb)'::regprocedure,
                    'public.undo_import_session(uuid,uuid)'::regprocedure)));

select tests.make_user(71), tests.make_user(72), tests.make_user(73), tests.make_user(74),
       tests.make_user(75), tests.make_user(76), tests.make_user(77), tests.make_user(78);
insert into public.anime (id) values
  (970001), (970002), (970005), (970010), (970011), (970012), (970013), (970014),
  (970020), (970021), (970022), (970030), (970040), (970041), (970042), (970050), (970051);
insert into public.manga (id) values (970101), (970130);

select tests.as_user(tests.uid(71));
select tests.denied('grant: authenticated calling apply_import_session is refused (42501)',
  format($q$select public.apply_import_session(%L, null, null, '[{"media_type":"ANIME","media_id":970001,"import_action":"skip"}]'::jsonb)$q$, tests.uid(71)));
select tests.denied('grant: authenticated calling undo_import_session is refused (42501)',
  format($q$select public.undo_import_session(%L, gen_random_uuid())$q$, tests.uid(71)));
select tests.as_anon();
select tests.denied('grant: anon calling apply_import_session is refused (42501)',
  format($q$select public.apply_import_session(%L, null, null, '[{"media_type":"ANIME","media_id":970001,"import_action":"skip"}]'::jsonb)$q$, tests.uid(71)));

-- ---- A. atomic Apply: list writes + journal (before AND after image) + session --
select tests.reset();
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, notes)
values (tests.uid(71)::text, 970002, 'WATCHING', 3, 8, 'mine');
select coalesce(max(id), 0) as a_before_event from public.taste_signal_events \gset
:as_service
select public.apply_import_session(tests.uid(71), null, 'k-happy', $j$[
  {"media_type":"ANIME","media_id":970001,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},
   "journal":{"raw":"Frieren","parsed":{"status":"PLANNING"},"candidates":[],"confidence":0.9}},
  {"media_type":"ANIME","media_id":970002,"import_action":"update","expected":{"list_type":"WATCHING","progress":3},
   "insert_values":{"list_type":"WATCHING","progress":5,"rating":9},"update_values":{"list_type":"WATCHING","progress":5,"rating":9},
   "journal":{"raw":"Mushishi ep 5 9/10","parsed":{},"candidates":[],"confidence":0.8}},
  {"media_type":"MANGA","media_id":970101,"import_action":"skip","journal":{"raw":"skip me"}}
]$j$::jsonb) as a_out \gset
select tests.reset();
select (:'a_out'::jsonb) ->> 'session_id' as a_sid \gset
select tests.eq('A: applied lists the add and the update in request order', (:'a_out'::jsonb) -> 'applied',
  '[{"mediaType":"ANIME","mediaId":970001,"status":"PLANNING","action":"add"},{"mediaType":"ANIME","mediaId":970002,"status":"WATCHING","action":"update"}]'::jsonb);
select tests.eq('A: skipped lists the skip item', (:'a_out'::jsonb) -> 'skipped', '[{"mediaType":"MANGA","mediaId":970101}]'::jsonb);
select tests.eq('A: no conflicts, no errors', ((:'a_out'::jsonb) -> 'conflicts') || ((:'a_out'::jsonb) -> 'errors'), '[]'::jsonb);
select tests.eq('A: undoable, not replayed', ((:'a_out'::jsonb) ->> 'undoable') || '/' || ((:'a_out'::jsonb) ->> 'replayed'), 'true/false');
select tests.eq('A: session is applied, owned by the JWT user, carries the key',
  (select status || '/' || user_id::text || '/' || idempotency_key from public.import_sessions where id = :'a_sid'),
  'applied/' || tests.uid(71)::text || '/k-happy');
select tests.eq('A: new row written with the insert values (progress default 0, no rating/notes)',
  (select list_type || '/' || progress || '/' || coalesce(rating::text, 'null') || '/' || coalesce(notes, 'null')
     from public.anime_user_lists where user_id = tests.uid(71)::text and anime_id = 970001), 'PLANNING/0/null/null');
select tests.eq('A: existing row: only the written fields changed, authored notes kept',
  (select list_type || '/' || progress || '/' || rating || '/' || notes
     from public.anime_user_lists where user_id = tests.uid(71)::text and anime_id = 970002), 'WATCHING/5/9/mine');
select tests.eq('A: add journal: after image is the whole inserted row, no before image',
  (select after_values || jsonb_build_object('prev', previous_values) from public.import_session_items
    where session_id = :'a_sid' and chosen ->> 'mediaId' = '970001'),
  '{"list_type":"PLANNING","progress":0,"rating":null,"notes":null,"verdict":null,"prev":null}'::jsonb);
select tests.eq('A: update journal: after image = the written fields only',
  (select after_values from public.import_session_items where session_id = :'a_sid' and chosen ->> 'mediaId' = '970002'),
  '{"list_type":"WATCHING","progress":5,"rating":9}'::jsonb);
select tests.eq('A: update journal: before image = the whole row before the import',
  (select previous_values from public.import_session_items where session_id = :'a_sid' and chosen ->> 'mediaId' = '970002'),
  '{"list_type":"WATCHING","progress":3,"rating":8,"notes":"mine","verdict":null}'::jsonb);
select tests.eq('A: three journal rows (applied, applied, skipped)',
  (select string_agg(state, ',' order by (action ->> 'ordinal')::int) from public.import_session_items where session_id = :'a_sid'),
  'applied,applied,skipped');
select tests.ok('A: taste events of the import exist (planned_add, rating_high) - not vacuous',
  (select count(*) >= 2 from public.taste_signal_events where user_id = tests.uid(71) and id > :a_before_event));
select tests.ok('A: every taste event of the import is import-origin for this session',
  (select bool_and(is_import and import_session_id = :'a_sid'::uuid) from public.taste_signal_events
    where user_id = tests.uid(71) and id > :a_before_event));
select tests.eq('A: taste_import_context is gone after commit (never leaks to later edits)',
  (select count(*) from public.taste_import_context where user_id = tests.uid(71)), 0::bigint);
select max(id) as a_last_event from public.taste_signal_events \gset
select tests.as_user(tests.uid(71));
update public.anime_user_lists set rating = 10 where anime_id = 970002;
select tests.reset();
select tests.ok('A: a later manual edit is NOT import-origin',
  (select bool_and(not is_import and import_session_id is null) from public.taste_signal_events
    where user_id = tests.uid(71) and id > :a_last_event));
update public.anime_user_lists set rating = 9 where user_id = tests.uid(71)::text and anime_id = 970002;

-- ---- F. idempotency: same key returns the stored outcome, writes nothing --------
:as_service
select public.apply_import_session(tests.uid(71), null, 'k-happy', $j$[
  {"media_type":"ANIME","media_id":970005,"import_action":"add","expected":null,
   "insert_values":{"list_type":"WATCHING","progress":2},"update_values":{"list_type":"WATCHING","progress":2},
   "journal":{"raw":"other"}}
]$j$::jsonb) as f_out \gset
select tests.reset();
select tests.eq('F: replay returns the stored outcome with replayed=true',
  (:'f_out'::jsonb), jsonb_set(:'a_out'::jsonb, '{replayed}', 'true'::jsonb));
select tests.eq('F: replay wrote no list row', (select count(*) from public.anime_user_lists where anime_id = 970005), 0::bigint);
select tests.eq('F: still one session for the key', (select count(*) from public.import_sessions where idempotency_key = 'k-happy'), 1::bigint);
select tests.eq('F: no journal rows added', (select count(*) from public.import_session_items where session_id = :'a_sid'), 3::bigint);

-- ---- G. owner isolation (service-role params cannot cross users) ---------------
:as_service
select public.undo_import_session(tests.uid(76), :'a_sid') as g_undo \gset
select public.apply_import_session(tests.uid(76), null, 'k-happy', $j$[
  {"media_type":"ANIME","media_id":970005,"import_action":"add","expected":null,
   "insert_values":{"list_type":"WATCHING","progress":2},"update_values":{"list_type":"WATCHING","progress":2},"journal":{}}
]$j$::jsonb) as g_apply \gset
select tests.reset();
select tests.eq('G: user B undoing user A''s session is reported as not found', (:'g_undo'::jsonb) ->> 'result', 'not_found');
select tests.eq('G: ...and A''s session stays applied', (select status from public.import_sessions where id = :'a_sid'), 'applied');
select tests.eq('G: ...and A''s rows are untouched',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(71)::text and anime_id in (970001, 970002)), 2::bigint);
select tests.eq('G: keys are per user: B''s apply with A''s key is a new Apply, not A''s replay',
  ((:'g_apply'::jsonb) ->> 'replayed') || '/' || (select user_id::text from public.import_sessions where id = ((:'g_apply'::jsonb) ->> 'session_id')::uuid),
  'false/' || tests.uid(76)::text);
select tests.eq('G: B''s write went to B''s row only',
  (select string_agg(user_id, ',') from public.anime_user_lists where anime_id = 970005), tests.uid(76)::text);

-- ---- H. only the most recent applied session can be undone ---------------------
:as_service
select public.apply_import_session(tests.uid(71), null, 'k-second', $j$[
  {"media_type":"ANIME","media_id":970005,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PAUSED","progress":1},"update_values":{"list_type":"PAUSED","progress":1},"journal":{}}
]$j$::jsonb) as h_apply \gset
-- both sessions were created in this one test transaction (same now()); make the order explicit,
-- as separate production transactions would have it
select tests.reset();
update public.import_sessions set created_at = created_at + interval '1 second'
 where id = ((:'h_apply'::jsonb) ->> 'session_id')::uuid;
:as_service
select public.undo_import_session(tests.uid(71), :'a_sid') as h_undo \gset
select tests.reset();
select tests.eq('H: undo of an older session is refused as not_latest', (:'h_undo'::jsonb) ->> 'result', 'not_latest');
select tests.eq('H: ...and nothing was reverted, the session stays applied',
  (select status from public.import_sessions where id = :'a_sid') || '/' ||
  (select count(*) from public.anime_user_lists where user_id = tests.uid(71)::text and anime_id = 970001), 'applied/1');
select tests.eq('H: ...and no taste context is left behind',
  (select count(*) from public.taste_import_context where user_id = tests.uid(71)), 0::bigint);

-- ---- B. Undo compare-and-revert: later edits and deletions survive (F08, F09) ----
select tests.reset();
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, notes) values
  (tests.uid(72)::text, 970010, 'WATCHING', 2, 7, 'orig'),
  (tests.uid(72)::text, 970011, 'WATCHING', 4, null, null),
  (tests.uid(72)::text, 970012, 'PLANNING', 0, null, null);
:as_service
select public.apply_import_session(tests.uid(72), null, 'k-undo', $j$[
  {"media_type":"ANIME","media_id":970010,"import_action":"update","expected":{"list_type":"WATCHING","progress":2},
   "insert_values":{"list_type":"WATCHING","progress":6,"rating":8,"notes":"import note"},
   "update_values":{"list_type":"WATCHING","progress":6,"rating":8,"notes":"import note"},"journal":{}},
  {"media_type":"ANIME","media_id":970011,"import_action":"update","expected":{"list_type":"WATCHING","progress":4},
   "insert_values":{"list_type":"COMPLETED","progress":12},"update_values":{"list_type":"COMPLETED","progress":12},"journal":{}},
  {"media_type":"ANIME","media_id":970012,"import_action":"update","expected":{"list_type":"PLANNING"},
   "insert_values":{"list_type":"WATCHING","progress":1},"update_values":{"list_type":"WATCHING","progress":1},"journal":{}},
  {"media_type":"ANIME","media_id":970013,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{}},
  {"media_type":"ANIME","media_id":970014,"import_action":"add","expected":null,
   "insert_values":{"list_type":"WATCHING","progress":3},"update_values":{"list_type":"WATCHING","progress":3},"journal":{}}
]$j$::jsonb) as b_apply \gset
select tests.reset();
select (:'b_apply'::jsonb) ->> 'session_id' as b_sid \gset
-- the user edits after the import (PostgREST path, own rows)
select tests.as_user(tests.uid(72));
update public.anime_user_lists set rating = 10, notes = 'my later note' where anime_id = 970010;
delete from public.anime_user_lists where anime_id = 970011;
update public.anime_user_lists set rating = 6 where anime_id = 970014;
select tests.reset();
select max(id) as b_last_event from public.taste_signal_events \gset
:as_service
select public.undo_import_session(tests.uid(72), :'b_sid') as b_undo \gset
select tests.reset();
select tests.eq('B: undo result', (:'b_undo'::jsonb) ->> 'result', 'undone');
select tests.eq('B F08: later rating and notes edits survive; untouched written fields revert',
  (select list_type || '/' || progress || '/' || rating || '/' || notes
     from public.anime_user_lists where user_id = tests.uid(72)::text and anime_id = 970010), 'WATCHING/2/10/my later note');
select tests.eq('B F09: a row deleted after an update import stays deleted',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(72)::text and anime_id = 970011), 0::bigint);
select tests.eq('B: an untouched update is fully restored',
  (select list_type || '/' || progress from public.anime_user_lists where user_id = tests.uid(72)::text and anime_id = 970012), 'PLANNING/0');
select tests.eq('B: an untouched add is deleted',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(72)::text and anime_id = 970013), 0::bigint);
select tests.eq('B F08: an add edited later is kept as edited',
  (select list_type || '/' || progress || '/' || rating from public.anime_user_lists where user_id = tests.uid(72)::text and anime_id = 970014), 'WATCHING/3/6');
select tests.eq('B: reverted entries',
  (:'b_undo'::jsonb) -> 'reverted',
  '[{"mediaType":"ANIME","mediaId":970010,"undoType":"restored","fields":["list_type","progress"]},
    {"mediaType":"ANIME","mediaId":970012,"undoType":"restored","fields":["list_type","progress"]},
    {"mediaType":"ANIME","mediaId":970013,"undoType":"deleted"}]'::jsonb);
select tests.eq('B: skipped entries explain every kept change',
  (:'b_undo'::jsonb) -> 'skipped',
  '[{"mediaType":"ANIME","mediaId":970010,"reason":"edited_since_import","fields":["notes","rating"]},
    {"mediaType":"ANIME","mediaId":970011,"reason":"deleted_since_import"},
    {"mediaType":"ANIME","mediaId":970014,"reason":"edited_since_import","fields":["rating"]}]'::jsonb);
select tests.eq('B: session cancelled only after every item resolved', (select status from public.import_sessions where id = :'b_sid'), 'cancelled');
select tests.eq('B: reverted_at marks exactly the reverted items',
  (select string_agg(chosen ->> 'mediaId', ',' order by (action ->> 'ordinal')::int) from public.import_session_items
    where session_id = :'b_sid' and reverted_at is not null), '970010,970012,970013');
select tests.ok('B: revert writes are import-origin for the undone session (taste semantics kept)',
  (select count(*) > 0 and bool_and(is_import and import_session_id = :'b_sid'::uuid)
     from public.taste_signal_events where user_id = tests.uid(72) and id > :b_last_event));
:as_service
select public.undo_import_session(tests.uid(72), :'b_sid') as b_again \gset
select tests.reset();
select tests.eq('B: a second undo is the idempotent already_undone outcome',
  (:'b_again'::jsonb) - 'session_id', '{"result":"already_undone","reverted":[],"skipped":[],"warnings":[]}'::jsonb);

-- ---- C. journal failure mid-batch: nothing commits (F10) ------------------------
select tests.reset();
create function tests.l2a_fail_journal() returns trigger language plpgsql as $f$
begin
  if new.raw = 'JOURNAL_FAIL' then raise exception 'injected journal failure'; end if;
  return new;
end $f$;
create trigger l2a_fail_journal before insert on public.import_session_items
  for each row execute function tests.l2a_fail_journal();
\set c_items '[{"media_type":"ANIME","media_id":970020,"import_action":"add","expected":null,"insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{"raw":"first"}},{"media_type":"ANIME","media_id":970021,"import_action":"add","expected":null,"insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{"raw":"JOURNAL_FAIL"}},{"media_type":"ANIME","media_id":970022,"import_action":"add","expected":null,"insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{"raw":"third"}}]'
:as_service
select tests.raises('C F10: a journal insert failure on item 2 aborts the whole Apply',
  format('select public.apply_import_session(%L, null, %L, %L::jsonb)', tests.uid(73), 'k-journal', :'c_items'),
  '%injected journal failure%');
select tests.reset();
select tests.eq('C F10: no list write of item 1 survives (no unjournaled write)',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(73)::text), 0::bigint);
select tests.eq('C: no session, no journal rows, no taste context, no taste events',
  (select count(*) from public.import_sessions where user_id = tests.uid(73))
  + (select count(*) from public.taste_import_context where user_id = tests.uid(73))
  + (select count(*) from public.taste_signal_events where user_id = tests.uid(73)), 0::bigint);
drop trigger l2a_fail_journal on public.import_session_items;
:as_service
select public.apply_import_session(tests.uid(73), null, 'k-journal', :'c_items'::jsonb) as c_retry \gset
select tests.reset();
select tests.eq('C: the retry with the same key is a fresh Apply (the failed one left nothing to replay)',
  ((:'c_retry'::jsonb) ->> 'replayed') || '/' || jsonb_array_length((:'c_retry'::jsonb) -> 'applied'), 'false/3');

-- ---- D. session finalisation failure: nothing commits (F11) ---------------------
create function tests.l2a_fail_finalize() returns trigger language plpgsql as $f$
begin
  if new.status is distinct from old.status and old.user_id = tests.uid(74) then
    raise exception 'injected finalisation failure';
  end if;
  return new;
end $f$;
create trigger l2a_fail_finalize before update on public.import_sessions
  for each row execute function tests.l2a_fail_finalize();
:as_service
select tests.raises('D F11: a failed session transition aborts the whole Apply',
  format('select public.apply_import_session(%L, null, %L, %L::jsonb)', tests.uid(74), 'k-final',
    '[{"media_type":"ANIME","media_id":970020,"import_action":"add","expected":null,"insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{}}]'),
  '%injected finalisation failure%');
select tests.reset();
select tests.eq('D F11: no list row, no session, no journal survive',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(74)::text)
  + (select count(*) from public.import_sessions where user_id = tests.uid(74)), 0::bigint);
drop trigger l2a_fail_finalize on public.import_sessions;

-- ---- E. mixed outcome: accepted + conflict + item error, Undo-eligible (F12) ----
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(75)::text, 970030, 'WATCHING', 3);
:as_service
select public.apply_import_session(tests.uid(75), null, 'k-partial', $j$[
  {"media_type":"ANIME","media_id":970030,"import_action":"update","expected":{"list_type":"WATCHING","progress":1},
   "insert_values":{"list_type":"WATCHING","progress":5},"update_values":{"list_type":"WATCHING","progress":5},"journal":{}},
  {"media_type":"MANGA","media_id":970130,"import_action":"add","expected":null,
   "insert_values":{"list_type":"READING","progress":0},"update_values":{"list_type":"READING"},"journal":{}},
  {"media_type":"ANIME","media_id":979999,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{}}
]$j$::jsonb) as e_out \gset
select tests.reset();
select (:'e_out'::jsonb) ->> 'session_id' as e_sid \gset
select tests.eq('E: the accepted manga add is applied', (:'e_out'::jsonb) -> 'applied',
  '[{"mediaType":"MANGA","mediaId":970130,"status":"READING","action":"add"}]'::jsonb);
select tests.eq('E: the stale update is a conflict (compare-and-set under the row lock)', (:'e_out'::jsonb) -> 'conflicts',
  '[{"mediaType":"ANIME","mediaId":970030,"error":"State changed since parse — review and retry"}]'::jsonb);
select tests.eq('E: the rejected item (unknown catalog id) is an isolated item error with a fixed message (no schema names)',
  (:'e_out'::jsonb) -> 'errors', '[{"mediaType":"ANIME","mediaId":979999,"error":"Unknown title"}]'::jsonb);
select tests.eq('E F12: the session is applied and undoable',
  (select status from public.import_sessions where id = :'e_sid') || '/' || ((:'e_out'::jsonb) ->> 'undoable'), 'applied/true');
select tests.eq('E: the conflicted row is untouched',
  (select progress from public.anime_user_lists where user_id = tests.uid(75)::text and anime_id = 970030), 3);
:as_service
select public.undo_import_session(tests.uid(75), :'e_sid') as e_undo \gset
select tests.reset();
select tests.eq('E F12: undo of the partial session removes exactly the accepted write',
  ((:'e_undo'::jsonb) ->> 'result') || '/' ||
  (select count(*) from public.manga_user_lists where user_id = tests.uid(75)::text) || '/' ||
  (select progress from public.anime_user_lists where user_id = tests.uid(75)::text and anime_id = 970030), 'undone/0/3');

-- ---- I. a failed Undo rolls back and stays retryable (F13) ------------------------
:as_service
select public.apply_import_session(tests.uid(77), null, 'k-undo-fail', $j$[
  {"media_type":"ANIME","media_id":970040,"import_action":"add","expected":null,"insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{}},
  {"media_type":"ANIME","media_id":970041,"import_action":"add","expected":null,"insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{}},
  {"media_type":"ANIME","media_id":970042,"import_action":"add","expected":null,"insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{}}
]$j$::jsonb) as i_apply \gset
select tests.reset();
select (:'i_apply'::jsonb) ->> 'session_id' as i_sid \gset
create function tests.l2a_fail_delete() returns trigger language plpgsql as $f$
begin
  if old.anime_id = 970041 and old.user_id = tests.uid(77)::text then raise exception 'injected compensation failure'; end if;
  return old;
end $f$;
create trigger l2a_fail_delete before delete on public.anime_user_lists
  for each row execute function tests.l2a_fail_delete();
:as_service
select tests.raises('I F13: a compensation failure on item 2 aborts the whole Undo',
  format('select public.undo_import_session(%L, %L)', tests.uid(77), :'i_sid'), '%injected compensation failure%');
select tests.reset();
select tests.eq('I F13: item 1 was not removed, the session stays applied, nothing is marked reverted',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(77)::text) || '/' ||
  (select status from public.import_sessions where id = :'i_sid') || '/' ||
  (select count(*) from public.import_session_items where session_id = :'i_sid' and reverted_at is not null), '3/applied/0');
drop trigger l2a_fail_delete on public.anime_user_lists;
:as_service
select public.undo_import_session(tests.uid(77), :'i_sid') as i_retry \gset
select tests.reset();
select tests.eq('I F13: the retry completes every item and only then cancels the session',
  ((:'i_retry'::jsonb) ->> 'result') || '/' || jsonb_array_length((:'i_retry'::jsonb) -> 'reverted') || '/' ||
  (select count(*) from public.anime_user_lists where user_id = tests.uid(77)::text) || '/' ||
  (select status from public.import_sessions where id = :'i_sid'), 'undone/3/0/cancelled');

-- ---- J. journals written before this migration stay undoable --------------------
insert into public.import_sessions (id, user_id, status, source)
values ('00000000-0000-4000-8000-0000000a0078', tests.uid(78), 'applied', 'chat');
insert into public.import_session_items (session_id, raw, chosen, action, state, import_action, previous_values) values
  ('00000000-0000-4000-8000-0000000a0078', 'legacy update', '{"mediaType":"ANIME","mediaId":970050}',
   jsonb_build_object('table', 'anime_user_lists', 'key', jsonb_build_object('user_id', tests.uid(78)::text, 'anime_id', 970050),
     'before', '{"list_type":"WATCHING","progress":2,"rating":7,"notes":"n"}'::jsonb,
     'after', jsonb_build_object('user_id', tests.uid(78)::text, 'anime_id', 970050, 'list_type', 'COMPLETED', 'progress', 12)),
   'applied', 'update', '{"list_type":"WATCHING","progress":2,"rating":7,"notes":"n"}'),
  ('00000000-0000-4000-8000-0000000a0078', 'legacy add', '{"mediaType":"ANIME","mediaId":970051}',
   jsonb_build_object('table', 'anime_user_lists', 'before', null,
     'after', jsonb_build_object('user_id', tests.uid(78)::text, 'anime_id', 970051, 'list_type', 'PLANNING', 'progress', 0)),
   'applied', 'add', null);
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, notes) values
  (tests.uid(78)::text, 970050, 'COMPLETED', 12, 7, 'n'),
  (tests.uid(78)::text, 970051, 'PLANNING', 0, null, null);
:as_service
select public.undo_import_session(tests.uid(78), '00000000-0000-4000-8000-0000000a0078') as j_undo \gset
select tests.reset();
select tests.eq('J: legacy update journal (after image in action.after) is restored',
  (select list_type || '/' || progress || '/' || rating || '/' || notes from public.anime_user_lists
    where user_id = tests.uid(78)::text and anime_id = 970050), 'WATCHING/2/7/n');
select tests.eq('J: legacy add journal is deleted',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(78)::text and anime_id = 970051), 0::bigint);

-- ---- L. malformed journal values are handled deterministically (never a blind cast) ----
select tests.make_user(79), tests.make_user(80);
insert into public.anime (id) values (970052), (970060), (970063);
:as_service
select public.apply_import_session(tests.uid(80), null, 'k-malformed', $j$[
  {"media_type":"ANIME","media_id":970060,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},
   "journal":{"raw":42,"parsed":"free text","candidates":{"not":"an array"},"confidence":"high"}},
  {"media_type":"ANIME","media_id":970063,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},
   "journal":"not an object"}
]$j$::jsonb) as l_apply \gset
select tests.reset();
select tests.eq('L: malformed journal descriptors do not abort the Apply',
  jsonb_array_length((:'l_apply'::jsonb) -> 'applied') || '/' || jsonb_array_length((:'l_apply'::jsonb) -> 'errors'), '2/0');
select tests.eq('L: each malformed descriptor is replaced by its default (raw, parsed, candidates, confidence)',
  (select string_agg(raw || '|' || parsed::text || '|' || candidates::text || '|' || confidence::text, ' ; ' order by raw)
     from public.import_session_items where session_id = ((:'l_apply'::jsonb) ->> 'session_id')::uuid),
  'ANIME:970060|{}|[]|0 ; ANIME:970063|{}|[]|0');
-- a journal row with a non-numeric ordinal and before values of the wrong type
insert into public.import_sessions (id, user_id, status, source)
values ('00000000-0000-4000-8000-0000000a0079', tests.uid(79), 'applied', 'chat');
insert into public.import_session_items (session_id, raw, chosen, action, state, import_action, previous_values, after_values) values
  ('00000000-0000-4000-8000-0000000a0079', 'malformed', '{"mediaType":"ANIME","mediaId":970052}', '{"ordinal":"x","outcome":"applied"}',
   'applied', 'update', '{"list_type":"WATCHING","progress":"two","rating":"x","notes":5}',
   '{"list_type":"COMPLETED","progress":12,"rating":9,"notes":"n2"}'),
  ('00000000-0000-4000-8000-0000000a0079', 'malformed identity', '{"mediaType":"ANIME","mediaId":"x"}', '{"ordinal":2}',
   'applied', 'add', null, '{"list_type":"PLANNING","progress":0}');
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating, notes)
values (tests.uid(79)::text, 970052, 'COMPLETED', 12, 9, 'n2');
:as_service
select public.undo_import_session(tests.uid(79), '00000000-0000-4000-8000-0000000a0079') as l_undo \gset
select tests.reset();
select tests.eq('L: undo reverts the restorable field, keeps the unrestorable ones and says why',
  jsonb_build_object('result', (:'l_undo'::jsonb) -> 'result', 'reverted', (:'l_undo'::jsonb) -> 'reverted',
                     'warning', (:'l_undo'::jsonb) -> 'warnings' -> 0),
  '{"result":"undone","reverted":[{"mediaType":"ANIME","mediaId":970052,"undoType":"restored","fields":["list_type"]}],
    "warning":{"mediaType":"ANIME","mediaId":970052,"reason":"unrestorable_before_value","fields":["notes","progress","rating"]}}'::jsonb);
select tests.eq('L: a journal row with a malformed identity is skipped with a warning, not a failed Undo',
  (:'l_undo'::jsonb) #>> '{warnings,1,reason}', 'invalid_journal_identity');

-- ---- M. 10-digit media ids round-trip in the outcome (review R1) ------------------
select tests.make_user(81), tests.make_user(82);
insert into public.anime (id) values (1500000000);
:as_service
select public.apply_import_session(tests.uid(81), null, 'k-big-ids', $j$[
  {"media_type":"ANIME","media_id":1500000000,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{}},
  {"media_type":"ANIME","media_id":2147483647,"import_action":"skip","journal":{}}
]$j$::jsonb) as m_out \gset
select tests.reset();
select tests.eq('M R1: 1500000000 (applied) and 2147483647 (skipped) come back as numbers, never null',
  jsonb_build_object('applied', (:'m_out'::jsonb) -> 'applied', 'skipped', (:'m_out'::jsonb) -> 'skipped'),
  '{"applied":[{"mediaType":"ANIME","mediaId":1500000000,"status":"PLANNING","action":"add"}],
    "skipped":[{"mediaType":"ANIME","mediaId":2147483647}]}'::jsonb);

-- ---- N. a chain on one title in one batch unwinds completely (review A1) -----------
insert into public.anime (id) values (970090);
:as_service
select public.apply_import_session(tests.uid(82), null, 'k-chain', $j$[
  {"media_type":"ANIME","media_id":970090,"import_action":"add","expected":null,
   "insert_values":{"list_type":"WATCHING","progress":3},"update_values":{"list_type":"WATCHING","progress":3},"journal":{}},
  {"media_type":"ANIME","media_id":970090,"import_action":"update","expected":null,
   "insert_values":{"list_type":"WATCHING","progress":5},"update_values":{"list_type":"WATCHING","progress":5},"journal":{}}
]$j$::jsonb) as n_apply \gset
select public.undo_import_session(tests.uid(82), ((:'n_apply'::jsonb) ->> 'session_id')::uuid) as n_undo \gset
select tests.reset();
select tests.eq('N A1: [add 3, update 5] on one title: Undo (last write first) removes the row entirely',
  (select count(*) from public.anime_user_lists where user_id = tests.uid(82)::text and anime_id = 970090), 0::bigint);
select tests.eq('N A1: ...reported in request order, nothing mislabelled as a later edit',
  jsonb_build_object('reverted', (:'n_undo'::jsonb) -> 'reverted', 'skipped', (:'n_undo'::jsonb) -> 'skipped'),
  '{"reverted":[{"mediaType":"ANIME","mediaId":970090,"undoType":"deleted"},
                {"mediaType":"ANIME","mediaId":970090,"undoType":"restored","fields":["list_type","progress"]}],
    "skipped":[]}'::jsonb);
select tests.eq('L: ...and the row is exactly that',
  (select list_type || '/' || progress || '/' || rating || '/' || notes from public.anime_user_lists
    where user_id = tests.uid(79)::text and anime_id = 970052), 'WATCHING/12/9/n2');

select tests.reset();
rollback;

-- ============================================================================
-- K. Two real concurrent sessions (dblink). Committed rows of users 791/792 are
--    removed at the end of this section.
-- ============================================================================
select exists (select 1 from pg_available_extensions where name = 'dblink') as have_dblink \gset
\if :have_dblink
create extension if not exists dblink with schema extensions;
create function pg_temp.l2a_wait_for_lock(p_pid integer, p_label text) returns void language plpgsql as $f$
declare n integer := 0;
begin
  -- state-based wait: the other backend is blocked on a lock held by our open transaction
  loop
    exit when exists (select 1 from pg_stat_activity where pid = p_pid and wait_event_type = 'Lock');
    n := n + 1;
    if n > 3000 then
      raise exception 'TEST FAIL: % never waited on the lock (state: %)', p_label,
        (select coalesce(state, '?') || '/' || coalesce(wait_event_type, '-') from pg_stat_activity where pid = p_pid);
    end if;
    perform pg_sleep(0.01);
  end loop;
end $f$;
select format('dbname=%s host=%s port=%s user=%s', current_database(), current_setting('unix_socket_directories'),
              current_setting('port'), current_user) as l2a_conn \gset
select tests.make_user(791), tests.make_user(792);
insert into public.anime (id) values (970061), (970062) on conflict (id) do nothing;
select dblink_connect('l2a_a', :'l2a_conn'), dblink_connect('l2a_b', :'l2a_conn');
select pid as l2a_b_pid from dblink('l2a_b', 'select pg_backend_pid()') as t(pid integer) \gset

-- K1. compare-and-revert race: a user edit that commits while Undo waits on the row survives (F08)
insert into public.anime_user_lists (user_id, anime_id, list_type, progress, rating) values (tests.uid(791)::text, 970061, 'WATCHING', 3, 8);
select (public.apply_import_session(tests.uid(791), null, 'k-race', $j$[
  {"media_type":"ANIME","media_id":970061,"import_action":"update","expected":{"list_type":"WATCHING","progress":3},
   "insert_values":{"list_type":"WATCHING","progress":5,"rating":9},"update_values":{"list_type":"WATCHING","progress":5,"rating":9},"journal":{}}
]$j$::jsonb)) ->> 'session_id' as k1_sid \gset
select dblink_exec('l2a_a', 'begin');
select dblink_exec('l2a_a', format('update public.anime_user_lists set rating = 10 where user_id = %L and anime_id = 970061', tests.uid(791)));
select dblink_send_query('l2a_b', format('select public.undo_import_session(%L, %L)::text', tests.uid(791), :'k1_sid'));
select pg_temp.l2a_wait_for_lock(:l2a_b_pid, 'undo');
select dblink_exec('l2a_a', 'commit');
select r as k1_undo from dblink_get_result('l2a_b') as t(r text) \gset
select count(*) from dblink_get_result('l2a_b') as t(r text);
select tests.eq('K1 F08 race: the concurrent edit committed during Undo survives; the untouched field reverts',
  (select list_type || '/' || progress || '/' || rating from public.anime_user_lists
    where user_id = tests.uid(791)::text and anime_id = 970061), 'WATCHING/3/10');
select tests.eq('K1: ...and Undo reports the kept field',
  (:'k1_undo'::jsonb) -> 'skipped', '[{"mediaType":"ANIME","mediaId":970061,"reason":"edited_since_import","fields":["rating"]}]'::jsonb);

-- K2. a retry that arrives while the first Apply is still open replays it (no second write)
\set k2_items '[{"media_type":"ANIME","media_id":970062,"import_action":"add","expected":null,"insert_values":{"list_type":"WATCHING","progress":4},"update_values":{"list_type":"WATCHING","progress":4},"journal":{"raw":"first"}}]'
select dblink_exec('l2a_a', 'begin');
select r as k2_first from dblink('l2a_a', format('select public.apply_import_session(%L, null, %L, %L::jsonb)::text',
  tests.uid(792), 'k-concurrent', :'k2_items')) as t(r text) \gset
select dblink_send_query('l2a_b', format('select public.apply_import_session(%L, null, %L, %L::jsonb)::text',
  tests.uid(792), 'k-concurrent', replace(:'k2_items', '"progress":4', '"progress":7')));
select pg_temp.l2a_wait_for_lock(:l2a_b_pid, 'concurrent apply');
select dblink_exec('l2a_a', 'commit');
select r as k2_second from dblink_get_result('l2a_b') as t(r text) \gset
select count(*) from dblink_get_result('l2a_b') as t(r text);
select tests.eq('K2: the concurrent duplicate returns the first outcome as a replay',
  (:'k2_second'::jsonb), jsonb_set(:'k2_first'::jsonb, '{replayed}', 'true'::jsonb));
select tests.eq('K2: one session, one journal row, the first write only',
  (select count(*) from public.import_sessions where user_id = tests.uid(792)) || '/' ||
  (select count(*) from public.import_session_items i join public.import_sessions s on s.id = i.session_id where s.user_id = tests.uid(792)) || '/' ||
  (select progress from public.anime_user_lists where user_id = tests.uid(792)::text and anime_id = 970062), '1/1/4');

-- K3/K4. Lock order (review R2): the batch is paused right after its FIRST write (which took the
-- user's recompute-queue row through taste_capture); meanwhile the user saves a manual edit of
-- ANOTHER row of the same batch. Without the pre-lock pass the two cross (row -> queue vs
-- queue -> row) and PostgreSQL aborts one of them (40P01). The pause is an advisory lock held by
-- this session and taken by a journal trigger in the batch's backend; every wait is state-based.
create function tests.l2a_pause() returns trigger language plpgsql as $f$
begin
  if new.raw = tg_argv[0] then perform pg_advisory_xact_lock_shared(7020001); end if;
  return new;
end $f$;
create trigger l2a_pause_apply before insert on public.import_session_items
  for each row execute function tests.l2a_pause('PAUSE_APPLY');
create trigger l2a_pause_undo before update on public.import_session_items
  for each row execute function tests.l2a_pause('PAUSE_UNDO');
select pid as l2a_a_pid from dblink('l2a_a', 'select pg_backend_pid()') as t(pid integer) \gset
select tests.make_user(793), tests.make_user(794);
insert into public.anime (id) values (970071), (970072), (970073), (970074) on conflict (id) do nothing;

-- K3: Apply [add 970071 (pause after its write), update 970072]; the user edits 970072 meanwhile
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(793)::text, 970072, 'WATCHING', 2);
select pg_advisory_lock(7020001);
select dblink_send_query('l2a_a', format($q$select public.apply_import_session(%L, null, 'k-lock-order', $j$[
  {"media_type":"ANIME","media_id":970071,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{"raw":"PAUSE_APPLY"}},
  {"media_type":"ANIME","media_id":970072,"import_action":"update","expected":{"list_type":"WATCHING","progress":2},
   "insert_values":{"list_type":"WATCHING","progress":6},"update_values":{"list_type":"WATCHING","progress":6},"journal":{"raw":"second"}}
]$j$::jsonb)::text$q$, tests.uid(793)));
select pg_temp.l2a_wait_for_lock(:l2a_a_pid, 'paused Apply');
select dblink_send_query('l2a_b', format('update public.anime_user_lists set rating = 9 where user_id = %L and anime_id = 970072', tests.uid(793)));
select pg_temp.l2a_wait_for_lock(:l2a_b_pid, 'manual edit during Apply');
select pg_advisory_unlock(7020001);
select coalesce((select r from dblink_get_result('l2a_a', false) as t(r text)), 'ERROR: ' || dblink_error_message('l2a_a')) as k3_apply \gset
select count(*) from dblink_get_result('l2a_a', false) as t(r text);
select coalesce((select r from dblink_get_result('l2a_b', false) as t(r text)), 'ERROR: ' || dblink_error_message('l2a_b')) as k3_edit \gset
select count(*) from dblink_get_result('l2a_b', false) as t(r text);
select tests.eq('K3 R2: the Apply commits (no deadlock)',
  case when :'k3_apply' like 'ERROR:%' then :'k3_apply' else (:'k3_apply'::jsonb) #>> '{applied,1,mediaId}' end, '970072');
select tests.eq('K3 R2: the user''s concurrent save commits (not a deadlock victim)', :'k3_edit'::text, 'UPDATE 1'::text);
select tests.eq('K3 R2: the manual edit applies on top of the import (both survive)',
  (select list_type || '/' || progress || '/' || coalesce(rating::text, 'null') from public.anime_user_lists
    where user_id = tests.uid(793)::text and anime_id = 970072), 'WATCHING/6/9');

-- K4: Undo of [update 970073, add 970074]: descending order reverts 970074 first (its delete takes
-- the queue row), pauses, and the user edits 970073 meanwhile
insert into public.anime_user_lists (user_id, anime_id, list_type, progress) values (tests.uid(794)::text, 970073, 'WATCHING', 2);
select (public.apply_import_session(tests.uid(794), null, 'k-lock-order-undo', $j$[
  {"media_type":"ANIME","media_id":970073,"import_action":"update","expected":{"list_type":"WATCHING","progress":2},
   "insert_values":{"list_type":"WATCHING","progress":6},"update_values":{"list_type":"WATCHING","progress":6},"journal":{"raw":"first"}},
  {"media_type":"ANIME","media_id":970074,"import_action":"add","expected":null,
   "insert_values":{"list_type":"PLANNING","progress":0},"update_values":{"list_type":"PLANNING"},"journal":{"raw":"PAUSE_UNDO"}}
]$j$::jsonb)) ->> 'session_id' as k4_sid \gset
select pg_advisory_lock(7020001);
select dblink_send_query('l2a_a', format('select public.undo_import_session(%L, %L)::text', tests.uid(794), :'k4_sid'));
select pg_temp.l2a_wait_for_lock(:l2a_a_pid, 'paused Undo');
select dblink_send_query('l2a_b', format('update public.anime_user_lists set rating = 9 where user_id = %L and anime_id = 970073', tests.uid(794)));
select pg_temp.l2a_wait_for_lock(:l2a_b_pid, 'manual edit during Undo');
select pg_advisory_unlock(7020001);
select coalesce((select r from dblink_get_result('l2a_a', false) as t(r text)), 'ERROR: ' || dblink_error_message('l2a_a')) as k4_undo \gset
select count(*) from dblink_get_result('l2a_a', false) as t(r text);
select coalesce((select r from dblink_get_result('l2a_b', false) as t(r text)), 'ERROR: ' || dblink_error_message('l2a_b')) as k4_edit \gset
select count(*) from dblink_get_result('l2a_b', false) as t(r text);
select tests.eq('K4 R2: the Undo commits (no deadlock)',
  case when :'k4_undo' like 'ERROR:%' then :'k4_undo' else (:'k4_undo'::jsonb) ->> 'result' end, 'undone');
select tests.eq('K4 R2: the user''s concurrent save commits (not a deadlock victim)', :'k4_edit'::text, 'UPDATE 1'::text);
select tests.eq('K4 R2: Undo reverted its fields, the manual edit applies on top, the add is gone',
  (select list_type || '/' || progress || '/' || coalesce(rating::text, 'null') from public.anime_user_lists
    where user_id = tests.uid(794)::text and anime_id = 970073) || '/' ||
  (select count(*) from public.anime_user_lists where user_id = tests.uid(794)::text and anime_id = 970074), 'WATCHING/2/9/0');
drop trigger l2a_pause_apply on public.import_session_items;
drop trigger l2a_pause_undo on public.import_session_items;
drop function tests.l2a_pause();

select dblink_disconnect('l2a_a'), dblink_disconnect('l2a_b');
delete from public.anime_user_lists where user_id in (tests.uid(791)::text, tests.uid(792)::text, tests.uid(793)::text, tests.uid(794)::text);
delete from public.taste_import_context where user_id in (tests.uid(791), tests.uid(792), tests.uid(793), tests.uid(794));
delete from public.import_sessions where user_id in (tests.uid(791), tests.uid(792), tests.uid(793), tests.uid(794));
delete from public.taste_signal_events where user_id in (tests.uid(791), tests.uid(792), tests.uid(793), tests.uid(794));
delete from public.taste_profile_recompute_queue where user_id in (tests.uid(791), tests.uid(792), tests.uid(793), tests.uid(794));
delete from public.profiles where id in (tests.uid(791), tests.uid(792), tests.uid(793), tests.uid(794));
delete from auth.users where id in (tests.uid(791), tests.uid(792), tests.uid(793), tests.uid(794));
delete from public.anime where id in (970061, 970062, 970071, 970072, 970073, 970074);
drop extension dblink;
\else
select tests.blocked('K two-session races (compare-and-revert, concurrent idempotent replay)',
  'dblink is not available in this PostgreSQL; recovery: install the postgresql@17 contrib modules (dblink) and rerun');
\endif
