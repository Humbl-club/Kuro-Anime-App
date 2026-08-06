begin;
do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'realm-describe-drain-2m';
exception when others then null;
end $$;
commit;
