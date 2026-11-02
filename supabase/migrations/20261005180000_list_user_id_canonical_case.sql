-- ============================================================================
-- anime_user_lists / manga_user_lists: canonical lower-case user_id (F16, SQL side)
--
-- STATUS: PREPARED, NOT APPLIED TO PRODUCTION. Deployment needs a separate, explicit
--   human approval; the lead registers it in supabase/tests/pending_migrations.txt.
--
-- Problem: user_id on the two legacy list tables is TEXT and the captured policy
-- "Users can manage their own lists" compares auth.uid()::text (lower-case). Swift's
-- UUID.uuidString is UPPER-case, so an upper-case owner id is denied by RLS (fixture
-- reproduction: supabase/tests/rls/10_user_lists.sql) and a fake backend that uses the
-- same string on both sides hides it. The native adapter (lane L1) canonicalizes at its
-- one boundary; this trigger makes the database canonical for every writer as well.
--
-- Mechanism: BEFORE INSERT OR UPDATE OF user_id normalizes NEW.user_id := lower(btrim()).
-- RLS WITH CHECK runs after BEFORE ROW triggers, so an owner sending the upper-case
-- spelling of their own id is accepted and stored as auth.uid()::text; another user's id
-- in any spelling is still denied. The unique key (user_id, media_id) then also holds
-- across spellings for NEW writes.
--
-- Historical rows are NOT touched here. A separate, opt-in, human-approved repair with
-- explicit collision handling lives in
-- supabase/prepared-migrations/opt-in/20261005180100_list_user_id_lowercase_backfill.sql
-- (read-only counts first; never a blanket rewrite of production rows).
--
-- Read-only check before deploying:
--   select count(*) filter (where user_id <> lower(user_id)) from public.anime_user_lists;
--   select count(*) filter (where user_id <> lower(user_id)) from public.manga_user_lists;
-- Rollback: drop trigger list_user_id_canonical_case on both tables;
--   drop function public.list_user_id_canonical_case().
-- ============================================================================

create or replace function public.list_user_id_canonical_case()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  if new.user_id is not null then
    new.user_id := lower(btrim(new.user_id));
  end if;
  return new;
end;
$$;
revoke all on function public.list_user_id_canonical_case() from public, anon, authenticated;

drop trigger if exists list_user_id_canonical_case on public.anime_user_lists;
create trigger list_user_id_canonical_case
  before insert or update of user_id on public.anime_user_lists
  for each row execute function public.list_user_id_canonical_case();

drop trigger if exists list_user_id_canonical_case on public.manga_user_lists;
create trigger list_user_id_canonical_case
  before insert or update of user_id on public.manga_user_lists
  for each row execute function public.list_user_id_canonical_case();
