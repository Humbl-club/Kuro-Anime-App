-- Reduce hard overlap between school_manga and shoujo_josei_manga
-- to satisfy curated rail overlap hard gate.

begin;

-- Remove titles that are strongly shoujo/josei-coded from school_manga.
delete from public.curated_rail_items
where rail_id = 'school_manga'
  and media_type = 'MANGA'
  and anilist_id in (
    277,  -- Skip and Loafer
    152,  -- Blue Box
    240,  -- Fruits Basket
    292,  -- Ouran High School Host Club
    226   -- Kimi ni Todoke
  );

-- Keep school_manga ordering stable after removals.
with ranked as (
  select
    id,
    row_number() over (order by sort_order, id) as new_sort_order
  from public.curated_rail_items
  where rail_id = 'school_manga'
    and media_type = 'MANGA'
)
update public.curated_rail_items cri
set sort_order = ranked.new_sort_order
from ranked
where cri.id = ranked.id
  and cri.sort_order is distinct from ranked.new_sort_order;

commit;
