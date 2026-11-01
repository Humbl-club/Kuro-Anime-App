-- 20261101030000_auth_hardening.sql
-- PREPARED, NOT DEPLOYED (2026-11-01 overnight production pass, lane 1 / SQL).
-- Deploying needs explicit owner approval.
--
-- Decision D13 (spec 2026-11-01): check_email_exists(text) is an account-enumeration oracle
-- (SECURITY DEFINER over auth.users, callable without signing in). The client stops the
-- live "Taken" check and reports a duplicate e-mail on submit (lane 7). This revokes EXECUTE
-- from PUBLIC, anon and authenticated; service_role keeps it (server-side use only).
--
-- ORDER: ship the iOS build that no longer calls check_email_exists
-- (Kuro/Identity/AuthService.swift) BEFORE applying this; an older build calling it after
-- the revoke gets a permission error (42501) instead of a boolean.
-- The function body is unchanged.
-- Rollback: grant execute on function public.check_email_exists(text) to anon, authenticated;

begin;

do $$
begin
  if to_regprocedure('public.check_email_exists(text)') is null then
    raise notice 'check_email_exists(text) absent here: nothing to revoke';
    return;
  end if;
  revoke all on function public.check_email_exists(text) from public, anon, authenticated;
  grant execute on function public.check_email_exists(text) to service_role;
  comment on function public.check_email_exists(text) is
    'Service role only since 20261101030000 (D13: no unauthenticated e-mail enumeration). Duplicate e-mail is reported by sign-up on submit.';
end $$;

commit;
