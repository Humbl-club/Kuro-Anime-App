
-- Migration: Add Sports vibe mode with curated rails
-- Sports anime and manga: hand-picked best titles, one entry per franchise, score >= 72

-- 1. Create the rails
INSERT INTO curated_rails (id, title, media_type, description) VALUES
  ('sports_anime', 'Sports', 'ANIME', 'The best sports anime — competitive spirit, training arcs, and unforgettable rivalries'),
  ('sports_manga', 'Sports', 'MANGA', 'The best sports manga — where athletic drama meets masterful storytelling')
ON CONFLICT (id) DO NOTHING;

-- 2. Seed sports_anime rail (45 items, one per franchise, score >= 72)
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank) VALUES
  -- Tier 1: Masterpieces (score 83+)
  ('sports_anime', 'ANIME', 20464, 1),   -- Haikyuu!! (83, 536K pop)
  ('sports_anime', 'ANIME', 20607, 2),   -- Ping Pong the Animation (85, 116K)
  ('sports_anime', 'ANIME', 263, 3),      -- Hajime no Ippo (87, 127K)
  ('sports_anime', 'ANIME', 170, 4),      -- Slam Dunk (83, 67K)
  ('sports_anime', 'ANIME', 101903, 5),   -- Run with the Wind (83, 91K)
  ('sports_anime', 'ANIME', 128207, 6),   -- THE FIRST SLAM DUNK movie (87, 28K)
  ('sports_anime', 'ANIME', 10800, 7),    -- Chihayafuru (80, 115K)
  ('sports_anime', 'ANIME', 2921, 8),     -- Ashita no Joe 2 (88, 19K)
  ('sports_anime', 'ANIME', 100922, 9),   -- Grand Blue Dreaming (82, 209K)
  ('sports_anime', 'ANIME', 177687, 10),  -- 100 METERS / Hyakuemu (84, 25K)
  -- Tier 2: Excellent (score 79-82)
  ('sports_anime', 'ANIME', 137822, 11),  -- Blue Lock (80, 268K)
  ('sports_anime', 'ANIME', 134732, 12),  -- Aoashi (81, 79K)
  ('sports_anime', 'ANIME', 113359, 13),  -- Megalobox 2: NOMAD (81, 55K)
  ('sports_anime', 'ANIME', 185, 14),     -- Initial D 1st Stage (82, 105K)
  ('sports_anime', 'ANIME', 5040, 15),    -- One Outs (81, 49K)
  ('sports_anime', 'ANIME', 11771, 16),   -- Kuroko no Basket (78, 260K)
  ('sports_anime', 'ANIME', 5941, 17),    -- Cross Game (81, 28K)
  ('sports_anime', 'ANIME', 6675, 18),    -- Redline (81, 103K)
  ('sports_anime', 'ANIME', 170942, 19),  -- Blue Box (81, 115K)
  ('sports_anime', 'ANIME', 165171, 20),  -- Medalist (83, 32K)
  ('sports_anime', 'ANIME', 18689, 21),   -- Ace of the Diamond (80, 61K)
  ('sports_anime', 'ANIME', 2402, 22),    -- Ashita no Joe (81, 35K)
  ('sports_anime', 'ANIME', 124153, 23),  -- SK8 the Infinity (79, 214K)
  ('sports_anime', 'ANIME', 98005, 24),   -- Welcome to the Ballroom (79, 80K)
  ('sports_anime', 'ANIME', 627, 25),     -- Major S1 (80, 22K)
  ('sports_anime', 'ANIME', 153841, 26),  -- Tsurune: The Linking Shot (81, 17K)
  ('sports_anime', 'ANIME', 135, 27),     -- Hikaru no Go (78, 26K)
  ('sports_anime', 'ANIME', 1065, 28),    -- Touch (78, 12K)
  -- Tier 3: Strong picks (score 72-78)
  ('sports_anime', 'ANIME', 20854, 29),   -- Baby Steps 2 (78, 17K)
  ('sports_anime', 'ANIME', 20723, 30),   -- Yowamushi Pedal: Grande Road (78, 27K)
  ('sports_anime', 'ANIME', 153658, 31),  -- Haikyuu!! Dumpster Battle movie (86, 77K) - standalone movie OK
  ('sports_anime', 'ANIME', 182309, 32),  -- Grand Blue Dreaming S2 (83, 52K) - skip if sequel policy
  ('sports_anime', 'ANIME', 7720, 33),    -- Big Windup! 2 / Ookiku Furikabutte (78, 9K)
  ('sports_anime', 'ANIME', 140499, 34),  -- Blue Giant movie (83, 22K)
  ('sports_anime', 'ANIME', 146646, 35)   -- Baki Hanma S2 (79, 36K)
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- 3. Seed sports_manga rail (35 items, one per franchise, score >= 72)
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank) VALUES
  -- Tier 1: Masterpieces
  ('sports_manga', 'MANGA', 30051, 1),    -- Slam Dunk (90, 69K)
  ('sports_manga', 'MANGA', 65243, 2),    -- Haikyuu!! (89, 97K)
  ('sports_manga', 'MANGA', 30657, 3),    -- Real (89, 46K)
  ('sports_manga', 'MANGA', 31303, 4),    -- Ashita no Joe (89, 27K)
  ('sports_manga', 'MANGA', 87395, 5),    -- Grand Blue Dreaming (89, 62K)
  ('sports_manga', 'MANGA', 37375, 6),    -- The Climber / Kokou no Hito (87, 59K)
  ('sports_manga', 'MANGA', 30007, 7),    -- Hajime no Ippo (87, 33K)
  ('sports_manga', 'MANGA', 118371, 8),   -- Medalist (87, 11K)
  -- Tier 2: Excellent
  ('sports_manga', 'MANGA', 107279, 9),   -- Aoashi (86, 23K)
  ('sports_manga', 'MANGA', 43245, 10),   -- Chihayafuru (86, 22K)
  ('sports_manga', 'MANGA', 86099, 11),   -- Wind Breaker (85, 40K)
  ('sports_manga', 'MANGA', 35744, 12),   -- Ping Pong (84, 11K)
  ('sports_manga', 'MANGA', 119174, 13),  -- The Boxer (83, 39K)
  ('sports_manga', 'MANGA', 41327, 14),   -- One Outs (83, 11K)
  ('sports_manga', 'MANGA', 31183, 15),   -- Cross Game (83, 7K)
  ('sports_manga', 'MANGA', 106130, 16),  -- Blue Lock (82, 113K)
  ('sports_manga', 'MANGA', 30043, 17),   -- Eyeshield 21 (82, 21K)
  ('sports_manga', 'MANGA', 78347, 18),   -- Welcome to the Ballroom (82, 15K)
  ('sports_manga', 'MANGA', 30915, 19),   -- Rookies (82, 11K)
  ('sports_manga', 'MANGA', 40884, 20),   -- Ace of Diamond (82, 10K)
  ('sports_manga', 'MANGA', 34625, 21),   -- The Summit of the Gods (82, 10K)
  -- Tier 3: Strong picks
  ('sports_manga', 'MANGA', 132182, 22),  -- Blue Box (81, 49K)
  ('sports_manga', 'MANGA', 86265, 23),   -- Kengan Ashura (81, 26K)
  ('sports_manga', 'MANGA', 30375, 24),   -- Initial D (81, 12K)
  ('sports_manga', 'MANGA', 31013, 25),   -- Touch (81, 6K)
  ('sports_manga', 'MANGA', 31014, 26),   -- H2 (81, 5K)
  ('sports_manga', 'MANGA', 30020, 27),   -- Hikaru no Go (79, 12K)
  ('sports_manga', 'MANGA', 38300, 28),   -- Baby Steps (79, 8K)
  ('sports_manga', 'MANGA', 43897, 29),   -- Giant Killing (79, 5K)
  ('sports_manga', 'MANGA', 107321, 30),  -- Wandance (78, 7K)
  ('sports_manga', 'MANGA', 53627, 31),   -- Yowamushi Pedal (78, 5K)
  ('sports_manga', 'MANGA', 41652, 32),   -- Kuroko no Basket (77, 16K)
  ('sports_manga', 'MANGA', 41425, 33),   -- Baki the Grappler (77, 13K)
  ('sports_manga', 'MANGA', 85475, 34),   -- Rikudou (77, 12K)
  ('sports_manga', 'MANGA', 85612, 35)    -- Hinomaru Sumo (76, 5K)
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;
