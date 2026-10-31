CREATE OR REPLACE FUNCTION public.shares_club_with(p_other_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM club_members cm1
    JOIN club_members cm2 ON cm1.club_id = cm2.club_id
    JOIN clubs c ON c.id = cm1.club_id
    WHERE cm1.user_id = (SELECT auth.uid())
      AND cm2.user_id = p_other_user_id
      AND NOT c.is_archived
      AND cm1.user_id != cm2.user_id
  );
$function$

