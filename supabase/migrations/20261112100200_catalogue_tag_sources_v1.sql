-- Prepared 2026-11-18 (docs/superpowers/plans/2026-11-09-catalogue-sources.md Task 11). NOT applied.
--
-- Kuro tag assignments from allowed sources. Adds:
--   catalogue_tag_source_map(source, source_label, tag_id, weight): service-only (RLS on, no client
--     policy, no anon/authenticated grant). Sources are limited to ann, mangaupdates and wikidata:
--     AniDB is excluded (gate Q6, docs/catalogue-sources-2026-11/sources/anidb.md).
--   tags.description_kuro / tags.retired_at: Kuro's own tag text (AniList text stays in `description`
--     until Task 17) and a retirement marker. Both nullable; existing readers are unchanged, and
--     anime_tags, manga_tags and media_tag_vectors are not touched.
--   catalogue_tag_map_v1(): service-only reader of the map that never returns a retired tag.
--
-- Not in this file: the 430 `description_kuro` texts (plan Task 11 Step 4). They need the live tag list and
-- the owner's review, so they ship as a later data file. The map is loaded from tag-map.csv rows marked
-- reviewed=yes only; nothing is inserted here.
begin;
set local search_path = public, extensions;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

alter table public.tags add column if not exists description_kuro text;
alter table public.tags add column if not exists retired_at timestamptz;

create table if not exists public.catalogue_tag_source_map (
  source       text not null constraint catalogue_tag_source_map_source_check check (source in ('ann', 'mangaupdates', 'wikidata')),
  source_label text not null,
  tag_id       integer not null references public.tags (id) on delete cascade,
  weight       numeric not null default 1 constraint catalogue_tag_source_map_weight_check check (weight > 0),
  constraint catalogue_tag_source_map_pkey primary key (source, source_label)
);

-- Deleting a tag removes its map rows. The tag id lookup of a retired-tag check scans by tag.
create index if not exists catalogue_tag_source_map_tag_idx on public.catalogue_tag_source_map (tag_id);

alter table public.catalogue_tag_source_map enable row level security;
-- No policies on purpose: anon/authenticated get nothing even if a grant reappears.
revoke all on table public.catalogue_tag_source_map from public, anon, authenticated;
grant select, insert, update, delete on table public.catalogue_tag_source_map to service_role;

-- SECURITY INVOKER: the only caller is the service-role composer, which already holds the table grants.
create or replace function public.catalogue_tag_map_v1()
returns table (source text, source_label text, tag_id integer, weight numeric)
language plpgsql
stable
set search_path = public, extensions
as $$
begin
  return query
    select m.source, m.source_label, m.tag_id, m.weight
    from public.catalogue_tag_source_map m
    join public.tags t on t.id = m.tag_id
    where t.retired_at is null;
end $$;

revoke all on function public.catalogue_tag_map_v1() from public, anon, authenticated;
grant execute on function public.catalogue_tag_map_v1() to service_role;

notify pgrst, 'reload schema';
commit;
