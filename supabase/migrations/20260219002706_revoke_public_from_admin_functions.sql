-- Revoke public role access from admin functions 
-- (anon/authenticated inherit EXECUTE from public role)
REVOKE EXECUTE ON FUNCTION public.concierge_housekeeping() FROM public;
REVOKE EXECUTE ON FUNCTION public.check_mirror_health(integer, integer) FROM public;;
