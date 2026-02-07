-- Concierge modes v4: attach pinned curated rails to additional vibe modes.
-- This keeps the router the same, but upgrades output quality for the most common vibes by
-- serving from curated_rail_cards() when rail_id is present (with algorithmic fallback if empty).

begin;

update public.concierge_config
set config = jsonb_set(
  config,
  '{modes}',
  (
    select jsonb_agg(
      case
        when m->>'id' = 'premium_action' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','premium_action_anime','manga','premium_action_manga'))
        when m->>'id' = 'premium_comedy_grownup' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','premium_comedy_grownup_anime','manga','premium_comedy_grownup_manga'))
        when m->>'id' = 'cozy_comfort' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','cozy_comfort_anime','manga','cozy_comfort_manga'))
        when m->>'id' = 'dark_serious' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','dark_serious_anime','manga','dark_serious_manga'))
        when m->>'id' = 'hidden_gems' then
          m || jsonb_build_object('rail_id', jsonb_build_object('anime','hidden_gems_anime','manga','hidden_gems_manga'))
        else m
      end
    )
    from jsonb_array_elements(config->'modes') as m
  ),
  true
)
where id = true;

commit;

