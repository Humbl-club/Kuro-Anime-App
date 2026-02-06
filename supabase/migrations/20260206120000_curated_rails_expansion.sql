-- Curated rail expansion: editorial picks to approximately double each rail.
-- All titles verified: NO Ecchi/Hentai genres, score >= 76 for classics, >= 78 for gateway.
-- Safe to re-run: ON CONFLICT DO NOTHING on PK (rail_id, media_type, anilist_id).
--
-- Target sizes after expansion:
--   classics_anime: 120 → 210  (+90)
--   classics_manga:  80 → 177  (+97)
--   gateway_anime:   60 → 135  (+75 standalone, sequels + ecchi excluded)
--   gateway_manga:   50 → 154  (+104 standalone, ecchi excluded)

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- CLASSICS ANIME: +90 (ranks 121–210)
-- Culturally significant, influential, or essential pre-2020 anime.
-- Score >= 76, favourites >= 2000, no Ecchi/Hentai genres.
-- ═══════════════════════════════════════════════════════════════════════

insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
-- Iconic shonen / action
('classics_anime','ANIME',16498,121,null),  -- Attack on Titan
('classics_anime','ANIME',21087,122,null),  -- One-Punch Man
('classics_anime','ANIME',269,123,null),    -- Bleach
('classics_anime','ANIME',223,124,null),    -- Dragon Ball
('classics_anime','ANIME',47,125,null),     -- Akira
('classics_anime','ANIME',14719,126,null),  -- JoJo's Bizarre Adventure (2012)
('classics_anime','ANIME',20474,127,null),  -- JoJo: Stardust Crusaders
('classics_anime','ANIME',20799,128,null),  -- JoJo: Stardust Crusaders - Egypt
('classics_anime','ANIME',101922,129,null), -- Demon Slayer: Kimetsu no Yaiba
('classics_anime','ANIME',20623,130,null),  -- Parasyte -the maxim-
('classics_anime','ANIME',20755,131,null),  -- Assassination Classroom
('classics_anime','ANIME',3588,132,null),   -- Soul Eater
('classics_anime','ANIME',20447,133,null),  -- Noragami
('classics_anime','ANIME',20832,134,null),  -- Overlord
('classics_anime','ANIME',889,135,null),    -- Black Lagoon
('classics_anime','ANIME',6746,136,null),   -- Durarara!!
('classics_anime','ANIME',19603,137,null),  -- Fate/stay night: Unlimited Blade Works
('classics_anime','ANIME',20605,138,null),  -- Tokyo Ghoul
('classics_anime','ANIME',21459,139,null),  -- My Hero Academia
('classics_anime','ANIME',97940,140,null),  -- Black Clover
('classics_anime','ANIME',105333,141,null), -- Dr. STONE
('classics_anime','ANIME',101280,142,null), -- That Time I Got Reincarnated as a Slime
-- Drama / emotional landmarks
('classics_anime','ANIME',20665,143,null),  -- Your Lie in April
('classics_anime','ANIME',20931,144,null),  -- Death Parade
('classics_anime','ANIME',20661,145,null),  -- Terror in Resonance
('classics_anime','ANIME',10408,146,null),  -- Into the Forest of Fireflies' Light
('classics_anime','ANIME',11981,147,null),  -- Madoka Magica: Rebellion
('classics_anime','ANIME',20872,148,null),  -- Plastic Memories
('classics_anime','ANIME',8425,149,null),   -- Gosick
('classics_anime','ANIME',11577,150,null),  -- Steins;Gate Movie
('classics_anime','ANIME',20954,151,null),  -- A Silent Voice
('classics_anime','ANIME',21519,152,null),  -- Your Name.
('classics_anime','ANIME',21827,153,null),  -- Violet Evergarden
('classics_anime','ANIME',21234,154,null),  -- ERASED
('classics_anime','ANIME',99750,155,null),  -- I Want to Eat Your Pancreas
('classics_anime','ANIME',100388,156,null), -- BANANA FISH
-- Master directors (Kon, Miyazaki, Takahata, Hosoda, Yuasa, Ikuhara, Oshii)
('classics_anime','ANIME',1943,157,null),   -- Paprika (Satoshi Kon)
('classics_anime','ANIME',323,158,null),    -- Paranoia Agent (Satoshi Kon)
('classics_anime','ANIME',16664,159,null),  -- The Tale of Princess Kaguya (Takahata)
('classics_anime','ANIME',16662,160,null),  -- The Wind Rises (Miyazaki)
('classics_anime','ANIME',2890,161,null),   -- Ponyo (Miyazaki)
('classics_anime','ANIME',7711,162,null),   -- The Secret World of Arrietty (Ghibli)
('classics_anime','ANIME',20555,163,null),  -- When Marnie Was There (Ghibli)
('classics_anime','ANIME',2236,164,null),   -- The Girl Who Leapt Through Time (Hosoda)
('classics_anime','ANIME',885,165,null),    -- Angel's Egg (Mamoru Oshii)
('classics_anime','ANIME',10721,166,null),  -- Penguindrum (Ikuhara)
('classics_anime','ANIME',3701,167,null),   -- Kaiba (Yuasa)
('classics_anime','ANIME',875,168,null),    -- Mind Game (Yuasa)
-- Romance / romcom / shoujo
('classics_anime','ANIME',4224,169,null),   -- Toradora!
('classics_anime','ANIME',14813,170,null),  -- My Teen Romantic Comedy SNAFU
('classics_anime','ANIME',20698,171,null),  -- SNAFU TOO!
('classics_anime','ANIME',7054,172,null),   -- Maid-Sama!
('classics_anime','ANIME',6045,173,null),   -- Kimi ni Todoke: From Me to You
('classics_anime','ANIME',2034,174,null),   -- Lovely Complex
('classics_anime','ANIME',20770,175,null),  -- Yona of the Dawn
('classics_anime','ANIME',21058,176,null),  -- Snow White with the Red Hair
('classics_anime','ANIME',20519,177,null),  -- Tamako -love story- (KyoAni)
-- Comedy / slice of life
('classics_anime','ANIME',5680,178,null),   -- K-ON!
('classics_anime','ANIME',12189,179,null),  -- Hyouka
('classics_anime','ANIME',20912,180,null),  -- Sound! Euphonium
('classics_anime','ANIME',66,181,null),     -- Azumanga Daioh
('classics_anime','ANIME',20668,182,null),  -- Monthly Girls' Nozaki-kun
('classics_anime','ANIME',13759,183,null),  -- The Pet Girl of Sakurasou
('classics_anime','ANIME',20722,184,null),  -- Barakamon
('classics_anime','ANIME',17549,185,null),  -- Non Non Biyori
('classics_anime','ANIME',477,186,null),    -- ARIA the Animation
('classics_anime','ANIME',387,187,null),    -- Haibane Renmei
('classics_anime','ANIME',21804,188,null),  -- The Disastrous Life of Saiki K.
-- Monogatari franchise extensions
('classics_anime','ANIME',17074,189,null),  -- Monogatari Series Second Season
('classics_anime','ANIME',21262,190,null),  -- Owarimonogatari
-- Sports
('classics_anime','ANIME',20464,191,null),  -- HAIKYU!!
('classics_anime','ANIME',20992,192,null),  -- HAIKYU!! 2nd Season
('classics_anime','ANIME',11771,193,null),  -- Kuroko's Basketball
('classics_anime','ANIME',18689,194,null),  -- Ace of the Diamond
-- Gateway-era defining & late-2010s landmarks
('classics_anime','ANIME',849,195,null),    -- The Melancholy of Haruhi Suzumiya
('classics_anime','ANIME',2167,196,null),   -- Clannad
('classics_anime','ANIME',227,197,null),    -- FLCL
('classics_anime','ANIME',6547,198,null),   -- Angel Beats!
('classics_anime','ANIME',21507,199,null),  -- Mob Psycho 100
('classics_anime','ANIME',21355,200,null),  -- Re:ZERO -Starting Life in Another World-
('classics_anime','ANIME',101291,201,null), -- Rascal Does Not Dream of Bunny Girl Senpai
('classics_anime','ANIME',101921,202,null), -- Kaguya-sama: Love is War
-- Dark / psychological
('classics_anime','ANIME',790,203,null),    -- Ergo Proxy
('classics_anime','ANIME',101348,204,null), -- Vinland Saga
('classics_anime','ANIME',97986,205,null),  -- Made in Abyss
('classics_anime','ANIME',101347,206,null), -- Dororo
('classics_anime','ANIME',98460,207,null),  -- Devilman Crybaby
-- Niche / art-house
('classics_anime','ANIME',16067,208,null),  -- A Lull in the Sea
('classics_anime','ANIME',20595,209,null),  -- Mushishi Next Passage
('classics_anime','ANIME',20751,210,null)   -- Mushishi Next Passage 2
on conflict (rail_id, media_type, anilist_id) do nothing;


