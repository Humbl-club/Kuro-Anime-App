-- Concierge modes v6: attach pinned curated rails to `premium_picks` (default fallback).
-- Rails are seeded by: 20260208091500_curated_rails_premium_picks_seed.sql

begin;
update public.concierge_config
set config = jsonb_set(
  config,
  '{modes}',
  (
    select jsonb_agg(
      case
        when m->>'id' = 'premium_picks' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','premium_picks_anime','manga','premium_picks_manga'))
        else m
      end
    )
    from jsonb_array_elements(config->'modes') as m
  ),
  true
)
where id = true;
commit;
