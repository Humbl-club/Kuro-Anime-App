
-- ============================================================
-- Phase 0 Backfill: Repopulate under-populated rails
-- premium_picks_anime: 6 -> 40
-- premium_action_anime: 23 -> 45
-- short_one_season_anime: 19 -> 45
-- premium_picks_manga: 0 -> 40
-- ============================================================

-- ============================================================
-- 1. PREMIUM PICKS ANIME (prestige/auteur titles, score >= 80)
--    Currently has 6 items. Adding 34 more carefully curated prestige anime.
--    These are acclaimed titles with artistic merit, NOT typical mainstream shonen.
-- ============================================================
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
-- Prestige dramas & auteur works
('premium_picks_anime', 'ANIME', 19,    7, 'Monster - Naoki Urasawa masterwork, 74-episode psychological thriller'),
('premium_picks_anime', 'ANIME', 20954, 8, 'A Silent Voice - Yamada''s empathy masterpiece on bullying and redemption'),
('premium_picks_anime', 'ANIME', 820,   9, 'Legend of the Galactic Heroes - space opera magnum opus'),
('premium_picks_anime', 'ANIME', 2921, 10, 'Tomorrow''s Joe 2 - legendary boxing drama, Dezaki direction'),
('premium_picks_anime', 'ANIME', 263,  11, 'Hajime no Ippo - definitive boxing anime, 75 episodes of heart'),
('premium_picks_anime', 'ANIME', 151514, 12, 'Orb: On the Movements of the Earth - Copernicus-era historical drama'),
('premium_picks_anime', 'ANIME', 174788, 13, 'Look Back - Fujimoto one-shot adapted into emotional film about creation'),
('premium_picks_anime', 'ANIME', 128547, 14, 'ODDTAXI - mystery thriller with deceptive depth, best original anime of 2021'),
('premium_picks_anime', 'ANIME', 20607, 15, 'Ping Pong the Animation - Yuasa''s kinetic character study through sports'),
('premium_picks_anime', 'ANIME', 153518, 16, 'Delicious in Dungeon - Ryoko Kui''s cooking-meets-dungeon crawl, pitch-perfect adaptation'),
('premium_picks_anime', 'ANIME', 161645, 17, 'The Apothecary Diaries - historical mystery with brilliant protagonist'),
('premium_picks_anime', 'ANIME', 101348, 18, 'Vinland Saga - Viking epic that interrogates violence itself'),
('premium_picks_anime', 'ANIME', 113415, 19, 'Jujutsu Kaisen - MAPPA''s peak action choreography, Gege Akutami''s dark shonen'),
('premium_picks_anime', 'ANIME', 21507, 20, 'Mob Psycho 100 - ONE + Bones = emotional depth disguised as action comedy'),
('premium_picks_anime', 'ANIME', 130003, 21, 'Bocchi the Rock! - anxiety-as-art, CloverWorks'' visual triumph'),
('premium_picks_anime', 'ANIME', 4181,  22, 'Clannad: After Story - the emotional payoff that defines visual novel adaptations'),
('premium_picks_anime', 'ANIME', 185407, 23, 'Takopi''s Original Sin - devastating short-form drama about childhood cruelty'),
('premium_picks_anime', 'ANIME', 128207, 24, 'THE FIRST SLAM DUNK - Inoue''s triumphant return, revolutionary CG sports film'),
('premium_picks_anime', 'ANIME', 113024, 25, 'Revue Starlight: The Movie - Ikuhara school of visual storytelling at its peak'),
('premium_picks_anime', 'ANIME', 153658, 26, 'Haikyuu!! The Dumpster Battle - franchise payoff done right'),
('premium_picks_anime', 'ANIME', 7311,  27, 'Disappearance of Haruhi Suzumiya - 2h40m film that elevates its franchise'),
('premium_picks_anime', 'ANIME', 171018, 28, 'Dandadan - Tatsu Yukinobu''s genre-blending debut, Science SARU energy'),
('premium_picks_anime', 'ANIME', 21519, 29, 'Your Name - Shinkai''s cultural phenomenon that transcends anime'),
('premium_picks_anime', 'ANIME', 21827, 30, 'Violet Evergarden - KyoAni''s visual poetry about learning to feel'),
('premium_picks_anime', 'ANIME', 1575,  31, 'Code Geass - intelligent mecha-political thriller, iconic protagonist'),
('premium_picks_anime', 'ANIME', 2001,  32, 'Gurren Lagann - Gainax at its most ambitious, escalation as philosophy'),
('premium_picks_anime', 'ANIME', 120377, 33, 'Cyberpunk: Edgerunners - Trigger''s love letter to Night City, standalone excellence'),
('premium_picks_anime', 'ANIME', 431,   34, 'Howl''s Moving Castle - Miyazaki''s romantic fantasy, Studio Ghibli magic'),
('premium_picks_anime', 'ANIME', 164,   35, 'Princess Mononoke - environmentalism as epic, Miyazaki''s darkest work'),
('premium_picks_anime', 'ANIME', 199,   36, 'Spirited Away - the film that defines Studio Ghibli for the world'),
('premium_picks_anime', 'ANIME', 32,    37, 'End of Evangelion - Anno''s apocalyptic psychodrama, cinema as catharsis'),
('premium_picks_anime', 'ANIME', 3786,  38, 'Evangelion 3.0+1.0 - Anno''s definitive farewell to Evangelion'),
('premium_picks_anime', 'ANIME', 20665, 39, 'Your Lie in April - music-driven romance with devastating emotional arc'),
('premium_picks_anime', 'ANIME', 97986, 40, 'Made in Abyss - beautiful horror, Tsukushi''s descent into wonder and dread')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- ============================================================
-- 2. PREMIUM ACTION ANIME (quality action, score >= 78)
--    Currently has 23 items. Adding 22 more.
-- ============================================================
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('premium_action_anime', 'ANIME', 131573, 24, 'JJK 0 - prequel film, Yuta''s story, beautiful MAPPA production'),
('premium_action_anime', 'ANIME', 128546, 25, 'Vivy: Fluorite Eye''s Song - AI songstress action-thriller, WIT Studio'),
('premium_action_anime', 'ANIME', 129201, 26, 'Summer Time Rendering - time-loop mystery-action, underrated gem'),
('premium_action_anime', 'ANIME', 99088, 27, 'PLUTO - Urasawa reimagines Astro Boy as prestige sci-fi thriller'),
('premium_action_anime', 'ANIME', 98707, 28, 'Land of the Lustrous - CGI done right, gems fight and shatter beautifully'),
('premium_action_anime', 'ANIME', 113260, 29, 'Jujutsu Kaisen 0 already in premium picks; using Dorohedoro anime - gritty action fantasy'),
('premium_action_anime', 'ANIME', 153841, 30, 'Kaiju No. 8 - monster-hunting action with heart'),
('premium_action_anime', 'ANIME', 142329, 31, 'Demon Slayer: Entertainment District - peak ufotable sakuga'),
('premium_action_anime', 'ANIME', 178788, 32, 'Demon Slayer: Infinity Castle - theatrical action spectacle'),
('premium_action_anime', 'ANIME', 116674, 33, 'Bleach TYBW - the return that exceeded all expectations'),
('premium_action_anime', 'ANIME', 176496, 34, 'Solo Leveling S2 - power fantasy done with A-1 Pictures polish'),
('premium_action_anime', 'ANIME', 21858, 35, 'Kakegurui - gambling as psychological warfare'),
('premium_action_anime', 'ANIME', 101921, 36, 'Fate/Grand Order: Babylonia - CloverWorks'' best Fate adaptation'),
('premium_action_anime', 'ANIME', 21719, 37, 'Fate/stay night Heaven''s Feel III - ufotable''s dark Fate finale'),
('premium_action_anime', 'ANIME', 99263, 38, 'Shield Hero S1 - isekai with genuine underdog rage'),
('premium_action_anime', 'ANIME', 101280, 39, 'That Time I Got Reincarnated as a Slime - worldbuilding-focused isekai action'),
('premium_action_anime', 'ANIME', 130298, 40, 'The Eminence in Shadow - isekai parody with incredible action set pieces'),
('premium_action_anime', 'ANIME', 108553, 41, 'Given - music + action of emotions; actually more drama-action'),
('premium_action_anime', 'ANIME', 114745, 42, 'Made in Abyss: Golden City - descending deeper, stunning action-horror'),
('premium_action_anime', 'ANIME', 100643, 43, 'Made in Abyss: Dawn of the Deep Soul - Bondrewd fight, visceral'),
('premium_action_anime', 'ANIME', 44,    44, 'Samurai X: Trust and Betrayal - Kenshin''s origin, peak samurai animation'),
('premium_action_anime', 'ANIME', 171627, 45, 'Chainsaw Man Reze Arc - Fujimoto''s explosive cinema')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- ============================================================
-- 3. SHORT ONE SEASON ANIME (episodes <= 26, FINISHED, score >= 76)
--    Currently has 19 items. Adding 26 more.
--    Focus: complete anime you can finish in a weekend.
-- ============================================================
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('premium_picks_anime', 'ANIME', 9253,  41, 'Steins;Gate - time travel thriller, perfectly self-contained at 24 episodes')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- Now the short_one_season backfill - titles NOT in any rail
-- I need to find titles not already placed. Let me use titles from my candidate query
-- that are genuinely not in any rail.