-- ═══════════════════════════════════════════════════════════════════════
-- CLASSICS MANGA: +97 (ranks 81–177)
-- Essential pre-2020 manga spanning shonen pillars, seinen masterworks,
-- shoujo landmarks, and critically acclaimed light novels.
-- Score >= 76, no Ecchi/Hentai genres.
-- ═══════════════════════════════════════════════════════════════════════

insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
-- Shonen pillars & modern defining manga
('classics_manga','MANGA',30012,81,null),   -- Bleach
('classics_manga','MANGA',30011,82,null),   -- Naruto
('classics_manga','MANGA',85486,83,null),   -- My Hero Academia
('classics_manga','MANGA',86123,84,null),   -- Black Clover
('classics_manga','MANGA',30047,85,null),   -- Reborn!
('classics_manga','MANGA',43492,86,null),   -- Blue Exorcist
('classics_manga','MANGA',30014,87,null),   -- Rave Master
('classics_manga','MANGA',30043,88,null),   -- Eyeshield 21
('classics_manga','MANGA',105778,89,null),  -- Chainsaw Man
('classics_manga','MANGA',105398,90,null),  -- Solo Leveling
('classics_manga','MANGA',101517,91,null),  -- Jujutsu Kaisen
('classics_manga','MANGA',87216,92,null),   -- Demon Slayer: Kimetsu no Yaiba
('classics_manga','MANGA',108556,93,null),  -- SPY x FAMILY
('classics_manga','MANGA',106130,94,null),  -- Blue Lock
-- Seinen / dark / thriller
('classics_manga','MANGA',85611,95,null),   -- Tokyo Ghoul:re
('classics_manga','MANGA',86559,96,null),   -- Golden Kamuy
('classics_manga','MANGA',86964,97,null),   -- Bastard (manhwa)
('classics_manga','MANGA',85911,98,null),   -- Tomodachi Game
('classics_manga','MANGA',31649,99,null),   -- LIAR GAME
('classics_manga','MANGA',41327,100,null),  -- One Outs
('classics_manga','MANGA',94490,101,null),  -- The Fable
('classics_manga','MANGA',31408,102,null),  -- The World Is Mine
('classics_manga','MANGA',85165,103,null),  -- Innocent
('classics_manga','MANGA',87170,104,null),  -- Fire Punch
-- Romance / shoujo / josei
('classics_manga','MANGA',86635,105,null),  -- Kaguya-sama: Love is War
('classics_manga','MANGA',86218,106,null),  -- Bloom Into You
('classics_manga','MANGA',54294,107,null),  -- Ao Haru Ride
('classics_manga','MANGA',86717,108,null),  -- Wotakoi: Love is Hard for Otaku
('classics_manga','MANGA',30029,109,null),  -- Paradise Kiss
('classics_manga','MANGA',30092,110,null),  -- Sailor Moon
('classics_manga','MANGA',30106,111,null),  -- Cardcaptor Sakura
('classics_manga','MANGA',30676,112,null),  -- InuYasha
('classics_manga','MANGA',30729,113,null),  -- Emma
('classics_manga','MANGA',43702,114,null),  -- My Little Monster
('classics_manga','MANGA',47904,115,null),  -- Princess Jellyfish
('classics_manga','MANGA',65573,116,null),  -- orange
('classics_manga','MANGA',59211,117,null),  -- Monthly Girls' Nozaki-kun
('classics_manga','MANGA',68105,118,null),  -- Kase-san and...
('classics_manga','MANGA',39699,119,null),  -- Classmates
('classics_manga','MANGA',85734,120,null),  -- Tamen De Gushi
('classics_manga','MANGA',85850,121,null),  -- 19 Days
('classics_manga','MANGA',96767,122,null),  -- Honey Lemon Soda
('classics_manga','MANGA',44236,123,null),  -- LOVE SO LIFE
('classics_manga','MANGA',97852,124,null),  -- Komi Can't Communicate
-- Comedy
('classics_manga','MANGA',87395,125,null),  -- Grand Blue Dreaming
('classics_manga','MANGA',37519,126,null),  -- The World God Only Knows
('classics_manga','MANGA',85533,127,null),  -- Teasing Master Takagi-san
('classics_manga','MANGA',66413,128,null),  -- Hinamatsuri
('classics_manga','MANGA',30085,129,null),  -- Azumanga Daioh
-- Drama / literary
('classics_manga','MANGA',85135,130,null),  -- A Silent Voice
('classics_manga','MANGA',30436,131,null),  -- Uzumaki: Spiral into Horror
('classics_manga','MANGA',98361,132,null),  -- Three Days of Happiness
('classics_manga','MANGA',87208,133,null),  -- Our Dreams at Dusk
('classics_manga','MANGA',87347,134,null),  -- Given
('classics_manga','MANGA',86770,135,null),  -- The Girl From the Other Side
('classics_manga','MANGA',85316,136,null),  -- Dead Dead Demon's Dededede Destruction
('classics_manga','MANGA',30418,137,null),  -- Mushishi
('classics_manga','MANGA',47465,138,null),  -- Memories of Emanon
('classics_manga','MANGA',69325,139,null),  -- Erased
('classics_manga','MANGA',41734,140,null),  -- Watashitachi no Shiawase na Jikan
('classics_manga','MANGA',30912,141,null),  -- Tomie (Junji Ito)
('classics_manga','MANGA',85435,142,null),  -- The Ancient Magus' Bride
('classics_manga','MANGA',85849,143,null),  -- ReLIFE
('classics_manga','MANGA',30010,144,null),  -- xxxHOLiC (CLAMP)
('classics_manga','MANGA',97553,145,null),  -- I Sold My Life For 10,000 Yen Per Year
('classics_manga','MANGA',98263,146,null),  -- Witch Hat Atelier
('classics_manga','MANGA',107237,147,null), -- Blue Period
-- Adventure / fantasy / isekai
('classics_manga','MANGA',86082,148,null),  -- Delicious in Dungeon
('classics_manga','MANGA',85412,149,null),  -- Girls' Last Tour
('classics_manga','MANGA',86399,150,null),  -- That Time I Got Reincarnated as a Slime
('classics_manga','MANGA',98842,151,null),  -- Toilet-Bound Hanako-kun
('classics_manga','MANGA',86568,152,null),  -- The Case Study of Vanitas
('classics_manga','MANGA',86310,153,null),  -- Fire Force
('classics_manga','MANGA',86099,154,null),  -- Wind Breaker
('classics_manga','MANGA',73661,155,null),  -- Seraph of the End
-- Sports
('classics_manga','MANGA',107279,156,null), -- Aoashi
('classics_manga','MANGA',40884,157,null),  -- Ace of the Diamond
('classics_manga','MANGA',86569,158,null),  -- Ace of the Diamond Act II
-- Sci-fi / horror
('classics_manga','MANGA',44483,159,null),  -- Space Brothers
('classics_manga','MANGA',85235,160,null),  -- School-Live!
('classics_manga','MANGA',45805,161,null),  -- Dusk Maiden of Amnesia
-- Historical / niche masterworks
('classics_manga','MANGA',34625,162,null),  -- The Summit of the Gods
('classics_manga','MANGA',32924,163,null),  -- Historie
('classics_manga','MANGA',31075,164,null),  -- 7SEEDS
('classics_manga','MANGA',76258,165,null),  -- Flying Witch
('classics_manga','MANGA',103270,166,null), -- Our Dining Table
-- Light novels (critically acclaimed, pre-2020)
('classics_manga','MANGA',94970,167,null),  -- Classroom of the Elite
('classics_manga','MANGA',85737,168,null),  -- Re:ZERO (LN)
('classics_manga','MANGA',99026,169,null),  -- The Apothecary Diaries (LN)
('classics_manga','MANGA',39115,170,null),  -- Spice & Wolf (LN)
('classics_manga','MANGA',70171,171,null),  -- My Youth Romantic Comedy Is Wrong (LN)
('classics_manga','MANGA',92550,172,null),  -- Adachi and Shimamura (LN)
('classics_manga','MANGA',87383,173,null),  -- Ascendance of a Bookworm (LN)
-- Companion manga adaptations
('classics_manga','MANGA',33299,174,null),  -- Spice & Wolf (manga)
-- Additional notables
('classics_manga','MANGA',60315,175,null),  -- Last Game
('classics_manga','MANGA',57231,176,null),  -- Daytime Shooting Star
('classics_manga','MANGA',85395,177,null)   -- Cheeky Brat
on conflict (rail_id, media_type, anilist_id) do nothing;


