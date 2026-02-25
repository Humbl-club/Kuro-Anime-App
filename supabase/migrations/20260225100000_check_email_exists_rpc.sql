-- check_email_exists: lightweight email uniqueness check for inline sign-up validation.
-- Called by the iOS client with debounced input (anon role, pre-login).

CREATE OR REPLACE FUNCTION public.check_email_exists(p_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, auth
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM auth.users
    WHERE email = lower(trim(p_email))
  );
END;
$$;

-- anon needed because the check runs before the user has signed in.
GRANT EXECUTE ON FUNCTION public.check_email_exists(text) TO anon, authenticated;
