-- W5 guest browsing: the anonymous API role gets an explicit EXECUTE allowlist.
--
-- PREPARED ONLY. Not applied anywhere. Apply only after explicit owner approval, and only together with
-- the approved W5 build plan: client guests depend on this allowlist. The release switch
-- `guest_browsing_v1` is inserted DISABLED at 0 %; applying this file does not show guest mode.
--
-- What it does (the order matters):
--   1. Resolves the allowlist. A signature that does not exist yet (W4's search_*_v2 before 20261118100000)
--      is reported with a NOTICE and skipped; the live audit (docs/tracker-gaps-2026-11/W5-guest/live-anon-grants.sql)
--      enforces presence.
--   2. Snapshots which other roles can execute which function (excluding anon, superusers, pg_* roles and
--      roles that inherit from anon).
--   3. Revokes EXECUTE from PUBLIC and anon on every non-extension function, aggregate and procedure in `public`.
--   4. Re-grants the snapshot to every role that only had it through PUBLIC (authenticated, service_role and any
--      other role keep exactly what they could do before).
--   5. Grants the allowlist to anon.
--   6. Drops Supabase's per-schema default that grants anon EXECUTE on every new public function (D-W5-DP:
--      the global PUBLIC default is deliberately NOT revoked; a later migration must still
--      `revoke all on function ... from public`, which test 114's exact-set assertion enforces).
--   7. Inserts the flag row (off).
--   8. Self-asserts: anon executes nothing outside the allowlist; no other role lost anything. A function owned
--      by a role postgres cannot revoke from aborts the whole migration instead of staying silently open.
--
-- The allowlist is 23 signatures:
--   19 guest page reads (Discover, Search, Browse, title, entity and season pages), and
--   4 signed-out infrastructure functions that live callers need with the anon key:
--     check_concierge_rate_limit  (contact-submit runs its limiter on the ANON client; Edge anonymous parse)
--     get_concierge_config        (concierge-parse anonymous public parse)
--     search_titles               (concierge-parse anonymous public parse; SECURITY INVOKER)
--     normalize_title             (pure helper that search_titles calls as the invoker)
--   check_concierge_rate_limit writes a rate-limit counter row. That is an existing, deliberately anonymous
--   limiter write that the contact form relies on; it is the only anonymous write left and is an owner
--   decision to keep (see the W5 evidence note). Nothing else anonymous can write: every list, club,
--   taste, import, telemetry and queue writer loses anon.
--   Already service-role only before this file (20261108120159): check_email_exists, rate_limit_hit.
--
-- Rollback: this removes only access nobody needs. To re-open a single function:
--   grant execute on function <signature> to anon;
-- To restore the per-schema default:
--   alter default privileges for role postgres in schema public grant execute on functions to anon;
begin;
set local lock_timeout = '3s';
set local search_path = public, extensions;

create temp table w5_allow_sigs(sig text primary key) on commit drop;
insert into w5_allow_sigs(sig) values
  ('public.discover_bundle(integer,integer)'),
  ('public.discover_section_page_v1(text,text,text,text,text,text,integer,integer)'),
  ('public.discover_mood_v1(text,text,integer,integer)'),
  ('public.media_franchise_ids_v1(integer[],integer[])'),
  ('public.recommend_ids_similar_to_seeds(text,integer[],integer,boolean)'),
  ('public.media_similar_v1(text,integer,integer)'),
  ('public.browse_anime_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text)'),
  ('public.browse_manga_page(text,text,integer,integer,text,integer,timestamptz,integer,integer,integer,integer,text)'),
  ('public.search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'),
  ('public.search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'),
  ('public.get_media_ladder(text,integer)'),
  ('public.get_manga_chapter_status(integer)'),
  ('public.media_release_schedule_v1(text,integer,integer)'),
  ('public.media_themes_v1(integer)'),
  ('public.anime_cast_v1(integer,text,integer)'),
  ('public.character_voice_actors_v1(integer,text)'),
  ('public.staff_voice_roles_v1(integer,integer)'),
  ('public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)'),
  ('public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)'),
  ('public.check_concierge_rate_limit(text,text,integer,integer,integer)'),
  ('public.get_concierge_config()'),
  ('public.search_titles(text,text,integer)'),
  ('public.normalize_title(text)');

do $$
declare
  r record;
  v_allow oid[] := '{}';
begin
  -- 1. resolve the allowlist
  for r in select sig from w5_allow_sigs order by sig loop
    if to_regprocedure(r.sig) is null then
      raise notice 'W5: allowlisted function absent: %', r.sig;
    else
      v_allow := v_allow || to_regprocedure(r.sig)::oid;
    end if;
  end loop;

  -- 2. snapshot what every other role can execute today
  create temp table w5_before(fn oid, role_name name) on commit drop;
  insert into w5_before(fn, role_name)
  select p.oid, ro.rolname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join pg_roles ro
  where n.nspname = 'public'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    and ro.rolname <> 'anon'
    and not ro.rolsuper
    and ro.rolname !~ '^pg_'
    and not pg_has_role(ro.oid, 'anon', 'USAGE')
    and has_function_privilege(ro.oid, p.oid, 'EXECUTE');

  -- 3. revoke PUBLIC and anon everywhere
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    order by 1
  loop
    execute format('revoke execute on routine %s from public, anon', r.sig);
  end loop;

  -- 4. restore every other role that held EXECUTE only through PUBLIC
  for r in
    select b.fn::regprocedure::text as sig, b.role_name
    from w5_before b
    where not has_function_privilege(b.role_name, b.fn, 'EXECUTE')
    order by 1, 2
  loop
    execute format('grant execute on routine %s to %I', r.sig, r.role_name);
  end loop;

  -- 5. the allowlist
  for r in select unnest(v_allow)::regprocedure::text as sig loop
    execute format('grant execute on routine %s to anon', r.sig);
  end loop;
end $$;

-- 6. Supabase's per-schema default (anon EXECUTE on every new function). authenticated/service_role keep theirs.
alter default privileges for role postgres in schema public revoke execute on functions from anon;

-- 7. the release switch, off
insert into public.feature_flags (flag_name, enabled, rollout_percentage, target_markets, description)
values ('guest_browsing_v1', false, 0, '{}', 'W5: browse before signing up (guest mode)')
on conflict (flag_name) do nothing;

-- 8. self-assertion
do $$
declare
  r record;
  v_extra text;
  v_lost text;
begin
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_extra
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    and has_function_privilege('anon', p.oid, 'EXECUTE')
    and p.oid::regprocedure::text not in (
      select to_regprocedure(sig)::text from w5_allow_sigs where to_regprocedure(sig) is not null);
  if v_extra is not null then
    raise exception 'W5: anon EXECUTE outside allowlist: %', v_extra;
  end if;

  select string_agg(b.role_name || ' on ' || b.fn::regprocedure::text, ', ' order by b.role_name, b.fn::regprocedure::text) into v_lost
  from w5_before b
  where not has_function_privilege(b.role_name, b.fn, 'EXECUTE');
  if v_lost is not null then
    raise exception 'W5: role lost EXECUTE: %', v_lost;
  end if;
end $$;

commit;
