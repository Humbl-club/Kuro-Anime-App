-- Pause realm-describe cron while the Mac worker drains under Groq TPM limits.
begin;
do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname in ('realm-describe-drain-3m', 'realm-describe-drain-2m');
exception when others then null;
end $$;
commit;
