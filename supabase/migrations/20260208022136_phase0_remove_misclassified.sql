-- Phase 0 Migration 2: Remove misclassified items from rails
-- Idempotent: DELETE WHERE only removes rows that exist.

-- ========================================
-- DARK SERIOUS ANIME: Remove misclassified items
-- Items that are NOT dark/serious by any reasonable definition
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'dark_serious_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  -- IDOLiSH7 entries (idol show, not dark/serious)
  103110,  -- IDOLiSH7 Second BEAT!
  127721,  -- IDOLiSH7 Third BEAT!
  -- Detective Conan movies (mystery procedural, not dark)
  156841,  -- Detective Conan: Black Iron Submarine
  1363,    -- Case Closed: Captured In Her Eyes
  142219,  -- Detective Conan: Bride of Halloween
  5460,    -- Case Closed: Jet Black Chaser
  -- Uma Musume (horse girl sports anime)
  172420,  -- Uma Musume: Pretty Derby
  -- Medalist (sports anime, not dark)
  165171,  -- Medalist
  -- BanG Dream (music anime)
  169295,  -- Ave Mujica
  -- Scott Pilgrim (comedy cartoon)
  170206,  -- Scott Pilgrim Takes Off
  -- Fate/kaleid liner Prisma Illya (magical girl spinoff, borderline ecchi)
  97757,   -- Fate/kaleid liner Prisma Illya: Vow in the Snow
  -- Demon Slayer (action, not dark/serious)
  112151,  -- Demon Slayer Mugen Train Movie
  129874,  -- Demon Slayer Mugen Train Arc TV
  -- Fruits Basket (drama/romance, not dark)
  -- (already removed as sequels: 111762, 124194)
  -- Code Geass III Glorification (recap/cash-grab)
  101813,  -- Code Geass: Lelouch of the Rebellion III
  -- Steins;Gate movie/extras (keep S1 and 0, remove extras)
  11577,   -- Steins;Gate Movie
  21624,   -- Steins;Gate 0: Divide By Zero
  -- Rascal Does Not Dream extras (keep first movie, remove deep sequels)
  154967,  -- Rascal: Sister Venturing Out
  171046,  -- Rascal: Santa Claus
  161474,  -- Rascal: Knapsack Kid
  -- Kizumonogatari (already have Bakemonogatari and Monogatari SS)
  181970,  -- KIZUMONOGATARI
  -- Zoku Owarimonogatari (deep Monogatari sequel)
  100815,  -- Zoku Owarimonogatari
  -- Hanamonogatari (deep Monogatari sequel)
  20593,   -- Hanamonogatari
  -- MONOGATARI Off & Monster Season (deep sequel)
  173533,  -- MONOGATARI Series: OFF & MONSTER Season
  -- Mob Psycho 100 (uplifting comedy-drama, not dark/serious)
  21507    -- Mob Psycho 100
);

