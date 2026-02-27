-- Allow title_fuzzy mapping method for additive fuzzy disambiguation.
-- This is backward-safe: keeps prior methods and review_approved.

begin;

do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'manga_source_links'
  ) then
    alter table public.manga_source_links
      drop constraint if exists manga_source_links_mapping_method_check;

    alter table public.manga_source_links
      add constraint manga_source_links_mapping_method_check
      check (mapping_method in ('al_link', 'mal_link', 'title_strict', 'review_approved', 'title_fuzzy'));
  end if;
end $$;

commit;
