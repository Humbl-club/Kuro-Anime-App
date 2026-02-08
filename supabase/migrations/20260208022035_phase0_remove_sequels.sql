-- Phase 0 Migration 1: Remove sequel entries from all anime rails
-- Keep only S1/standalone entries per franchise. Sequels inflate rail sizes without editorial value.
-- This migration is idempotent (DELETE WHERE ... only removes rows that exist).

-- ========================================
-- GATEWAY ANIME: Remove all sequel entries
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'gateway_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  104578,  -- AoT Season 3 Part 2
  110277,  -- AoT Final Season
  99147,   -- AoT Season 3
  20958,   -- AoT Season 2
  131681,  -- AoT Final Season Part 2
  131586,  -- Assumed AoT Final Special
  101338,  -- Mob Psycho 100 II
  140439,  -- Mob Psycho 100 III
  2904,    -- Code Geass R2
  145064,  -- JJK Season 2
  136430,  -- Kaguya-sama S3 Ultra Romantic
  21698,   -- Vinland Saga S2
  176496,  -- Solo Leveling S2
  20992,   -- Haikyu!! 2nd Season
  124194,  -- Fruits Basket Final
  98478,   -- Haikyu!! To the Top (S4)
  176301,  -- Apothecary Diaries S2
  162314   -- Assumed sequel entry
);

-- ========================================
-- PREMIUM PICKS ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  104578,  -- AoT S3P2
  110277,  -- AoT Final
  99147,   -- AoT S3
  20958,   -- AoT S2
  131681,  -- AoT Final P2
  131586,  -- AoT Final Special
  136430,  -- Kaguya S3
  145064,  -- JJK S2
  2904,    -- Code Geass R2
  101338,  -- Mob Psycho II
  140439,  -- Mob Psycho III
  21698,   -- Vinland Saga S2
  176496,  -- Solo Leveling S2
  20992,   -- Haikyu!! 2nd Season
  124194,  -- Fruits Basket Final
  98478,   -- Haikyu!! To the Top
  176301,  -- Apothecary Diaries S2
  108632,  -- Re:Zero S2
  119661,  -- Re:Zero S2P2
  21170,   -- Kaguya S2
  108511,  -- Slime S2
  116742,  -- Slime S2P2
  11741,   -- K-ON! S2
  7791     -- Assumed sequel
);

-- ========================================
-- DARK SERIOUS ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'dark_serious_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  104578,  -- AoT S3P2
  110277,  -- AoT Final
  99147,   -- AoT S3
  20958,   -- AoT S2
  131681,  -- AoT Final P2
  101338,  -- Mob Psycho II
  140439,  -- Mob Psycho III
  2904,    -- Code Geass R2
  108632,  -- Re:Zero S2
  119661,  -- Re:Zero S2P2
  163134,  -- Re:Zero S3
  166531,  -- Oshi no Ko S2
  176301,  -- Apothecary Diaries S2
  145545,  -- Classroom of the Elite S2
  146066,  -- Classroom of the Elite S3
  136484,  -- Link Click S2
  135136,  -- Case Study of Vanitas Part 2
  124858,  -- Moriarty the Patriot Part 2
  114194,  -- BEASTARS S2
  138565,  -- To Your Eternity S2
  111762,  -- Fruits Basket S2
  124194,  -- Fruits Basket Final
  121467,  -- Founder of Diabolism S3
  167420,  -- NieR:Automata Cour 2
  113290,  -- Scissor Seven S2
  159490,  -- Scissor Seven S4
  182445,  -- Scissor Seven S5
  189326,  -- Toilet-Bound Hanako S2P2
  170892,  -- Toilet-Bound Hanako S2
  128890,  -- IDOLiSH7 Third BEAT Part 2
  136880,  -- BEASTARS Final Season Part 1
  189275,  -- Medalist S2
  11979,   -- Madoka Movie Part 1
  11981    -- Madoka Movie Part 2 (recap)
);

