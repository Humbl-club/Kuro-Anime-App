-- Regression for new private state, revoked tokens and deletion's own writes.
-- @requires function public.begin_account_deletion(uuid)
-- @requires table public.anime_user_lists
\set ON_ERROR_STOP on
BEGIN;
SELECT tests.make_user(98), tests.make_user(99);
INSERT INTO public.anime(id,title_romaji) VALUES (796001,'Lifecycle test');
INSERT INTO public.series(medium,title) VALUES ('anime','Lifecycle test') RETURNING id AS series_id \gset
SELECT tests.as_user(tests.uid(98));
INSERT INTO public.anime_user_lists(user_id,anime_id,list_type,progress)
    VALUES (tests.uid(98)::text,796001,'WATCHING',2);
INSERT INTO public.user_series_intent(user_id,series_id,saved)
    VALUES (tests.uid(98)::text,:'series_id',true);
SELECT public.start_library_import_v1('anilist','export','both','lifecycle-96','lifecycle-payload')->>'job_id' AS job_id \gset
SELECT tests.reset();
SELECT tests.eq('job start persists exactly one baseline',
    (SELECT count(*) FROM public.library_import_baselines WHERE job_id=:'job_id'::uuid),1::bigint);
SELECT tests.ok('persisted baseline captures the actual entry lifecycle and revision',
    EXISTS(SELECT 1 FROM public.library_import_baselines b JOIN public.anime_user_lists l
      ON b.media_id=l.anime_id AND b.lifecycle_id=l.lifecycle_id AND b.server_revision=l.server_revision
      WHERE b.job_id=:'job_id'::uuid AND b.medium='anime' AND l.user_id=tests.uid(98)::text));
INSERT INTO public.home_publications(user_id,medium,revision) VALUES (tests.uid(98)::text,'anime',1)
    ON CONFLICT(user_id,medium) DO NOTHING;
SELECT public.begin_account_deletion(tests.uid(98));
SELECT tests.as_user(tests.uid(98));
SELECT tests.denied('barrier denies new import job',
    $$SELECT public.start_library_import_v1('myanimelist','export','anime','new-during-delete','new-payload')$$);
SELECT tests.denied('barrier denies follow update','UPDATE public.user_series_intent SET followed=true');
SELECT tests.reset();
-- The internal tombstone from deletion must not be rejected by the barrier.
DELETE FROM public.anime_user_lists WHERE user_id=tests.uid(98)::text;
SELECT tests.eq('tracked deletion succeeds after barrier',
    (SELECT count(*) FROM public.anime_user_lists WHERE user_id=tests.uid(98)::text),0::bigint);
SELECT tests.ok('internal tombstone remains until auth cascade',
    EXISTS(SELECT 1 FROM public.list_entry_tombstones WHERE user_id=tests.uid(98)::text));
DELETE FROM auth.users WHERE id=tests.uid(98);
SELECT tests.eq('job cascade purges baselines',
    (SELECT count(*) FROM public.library_import_baselines WHERE job_id=:'job_id'::uuid),0::bigint);
SELECT tests.eq('job cascade purges import action',
    (SELECT count(*) FROM public.library_import_jobs WHERE id=:'job_id'::uuid),0::bigint);
SELECT tests.eq('follow state purged',
    (SELECT count(*) FROM public.user_series_intent WHERE user_id=tests.uid(98)::text),0::bigint);
SELECT tests.eq('home publication purged',
    (SELECT count(*) FROM public.home_publications WHERE user_id=tests.uid(98)::text),0::bigint);
SELECT tests.eq('tombstone purged',
    (SELECT count(*) FROM public.list_entry_tombstones WHERE user_id=tests.uid(98)::text),0::bigint);
SELECT tests.as_user(tests.uid(98));
SELECT tests.denied('old JWT cannot create job after deletion',
    $$SELECT public.start_library_import_v1('anilist','export','both','after-deletion','after-payload')$$);
SELECT tests.denied('old JWT cannot recreate follow',format(
    'INSERT INTO public.user_series_intent(user_id,series_id,saved) VALUES (%L,%L,true)',tests.uid(98)::text,:'series_id'));
SELECT tests.reset();
SELECT tests.ok('other account retained',EXISTS(SELECT 1 FROM auth.users WHERE id=tests.uid(99)));
ROLLBACK;
