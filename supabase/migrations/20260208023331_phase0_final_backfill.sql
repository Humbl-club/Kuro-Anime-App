
-- ============================================================
-- Final Backfill: Fill remaining slots with unique quality titles
-- premium_picks_anime: 24 → 40 (add 16)
-- short_one_season_anime: 35 → 45 (add 10)
-- premium_picks_manga: 38 → 40 (add 2)
-- ============================================================

-- PREMIUM PICKS ANIME: Add 16 more prestige titles
-- Mix of movies, longer series, and distinctive prestige works
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
-- Movies (won't overlap with short_one_season since it's TV/ONA only)
('premium_picks_anime', 'ANIME', 19,     30, 'Monster - 74-episode psychological masterpiece, Urasawa''s magnum opus'),
('premium_picks_anime', 'ANIME', 263,    31, 'Hajime no Ippo - 75-episode boxing classic, pure heart'),
('premium_picks_anime', 'ANIME', 820,    32, 'Legend of the Galactic Heroes - 110-episode space opera, the prestige anime'),
('premium_picks_anime', 'ANIME', 100178, 33, 'Liz and the Blue Bird - Yamada''s masterful character study, standalone film'),
('premium_picks_anime', 'ANIME', 140499, 34, 'Blue Giant - jazz film that makes you feel the music'),
('premium_picks_anime', 'ANIME', 99750,  35, 'I Want to Eat Your Pancreas - devastating film about connection and mortality'),
('premium_picks_anime', 'ANIME', 12431,  36, 'Space Brothers - 99-episode astronaut dream story, deeply human'),
('premium_picks_anime', 'ANIME', 103047, 37, 'Violet Evergarden: the Movie - KyoAni''s emotional crescendo'),
('premium_picks_anime', 'ANIME', 100643, 38, 'Made in Abyss: Dawn of the Deep Soul - Bondrewd film, visceral and unforgettable'),
('premium_picks_anime', 'ANIME', 112151, 39, 'Demon Slayer: Mugen Train - box office phenomenon, peak ufotable sakuga'),
('premium_picks_anime', 'ANIME', 153288, 40, 'Kaiju No. 8 - monster-hunting action with an everyman protagonist'),
('premium_picks_anime', 'ANIME', 21860,  41, 'Grand Blue Dreaming anime - diving comedy that''s actually about drinking'),
('premium_picks_anime', 'ANIME', 99578,  42, 'Wotakoi - adult workplace otaku romance, refreshing maturity'),
('premium_picks_anime', 'ANIME', 20519,  43, 'Terror in Resonance - Watanabe''s thriller about two teen terrorists, stunning OST'),
('premium_picks_anime', 'ANIME', 104458, 44, 'Banana Fish anime - crime thriller adaptation with unforgettable impact'),
('premium_picks_anime', 'ANIME', 21647,  45, 'Tsuki ga Kirei - pure middle school romance, one perfect season')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- SHORT ONE SEASON ANIME: Add 10 more quality single-cour titles
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('short_one_season_anime', 'ANIME', 21647, 50, 'Tsuki ga Kirei - 12-episode pure romance, complete and perfect'),
('short_one_season_anime', 'ANIME', 21860, 51, 'Grand Blue Dreaming - 12-episode diving/drinking comedy'),
('short_one_season_anime', 'ANIME', 99578, 52, 'Wotakoi - 11-episode otaku workplace romance'),
('short_one_season_anime', 'ANIME', 104458, 53, 'Banana Fish - 24-episode crime thriller'),
('short_one_season_anime', 'ANIME', 20519, 54, 'Terror in Resonance - 11-episode Watanabe thriller'),
('short_one_season_anime', 'ANIME', 153288, 55, 'Kaiju No. 8 - 12-episode monster action'),
('short_one_season_anime', 'ANIME', 100178, 56, 'Liz and the Blue Bird - standalone Yamada film'),
('short_one_season_anime', 'ANIME', 140499, 57, 'Blue Giant - jazz film, complete story'),
('short_one_season_anime', 'ANIME', 99750,  58, 'I Want to Eat Your Pancreas - standalone drama film'),
('short_one_season_anime', 'ANIME', 10271,  59, 'Kaiji Against All Rules - 26-episode gambling thriller')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- PREMIUM PICKS MANGA: Add 2 more to reach 40
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('premium_picks_manga', 'MANGA', 30743, 50, 'Parasyte manga - Iwaaki''s sci-fi horror classic about symbiosis and identity'),
('premium_picks_manga', 'MANGA', 85134, 51, 'Spy x Family manga - Endo''s action-comedy about a fake family, universally loved')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- RE-RANK ALL 3 RAILS
WITH ranked AS (
  SELECT rail_id, media_type, anilist_id,
         ROW_NUMBER() OVER (PARTITION BY rail_id, media_type ORDER BY rank) AS new_rank
  FROM curated_rail_items
  WHERE (rail_id = 'premium_picks_anime' AND media_type = 'ANIME')
     OR (rail_id = 'short_one_season_anime' AND media_type = 'ANIME')
     OR (rail_id = 'premium_picks_manga' AND media_type = 'MANGA')
)
UPDATE curated_rail_items cri
SET rank = ranked.new_rank,
    updated_at = now()
FROM ranked
WHERE cri.rail_id = ranked.rail_id
  AND cri.media_type = ranked.media_type
  AND cri.anilist_id = ranked.anilist_id
  AND cri.rank IS DISTINCT FROM ranked.new_rank;
;
