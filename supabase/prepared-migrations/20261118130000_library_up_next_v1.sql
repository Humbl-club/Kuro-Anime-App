-- W10 "Up next in your series": library_up_next_v1(p_medium, p_limit).
-- PREPARED, NOT DEPLOYED. Owner approval is required before this is applied.
-- Depends on 20261007040000 (series tables, live) and 20260307120000 (media_relations, live).
-- SECURITY INVOKER: every relation read is readable by `authenticated` under RLS.
create or replace function public.library_up_next_v1(p_medium text, p_limit integer default 30)
returns table(media_type text, media_id integer, title text, cover_image text, format text, status text,
              start_year integer, total_units integer, after_media_id integer, after_title text, link text)
language plpgsql stable security invoker
set search_path = public, extensions
set jit = off
as $fn$
declare
  v_limit integer;
  v_uid uuid;
begin
  if p_medium is null or p_medium not in ('anime', 'manga') then
    raise exception 'INVALID_MEDIUM: %', coalesce(p_medium, '<null>') using errcode = '22023';
  end if;
  v_limit := least(greatest(coalesce(p_limit, 30), 1), 30);
  v_uid := auth.uid();
  if v_uid is null then
    return;
  end if;
  return;
end;
$fn$;

revoke all on function public.library_up_next_v1(text, integer) from public, anon;
grant execute on function public.library_up_next_v1(text, integer) to authenticated;

comment on function public.library_up_next_v1(text, integer) is
  'W10: sequels / reviewed next sections of the caller''s COMPLETED titles that are not in the library. INVOKER; account from auth.uid().';
