-- W5 guest browsing: the anonymous API role gets an explicit EXECUTE allowlist.
--
-- PREPARED ONLY. Not applied anywhere. Apply only after explicit owner approval, and only together with
-- the approved W5 build plan: client guests depend on this allowlist. The release switch
-- `guest_browsing_v1` is inserted DISABLED at 0 %; applying this file does not show guest mode.
--
-- What it does (the order matters):
--   1. Resolves the allowlist. EVERY signature must resolve, otherwise the migration RAISES, except W4's
--      search_anime_page_v2 / search_manga_page_v2 (20261118100000), which may still be absent and are then
--      skipped with a NOTICE (re-run live audit query 1 after W4 is applied).
--   2. Snapshots which of `authenticated` and `service_role` can execute which function.
--   3. Revokes EXECUTE from PUBLIC and anon on every non-extension function, aggregate and procedure in `public`.
--   4. Re-grants the snapshot to `authenticated` and `service_role` only, and only where they held EXECUTE
--      before (typically through PUBLIC). No other role (authenticator, dashboard_user, supabase_*) receives
--      a new explicit grant: PUBLIC-only access is not turned into explicit grants for every role.
--   4b. Revokes EXECUTE on get_provider_availability_refresh_candidates(integer,text,integer,integer) from
--      `authenticated`: it is SECURITY DEFINER with no auth guard and is service-only by intent (only
--      scripts/provider_availability_worker.swift calls it, with the service-role key). The two
--      auth.role()-guarded functions (publish_mapping_revision, recompute_media_realm_llm_deltas) are untouched.
--   5. Grants the allowlist to anon.
--   6. Drops Supabase's per-schema default that grants anon EXECUTE on every new public function, for role
--      postgres, and for role supabase_admin when this role may alter it (superuser or member of that role;
--      otherwise a NOTICE and live audit query 3b documents the remaining row). D-W5-DP: the global PUBLIC
--      default is deliberately NOT revoked; a later migration must still `revoke all on function ... from public`.
--   7. Inserts the flag row (off).
--   8. Self-asserts: anon executes nothing outside the allowlist; authenticated/service_role lost nothing
--      (except the deliberate 4b revoke). A function owned by a role postgres cannot revoke from aborts the whole
--      migration instead of staying silently open.
--
-- ORDER RULE: this file only closes what exists when it runs. Every LATER migration that adds a public function
-- must `revoke all on function ... from public` itself (the global PUBLIC default stays open), and live audit
-- query 1 (docs/tracker-gaps-2026-11/W5-guest/live-anon-grants.sql) must be RE-RUN after every later migration.
--
-- The allowlist is 22 signatures:
--   19 guest page reads (Discover, Search, Browse, title, entity and season pages), and
--   3 signed-out infrastructure functions that live callers need with the anon key:
--     check_concierge_rate_limit  (contact-submit runs its limiter on the ANON client; Edge anonymous parse)
--     search_titles               (concierge-parse anonymous public parse; SECURITY INVOKER)
--     normalize_title             (pure helper that search_titles calls as the invoker)
--   get_concierge_config is NOT allowlisted: it is called only for signed-in callers or from inside a
--   SECURITY DEFINER function.
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
-- To restore get_provider_availability_refresh_candidates for signed-in users (not recommended):
--   grant execute on function public.get_provider_availability_refresh_candidates(integer,text,integer,integer) to authenticated;
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
      if r.sig like 'public.search\_%\_page\_v2(%' then
        raise notice 'W5: W4 allowlisted function absent (allowed): %', r.sig;
      else
        raise exception 'W5: allowlisted function absent: %', r.sig;
      end if;
    else
      v_allow := v_allow || to_regprocedure(r.sig)::oid;
    end if;
  end loop;

  -- 2. snapshot what authenticated and service_role can execute today
  create temp table w5_before(fn oid, role_name name) on commit drop;
  insert into w5_before(fn, role_name)
  select p.oid, ro.rolname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  cross join pg_roles ro
  where n.nspname = 'public'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    and ro.rolname in ('authenticated', 'service_role')
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

  -- 4. restore authenticated/service_role where they held EXECUTE (never any other role)
  for r in
    select b.fn::regprocedure::text as sig, b.role_name
    from w5_before b
    where not has_function_privilege(b.role_name, b.fn, 'EXECUTE')
    order by 1, 2
  loop
    execute format('grant execute on routine %s to %I', r.sig, r.role_name);
  end loop;

  -- 4b. service-only by intent, no internal auth guard: authenticated loses it deliberately
  if to_regprocedure('public.get_provider_availability_refresh_candidates(integer,text,integer,integer)') is not null then
    revoke execute on function public.get_provider_availability_refresh_candidates(integer,text,integer,integer) from authenticated;
    delete from w5_before
    where fn = 'public.get_provider_availability_refresh_candidates(integer,text,integer,integer)'::regprocedure
      and role_name = 'authenticated';
  end if;

  -- 5. the allowlist
  for r in select unnest(v_allow)::regprocedure::text as sig loop
    execute format('grant execute on routine %s to anon', r.sig);
  end loop;
end $$;

-- 6. Supabase's per-schema default (anon EXECUTE on every new function). authenticated/service_role keep theirs.
alter default privileges for role postgres in schema public revoke execute on functions from anon;
-- Supabase also keeps a default ACL row for role supabase_admin (objects the dashboard creates). Only a superuser
-- or a member of supabase_admin may change it; migrations run as postgres, whose objects the postgres row covers.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_admin')
     and (exists (select 1 from pg_roles where rolname = current_user and rolsuper)
          or pg_has_role(current_user, 'supabase_admin', 'MEMBER')) then
    alter default privileges for role supabase_admin in schema public revoke execute on functions from anon;
  else
    raise notice 'W5: not allowed to alter default privileges for role supabase_admin; leaving that row (live audit query 3b)';
  end if;
end $$;

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
