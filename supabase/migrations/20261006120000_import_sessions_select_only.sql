-- F77: import_sessions / import_session_items — authenticated users SELECT-only.
-- The iOS app never writes these tables (no `.from("import_sessions")`). Apply/Undo
-- write them only inside SECURITY DEFINER RPCs as the service role
-- (`apply_import_session` / `undo_import_session`, 20261005130000). Drop the
-- previous FOR ALL policies and leave SELECT for the owning user.
--
-- Rollback:
--   drop policy if exists import_sessions_own_select on public.import_sessions;
--   drop policy if exists import_session_items_own_select on public.import_session_items;
--   create policy import_sessions_own_all on public.import_sessions
--     for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
--   create policy import_session_items_own_all on public.import_session_items
--     for all using (exists (select 1 from public.import_sessions s
--       where s.id = import_session_items.session_id and s.user_id = auth.uid()))
--     with check (exists (select 1 from public.import_sessions s
--       where s.id = import_session_items.session_id and s.user_id = auth.uid()));

set search_path = public, extensions;

drop policy if exists import_sessions_own_all on public.import_sessions;
drop policy if exists import_sessions_own_select on public.import_sessions;
create policy import_sessions_own_select on public.import_sessions
  for select
  using (auth.uid() = user_id);

drop policy if exists import_session_items_own_all on public.import_session_items;
drop policy if exists import_session_items_own_select on public.import_session_items;
create policy import_session_items_own_select on public.import_session_items
  for select
  using (
    exists (
      select 1 from public.import_sessions s
      where s.id = import_session_items.session_id
        and s.user_id = auth.uid()
    )
  );

revoke insert, update, delete on table public.import_sessions from authenticated;
revoke insert, update, delete on table public.import_session_items from authenticated;
grant select on table public.import_sessions to authenticated;
grant select on table public.import_session_items to authenticated;