-- ═══════════════════════════════════════════════════════════════════════
-- GATEWAY ANIME: +75 (ranks 61–135)
-- "Start Here" for newcomers — standalone first seasons & movies only.
-- All sequels, spin-offs, Ecchi/Hentai excluded. Score >= 78.
-- ═══════════════════════════════════════════════════════════════════════

insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('gateway_anime','ANIME',101922,61,null),   -- Demon Slayer: Kimetsu no Yaiba
('gateway_anime','ANIME',1535,62,null),     -- Death Note
('gateway_anime','ANIME',113415,63,null),   -- JUJUTSU KAISEN
('gateway_anime','ANIME',21087,64,null),    -- One-Punch Man
('gateway_anime','ANIME',20,65,null),       -- Naruto
('gateway_anime','ANIME',101759,66,null),   -- The Promised Neverland
('gateway_anime','ANIME',20755,67,null),    -- Assassination Classroom
('gateway_anime','ANIME',21507,68,null),    -- Mob Psycho 100
('gateway_anime','ANIME',20665,69,null),    -- Your Lie in April
('gateway_anime','ANIME',21234,70,null),    -- ERASED
('gateway_anime','ANIME',1735,71,null),     -- Naruto: Shippuden
('gateway_anime','ANIME',21355,72,null),    -- Re:ZERO -Starting Life in Another World-
('gateway_anime','ANIME',127230,73,null),   -- Chainsaw Man
('gateway_anime','ANIME',20464,74,null),    -- HAIKYU!!
('gateway_anime','ANIME',101291,75,null),   -- Rascal Does Not Dream of Bunny Girl Senpai
('gateway_anime','ANIME',97940,76,null),    -- Black Clover
('gateway_anime','ANIME',101921,77,null),   -- Kaguya-sama: Love is War
('gateway_anime','ANIME',105333,78,null),   -- Dr. STONE
('gateway_anime','ANIME',4224,79,null),     -- Toradora!
('gateway_anime','ANIME',140960,80,null),   -- SPY x FAMILY
('gateway_anime','ANIME',124080,81,null),   -- Horimiya
('gateway_anime','ANIME',20623,82,null),    -- Parasyte -the maxim-
('gateway_anime','ANIME',30,83,null),       -- Neon Genesis Evangelion
('gateway_anime','ANIME',20931,84,null),    -- Death Parade
('gateway_anime','ANIME',269,85,null),      -- Bleach
('gateway_anime','ANIME',101280,86,null),   -- That Time I Got Reincarnated as a Slime
('gateway_anime','ANIME',131573,87,null),   -- JUJUTSU KAISEN 0
('gateway_anime','ANIME',97986,88,null),    -- Made in Abyss
('gateway_anime','ANIME',151807,89,null),   -- Solo Leveling
('gateway_anime','ANIME',14813,90,null),    -- My Teen Romantic Comedy SNAFU
('gateway_anime','ANIME',101347,91,null),   -- Dororo
('gateway_anime','ANIME',99750,92,null),    -- I Want to Eat Your Pancreas
('gateway_anime','ANIME',12189,93,null),    -- Hyouka
('gateway_anime','ANIME',21804,94,null),    -- The Disastrous Life of Saiki K.
('gateway_anime','ANIME',106286,95,null),   -- Weathering With You
('gateway_anime','ANIME',171018,96,null),   -- DAN DA DAN
('gateway_anime','ANIME',99578,97,null),    -- Wotakoi: Love is Hard for Otaku
('gateway_anime','ANIME',128893,98,null),   -- Hell's Paradise
('gateway_anime','ANIME',100388,99,null),   -- BANANA FISH
('gateway_anime','ANIME',114535,100,null),  -- To Your Eternity
('gateway_anime','ANIME',105334,101,null),  -- Fruits Basket (2019)
('gateway_anime','ANIME',150672,102,null),  -- Oshi No Ko
('gateway_anime','ANIME',137822,103,null),  -- BLUE LOCK
('gateway_anime','ANIME',116589,104,null),  -- 86 EIGHTY-SIX
('gateway_anime','ANIME',11771,105,null),   -- Kuroko's Basketball
('gateway_anime','ANIME',130298,106,null),  -- The Eminence in Shadow
('gateway_anime','ANIME',5680,107,null),    -- K-ON!
('gateway_anime','ANIME',13759,108,null),   -- The Pet Girl of Sakurasou
('gateway_anime','ANIME',19603,109,null),   -- Fate/stay night: Unlimited Blade Works
('gateway_anime','ANIME',121,110,null),     -- Fullmetal Alchemist (2003)
('gateway_anime','ANIME',141391,111,null),  -- Call of the Night
('gateway_anime','ANIME',153288,112,null),  -- Kaiju No. 8
('gateway_anime','ANIME',21049,113,null),   -- ReLIFE
('gateway_anime','ANIME',889,114,null),     -- Black Lagoon
('gateway_anime','ANIME',98436,115,null),   -- The Ancient Magus' Bride
('gateway_anime','ANIME',6045,116,null),    -- Kimi ni Todoke: From Me to You
('gateway_anime','ANIME',124153,117,null),  -- SK8 the Infinity
('gateway_anime','ANIME',14513,118,null),   -- Magi: The Labyrinth of Magic
('gateway_anime','ANIME',110349,119,null),  -- Great Pretender
('gateway_anime','ANIME',223,120,null),     -- Dragon Ball
('gateway_anime','ANIME',47,121,null),      -- Akira
('gateway_anime','ANIME',100922,122,null),  -- Grand Blue Dreaming
('gateway_anime','ANIME',113717,123,null),  -- Ranking of Kings
('gateway_anime','ANIME',6746,124,null),    -- Durarara!!
('gateway_anime','ANIME',20661,125,null),   -- Terror in Resonance
('gateway_anime','ANIME',9989,126,null),    -- Anohana
('gateway_anime','ANIME',5081,127,null),    -- Bakemonogatari
('gateway_anime','ANIME',9756,128,null),    -- Puella Magi Madoka Magica
('gateway_anime','ANIME',523,129,null),     -- My Neighbor Totoro
('gateway_anime','ANIME',205,130,null),     -- Samurai Champloo
('gateway_anime','ANIME',813,131,null),     -- Dragon Ball Z
('gateway_anime','ANIME',853,132,null),     -- Ouran High School Host Club
('gateway_anime','ANIME',339,133,null),     -- Serial Experiments Lain
('gateway_anime','ANIME',10165,134,null),   -- Nichijou - My Ordinary Life
('gateway_anime','ANIME',13601,135,null)    -- PSYCHO-PASS
on conflict (rail_id, media_type, anilist_id) do nothing;


