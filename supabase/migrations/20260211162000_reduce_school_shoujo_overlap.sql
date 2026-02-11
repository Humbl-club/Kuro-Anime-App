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
    rail_id,
    media_type,
    anilist_id,
    row_number() over (order by rank, anilist_id) as new_rank
  from public.curated_rail_items
  where rail_id = 'school_manga'
    and media_type = 'MANGA'
)
update public.curated_rail_items cri
set rank = ranked.new_rank
from ranked
where cri.rail_id = ranked.rail_id
  and cri.media_type = ranked.media_type
  and cri.anilist_id = ranked.anilist_id
  and cri.rank is distinct from ranked.new_rank;

commit;
