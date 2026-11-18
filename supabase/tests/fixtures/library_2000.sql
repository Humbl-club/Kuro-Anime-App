-- Shared 2,000-title library fixture for SQL plan checks (tracker-gaps F3.2).
-- Include inside a test's own transaction:  \ir ../fixtures/library_2000.sql
-- Disposable local fixture only. Needs the `tests` helper schema (tests.make_user / tests.uid).
-- Both helpers are plpgsql and live in pg_temp, so they vanish with the session.

-- pg_temp.load_library_2000(p_user, p_noise_users, p_noise_rows) -> p_user's row count
--   * catalogue rows 9100001..9101400 (anime) and 9100001..9100600 (manga) if missing
--   * 2,000 list rows for p_user::text: 1,400 anime + 600 manga, statuses spread
--     40/30/20/5/5 % WATCHING|READING / PLANNING / COMPLETED / PAUSED / DROPPED
--   * p_noise_rows rows for each of p_noise_users users tests.make_user(1000..): many small
--     libraries, so the user holds ~2 % of ~102,000 rows (production-like selectivity)
--   * list triggers are skipped with session_replication_role=replica, then the four tables are
--     analyzed, so the planner sees real statistics (never enable_seqscan=off)
create or replace function pg_temp.load_library_2000(
  p_user uuid,
  p_noise_users integer default 400,
  p_noise_rows integer default 250
) returns integer
language plpgsql
as $fn$
declare
  v_noise_anime integer := ceil(p_noise_rows * 0.6);
  v_noise_manga integer := p_noise_rows - ceil(p_noise_rows * 0.6);
  v_count integer;
  v_u integer;
begin
  perform set_config('session_replication_role', 'replica', true);

  insert into public.anime (id, title_romaji)
  select 9100000 + n, 'Fixture anime ' || n
  from generate_series(1, 1400) n
  where not exists (select 1 from public.anime a where a.id = 9100000 + n);
  insert into public.manga (id, title_romaji)
  select 9100000 + n, 'Fixture manga ' || n
  from generate_series(1, 600) n
  where not exists (select 1 from public.manga m where m.id = 9100000 + n);

  insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
  select p_user::text, 9100000 + n,
    case when n % 20 < 8 then 'WATCHING' when n % 20 < 14 then 'PLANNING'
         when n % 20 < 18 then 'COMPLETED' when n % 20 < 19 then 'PAUSED' else 'DROPPED' end,
    n % 12
  from generate_series(1, 1400) n;
  insert into public.manga_user_lists (user_id, manga_id, list_type, progress)
  select p_user::text, 9100000 + n,
    case when n % 20 < 8 then 'READING' when n % 20 < 14 then 'PLANNING'
         when n % 20 < 18 then 'COMPLETED' when n % 20 < 19 then 'PAUSED' else 'DROPPED' end,
    n % 40
  from generate_series(1, 600) n;

  for v_u in 1..p_noise_users loop
    perform tests.make_user(1000 + v_u);
  end loop;
  insert into public.anime_user_lists (user_id, anime_id, list_type, progress)
  select tests.uid(1000 + u)::text, 9100000 + a, 'PLANNING', 0
  from generate_series(1, p_noise_users) u, generate_series(1, v_noise_anime) a;
  insert into public.manga_user_lists (user_id, manga_id, list_type, progress)
  select tests.uid(1000 + u)::text, 9100000 + a, 'PLANNING', 0
  from generate_series(1, p_noise_users) u, generate_series(1, v_noise_manga) a;

  perform set_config('session_replication_role', 'origin', true);
  analyze public.anime;
  analyze public.manga;
  analyze public.anime_user_lists;
  analyze public.manga_user_lists;

  select (select count(*) from public.anime_user_lists where user_id = p_user::text)
       + (select count(*) from public.manga_user_lists where user_id = p_user::text)
    into v_count;
  return v_count;
end
$fn$;

-- pg_temp.plan_uses_index(p_query, p_index): EXPLAIN (FORMAT JSON) p_query; true when any plan
-- node is an Index Scan / Index Only Scan / Bitmap Index Scan on index p_index. The plan is
-- raised as a NOTICE for the evidence log.
create or replace function pg_temp.plan_uses_index(p_query text, p_index text)
returns boolean
language plpgsql
as $fn$
declare
  v_plan jsonb;
begin
  execute 'explain (format json) ' || p_query into v_plan;
  raise notice 'PLAN %', v_plan::text;
  return jsonb_path_exists(
    v_plan,
    '$.** ? (@."Index Name" == $idx && (@."Node Type" == "Index Scan" || @."Node Type" == "Index Only Scan" || @."Node Type" == "Bitmap Index Scan"))',
    jsonb_build_object('idx', p_index)
  );
end
$fn$;