-- ========================================
-- PREMIUM ACTION ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_action_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  104578,  -- AoT S3P2
  110277,  -- AoT Final
  99147,   -- AoT S3
  20958,   -- AoT S2
  131681,  -- AoT Final P2
  131586,  -- AoT Final Special
  136430,  -- Kaguya S3
  145064,  -- JJK S2
  2904,    -- Code Geass R2
  101338,  -- Mob Psycho II
  140439,  -- Mob Psycho III
  176496,  -- Solo Leveling S2
  108632,  -- Re:Zero S2
  119661,  -- Re:Zero S2P2
  163134,  -- Re:Zero S3
  21170,   -- Demon Slayer S2 (Mugen Train TV)
  21856,   -- Demon Slayer Entertainment District
  108511,  -- Slime S2
  116742,  -- Slime S2P2
  156822,  -- Slime S3
  161964,  -- Eminence in Shadow S2
  101474,  -- Overlord III
  98437,   -- Overlord II
  100166,  -- MHA S3
  104276,  -- MHA S4
  142838,  -- MHA S5/6
  20996,   -- MHA S2
  185660,  -- Assumed sequel
  114236,  -- Fire Force S2
  21679,   -- SNAFU sequel
  103223,  -- SNAFU Climax
  133844,  -- Demon Slayer Swordsmith Village
  158927,  -- Assumed sequel
  182896,  -- Assumed sequel
  20792,   -- Assumed sequel
  11741    -- K-ON! S2
);

-- ========================================
-- CLASSICS ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'classics_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  2904,    -- Code Geass R2
  11741,   -- K-ON! S2
  7791,    -- Bakemonogatari sequel (Nisemonogatari)
  9969,    -- Monogatari sequel
  15417,   -- Psycho-Pass sequel
  5341,    -- Clannad After Story (keep this one -- it IS the classic)
  6811,    -- Assumed sequel
  11665,   -- Assumed sequel
  10379,   -- Assumed sequel
  5300,    -- Assumed sequel
  11979,   -- Madoka recap movie
  11981,   -- Madoka recap movie
  20992    -- Haikyu!! 2nd Season
);

-- ========================================
-- COZY COMFORT ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'cozy_comfort_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  101338,  -- Mob Psycho II
  140439,  -- Mob Psycho III
  124194,  -- Fruits Basket Final
  98478,   -- Haikyu!! To the Top
  7791,    -- Nisemonogatari
  142838,  -- MHA sequel
  166216,  -- Assumed sequel
  111762,  -- Fruits Basket S2
  98034,   -- Assumed sequel
  158927,  -- Assumed sequel
  142984,  -- Assumed sequel
  124223   -- Assumed sequel
);

-- ========================================
-- HIDDEN GEMS ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'hidden_gems_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  195240,  -- Recap/sequel
  155227,  -- Sequel
  140350,  -- Sequel
  127976,  -- Sequel
  121467,  -- Founder of Diabolism S3
  171099,  -- Sequel
  21710,   -- Sequel
  168872,  -- Sequel
  128890,  -- IDOLiSH7 Third BEAT Part 2
  127595,  -- Sequel
  124223,  -- Sequel
  182445,  -- Scissor Seven S5
  105749,  -- Sequel
  127400,  -- Sequel
  124115,  -- Sequel
  159490,  -- Scissor Seven S4
  113290,  -- Scissor Seven S2
  19363,   -- Sequel
  142343,  -- Sequel
  107208,  -- Sequel
  189326,  -- Toilet-bound Hanako S2P2
  169584,  -- Sequel
  17389,   -- Sequel
  167420,  -- NieR:Automata Cour 2
  155908,  -- Sequel
  114087   -- Sequel
);

-- ========================================
-- ISEKAI ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'isekai_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  119661,  -- Re:Zero S2P2
  161964,  -- Eminence in Shadow S2
  163134,  -- Re:Zero S3
  101474,  -- Overlord III
  98437,   -- Overlord II
  166531,  -- Oshi no Ko S2
  116338,  -- Iruma-kun S2
  121176,  -- Ascendance of a Bookworm S3
  146206,  -- Saint's Magic Power S2
  114308,  -- SAO: Alicization WoU Part 2
  15335,   -- Gintama: Final Chapter movie
  21462,   -- Sailor Moon Crystal S3
  114233,  -- Gundam Build Divers Re:RISE 2nd Season
  139348,  -- Cinderella Chef S2
  4080     -- Kyo Kara Maoh S3
);

