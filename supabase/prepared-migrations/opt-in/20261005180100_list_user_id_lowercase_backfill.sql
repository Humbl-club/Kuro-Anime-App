-- ============================================================================
-- OPT-IN historical-row normalization: anime_user_lists / manga_user_lists user_id
-- to the canonical lower-case uuid text (F16, SQL side).
--
-- STATUS: PREPARED, OPT-IN, NOT DEPLOYED. Deliberately in a SUBDIRECTORY of
--   supabase/prepared-migrations/ so neither the fixture replay nor a bulk `git mv` of
--   the prepared files picks it up. It is NOT a migration to push. It is a one-time,
--   human-approved data repair for the approved target only, and it is pointless (and
--   refused below) unless 20261005180000_list_user_id_canonical_case.sql is applied.
--
-- Never run it before these READ-ONLY checks were run on the approved target and the
-- numbers reviewed (also in supabase/tests/prerequisites/delete_account_prereqs.sql):
--   select 'anime_user_lists' as tbl,
--          count(*) filter (where user_id <> lower(user_id))                as non_canonical_rows,
--          count(distinct lower(user_id)) filter (where user_id <> lower(user_id)) as affected_users
--     from public.anime_user_lists
--   union all
--   select 'manga_user_lists',
--          count(*) filter (where user_id <> lower(user_id)),
--          count(distinct lower(user_id)) filter (where user_id <> lower(user_id))
--     from public.manga_user_lists;
--   -- collisions: a non-canonical row whose canonical (lower-case) twin already exists
--   select count(*) from public.anime_user_lists u
--     join public.anime_user_lists c on c.user_id = lower(u.user_id) and c.anime_id = u.anime_id and c.id <> u.id
--    where u.user_id <> lower(u.user_id);
--   select count(*) from public.manga_user_lists u
--     join public.manga_user_lists c on c.user_id = lower(u.user_id) and c.manga_id = u.manga_id and c.id <> u.id
--    where u.user_id <> lower(u.user_id);
--   -- the effective policies decide whether non-canonical rows were ever visible:
--   select tablename, policyname, cmd, qual, with_check from pg_policies
--    where schemaname = 'public' and tablename in ('anime_user_lists', 'manga_user_lists');
-- If both counts are zero, do NOT run this file: there is nothing to repair.
--
-- Run (one transaction; nothing inside starts or ends a transaction):
--   psql -1 -v ON_ERROR_STOP=1 -f <this file>
--     default: refuses with COLLISIONS_PRESENT (and changes nothing) if any collision
--              exists; otherwise rewrites every non-canonical user_id to lower-case.
--   psql -1 -v ON_ERROR_STOP=1 -v resolve_collisions=keep_newest -f <this file>
--     explicit collision rule: per (canonical user, title) keep the most recently
--     updated row (ties: the already-canonical row, then the lowest id); the other rows
--     are DELETED and reported first as NOTICE lines (table, id, user, title, list_type,
--     updated_at) so the operator keeps the evidence outside the database. No backup
--     table is created on purpose: a copy would be one more personal-data store to
--     delete on account deletion.
--   The whole repair is ONE statement (a DO block), so a refusal is the only error and
--   nothing is changed.
--
-- Side effects to expect (existing triggers, not changed here):
--   * taste_bump_*_updated_at sets updated_at = now() on every normalized row, so
--     incremental readers see those rows as changed once (content is unchanged).
--   * taste_capture_* fires on the deleted duplicates (DELETE events) and may record a
--     'planned_add_removed_quickly' taste signal for a PLANNING duplicate created in the
--     last 24 hours.
--   * rows of users whose account deletion is in progress are skipped (the write
--     barrier would refuse them; the deletion removes both spellings anyway).
-- Rollback: none needed for the default mode on refusal; after a successful run the
-- previous spelling is not recoverable (it carried no information beyond its case).
-- ============================================================================

\if :{?resolve_collisions}
select set_config('kuro.list_case_resolve', :'resolve_collisions', true);
\else
select set_config('kuro.list_case_resolve', 'refuse', true);
\endif

