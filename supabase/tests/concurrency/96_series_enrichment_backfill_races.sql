-- Backfill versus catalogue source changes, in both blocking orders.
-- Disposable, separate real PostgreSQL actors; NOT RUN until the local fixture
-- can start. Do not remove shared-memory resources to run this test.
-- @requires extension dblink
-- @requires table public.anime
-- The enrichment objects are the subject, not prerequisite-BLOCK conditions.
\set ON_ERROR_STOP on
\o /dev/null

select coalesce(max(id),0)+1 as media_id from public.anime \gset
select :media_id-1 as after_id \gset
insert into public.anime(id,title_romaji,description)
values(:media_id,'Backfill race fixture','Source A.');
select tests.actor_open('backfill', :'conn') as backfill_pid \gset
select tests.actor_open('source', :'conn') as source_pid \gset

-- Backfill owns source+job first. A non-key source update must not be
-- admitted until backfill releases its source lock (KEY SHARE is insufficient).
select tests.eq('backfill starts',tests.actor_exec('backfill','begin'),'BEGIN');
select tests.actor_exec('backfill',format(
 'select public.backfill_series_enrichment_v1(%L,%s,1)', 'anime', :after_id)) as first_page \gset
select tests.eq('one bounded source row queued',(:'first_page'::jsonb->>'processed')::int,1);
select tests.ok('backfill locks source against non-key update',
 tests.actor_exec('source',format('select id from public.anime where id=%s for no key update nowait',:media_id))
 like '%could not obtain lock%');
select tests.eq('source starts',tests.actor_exec('source','begin'),'BEGIN');
select tests.actor_send('source',format('update public.anime set description=%L where id=%s','Source B.',:media_id));
select tests.wait_lock_wait(:source_pid) as source_wait \gset
select tests.ok('source update waits',:'source_wait' like '%transactionid%' or :'source_wait' like '%tuple%');
select tests.eq('backfill releases its locks',tests.actor_exec('backfill','commit'),'COMMIT');
select tests.eq('source update completes',tests.actor_result('source'),'UPDATE 1');
select tests.eq('new source commits',tests.actor_exec('source','commit'),'COMMIT');
select tests.eq('new source replaces old backfill payload',
 (select payload->>'description' from public.series_enrichment_jobs where medium='anime' and media_id=:media_id),'Source B.');

-- Source owns its row+new queued revision first. Backfill must wait and reread
-- C after commit, rather than retaining B and replacing C's job with stale B.
select tests.eq('source begins next revision',tests.actor_exec('source','begin'),'BEGIN');
select tests.eq('source writes next revision',tests.actor_exec('source',format(
 'update public.anime set description=%L where id=%s','Source C.',:media_id)),'UPDATE 1');
select tests.eq('backfill begins behind source',tests.actor_exec('backfill','begin'),'BEGIN');
select tests.actor_send('backfill',format(
 'select public.backfill_series_enrichment_v1(%L,%s,1)','anime',:after_id));
select tests.wait_lock_wait(:backfill_pid) as backfill_wait \gset
select tests.ok('backfill waits for newer source',:'backfill_wait' like '%transactionid%' or :'backfill_wait' like '%tuple%');
select tests.eq('source releases next revision',tests.actor_exec('source','commit'),'COMMIT');
select tests.actor_result('backfill') as second_page \gset
select tests.eq('waited backfill still processes one row',(:'second_page'::jsonb->>'processed')::int,1);
select tests.eq('waited backfill commits',tests.actor_exec('backfill','commit'),'COMMIT');
select tests.eq('waited backfill retains latest payload',
 (select payload->>'description' from public.series_enrichment_jobs where medium='anime' and media_id=:media_id),'Source C.');
select tests.eq('queued snapshot matches catalogue source',
 (select j.payload->>'description'=a.description from public.series_enrichment_jobs j
  join public.anime a on a.id=j.media_id where j.medium='anime' and j.media_id=:media_id),true);
select tests.actor_close('backfill');
select tests.actor_close('source');