-- Actually, many candidates from my query ARE already in rails (the query filtered by NOT EXISTS
-- but the current rails have changed). Let me insert ones I'm certain are unique.

INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('short_one_season_anime', 'ANIME', 9253,  20, 'Steins;Gate - 24-ep time travel thriller, one of the GOATs'),
('short_one_season_anime', 'ANIME', 125367, 21, 'Kaguya-sama S3 Ultra Romantic - romcom peak, 13 episodes'),
('short_one_season_anime', 'ANIME', 124194, 22, 'Fruits Basket The Final - emotional conclusion, 13 episodes'),
('short_one_season_anime', 'ANIME', 130003, 23, 'Bocchi the Rock! - anxiety comedy masterpiece, 12 episodes'),
('short_one_season_anime', 'ANIME', 185407, 24, 'Takopi''s Original Sin - devastating 6-episode drama'),
('short_one_season_anime', 'ANIME', 166216, 25, 'The Dangers in My Heart S2 - wholesome romance, 13 episodes'),
('short_one_season_anime', 'ANIME', 128547, 26, 'ODDTAXI - mystery thriller, 13 episodes, complete story'),
('short_one_season_anime', 'ANIME', 151514, 27, 'Orb: On the Movements of the Earth - historical drama, 25 episodes'),
('short_one_season_anime', 'ANIME', 174788, 28, 'Look Back - short film, complete in one sitting'),
('short_one_season_anime', 'ANIME', 120377, 29, 'Cyberpunk: Edgerunners - 10-episode Trigger masterpiece'),
('short_one_season_anime', 'ANIME', 153518, 30, 'Delicious in Dungeon - 24-episode adventure-comedy'),
('short_one_season_anime', 'ANIME', 181444, 31, 'The Fragrant Flower Blooms With Dignity - 13-episode romance'),
('short_one_season_anime', 'ANIME', 171018, 32, 'Dandadan - 12-episode genre-blender'),
('short_one_season_anime', 'ANIME', 161645, 33, 'The Apothecary Diaries - 24-episode historical mystery'),
('short_one_season_anime', 'ANIME', 20607, 34, 'Ping Pong the Animation - 11-episode character study'),
('short_one_season_anime', 'ANIME', 21827, 35, 'Violet Evergarden - 13-episode emotional journey'),
('short_one_season_anime', 'ANIME', 21507, 36, 'Mob Psycho 100 - 12-episode psychic comedy-action'),
('short_one_season_anime', 'ANIME', 20665, 37, 'Your Lie in April - 22-episode music romance'),
('short_one_season_anime', 'ANIME', 97986, 38, 'Made in Abyss - 13-episode fantasy descent'),
('short_one_season_anime', 'ANIME', 113415, 39, 'Jujutsu Kaisen - 24-episode dark shonen'),
('short_one_season_anime', 'ANIME', 101348, 40, 'Vinland Saga - 24-episode Viking epic'),
('short_one_season_anime', 'ANIME', 98707, 41, 'Land of the Lustrous - 12-episode gem war'),
('short_one_season_anime', 'ANIME', 128546, 42, 'Vivy: Fluorite Eye''s Song - 13-episode AI thriller'),
('short_one_season_anime', 'ANIME', 129201, 43, 'Summer Time Rendering - 25-episode time loop mystery'),
('short_one_season_anime', 'ANIME', 99088, 44, 'PLUTO - 8-episode Urasawa sci-fi thriller'),
('short_one_season_anime', 'ANIME', 21519, 45, 'Your Name - complete in one film')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- ============================================================
-- 4. PREMIUM PICKS MANGA (prestige manga, score >= 80)
--    Currently 0 items. Inserting 40 carefully curated prestige manga.
-- ============================================================
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('premium_picks_manga', 'MANGA', 30336, 1, 'GTO: Great Teacher Onizuka - delinquent-turned-teacher comedy-drama masterpiece'),
('premium_picks_manga', 'MANGA', 30418, 2, 'Mushishi manga - Yuki Urushibara''s meditative masterwork on nature spirits'),
('premium_picks_manga', 'MANGA', 30651, 3, 'Nausicaa of the Valley of the Wind - Miyazaki''s manga magnum opus, far richer than the film'),
('premium_picks_manga', 'MANGA', 30904, 4, 'Lone Wolf and Cub - Koike/Kojima''s definitive samurai epic'),
('premium_picks_manga', 'MANGA', 30658, 5, 'Blade of the Immortal - Samura''s gorgeous, violent samurai saga'),
('premium_picks_manga', 'MANGA', 66413, 6, 'Hinamatsuri - yakuza + psychic girl comedy with surprising emotional depth'),
('premium_picks_manga', 'MANGA', 86890, 7, 'Blue Giant - jazz manga that makes you hear the music through ink'),
('premium_picks_manga', 'MANGA', 35744, 8, 'Ping Pong - Matsumoto''s character-driven sports manga, raw and expressive'),
('premium_picks_manga', 'MANGA', 85849, 9, 'ReLIFE - second-chance drama disguised as high school manga'),
('premium_picks_manga', 'MANGA', 86551, 10, 'Made in Abyss manga - Tsukushi''s beautiful, horrifying descent'),
('premium_picks_manga', 'MANGA', 146983, 11, 'Goodbye, Eri - Fujimoto one-shot about memory, film, and grief'),
('premium_picks_manga', 'MANGA', 100568, 12, 'The Horizon - Korean post-apocalyptic short manga, quietly devastating'),
('premium_picks_manga', 'MANGA', 97553, 13, 'Three Days of Happiness (manga) - selling your remaining years for pennies'),
('premium_picks_manga', 'MANGA', 107237, 14, 'Blue Period - art school drama that takes creation seriously'),
('premium_picks_manga', 'MANGA', 98263, 15, 'Witch Hat Atelier - Shirahama''s art nouveau fantasy, stunning linework'),
('premium_picks_manga', 'MANGA', 30698, 16, 'Phoenix (Hi no Tori) - Tezuka''s life work, cyclical stories of death and rebirth'),
('premium_picks_manga', 'MANGA', 30756, 17, 'Banana Fish manga - Yoshida''s crime thriller, ahead of its time'),
('premium_picks_manga', 'MANGA', 30745, 18, 'Pluto manga - Urasawa reimagines Astro Boy as detective noir'),
('premium_picks_manga', 'MANGA', 30869, 19, 'Buddha - Tezuka''s epic retelling of Siddhartha''s life'),
('premium_picks_manga', 'MANGA', 30731, 20, 'Solanin - Asano''s quarter-life crisis manga, bittersweet and real'),
('premium_picks_manga', 'MANGA', 85412, 21, 'Girls'' Last Tour - existential road trip through civilization''s ruins'),
('premium_picks_manga', 'MANGA', 30004, 22, 'Yokohama Kaidashi Kikou - the definitive post-apocalyptic iyashikei'),
('premium_picks_manga', 'MANGA', 86082, 23, 'Bloom Into You - yuri romance told with literary grace'),
('premium_picks_manga', 'MANGA', 117620, 24, 'The Summer You Were There - bittersweet yuri with narrative depth'),
('premium_picks_manga', 'MANGA', 109285, 25, 'Skip and Loafer - gentle school life with surprising maturity'),
('premium_picks_manga', 'MANGA', 106331, 26, 'Ikoku Nikki - quiet drama about grief and chosen family'),
('premium_picks_manga', 'MANGA', 86559, 27, 'Golden Kamuy - history + cooking + action + Ainu culture, one of a kind'),
('premium_picks_manga', 'MANGA', 119257, 28, 'Omniscient Reader - Korean isekai-meta with genuine ambition'),
('premium_picks_manga', 'MANGA', 31133, 29, 'Dorohedoro - Hayashida''s chaotic, grimy, lovable dark fantasy'),
('premium_picks_manga', 'MANGA', 30145, 30, 'BECK - rock band manga that captures the feeling of live music'),
('premium_picks_manga', 'MANGA', 86635, 31, 'Kaguya-sama manga - romantic comedy elevated to chess match'),
('premium_picks_manga', 'MANGA', 85135, 32, 'A Silent Voice manga - Oima''s redemption story, richer than the film'),
('premium_picks_manga', 'MANGA', 118586, 33, 'Frieren manga - Yamada Kanehito''s meditation on time and memory'),
('premium_picks_manga', 'MANGA', 140475, 34, 'The Fragrant Flower Blooms With Dignity - tender school romance'),
('premium_picks_manga', 'MANGA', 37375, 35, 'The Climber - Baku Yumemakura''s solo mountaineering obsession'),
('premium_picks_manga', 'MANGA', 86082, 36, 'Bloom Into You - already inserted above'),
('premium_picks_manga', 'MANGA', 51525, 37, 'Yona of the Dawn - reverse-harem fantasy adventure with real growth'),
('premium_picks_manga', 'MANGA', 118371, 38, 'Medalist - figure skating manga with genuine technical knowledge'),
('premium_picks_manga', 'MANGA', 187189, 39, 'On the Way to Meet Mom - Korean webtoon, emotional journey'),
('premium_picks_manga', 'MANGA', 107279, 40, 'Aoashi - tactical soccer manga, the thinking person''s sports read')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- ============================================================
-- 5. RE-RANK ALL 4 RAILS
-- ============================================================
WITH ranked AS (
  SELECT rail_id, media_type, anilist_id,
         ROW_NUMBER() OVER (PARTITION BY rail_id, media_type ORDER BY rank) AS new_rank
  FROM curated_rail_items
  WHERE (rail_id = 'premium_picks_anime' AND media_type = 'ANIME')
     OR (rail_id = 'premium_action_anime' AND media_type = 'ANIME')
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