do $$
declare
  v_mode text := current_setting('kuro.list_case_resolve');
  v_collisions bigint;
  r record;
begin
  if not exists (select 1 from pg_trigger where tgname = 'list_user_id_canonical_case'
                   and tgrelid = 'public.anime_user_lists'::regclass and not tgisinternal) then
    raise exception 'PREREQUISITE_MISSING: apply 20261005180000_list_user_id_canonical_case.sql first (new upper-case writes would recreate the problem)';
  end if;
  if v_mode not in ('refuse', 'keep_newest') then
    raise exception 'resolve_collisions must be keep_newest (or omitted)';
  end if;

  -- every row of every affected (canonical) user, minus users whose deletion is running
  create temp table _list_case_ranked on commit drop as
    with rows_ as (
      select 'anime_user_lists'::text as tbl, a.id, a.user_id, lower(a.user_id) as canon, a.anime_id as media_id, a.list_type, a.updated_at
        from public.anime_user_lists a
       where lower(a.user_id) in (select lower(user_id) from public.anime_user_lists where user_id <> lower(user_id))
         and not exists (select 1 from public.account_deletion_barriers b where b.user_id::text = lower(a.user_id))
      union all
      select 'manga_user_lists', m.id, m.user_id, lower(m.user_id), m.manga_id, m.list_type, m.updated_at
        from public.manga_user_lists m
       where lower(m.user_id) in (select lower(user_id) from public.manga_user_lists where user_id <> lower(user_id))
         and not exists (select 1 from public.account_deletion_barriers b where b.user_id::text = lower(m.user_id))
    )
    select r_.*, row_number() over (
             partition by tbl, canon, media_id
             order by updated_at desc nulls last, (user_id = canon) desc, id asc) as rnk,
           count(*) over (partition by tbl, canon, media_id) as group_size
      from rows_ r_;

  select count(*) into v_collisions from _list_case_ranked where group_size > 1 and rnk > 1;
  if v_collisions > 0 and v_mode = 'refuse' then
    raise exception 'COLLISIONS_PRESENT: % duplicate row(s) would collide after normalization; nothing was changed. Review them, then rerun with -v resolve_collisions=keep_newest', v_collisions;
  end if;

  for r in select * from _list_case_ranked where group_size > 1 and rnk > 1 order by tbl, canon, media_id, rnk loop
    raise notice 'keep_newest removes %.id=% user_id=% title=% list_type=% updated_at=%',
      r.tbl, r.id, r.user_id, r.media_id, r.list_type, r.updated_at;
  end loop;

  delete from public.anime_user_lists a using _list_case_ranked k
   where k.tbl = 'anime_user_lists' and k.group_size > 1 and k.rnk > 1 and a.id = k.id;
  delete from public.manga_user_lists m using _list_case_ranked k
   where k.tbl = 'manga_user_lists' and k.group_size > 1 and k.rnk > 1 and m.id = k.id;

  update public.anime_user_lists a set user_id = lower(a.user_id)
    from _list_case_ranked k
   where k.tbl = 'anime_user_lists' and k.rnk = 1 and a.id = k.id and a.user_id <> lower(a.user_id);
  update public.manga_user_lists m set user_id = lower(m.user_id)
    from _list_case_ranked k
   where k.tbl = 'manga_user_lists' and k.rnk = 1 and m.id = k.id and m.user_id <> lower(m.user_id);

  -- post-condition in the same transaction: nothing non-canonical left except barrier users
  if exists (select 1 from public.anime_user_lists a where a.user_id <> lower(a.user_id)
               and not exists (select 1 from public.account_deletion_barriers b where b.user_id::text = lower(a.user_id)))
     or exists (select 1 from public.manga_user_lists m where m.user_id <> lower(m.user_id)
               and not exists (select 1 from public.account_deletion_barriers b where b.user_id::text = lower(m.user_id))) then
    raise exception 'POSTCONDITION_FAILED: non-canonical user_id rows remain';
  end if;
  drop table _list_case_ranked;
end $$;
