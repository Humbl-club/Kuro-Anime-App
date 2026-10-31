-- Disposable audited fixture only. Not a live schema clone or hosted proof.
\set ON_ERROR_STOP on
\ir /Users/max/Kuro-Anime-App/supabase/tests/lib/00_test_helpers.sql
CREATE SCHEMA supabase_migrations;
CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY, statements text[], name text, created_by text, idempotency_key text UNIQUE, rollback text[]);
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES ('fixture-prior','retained-history',ARRAY['SELECT 123;']);
SELECT tests.make_user(980);
INSERT INTO public.anime(id,title_romaji) VALUES(795998,'Atomic rehearsal anime');
INSERT INTO public.manga(id,title_romaji) VALUES(795998,'Atomic rehearsal manga');
INSERT INTO public.anime_user_lists(user_id,anime_id,list_type,progress,rating,notes) VALUES(tests.uid(980)::text,795998,'WATCHING',4,8,'preserve anime note');
INSERT INTO public.manga_user_lists(user_id,manga_id,list_type,progress,rating,notes) VALUES(tests.uid(980)::text,795998,'READING',7,9,'preserve manga note');
\ir /Users/max/Kuro-Anime-App/docs/handoffs/2026-10-07-integrated-release-evidence/simulator-home-import-atomic-DRAFT.sql
SELECT tests.ok('Existing migration history remains byte-identical',EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='fixture-prior' AND name='retained-history' AND statements=ARRAY['SELECT 123;']));
SELECT tests.eq('Exactly two new migration histories', (SELECT count(*) FROM supabase_migrations.schema_migrations),3::bigint);
SELECT tests.eq('Exact original history source 20261007040000',(SELECT md5(statements[1]) FROM supabase_migrations.schema_migrations WHERE version='20261007040000'),'991dc2bcc625cea4210392cf59c561ae');
SELECT tests.eq('Exact original history source 20261007130000',(SELECT md5(statements[1]) FROM supabase_migrations.schema_migrations WHERE version='20261007130000'),'7366bfc0f783361ae87fe7921547355a');
SELECT tests.eq('Preexisting anime progress preserved',(SELECT progress FROM public.anime_user_lists WHERE anime_id=795998),4);
SELECT tests.eq('Preexisting manga progress preserved',(SELECT progress FROM public.manga_user_lists WHERE manga_id=795998),7);
SELECT tests.eq('Preexisting anime private note preserved',(SELECT notes FROM public.anime_user_lists WHERE anime_id=795998),'preserve anime note');
SELECT tests.eq('Preexisting manga private note preserved',(SELECT notes FROM public.manga_user_lists WHERE manga_id=795998),'preserve manga note');
\ir /Users/max/Kuro-Anime-App/supabase/tests/rls/81_library_import_counts.sql
\ir /Users/max/Kuro-Anime-App/supabase/tests/rls/96_series_account_lifecycle.sql
