-- 00_harness_and_preconditions.sql
-- Proves the harness judges access through the real authorization path and that
-- its assertions are not vacuous, and that the fixture contains the objects the
-- later tests depend on (a missing object fails the run instead of silently
-- skipping a test).
\set ON_ERROR_STOP on
begin;

-- ---- role posture ----------------------------------------------------------
select tests.ok('role authenticated is not superuser and does not bypass RLS',
  (select not rolsuper and not rolbypassrls from pg_roles where rolname = 'authenticated'));
select tests.ok('role anon is not superuser and does not bypass RLS',
  (select not rolsuper and not rolbypassrls from pg_roles where rolname = 'anon'));
select tests.ok('role service_role bypasses RLS (so it is never used to judge user access)',
  (select rolbypassrls from pg_roles where rolname = 'service_role'));

-- ---- the identity switch really is the PostgREST path ----------------------
select tests.make_user(1);
select tests.as_user(tests.uid(1));
select tests.eq('as_user: current_user is authenticated', current_user::text, 'authenticated');
select tests.eq('as_user: auth.uid() resolves from request.jwt.claims', auth.uid(), tests.uid(1));
select tests.eq('as_user: auth.role() resolves from request.jwt.claims', auth.role(), 'authenticated');
select tests.ok('as_user: session is NOT acting as superuser',
  not (select rolsuper from pg_roles where rolname = current_user));
select tests.as_anon();
select tests.eq('as_anon: current_user is anon', current_user::text, 'anon');
select tests.ok('as_anon: auth.uid() is null', auth.uid() is null);
select tests.reset();

-- ---- negative control: the assertions MUST detect a leak -------------------
-- t_open has no RLS (a deliberate leak); t_rls has a correct owner policy.
create table tests.t_open (owner_id uuid, v text);
create table tests.t_rls  (owner_id uuid, v text);
alter table tests.t_rls enable row level security;
create policy own on tests.t_rls for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
grant all on tests.t_open, tests.t_rls to authenticated;
select tests.make_user(2);
insert into tests.t_open values (tests.uid(1), 'secret-1'), (tests.uid(2), 'secret-2');
insert into tests.t_rls  values (tests.uid(1), 'secret-1'), (tests.uid(2), 'secret-2');

select tests.as_user(tests.uid(2));
select tests.eq('control: correct RLS isolates user 2 from user 1 rows',
  (select count(*) from tests.t_rls where owner_id = tests.uid(1)), 0::bigint);
do $$
declare caught boolean := false;
begin
  begin
    perform tests.eq('control: no-RLS table must NOT look isolated',
      (select count(*) from tests.t_open where owner_id = tests.uid(1)), 0::bigint);
  exception when others then
    caught := sqlerrm like 'TEST FAIL:%';
  end;
  if not caught then
    raise exception 'HARNESS BROKEN: a leaking table passed the isolation assertion';
  end if;
  raise notice 'TEST ok: control: isolation assertion fails on a table without RLS (harness is not vacuous)';
end $$;
select tests.denied('control: tests.denied rejects a statement that is allowed (checked below)',
  $q$ insert into tests.t_rls values (tests.uid(1), 'forged') $q$);
do $$
declare caught boolean := false;
begin
  begin
    perform tests.denied('control: allowed insert must not count as denied',
      $q$ insert into tests.t_rls values (auth.uid(), 'legit') $q$);
  exception when others then
    caught := sqlerrm like 'TEST FAIL:%';
  end;
  if not caught then
    raise exception 'HARNESS BROKEN: tests.denied accepted an ALLOWED statement';
  end if;
  raise notice 'TEST ok: control: tests.denied fails when the statement is allowed';
end $$;
select tests.reset();

-- ---- fixture preconditions (fail loudly instead of skipping) ---------------
do $$
declare
  missing text;
begin
  select string_agg(t, ', ') into missing
  from unnest(array[
    'anime_user_lists','manga_user_lists','clubs','club_members','club_rails','club_rail_items',
    'club_rail_item_reactions','club_polls','club_poll_options','club_votes','title_comments',
    'title_comment_reactions','user_streaming_services','streaming_services','user_taste_profiles',
    'taste_signal_events','taste_import_context','profiles','anime','manga'
  ]) t
  where not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = t and c.relkind = 'r' and c.relrowsecurity);
  if missing is not null then
    raise exception 'FIXTURE PRECONDITION: tables missing or without RLS enabled: %', missing;
  end if;

  select string_agg(f, ', ') into missing
  from unnest(array[
    'create_club(text,text,text)','join_club(text)','leave_club(uuid)','fetch_club_bundle(uuid)',
    'is_club_member(uuid)','is_club_admin_or_owner(uuid)','is_club_owner(uuid)','shares_club_with(uuid)',
    'create_club_rail(uuid,text,text)','add_club_rail_item(uuid,text,integer,text)',
    'toggle_club_reaction(uuid,text)','create_club_poll(uuid,text,text[],timestamp with time zone)',
    'cast_club_vote(uuid,uuid)','upsert_title_comment(text,integer,text)','toggle_comment_reaction(uuid,text)',
    'save_user_streaming_services(text[])','delete_user_concierge_data(text)'
  ]) f
  where to_regprocedure('public.' || f) is null;
  if missing is not null then
    raise exception 'FIXTURE PRECONDITION: functions missing: %', missing;
  end if;
  raise notice 'TEST ok: fixture preconditions (tables with RLS + RPCs) present';
end $$;

rollback;