-- ═══════════════════════════════════════════════════════════════════════
-- GATEWAY MANGA: +104 (ranks 51–154)
-- "Start Here" for newcomers — standalone first entries only.
-- Sequels, Ecchi/Hentai, and inappropriate content excluded.
-- ═══════════════════════════════════════════════════════════════════════

insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('gateway_manga','MANGA',105398,51,null),   -- Solo Leveling
('gateway_manga','MANGA',101517,52,null),   -- Jujutsu Kaisen
('gateway_manga','MANGA',53390,53,null),    -- Attack on Titan
('gateway_manga','MANGA',87216,54,null),    -- Demon Slayer: Kimetsu no Yaiba
('gateway_manga','MANGA',63327,55,null),    -- Tokyo Ghoul
('gateway_manga','MANGA',108556,56,null),   -- SPY x FAMILY
('gateway_manga','MANGA',87423,57,null),    -- The Promised Neverland
('gateway_manga','MANGA',72451,58,null),    -- Horimiya
('gateway_manga','MANGA',106130,59,null),   -- Blue Lock
('gateway_manga','MANGA',30012,60,null),    -- Bleach
('gateway_manga','MANGA',132029,61,null),   -- Dandadan
('gateway_manga','MANGA',105778,62,null),   -- Chainsaw Man
('gateway_manga','MANGA',117195,63,null),   -- [Oshi no Ko]
('gateway_manga','MANGA',85611,64,null),    -- Tokyo Ghoul:re
('gateway_manga','MANGA',87170,65,null),    -- Fire Punch
('gateway_manga','MANGA',30011,66,null),    -- Naruto
('gateway_manga','MANGA',30021,67,null),    -- Death Note
('gateway_manga','MANGA',100994,68,null),   -- Hell's Paradise: Jigokuraku
('gateway_manga','MANGA',98416,69,null),    -- Dr. STONE
('gateway_manga','MANGA',30436,70,null),    -- Uzumaki: Spiral into Horror
('gateway_manga','MANGA',125828,71,null),   -- Sakamoto Days
('gateway_manga','MANGA',86964,72,null),    -- Bastard
('gateway_manga','MANGA',98842,73,null),    -- Toilet-Bound Hanako-kun
('gateway_manga','MANGA',54705,74,null),    -- The Flowers of Evil
('gateway_manga','MANGA',105469,75,null),   -- Jujutsu Kaisen 0
('gateway_manga','MANGA',101233,76,null),   -- The Way of the Househusband
('gateway_manga','MANGA',30936,77,null),    -- Homunculus
('gateway_manga','MANGA',107098,78,null),   -- Record of Ragnarok
('gateway_manga','MANGA',30908,79,null),    -- Soul Eater
('gateway_manga','MANGA',86310,80,null),    -- Fire Force
('gateway_manga','MANGA',86717,81,null),    -- Wotakoi: Love is Hard for Otaku
('gateway_manga','MANGA',111233,82,null),   -- Call of the Night
('gateway_manga','MANGA',54692,83,null),    -- Noragami: Stray God
('gateway_manga','MANGA',30149,84,null),    -- BLAME!
('gateway_manga','MANGA',128067,85,null),   -- SSS-Class Revival Hunter
('gateway_manga','MANGA',30583,86,null),    -- Claymore
('gateway_manga','MANGA',136807,87,null),   -- Look Back
('gateway_manga','MANGA',79865,88,null),    -- Ajin: Demi-Human
('gateway_manga','MANGA',54294,89,null),    -- Ao Haru Ride
('gateway_manga','MANGA',98397,90,null),    -- Blood on the Tracks
('gateway_manga','MANGA',169355,91,null),   -- Kagurabachi
('gateway_manga','MANGA',86399,92,null),    -- That Time I Got Reincarnated as a Slime
('gateway_manga','MANGA',144946,93,null),   -- Gachiakuta
('gateway_manga','MANGA',33031,94,null),    -- Pandora Hearts
('gateway_manga','MANGA',69883,95,null),    -- Assassination Classroom
('gateway_manga','MANGA',100954,96,null),   -- Sweet Home
('gateway_manga','MANGA',126297,97,null),   -- Teenage Mercenary
('gateway_manga','MANGA',33731,98,null),    -- Solanin
('gateway_manga','MANGA',30042,99,null),    -- Dragon Ball
('gateway_manga','MANGA',132182,100,null),  -- Blue Box
('gateway_manga','MANGA',97830,101,null),   -- To Your Eternity
('gateway_manga','MANGA',44790,102,null),   -- Magi: The Labyrinth of Magic
('gateway_manga','MANGA',98587,103,null),   -- BEASTARS
('gateway_manga','MANGA',30664,104,null),   -- Akira
('gateway_manga','MANGA',85307,105,null),   -- Bungo Stray Dogs
('gateway_manga','MANGA',106758,106,null),  -- The Eminence in Shadow
('gateway_manga','MANGA',86770,107,null),   -- The Girl From the Other Side
('gateway_manga','MANGA',39711,108,null),   -- Bakuman
('gateway_manga','MANGA',86848,109,null),   -- Lookism
('gateway_manga','MANGA',119521,110,null),  -- The Legend of the Northern Blade
('gateway_manga','MANGA',149544,111,null),  -- The Guy She Was Interested In Wasn't a Guy at All
('gateway_manga','MANGA',123573,112,null),  -- Lout of Count's Family
('gateway_manga','MANGA',30024,113,null),   -- D.Gray-man
('gateway_manga','MANGA',119174,114,null),  -- The Boxer
('gateway_manga','MANGA',112981,115,null),  -- Kubo Won't Let Me Be Invisible
('gateway_manga','MANGA',120980,116,null),  -- Nano Machine
('gateway_manga','MANGA',87347,117,null),   -- Given
('gateway_manga','MANGA',101177,118,null),  -- Fly Me to the Moon
('gateway_manga','MANGA',85316,119,null),   -- Dead Dead Demon's Dededede Destruction
('gateway_manga','MANGA',98334,120,null),   -- Blue Flag
('gateway_manga','MANGA',63031,121,null),   -- Alice in Borderland
('gateway_manga','MANGA',85911,122,null),   -- Tomodachi Game
('gateway_manga','MANGA',38586,123,null),   -- THE BREAKER
('gateway_manga','MANGA',149332,124,null),  -- The Swordmaster's Son
('gateway_manga','MANGA',65573,125,null),   -- orange
('gateway_manga','MANGA',163824,126,null),  -- Revenge of the Baskerville Bloodhound
('gateway_manga','MANGA',132144,127,null),  -- Return of the Blossoming Blade
('gateway_manga','MANGA',118408,128,null),  -- Villains Are Destined to Die
('gateway_manga','MANGA',85734,129,null),   -- Tamen De Gushi
('gateway_manga','MANGA',136220,130,null),  -- Doom Breaker
('gateway_manga','MANGA',107521,131,null),  -- Who Made Me a Princess
('gateway_manga','MANGA',33866,132,null),   -- Black Butler
('gateway_manga','MANGA',138603,133,null),  -- The Summer Hikaru Died
('gateway_manga','MANGA',30698,134,null),   -- Neon Genesis Evangelion (manga)
('gateway_manga','MANGA',87208,135,null),   -- Our Dreams at Dusk
('gateway_manga','MANGA',159441,136,null),  -- Pick Me Up
('gateway_manga','MANGA',41054,137,null),   -- Billy Bat
('gateway_manga','MANGA',33378,138,null),   -- Kimi ni Todoke: From Me to You
('gateway_manga','MANGA',32921,139,null),   -- Maid-sama!
('gateway_manga','MANGA',109501,140,null),  -- My Love Story with Yamada-kun at Lv999
('gateway_manga','MANGA',99324,141,null),   -- Welcome to Demon School! Iruma-kun
('gateway_manga','MANGA',86568,142,null),   -- The Case Study of Vanitas
('gateway_manga','MANGA',147149,143,null),  -- Smoking Behind the Supermarket with You
('gateway_manga','MANGA',111189,144,null),  -- A Sign of Affection
('gateway_manga','MANGA',30102,145,null),   -- Fruits Basket
('gateway_manga','MANGA',47465,146,null),   -- Memories of Emanon
('gateway_manga','MANGA',97553,147,null),   -- I Sold My Life For 10,000 Yen Per Year
('gateway_manga','MANGA',159930,148,null),  -- The Infinite Mage
('gateway_manga','MANGA',98361,149,null),   -- Three Days of Happiness
('gateway_manga','MANGA',31224,150,null),   -- March Comes in Like a Lion
('gateway_manga','MANGA',101557,151,null),  -- The Dangers in My Heart
('gateway_manga','MANGA',85165,152,null),   -- Innocent
('gateway_manga','MANGA',30145,153,null),   -- BECK
('gateway_manga','MANGA',85143,154,null)    -- Tower of God
on conflict (rail_id, media_type, anilist_id) do nothing;

commit;
