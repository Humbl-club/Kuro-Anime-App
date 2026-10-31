CREATE OR REPLACE FUNCTION public._account_write_guard(p_user text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_text text := lower(btrim(p_user));
begin
  if v_text is null
     or v_text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return;
  end if;
  perform pg_advisory_xact_lock_shared(public._account_deletion_lock_key(v_text));
  -- new statement => new snapshot (READ COMMITTED): sees a barrier committed while waiting
  if exists (select 1 from public.account_deletion_barriers where user_id = v_text::uuid) then
    raise exception 'ACCOUNT_DELETION_IN_PROGRESS'
      using errcode = '42501',
            hint = 'ACCOUNT_DELETION_IN_PROGRESS',
            detail = 'this account is being deleted; no new data is accepted for it';
  end if;
end;
$function$

