-- Follow-up 2 to 20260804130000 (realm repair Fix 5): driver batch 200 -> 100.
--
-- Evidence (2026-08-04, cron.job_run_details): every 'realm-similar-drive-5m'
-- run from 22:05 UTC onward FAILED at exactly 600s ("canceling statement due
-- to statement timeout", CONTEXT: create temp table _scored_m / _shared_m) —
-- a 200-seed MANGA batch no longer fits the 600s ceiling once the Micro
-- instance's disk-IO burst budget is drained (baseline 87 MB/s, 1GB RAM, the
-- pair tables spill to disk at default work_mem). Each failed run burned the
-- full 600s and rolled back, freezing convergence at ~2,213 built manga seeds.
--
-- p_batch 100 fits BOTH IO regimes with margin:
--   healthy burst IO (measured): 100 manga ~100s, 100 anime ~40s
--   drained baseline IO (measured 2026-08-04 22:xx): ~2.9s/manga seed -> ~300-380s
-- The 600s SET stays: it is sized for the statement, not the batch. Nightly
-- full re-stale now takes ~76 fires (~6.3h at the 5-min cadence, mostly much
-- faster once IO burst refills); the store keeps serving the previous rows
-- for not-yet-rebuilt seeds, so the longer tail is invisible to users.
-- Owner note: on this Micro instance, consider spacing the nightly re-stale
-- (e.g. weekly) or upgrading compute if the nightly IO churn matters.

begin;

select cron.unschedule(jobid)
from cron.job
where jobname = 'realm-similar-drive-5m';

select cron.schedule(
  'realm-similar-drive-5m',
  '*/5 * * * *',
  $cmd$set statement_timeout = '600s'; select public.rebuild_media_similar_titles(100);$cmd$
);

commit;
