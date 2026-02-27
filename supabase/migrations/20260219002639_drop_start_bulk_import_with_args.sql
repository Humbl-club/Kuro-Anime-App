-- Drop start_bulk_import with correct signature (SECURITY DEFINER, contains hardcoded JWT)
DROP FUNCTION IF EXISTS public.start_bulk_import(text, integer);;
