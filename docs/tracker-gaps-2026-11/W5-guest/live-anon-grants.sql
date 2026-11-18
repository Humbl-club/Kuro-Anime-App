-- W5 guest browsing: READ-ONLY live audit of what the anonymous API role can do.
-- Run only with explicit owner approval, read-only (for example the Supabase SQL editor or a read-only
-- connection). Nothing here writes. Save the outputs as anon-grants-before.tsv (before applying
-- 20261118110000_guest_anon_allowlist_v1.sql) and anon-grants-after.tsv (after).
--
-- ORDER RULE: re-run query 1 after EVERY later migration that adds or replaces a public function. The global
-- PUBLIC default is not revoked, so a later function that forgets `revoke all ... from public` is anon-executable.
--
-- 1. Every non-extension function in public that anon can EXECUTE.
--    Before the migration: many rows (every function that kept Supabase's default grant or a PUBLIC grant).
--    After the migration: EXACTLY the 22 allowlist rows below when W4's 20261118100000 is also applied,
--    20 while it is not (search_anime_page_v2 / search_manga_page_v2 absent). Re-run after W4 is applied.
select p.oid::regprocedure::text as fn
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  and has_function_privilege('anon', p.oid, 'EXECUTE')
order by 1;

-- The 22 expected rows after the migration (compare the output of query 1 against this list):
--   anime_cast_v1(integer,text,integer)
--   browse_anime_page(text,text,integer,integer,text,integer,timestamp with time zone,integer,integer,integer,integer,text)
--   browse_manga_page(text,text,integer,integer,text,integer,timestamp with time zone,integer,integer,integer,integer,text)
--   character_voice_actors_v1(integer,text)
--   check_concierge_rate_limit(text,text,integer,integer,integer)
--   discover_bundle(integer,integer)
--   discover_mood_v1(text,text,integer,integer)
--   discover_section_page_v1(text,text,text,text,text,text,integer,integer)
--   get_manga_chapter_status(integer)
--   get_media_ladder(text,integer)
--   media_franchise_ids_v1(integer[],integer[])
--   media_release_schedule_v1(text,integer,integer)
--   media_similar_v1(text,integer,integer)
--   media_themes_v1(integer)
--   normalize_title(text)
--   recommend_ids_similar_to_seeds(text,integer[],integer,boolean)
--   search_anime_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer)
--   search_anime_page_v2(...same arguments...)      -- W4
--   search_manga_page(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean)
--   search_manga_page_v2(...same arguments...)      -- W4
--   search_titles(text,text,integer)
--   staff_voice_roles_v1(integer,integer)

-- 2. No PUBLIC EXECUTE grant on a non-extension public function (expected after: zero rows).
select p.oid::regprocedure::text as fn
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where a.grantee = 0 and a.privilege_type = 'EXECUTE')
order by 1;

-- 3. Default privileges: no per-schema default for the migration owner (postgres) grants anon EXECUTE on new
--    functions in public (expected after: zero rows). supabase_admin is reported separately in 3b.
select d.defaclrole::regrole as owner_role, d.defaclobjtype, d.defaclacl
from pg_default_acl d
join pg_namespace n on n.oid = d.defaclnamespace
where n.nspname = 'public'
  and d.defaclobjtype = 'f'
  and d.defaclrole::regrole::text <> 'supabase_admin'
  and exists (select 1 from aclexplode(d.defaclacl) a where a.grantee = 'anon'::regrole and a.privilege_type = 'EXECUTE');

-- 3b. The supabase_admin default row (objects created by the dashboard/supabase_admin; live Q5 showed it grants anon).
--     Expected after: zero rows when the migration role could alter it, otherwise ONE row (owner_role = supabase_admin)
--     and the migration logged a NOTICE. Harmless for migration-created functions, which postgres owns (live Q1).
select d.defaclrole::regrole as owner_role, d.defaclobjtype, d.defaclacl
from pg_default_acl d
join pg_namespace n on n.oid = d.defaclnamespace
where n.nspname = 'public'
  and d.defaclobjtype = 'f'
  and d.defaclrole::regrole::text = 'supabase_admin'
  and exists (select 1 from aclexplode(d.defaclacl) a where a.grantee = 'anon'::regrole and a.privilege_type = 'EXECUTE');

-- 4. Anonymous catalogue table reads existed before W5 and are unchanged by it (expected: true both before
--    and after for the catalogue tables; the user lists are recorded as found, and the rows anon can see
--    through RLS must be 0, see check 5).
select t as relation, has_table_privilege('anon', 'public.' || t, 'select') as anon_can_select
from unnest(array['anime', 'manga', 'episodes', 'chapters', 'anime_characters', 'anime_staff', 'anime_studios',
  'manga_characters', 'manga_authors', 'manga_staff', 'external_links', 'characters', 'staff', 'studios', 'authors',
  'anime_tags', 'manga_tags', 'tags', 'character_voice_actors', 'theme_links', 'feature_flags', 'mv_anime_trending',
  'anime_user_lists', 'manga_user_lists']) as t
where to_regclass('public.' || t) is not null
order by 1;

-- 5. The release switch exists and is off (expected after: one row, enabled=false, rollout_percentage=0).
select flag_name, enabled, rollout_percentage from public.feature_flags where flag_name = 'guest_browsing_v1';
