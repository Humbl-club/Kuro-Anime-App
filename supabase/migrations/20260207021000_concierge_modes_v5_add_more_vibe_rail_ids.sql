-- Concierge modes v5: attach pinned curated rails to additional modes.
-- New rails are seeded by: 20260207020000_curated_rails_more_vibes_seed.sql

begin;
update public.concierge_config
set config = jsonb_set(
  config,
  '{modes}',
  (
    select jsonb_agg(
      case
        when m->>'id' = 'romcom' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','romcom_anime','manga','romcom_manga'))
        when m->>'id' = 'romance_serious' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','romance_serious_anime','manga','romance_serious_manga'))
        when m->>'id' = 'short_one_season' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','short_one_season_anime','manga','short_one_season_manga'))
        when m->>'id' = 'movie_night' then
          -- Anime-only rail; manga falls back to algorithmic.
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','movie_night_anime'))
        when m->>'id' = 'isekai' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','isekai_anime','manga','isekai_manga'))
        when m->>'id' = 'fantasy_non_isekai' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','fantasy_non_isekai_anime','manga','fantasy_non_isekai_manga'))
        else m
      end
    )
    from jsonb_array_elements(config->'modes') as m
  ),
  true
)
where id = true;
commit;
