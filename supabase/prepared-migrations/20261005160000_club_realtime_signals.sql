-- ============================================================================
-- Clubs: scoped Realtime invalidation + revocation signals (F42, server side)
--
-- STATUS: PREPARED, NOT APPLIED TO PRODUCTION. Deployment needs a separate, explicit
--   human approval; the lead registers it in supabase/tests/pending_migrations.txt.
--   Requires 20261005150000 (own-row club policies; the lifecycle trigger).
--
-- Why: after F34 a subscriber's postgres_changes on club_votes /
--   club_rail_item_reactions carry only that subscriber's OWN rows (Realtime applies
--   RLS per subscriber), and those subscriptions plus club_rail_items were never
--   filtered by club. club_members is not in the publication, so a removed member never
--   learns about the removal. Putting club_members into the publication would broadcast
--   every membership DELETE (primary key only, not RLS-checked, not filterable) to every
--   subscriber, so it stays OUT. Instead two small signal tables carry no private data:
--
--   club_activity_signals (club_id PK, revision, changed_at)
--     one row per club, revision bumped by every change to its rails, items, polls,
--     votes, reactions, members and settings. No user identifier. SELECT: current members
--     (is_club_member). Subscribe: table club_activity_signals, filter club_id=eq.<club>;
--     on any event refetch the authorized bundle (bounded: one refetch per event burst).
--   club_membership_signals (user_id, club_id, state, revision, changed_at)
--     one row per (user, club); state member | left | removed | club_deleted.
--     SELECT: only that user. Subscribe: table club_membership_signals, filter
--     user_id=eq.<me>; state <> 'member' => drop every cached private state of club_id
--     and stop its channel. This is the revocation event.
--   Nobody writes either table through the table API; SECURITY DEFINER triggers do.
--   Rows of a deleted user go with the auth user (FK cascade); a deleted club's activity
--   row goes with the club, while its members' membership rows remain (club_deleted).
--
-- Not changed: the existing publication membership of club_rail_items, club_polls,
--   club_votes and club_rail_item_reactions (old app builds still subscribe to them).
--   The native coordinator (lane L1) should replace those four streams with the two
--   above; see the report of lane L3 for the exact subscription contract.
--
-- Production parity (read-only, before deploying):
--   select schemaname, tablename from pg_publication_tables where pubname = 'supabase_realtime';
-- Rollback: alter publication supabase_realtime drop table public.club_activity_signals,
--   public.club_membership_signals; drop the club_realtime_signal triggers, the functions
--   public.club_realtime_signal() and public._club_activity_bump(uuid), and both tables.
-- ============================================================================

create table if not exists public.club_activity_signals (
  club_id    uuid primary key references public.clubs(id) on delete cascade,
  revision   bigint not null default 0,
  changed_at timestamptz not null default now()
);
comment on table public.club_activity_signals is
  'F42: per-club change revision for Realtime invalidation (filter club_id=eq.<club>). No user identifiers. Current members may read; written only by triggers.';
alter table public.club_activity_signals enable row level security;
drop policy if exists club_activity_signals_select_member on public.club_activity_signals;
create policy club_activity_signals_select_member on public.club_activity_signals
  for select to authenticated using (public.is_club_member(club_id));
revoke all on table public.club_activity_signals from public, anon, authenticated;
grant select on table public.club_activity_signals to authenticated;
grant all on table public.club_activity_signals to service_role;

create table if not exists public.club_membership_signals (
  user_id    uuid not null references auth.users(id) on delete cascade,
  club_id    uuid not null,
  state      text not null check (state in ('member', 'left', 'removed', 'club_deleted')),
  revision   bigint not null default 1,
  changed_at timestamptz not null default now(),
  primary key (user_id, club_id)
);
comment on table public.club_membership_signals is
  'F42: per-user membership state for Realtime revocation (filter user_id=eq.<me>). Only the user may read their rows; written only by triggers. club_id has no FK on purpose (club_deleted must survive the club).';