-- ========================================
-- ISEKAI ANIME: Remove non-isekai items
-- These are NOT actual isekai (protagonist transported to another world)
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'isekai_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  -- NOT isekai at all
  199,     -- Spirited Away (Miyazaki film, portal fantasy != isekai)
  20931,   -- Death Parade (afterlife setting, not isekai)
  121,     -- Fullmetal Alchemist (native fantasy)
  124845,  -- Wonder Egg Priority (not isekai)
  232,     -- Cardcaptor Sakura (magical girl)
  18115,   -- Magi: Kingdom of Magic (native fantasy)
  875,     -- Mind Game (art film)
  249,     -- InuYasha (barely isekai, remove)
  -- Sailor Moon entries (magical girl, NOT isekai)
  532,     -- Sailor Moon S
  740,     -- Sailor Moon R
  148149,  -- Sailor Moon Cosmos Part 1
  -- Precure entries (children's magical girl, NOT isekai)
  100661,  -- HUGtto! Precure
  157883,  -- Soaring Sky! Precure
  171030,  -- Wonderful Precure!
  5684,    -- Fresh Precure!
  21506,   -- Witchy Precure!
  9893,    -- Suite Precure
  1534,    -- PreCure Splash Star
  162722,  -- Witchy Precure!! MIRAI DAYS
  101908,  -- HUGtto! Precure All Stars
  15307,   -- Smile Precure! movie
  -- Fate entries (not isekai)
  103275,  -- Fate/Grand Order Babylonia
  166617,  -- Fate/strange Fake
  97757,   -- Fate/kaleid liner Prisma Illya
  -- Gundam entries (mecha, not isekai)
  19319,   -- Gundam Build Fighters
  -- Yakitate Japan (bread baking anime!)
  28,      -- Yakitate!! Japan
  -- Brave Bang Bravern (mecha parody)
  165598,  -- Brave Bang Bravern!
  -- Gintama movie (sci-fi comedy)
  -- (already removed as sequel: 15335)
  -- Dropkick on My Devil entries (comedy)
  107294,  -- Dropkick on My Devil!! Dash
  124641,  -- Dropkick on My Devil!!! X
  -- Baka and Test (school comedy)
  9471,    -- Baka and Test OVA
  -- Digimon entries (barely qualifies, remove)
  552,     -- Digimon Adventure
  874,     -- Digimon Tamers
  2961,    -- Digimon Adventure Movie
  -- Various non-isekai miscellany
  875,     -- Mind Game
  1365,    -- Case Closed: Baker Street (mystery)
  77,      -- Nanoha A's (magical girl)
  1642,    -- Sugar Sugar Rune
  165530,  -- Fated Magical Princess
  2685,    -- Tsubasa: Tokyo Revelations
  99935,   -- Psychic Princess
  108978,  -- Scumbag System (donghua)
  101920,  -- Soul Land (donghua)
  191974,  -- All-devouring Whale (donghua)
  10259,   -- Big Fish & Begonia
  183423,  -- One Piece Log: Fish-Man Island
  531,     -- Sailor Moon R Movie
  1023,    -- Wolf's Rain OVA
  452,     -- InuYasha Movie 1
  450,     -- InuYasha Movie 2
  451,     -- InuYasha Movie 3
  449,     -- InuYasha Movie 4
  97769,   -- Yuki Yuna Hero Chapter
  20800,   -- Yuki Yuna is a Hero
  182,     -- Vision of Escaflowne
  455,     -- Fantastic Children
  97988,   -- DRIFTERS OVA
  17947,   -- Nanoha Reflection
  17080,   -- Fafner Exodus
  21287,   -- Fafner Exodus 2
  97858,   -- Yuki Yuna: Washio Sumi 1
  97859,   -- Yuki Yuna: Washio Sumi 2
  122292,  -- Yuki Yuna: Great Mankai Chapter
  98107,   -- Idol Time Pripara
  15813,   -- Majokko Shimai no Yoyo to Nene
  2489,    -- Onegai My Melody
  4938,    -- Tsubasa: Spring Thunder
  2978,    -- New Getter Robo
  1316,    -- Idaten Jump
  102600,  -- Huyao Xiao Hongniang
  113811,  -- Ascendance of a Bookworm Side Story/OVA
  139643,  -- Drifting Home
  145739,  -- Lonely Castle in the Mirror
  104213,  -- Mr. Osomatsu Movie
  136436   -- Miss Kobayashi's Dragon Maid S OVA
);

-- ========================================
-- PREMIUM ACTION ANIME: Remove SAO and isekai titles
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_action_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  -- SAO entries (not premium quality)
  100182,  -- SAO: Alicization
  108759,  -- SAO: Alicization - War of Underworld
  -- Isekai that should be in the isekai rail only
  101280,  -- That Time I Got Reincarnated as a Slime
  130298,  -- The Eminence in Shadow
  99263,   -- The Rising of the Shield Hero
  151807,  -- Solo Leveling
  20832    -- Overlord
);

-- ========================================
-- PREMIUM PICKS ANIME: Remove isekai titles
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  101280,  -- That Time I Got Reincarnated as a Slime
  130298,  -- The Eminence in Shadow
  151807,  -- Solo Leveling
  176496   -- Solo Leveling S2 (if not already removed)
);

-- ========================================
-- GATEWAY ANIME: Remove isekai/low-quality items
-- ========================================
DELETE FROM curated_rail_items
WHERE rail_id = 'gateway_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  101280,  -- That Time I Got Reincarnated as a Slime
  130298,  -- The Eminence in Shadow
  151807,  -- Solo Leveling (power fantasy)
  97940    -- Black Clover (score 79, generic)
);

-- ========================================
-- HIDDEN GEMS ANIME: Remove recap movies and non-gems
-- ========================================
-- (Most hidden_gems sequels were already removed in migration 1.
--  Additional misclassified items to remove:)
DELETE FROM curated_rail_items
WHERE rail_id = 'hidden_gems_anime' AND media_type = 'ANIME'
AND anilist_id IN (
  -- These will be identified by sequel removal already done
  -- Add any remaining recap movies / franchise films if present
  103110,  -- IDOLiSH7 (if present)
  127721   -- IDOLiSH7 Third BEAT (if present)
);
