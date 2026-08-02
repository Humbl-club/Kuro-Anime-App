-- Re-enable a gentle realm-describe catch-up cron (batch 4 / every 3 minutes).
-- Safe alongside a paused/manual worker: pg_net + Groq 429 retries absorb overlap.
-- Unschedule when media_realm_llm_pending stays near zero.

begin;

do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'realm-describe-drain-2m';
exception when others then null;
end $$;

do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'realm-describe-drain-3m';
exception when others then null;
end $$;

select cron.schedule(
  'realm-describe-drain-3m',
  '*/3 * * * *',
  $job$
    select public.enqueue_realm_describe_batch(4);
  $job$
);

commit;