alter table public.club_membership_signals enable row level security;
drop policy if exists club_membership_signals_select_own on public.club_membership_signals;
create policy club_membership_signals_select_own on public.club_membership_signals
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on table public.club_membership_signals from public, anon, authenticated;
grant select on table public.club_membership_signals to authenticated;
grant all on table public.club_membership_signals to service_role;

create or replace function public._club_activity_bump(p_club_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
begin
  if p_club_id is null then
    return;
  end if;
  -- a club deleted in this command (cascade) gets no new row
  insert into public.club_activity_signals as s (club_id, revision, changed_at)
  select p_club_id, 1, now()
   where exists (select 1 from public.clubs where id = p_club_id)
  on conflict (club_id) do update set revision = s.revision + 1, changed_at = now();
end;
$$;
revoke all on function public._club_activity_bump(uuid) from public, anon, authenticated;

create or replace function public.club_realtime_signal()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_row record;
  v_club uuid;
  v_actor uuid := auth.uid();
  v_state text;
begin
  if tg_op = 'DELETE' then v_row := old; else v_row := new; end if;

  if tg_table_name = 'clubs' then
    v_club := v_row.id;
  elsif tg_table_name in ('club_rails', 'club_polls', 'club_members') then
    v_club := v_row.club_id;
  elsif tg_table_name = 'club_rail_items' then
    select cr.club_id into v_club from public.club_rails cr where cr.id = v_row.rail_id;
  elsif tg_table_name = 'club_votes' then
    select cp.club_id into v_club from public.club_polls cp where cp.id = v_row.poll_id;
  elsif tg_table_name = 'club_rail_item_reactions' then
    select cr.club_id into v_club
      from public.club_rail_items cri join public.club_rails cr on cr.id = cri.rail_id
     where cri.id = v_row.rail_item_id;
  end if;

  perform public._club_activity_bump(v_club);

  if tg_table_name = 'club_members' then
    -- the auth user is being deleted (FK cascade): its signal rows go with it
    if exists (select 1 from auth.users where id = v_row.user_id) then
      if tg_op = 'INSERT' then
        v_state := 'member';
      elsif tg_op = 'DELETE' then
        v_state := case
          when not exists (select 1 from public.clubs where id = old.club_id) then 'club_deleted'
          when v_actor is not null and v_actor <> old.user_id then 'removed'
          else 'left'
        end;
      end if;
      if v_state is not null then
        insert into public.club_membership_signals as s (user_id, club_id, state, revision, changed_at)
        values (v_row.user_id, v_row.club_id, v_state, 1, now())
        on conflict (user_id, club_id) do update
          set state = excluded.state, revision = s.revision + 1, changed_at = now();
      end if;
    end if;
  end if;
  return null;
end;
$$;
revoke all on function public.club_realtime_signal() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array['club_rails', 'club_rail_items', 'club_polls', 'club_votes',
                           'club_rail_item_reactions', 'club_members']
  loop
    execute format('drop trigger if exists club_realtime_signal on public.%I', t);
    execute format('create trigger club_realtime_signal after insert or update or delete on public.%I
                      for each row execute function public.club_realtime_signal()', t);
  end loop;
  drop trigger if exists club_realtime_signal on public.clubs;
  create trigger club_realtime_signal after insert or update on public.clubs
    for each row execute function public.club_realtime_signal();
end $$;

-- backfill: one activity row per existing club, one membership row per existing membership
insert into public.club_activity_signals (club_id)
select id from public.clubs
on conflict (club_id) do nothing;
insert into public.club_membership_signals (user_id, club_id, state)
select m.user_id, m.club_id, 'member' from public.club_members m
on conflict (user_id, club_id) do nothing;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'publication supabase_realtime is missing; this file needs the Supabase Realtime publication';
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'club_activity_signals') then
    alter publication supabase_realtime add table public.club_activity_signals;
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'club_membership_signals') then
    alter publication supabase_realtime add table public.club_membership_signals;
  end if;
end $$;
