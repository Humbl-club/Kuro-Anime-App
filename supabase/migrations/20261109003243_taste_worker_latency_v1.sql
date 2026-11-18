-- PREPARED: measured 100-user soak failed during the 31-second taste drain.
-- Keep personalization math and worker signature; bound each transaction and
-- process small FIFO batches more often (nominal 300 vs 200 users/hour).
begin;
set local lock_timeout='3s';
set local statement_timeout='30s';
set local search_path=public,extensions;
alter function public.recompute_user_taste_profile(uuid) set jit to 'off';
CREATE OR REPLACE FUNCTION public.drain_taste_recompute_queue()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
AS $function$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select q.user_id
    from public.taste_profile_recompute_queue q
    where q.processed_at is null
    order by q.requested_at asc
    limit 5
    for update of q skip locked
  loop
    begin
      perform public.recompute_user_taste_profile(v_user_id);
      update public.taste_profile_recompute_queue
      set processed_at = now(),
          last_error = null
      where user_id = v_user_id;
    exception when others then
      -- Poison rows must not block the batch: stamp processed_at, log the error.
      update public.taste_profile_recompute_queue
      set processed_at = now(),
          last_error = jsonb_build_object(
            'error', SQLERRM,
            'sqlstate', SQLSTATE,
            'at', now()
          )
      where user_id = v_user_id;
      raise warning 'recompute_user_taste_profile failed for %: %', v_user_id, SQLERRM;
    end;
  end loop;
end;
$function$;

-- Restate the already-live server-only grant contract (also closes fixture default grants).
revoke all on function public.recompute_user_taste_profile(uuid) from public,anon,authenticated;
grant execute on function public.recompute_user_taste_profile(uuid) to service_role;
revoke all on function public.drain_taste_recompute_queue() from public,anon,authenticated;
grant execute on function public.drain_taste_recompute_queue() to service_role;

-- Preserve existing job identity. No HTTP credential or unrelated job changes.
do $schedule$
declare j record;
begin
 select jobid,schedule,command into j from cron.job where jobname='taste-profile-drain-15m';
 if not found then
  if exists(select 1 from cron.job) then raise exception 'Taste worker job missing';end if;
  raise notice 'Empty local cron fixture: hosted schedule not exercised';
  return;
 end if;
 if j.schedule not in ('*/15 * * * *','* * * * *') or btrim(j.command)<>'select public.drain_taste_recompute_queue();' then
  raise exception 'Unexpected taste worker configuration';
 end if;
 perform cron.alter_job(j.jobid,schedule:='* * * * *');
end $schedule$;
commit;