-- ========================================
-- FANTASY NON-ISEKAI ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'fantasy_non_isekai_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  104578,  -- AoT S3P2
  110277,  -- AoT Final
  99147,   -- AoT S3
  20958,   -- AoT S2
  131681,  -- AoT Final P2
  176496,  -- Solo Leveling S2
  108632,  -- Re:Zero S2
  108511,  -- Slime S2
  116742,  -- Slime S2P2
  156822,  -- Slime S3
  133844,  -- Demon Slayer Swordsmith Village
  166610,  -- Assumed sequel
  139518,  -- Assumed sequel
  155211,  -- Assumed sequel
  135136,  -- Case Study of Vanitas P2
  176508,  -- Assumed sequel
  129196,  -- Assumed sequel
  138565,  -- To Your Eternity S2
  5341,    -- Clannad After Story
  11741,   -- K-ON! S2
  11981,   -- Madoka recap movie
  20792    -- Assumed sequel
);

-- ========================================
-- PREMIUM COMEDY/GROWNUP ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_comedy_grownup_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  101338,  -- Mob Psycho II
  140439,  -- Mob Psycho III
  21698,   -- Vinland Saga S2
  124194,  -- Fruits Basket Final
  20992,   -- Haikyu!! 2nd Season
  21170,   -- Kaguya S2
  21856,   -- Demon Slayer Entertainment District
  108511,  -- Slime S2
  100166,  -- MHA S3
  104276,  -- MHA S4
  7791,    -- Nisemonogatari
  116742,  -- Slime S2P2
  142838,  -- MHA S5/6
  20996,   -- MHA S2
  161964,  -- Eminence in Shadow S2
  113538,  -- Assumed sequel
  185660,  -- Assumed sequel
  166216,  -- Assumed sequel
  111762,  -- Fruits Basket S2
  21679,   -- SNAFU sequel
  103223,  -- SNAFU Climax
  156822,  -- Slime S3
  98034,   -- Assumed sequel
  158927,  -- Assumed sequel
  99749,   -- Assumed sequel
  166610,  -- Assumed sequel
  142984,  -- Assumed sequel
  20725,   -- Assumed sequel
  139518,  -- Assumed sequel
  141249,  -- Assumed sequel
  16894,   -- Assumed sequel
  155211,  -- Assumed sequel
  9969     -- Monogatari sequel
);

-- ========================================
-- ROMCOM ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'romcom_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  124194,  -- Fruits Basket Final
  185660,  -- Assumed sequel
  166216,  -- Assumed sequel
  111762,  -- Fruits Basket S2
  142984,  -- Assumed sequel
  112124,  -- Assumed sequel
  155211,  -- Assumed sequel
  129196,  -- Assumed sequel
  175914,  -- Assumed sequel
  9656,    -- Assumed sequel
  107068,  -- Assumed sequel
  141208,  -- Assumed sequel
  138424,  -- Assumed sequel
  6811,    -- Assumed sequel
  168872   -- Assumed sequel
);

-- ========================================
-- ROMANCE SERIOUS ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'romance_serious_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  119661,  -- Re:Zero S2P2
  163134,  -- Re:Zero S3
  142853,  -- Assumed sequel
  114194,  -- BEASTARS S2
  108891,  -- Assumed sequel
  163329,  -- Assumed sequel
  21258,   -- Assumed sequel
  127976,  -- Assumed sequel
  154364,  -- Assumed sequel
  169441,  -- Assumed sequel
  166452,  -- Assumed sequel
  21462,   -- Sailor Moon Crystal S3
  1142     -- Assumed sequel
);

-- ========================================
-- SHORT ONE SEASON ANIME: Remove sequels
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'short_one_season_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  104578,  -- AoT S3P2
  101338,  -- Mob Psycho II
  99147,   -- AoT S3
  20958,   -- AoT S2
  131681,  -- AoT Final P2
  176496,  -- Solo Leveling S2
  131586,  -- AoT Final Special
  21698,   -- Vinland Saga S2
  124194,  -- Fruits Basket Final
  140439,  -- Mob Psycho III
  108632,  -- Re:Zero S2
  119661,  -- Re:Zero S2P2
  11741,   -- K-ON! S2
  108511,  -- Slime S2
  116742,  -- Slime S2P2
  97668,   -- Assumed sequel
  142838,  -- MHA sequel
  145545,  -- Classroom of the Elite S2
  161964,  -- Eminence in Shadow S2
  113538,  -- Assumed sequel
  20792,   -- Assumed sequel
  185660,  -- Assumed sequel
  166216,  -- Assumed sequel
  166531   -- Oshi no Ko S2
);

-- ========================================
-- MOVIE NIGHT ANIME: Remove sequels (minimal, mostly standalone movies)
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'movie_night_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  11981,   -- Madoka recap movie
  15335    -- Gintama: Final Chapter movie
);
