CREATE OR REPLACE FUNCTION public.begin_account_deletion(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_started timestamptz;
begin
  if p_user_id is null then
    raise exception 'INVALID_USER_ID' using errcode = '22023';
  end if;
  -- waits for every in-flight guarded write of this user (they hold the shared lock)
  perform pg_advisory_xact_lock(public._account_deletion_lock_key(p_user_id::text));
  insert into public.account_deletion_barriers (user_id) values (p_user_id)
    on conflict (user_id) do nothing;
  select started_at into v_started from public.account_deletion_barriers where user_id = p_user_id;

  -- bounded retention of finished deletions (no cron needed)
  delete from public.account_deletion_barriers b
   where b.started_at < now() - interval '7 days'
     and b.user_id <> p_user_id
     and not exists (select 1 from auth.users u where u.id = b.user_id);

  return jsonb_build_object('success', true, 'started_at', v_started);
end;
$function$

