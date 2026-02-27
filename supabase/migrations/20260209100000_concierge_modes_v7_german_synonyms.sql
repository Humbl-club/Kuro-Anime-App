-- Concierge modes v7: add German synonyms to all existing modes.
-- Preserves all existing fields; only appends new synonym entries.

begin;
update public.concierge_config
set config = jsonb_set(
  config,
  '{modes}',
  (
    select jsonb_agg(
      case
        when m->>'id' = 'premium_picks' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["empfehlung","was empfiehlst du","was ist gut"]'::jsonb)

        when m->>'id' = 'dark_serious' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["duesteres","ernstes","schwere kost","nichts fuer kinder"]'::jsonb)

        when m->>'id' = 'premium_comedy_grownup' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["lustiges","witziges","zum totlachen","comedy fuer erwachsene"]'::jsonb)

        when m->>'id' = 'cozy_comfort' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["gemuetliches","entspannendes","zum abschalten","feelgood"]'::jsonb)

        when m->>'id' = 'hidden_gems' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["geheimtipps","kennt niemand","unterschaetztes"]'::jsonb)

        when m->>'id' = 'classics_expanded' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["die besten aller zeiten","muss man gesehen haben","legendaeres"]'::jsonb)

        when m->>'id' = 'romance_serious' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["liebesgeschichten","romantisches","herzzerreissend"]'::jsonb)

        when m->>'id' = 'romcom' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["lustige romanze","romantische komoedie","suesses"]'::jsonb)

        when m->>'id' = 'fantasy_non_isekai' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["fantasy ohne isekai","klassische fantasy","magisches"]'::jsonb)

        when m->>'id' = 'isekai' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["in eine andere welt","wiedergeburt","portal fantasy"]'::jsonb)

        when m->>'id' = 'sports' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["sportanime","sportmanga","fussball","basketball"]'::jsonb)

        when m->>'id' = 'scifi' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["science fiction","weltraum","zukunft"]'::jsonb)

        when m->>'id' = 'horror_supernatural' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["gruseliges","uebernatuerliches","horror anime"]'::jsonb)

        when m->>'id' = 'gateway_start_here' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["womit anfangen","fuer einsteiger","was zuerst schauen"]'::jsonb)

        when m->>'id' = 'premium_action' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["action anime","beste action","kampfszenen"]'::jsonb)

        when m->>'id' = 'short_one_season' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["kurze serie","eine staffel","schnell durchschauen"]'::jsonb)

        when m->>'id' = 'movie_night' then
          jsonb_set(m, '{synonyms}', (m->'synonyms') || '["filmabend","anime film","kinofilm"]'::jsonb)

        else m
      end
    )
    from jsonb_array_elements(config->'modes') as m
  ),
  true
)
where id = true;
commit;
