-- Seed curated rails for 6 new vibe modes:
--   mecha, mystery_detective, music_performance,
--   historical, school_coming_of_age, shoujo_josei.
-- One entry per franchise. No Hentai/Ecchi. No sequel spam.

begin;
-- ============================================================
-- Create rail definitions
-- ============================================================

insert into public.curated_rails(id,title,media_type,description) values
  ('mecha_anime','Mecha','ANIME','Giant robots and mecha action.'),
  ('mecha_manga','Mecha','MANGA','Giant robots and mecha manga.'),
  ('mystery_detective_anime','Mystery & Detective','ANIME','Whodunits, deductions, and psychological puzzles.'),
  ('mystery_detective_manga','Mystery & Detective','MANGA','Whodunits, deductions, and psychological puzzles.'),
  ('music_performance_anime','Music & Performance','ANIME','Music-driven stories, bands, and performers.'),
  ('music_performance_manga','Music & Performance','MANGA','Music-driven stories, bands, and performers.'),
  ('historical_anime','Historical & Period','ANIME','Period dramas, samurai epics, and historical settings.'),
  ('historical_manga','Historical & Period','MANGA','Period dramas, samurai epics, and historical settings.'),
  ('school_anime','School & Coming of Age','ANIME','High school life, youth, and growing up.'),
  ('school_manga','School & Coming of Age','MANGA','High school life, youth, and growing up.'),
  ('shoujo_josei_anime','Shoujo & Josei','ANIME','Stories aimed at female audiences: shoujo, josei, magical girl.'),
  ('shoujo_josei_manga','Shoujo & Josei','MANGA','Stories aimed at female audiences: shoujo, josei, magical girl.')
on conflict (id) do update set title = excluded.title, media_type = excluded.media_type, description = excluded.description;
-- ============================================================
-- Clear any old items for these rails
-- ============================================================

delete from public.curated_rail_items where rail_id in (
  'mecha_anime','mecha_manga',
  'mystery_detective_anime','mystery_detective_manga',
  'music_performance_anime','music_performance_manga',
  'historical_anime','historical_manga',
  'school_anime','school_manga',
  'shoujo_josei_anime','shoujo_josei_manga'
);
-- ============================================================
-- mecha_anime  (one per franchise, score >= 72)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('mecha_anime','ANIME',109,1,null),   -- Code Geass S1 (85)
('mecha_anime','ANIME',155,2,null),   -- Gurren Lagann (85)
('mecha_anime','ANIME',110,3,null),   -- Neon Genesis Evangelion (83)
('mecha_anime','ANIME',966,4,null),   -- PLUTO (84)
('mecha_anime','ANIME',204,5,null),   -- 86 EIGHTY-SIX S1 (82)
('mecha_anime','ANIME',13366,6,null), -- Turn A Gundam (80)
('mecha_anime','ANIME',1289,7,null),  -- Gundam IBO (78)
('mecha_anime','ANIME',1233,8,null),  -- Gundam Witch from Mercury (78)
('mecha_anime','ANIME',1837,9,null),  -- Gundam 00 (78)
('mecha_anime','ANIME',2463,10,null), -- Zeta Gundam (78)
('mecha_anime','ANIME',4551,11,null), -- Gundam The Origin (79)
('mecha_anime','ANIME',2786,12,null), -- Gundam Hathaway (79)
('mecha_anime','ANIME',1018,13,null), -- Eureka Seven (77)
('mecha_anime','ANIME',823,14,null),  -- Promare (77)
('mecha_anime','ANIME',1639,15,null), -- Tiger & Bunny (77)
('mecha_anime','ANIME',1859,16,null), -- Full Metal Panic! TSR (77)
('mecha_anime','ANIME',2938,17,null), -- Macross: Do You Remember Love? (77)
('mecha_anime','ANIME',12915,18,null),-- Macross Frontier (76)
('mecha_anime','ANIME',1746,19,null), -- Mobile Suit Gundam (76)
('mecha_anime','ANIME',3780,20,null), -- Patlabor TV (76)
('mecha_anime','ANIME',2934,21,null), -- Brave Bang Bravern! (76)
('mecha_anime','ANIME',4143,22,null), -- Armored Trooper Votoms (76)
('mecha_anime','ANIME',2602,23,null), -- Gundam Build Fighters (76)
('mecha_anime','ANIME',4558,24,null), -- GaoGaiGar (76)
('mecha_anime','ANIME',2746,25,null)  -- Gridman Universe (81)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- mecha_manga  (one per franchise, score >= 72)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('mecha_manga','MANGA',149,1,null),   -- Pluto (85)
('mecha_manga','MANGA',219,2,null),   -- Neon Genesis Evangelion (84)
('mecha_manga','MANGA',1733,3,null),  -- Gundam The Origin (83)
('mecha_manga','MANGA',4967,4,null),  -- Full Metal Panic! Sigma (79)
('mecha_manga','MANGA',5544,5,null),  -- Getter Robo Go (79)
('mecha_manga','MANGA',1004,6,null),  -- Bokurano (77)
('mecha_manga','MANGA',4372,7,null),  -- Five Star Stories (76)
('mecha_manga','MANGA',3832,8,null),  -- Gurren Lagann (75)
('mecha_manga','MANGA',174,9,null),   -- All You Need Is Kill (74)
('mecha_manga','MANGA',997,10,null),  -- Knights of Sidonia (74)
('mecha_manga','MANGA',8089,11,null), -- Gundam Thunderbolt (73)
('mecha_manga','MANGA',2857,12,null), -- Broken Blade (73)
('mecha_manga','MANGA',2219,13,null), -- Magic Knight Rayearth (72)
('mecha_manga','MANGA',2986,14,null), -- 86 Eighty-Six (72)
('mecha_manga','MANGA',5218,15,null)  -- Levius/est (72)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- mystery_detective_anime  (one per franchise, score >= 76)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('mystery_detective_anime','ANIME',181,1,null),   -- Monster (88)
('mystery_detective_anime','ANIME',233,2,null),   -- The Apothecary Diaries (88)
('mystery_detective_anime','ANIME',437,3,null),   -- Link Click (86)
('mystery_detective_anime','ANIME',1262,4,null),  -- Mushishi Zoku Shou (86)
('mystery_detective_anime','ANIME',485,5,null),   -- Disappearance of Haruhi (86)
('mystery_detective_anime','ANIME',4,6,null),     -- Death Note (84)
('mystery_detective_anime','ANIME',141,7,null),   -- Made in Abyss (84)
('mystery_detective_anime','ANIME',490,8,null),   -- ODDTAXI (85)
('mystery_detective_anime','ANIME',481,9,null),   -- The Tatami Galaxy (84)
('mystery_detective_anime','ANIME',966,10,null),  -- PLUTO (84)
('mystery_detective_anime','ANIME',444,11,null),  -- Land of the Lustrous (83)
('mystery_detective_anime','ANIME',19,12,null),   -- The Promised Neverland (83)
('mystery_detective_anime','ANIME',316,13,null),  -- Summer Time Rendering (83)
('mystery_detective_anime','ANIME',110,14,null),  -- Neon Genesis Evangelion (83)
('mystery_detective_anime','ANIME',195,15,null),  -- Oshi No Ko (84)
('mystery_detective_anime','ANIME',184,16,null),  -- BANANA FISH (82)
('mystery_detective_anime','ANIME',800,17,null),  -- Madoka Magica Rebellion (84)
('mystery_detective_anime','ANIME',874,18,null),  -- Bungo Stray Dogs 4 (84)
('mystery_detective_anime','ANIME',1116,19,null), -- Lord of Mysteries (84)
('mystery_detective_anime','ANIME',961,20,null),  -- To Be Hero X (85)
('mystery_detective_anime','ANIME',353,21,null),  -- Mushishi S1 (85)
('mystery_detective_anime','ANIME',2,22,null),    -- Attack on Titan S1 (85)
('mystery_detective_anime','ANIME',162,23,null),  -- Hyouka (79)
('mystery_detective_anime','ANIME',13601,24,null), -- Psycho-Pass (from premium_picks, high score mystery)
('mystery_detective_anime','ANIME',20931,25,null)  -- ID: Invaded (from premium_picks)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- mystery_detective_manga  (one per franchise, score >= 76)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('mystery_detective_manga','MANGA',76,1,null),    -- JoJo Part 7: Steel Ball Run (92)
('mystery_detective_manga','MANGA',29,2,null),    -- Monster (91)
('mystery_detective_manga','MANGA',91,3,null),    -- Land of the Lustrous (89)
('mystery_detective_manga','MANGA',30,4,null),    -- 20th Century Boys (88)
('mystery_detective_manga','MANGA',86,5,null),    -- Dorohedoro (86)
('mystery_detective_manga','MANGA',149,6,null),   -- Pluto (85)
('mystery_detective_manga','MANGA',183,7,null),   -- The Apothecary Diaries (85)
('mystery_detective_manga','MANGA',231,8,null),   -- Billy Bat (85)
('mystery_detective_manga','MANGA',300,9,null),   -- Mushishi (85)
('mystery_detective_manga','MANGA',6,10,null),    -- Attack on Titan (84)
('mystery_detective_manga','MANGA',80,11,null),   -- Death Note (84)
('mystery_detective_manga','MANGA',9,12,null),    -- Tokyo Ghoul (84)
('mystery_detective_manga','MANGA',138,13,null),  -- Pandora Hearts (84)
('mystery_detective_manga','MANGA',99,14,null),   -- Toilet-Bound Hanako-kun (84)
('mystery_detective_manga','MANGA',94,15,null),   -- Bastard (83)
('mystery_detective_manga','MANGA',105,16,null),  -- Homunculus (83)
('mystery_detective_manga','MANGA',170,17,null),  -- Bungo Stray Dogs (83)
('mystery_detective_manga','MANGA',225,18,null),  -- The Summer Hikaru Died (83)
('mystery_detective_manga','MANGA',238,19,null),  -- Case Study of Vanitas (83)
('mystery_detective_manga','MANGA',394,20,null),  -- Moriarty the Patriot (83)
('mystery_detective_manga','MANGA',175,21,null),  -- Girl From the Other Side (82)
('mystery_detective_manga','MANGA',374,22,null),  -- Shadows House (82)
('mystery_detective_manga','MANGA',519,23,null),  -- Case Closed / Detective Conan (82)
('mystery_detective_manga','MANGA',1212,24,null), -- Summit of the Gods (82)
('mystery_detective_manga','MANGA',81,25,null),   -- Hell's Paradise (81)
('mystery_detective_manga','MANGA',294,26,null),  -- My Dearest Self with Malice (81)
('mystery_detective_manga','MANGA',211,27,null),  -- Black Butler (81)
('mystery_detective_manga','MANGA',1907,28,null)  -- Don't Call it Mystery (83)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- music_performance_anime  (one per franchise, score >= 70)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('music_performance_anime','ANIME',271,1,null),   -- BOCCHI THE ROCK! (87)
('music_performance_anime','ANIME',2176,2,null),  -- Sound! Euphonium 3 (87)
('music_performance_anime','ANIME',2620,3,null),  -- Revue Starlight Movie (87)
('music_performance_anime','ANIME',338,4,null),   -- NANA (85)
('music_performance_anime','ANIME',23,5,null),    -- Your Lie in April (84)
('music_performance_anime','ANIME',1425,6,null),  -- Girls Band Cry (83)
('music_performance_anime','ANIME',1580,7,null),  -- Kono Oto Tomare! S2 (83)
('music_performance_anime','ANIME',13227,8,null), -- Blue Giant (83)
('music_performance_anime','ANIME',313,9,null),   -- given (82)
('music_performance_anime','ANIME',388,10,null),  -- Vivy: Fluorite Eye's Song (82)
('music_performance_anime','ANIME',2682,11,null), -- BanG Dream! MyGO!!!!! (82)
('music_performance_anime','ANIME',2930,12,null), -- Ave Mujica (81)
('music_performance_anime','ANIME',220,13,null),  -- K-ON! (78)
('music_performance_anime','ANIME',475,14,null),  -- Sound! Euphonium S1 (80)
('music_performance_anime','ANIME',866,15,null),  -- Ya Boy Kongming! (80)
('music_performance_anime','ANIME',921,16,null),  -- Kids on the Slope (80)
('music_performance_anime','ANIME',1103,17,null), -- Beck: Mongolian Chop Squad (80)
('music_performance_anime','ANIME',1401,18,null), -- Nodame Cantabile (80)
('music_performance_anime','ANIME',1625,19,null), -- Revue Starlight TV (77)
('music_performance_anime','ANIME',904,20,null),  -- Kono Oto Tomare! S1 (78)
('music_performance_anime','ANIME',2689,21,null), -- Inu-Oh (79)
('music_performance_anime','ANIME',1055,22,null), -- Doukyuusei (81)
('music_performance_anime','ANIME',15975,23,null) -- The Colors Within (78)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- music_performance_manga  (one per franchise, score >= 70)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('music_performance_manga','MANGA',140,1,null),   -- NANA (88)
('music_performance_manga','MANGA',370,2,null),   -- Kono Oto Tomare! (88)
('music_performance_manga','MANGA',270,3,null),   -- BECK (86)
('music_performance_manga','MANGA',884,4,null),   -- Blue Giant (84)
('music_performance_manga','MANGA',194,5,null),   -- Given (83)
('music_performance_manga','MANGA',1058,6,null),  -- SHIORI EXPERIENCE (83)
('music_performance_manga','MANGA',388,7,null),   -- Your Lie in April (82)
('music_performance_manga','MANGA',503,8,null),   -- Bocchi the Rock! (82)
('music_performance_manga','MANGA',1294,9,null),  -- Sakamichi no Apollon (82)
('music_performance_manga','MANGA',2101,10,null), -- Forest of Piano (82)
('music_performance_manga','MANGA',145,11,null),  -- Solanin (80)
('music_performance_manga','MANGA',1774,12,null), -- Nodame Cantabile (80)
('music_performance_manga','MANGA',306,13,null),  -- Whisper Me a Love Song (80)
('music_performance_manga','MANGA',1151,14,null), -- Me and the Devil Blues (79)
('music_performance_manga','MANGA',456,15,null),  -- Toki Doki (77)
('music_performance_manga','MANGA',3767,16,null), -- Detroit Metal City (76)
('music_performance_manga','MANGA',2108,17,null), -- Hello, Melancholic! (75)
('music_performance_manga','MANGA',1180,18,null), -- K-On! (74)
('music_performance_manga','MANGA',4065,19,null), -- Ya Boy Kongming! (73)
('music_performance_manga','MANGA',4895,20,null)  -- Let's Go Karaoke! (77)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- historical_anime  (one per franchise, score >= 72)
-- Note: no "Historical" AniList genre exists; curated by title.
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('historical_anime','ANIME',102,1,null),   -- Vinland Saga S1 (87)
('historical_anime','ANIME',2925,2,null),  -- Kingdom S4 (85)
('historical_anime','ANIME',222,3,null),   -- Samurai Champloo (84)
('historical_anime','ANIME',412,4,null),   -- Berserk 1997 (84)
('historical_anime','ANIME',336,5,null),   -- Grave of the Fireflies (83)
('historical_anime','ANIME',1495,6,null),  -- Showa Genroku Rakugo Shinju S2 (86)
('historical_anime','ANIME',1057,7,null),  -- Showa Genroku Rakugo Shinju S1 (84)
('historical_anime','ANIME',353,8,null),   -- Mushishi (85)
('historical_anime','ANIME',153,9,null),   -- Dororo (81)
('historical_anime','ANIME',557,10,null),  -- Golden Kamuy S1 (77)
('historical_anime','ANIME',994,11,null),  -- Rurouni Kenshin (79)
('historical_anime','ANIME',519,12,null),  -- Katanagatari (81)
('historical_anime','ANIME',992,13,null),  -- Rainbow (81)
('historical_anime','ANIME',841,14,null),  -- The Wind Rises (80)
('historical_anime','ANIME',2088,15,null), -- The Heike Story (76)
('historical_anime','ANIME',1780,16,null), -- Moribito: Guardian of the Spirit (79)
('historical_anime','ANIME',1415,17,null), -- Gankutsuou (79)
('historical_anime','ANIME',718,18,null),  -- DRIFTERS (75)
('historical_anime','ANIME',1166,19,null), -- Heroic Legend of Arslan (73)
('historical_anime','ANIME',1546,20,null)  -- Kingdom S1 (74)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- historical_manga  (one per franchise, score >= 72)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('historical_manga','MANGA',5,1,null),     -- Berserk (93)
('historical_manga','MANGA',14,2,null),    -- Vagabond (92)
('historical_manga','MANGA',16,3,null),    -- Vinland Saga (90)
('historical_manga','MANGA',97,4,null),    -- Kingdom (89)
('historical_manga','MANGA',155,5,null),   -- Golden Kamuy (86)
('historical_manga','MANGA',273,6,null),   -- Blade of the Immortal (83)
('historical_manga','MANGA',716,7,null),   -- Innocent Rouge (83)
('historical_manga','MANGA',322,8,null),   -- Rurouni Kenshin (82)
('historical_manga','MANGA',258,9,null),   -- Innocent (81)
('historical_manga','MANGA',2176,10,null), -- Altair: Record of Battles (76)
('historical_manga','MANGA',4066,11,null), -- Cesare (76)
('historical_manga','MANGA',925,12,null),  -- Drifters (75)
('historical_manga','MANGA',1365,13,null), -- Heroic Legend of Arslan (75)
('historical_manga','MANGA',5209,14,null), -- Nobunaga no Chef (73)
('historical_manga','MANGA',300,15,null)   -- Mushishi (85)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- school_anime  (one per franchise, score >= 74)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('school_anime','ANIME',402,1,null),   -- Fruits Basket: The Final (89)
('school_anime','ANIME',537,2,null),   -- March comes in like a lion S2 (89)
('school_anime','ANIME',16,3,null),    -- A Silent Voice (88)
('school_anime','ANIME',300,4,null),   -- Clannad: After Story (87)
('school_anime','ANIME',154,5,null),   -- Assassination Classroom S2 (83)
('school_anime','ANIME',270,6,null),   -- Nichijou (83)
('school_anime','ANIME',311,7,null),   -- March comes in like a lion S1 (83)
('school_anime','ANIME',308,8,null),   -- Oregairu S3 (82)
('school_anime','ANIME',760,9,null),   -- Skip and Loafer (81)
('school_anime','ANIME',794,10,null),  -- Blue Box (81)
('school_anime','ANIME',848,11,null),  -- Whisper of the Heart (81)
('school_anime','ANIME',138,12,null),  -- Anohana (80)
('school_anime','ANIME',340,13,null),  -- Daily Lives of High School Boys (80)
('school_anime','ANIME',243,14,null),  -- Ouran High School Host Club (80)
('school_anime','ANIME',162,15,null),  -- Hyouka (79)
('school_anime','ANIME',21,16,null),   -- Assassination Classroom S1 (79)
('school_anime','ANIME',96,17,null),   -- Toradora! (78)
('school_anime','ANIME',122,18,null),  -- Angel Beats! (77)
('school_anime','ANIME',203,19,null),  -- Clannad (77)
('school_anime','ANIME',325,20,null),  -- Melancholy of Haruhi Suzumiya (76)
('school_anime','ANIME',917,21,null),  -- Insomniacs After School (80)
('school_anime','ANIME',881,22,null),  -- Azumanga Daioh (79)
('school_anime','ANIME',888,23,null),  -- School Babysitters (78)
('school_anime','ANIME',733,24,null),  -- SCHOOL-LIVE! (74)
('school_anime','ANIME',1787,25,null)  -- Wasteful Days of High School Girls (74)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- school_manga  (one per franchise, score >= 72)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('school_manga','MANGA',83,1,null),    -- A Silent Voice (87)
('school_manga','MANGA',277,2,null),   -- Skip and Loafer (86)
('school_manga','MANGA',253,3,null),   -- March Comes in Like a Lion (88)
('school_manga','MANGA',732,4,null),   -- Nichijou (83)
('school_manga','MANGA',500,5,null),   -- Azumanga Daioh (82)
('school_manga','MANGA',139,6,null),   -- Assassination Classroom (81)
('school_manga','MANGA',152,7,null),   -- Blue Box (81)
('school_manga','MANGA',1282,8,null),  -- Daily Lives of High School Boys (80)
('school_manga','MANGA',1629,9,null),  -- Hyouka (78)
('school_manga','MANGA',1182,10,null), -- Toradora! (77)
('school_manga','MANGA',2599,11,null), -- Oregairu Monologue (78)
('school_manga','MANGA',240,12,null),  -- Fruits Basket (84)
('school_manga','MANGA',292,13,null),  -- Ouran High School Host Club (82)
('school_manga','MANGA',226,14,null),  -- Kimi ni Todoke (82)
('school_manga','MANGA',2912,15,null)  -- Angel Beats! Heaven's Door (75)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- shoujo_josei_anime  (one per franchise, score >= 72)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('shoujo_josei_anime','ANIME',402,1,null),   -- Fruits Basket: The Final (89)
('shoujo_josei_anime','ANIME',338,2,null),   -- NANA (85)
('shoujo_josei_anime','ANIME',1653,3,null),  -- Natsume Yuujinchou S4 (85)
('shoujo_josei_anime','ANIME',1753,4,null),  -- Chihayafuru 3 (85)
('shoujo_josei_anime','ANIME',800,5,null),   -- Madoka Magica Rebellion (84)
('shoujo_josei_anime','ANIME',1877,6,null),  -- Kimi ni Todoke S3 (84)
('shoujo_josei_anime','ANIME',180,7,null),   -- Puella Magi Madoka Magica (83)
('shoujo_josei_anime','ANIME',184,8,null),   -- BANANA FISH (82)
('shoujo_josei_anime','ANIME',1738,9,null),  -- Princess Tutu (81)
('shoujo_josei_anime','ANIME',2168,10,null), -- Rose of Versailles (81)
('shoujo_josei_anime','ANIME',243,11,null),  -- Ouran High School Host Club (80)
('shoujo_josei_anime','ANIME',751,12,null),  -- Chihayafuru S1 (80)
('shoujo_josei_anime','ANIME',892,13,null),  -- Cardcaptor Sakura (80)
('shoujo_josei_anime','ANIME',312,14,null),  -- Yona of the Dawn (79)
('shoujo_josei_anime','ANIME',273,15,null),  -- Kimi ni Todoke S1 (79)
('shoujo_josei_anime','ANIME',1779,16,null), -- Skip Beat! (77)
('shoujo_josei_anime','ANIME',869,17,null),  -- Sailor Moon (76)
('shoujo_josei_anime','ANIME',537,18,null),  -- March comes in like a lion S2 (89)
('shoujo_josei_anime','ANIME',1057,19,null), -- Showa Genroku Rakugo Shinju (84)
('shoujo_josei_anime','ANIME',760,20,null),  -- Skip and Loafer (81)
('shoujo_josei_anime','ANIME',730,21,null),  -- Natsume Yuujinchou S1 (80)
('shoujo_josei_anime','ANIME',23,22,null),   -- Your Lie in April (84)
('shoujo_josei_anime','ANIME',96,23,null),   -- Toradora! (78)
('shoujo_josei_anime','ANIME',271,24,null),  -- BOCCHI THE ROCK! (87)
('shoujo_josei_anime','ANIME',848,25,null)   -- Whisper of the Heart (81)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
-- ============================================================
-- shoujo_josei_manga  (one per franchise, score >= 72)
-- ============================================================
insert into public.curated_rail_items(rail_id,media_type,anilist_id,rank,note) values
('shoujo_josei_manga','MANGA',253,1,null),   -- March Comes in Like a Lion (88)
('shoujo_josei_manga','MANGA',140,2,null),   -- NANA (88)
('shoujo_josei_manga','MANGA',146,3,null),   -- Yona of the Dawn (87)
('shoujo_josei_manga','MANGA',386,4,null),   -- Chihayafuru (86)
('shoujo_josei_manga','MANGA',920,5,null),   -- Natsume's Book of Friends (85)
('shoujo_josei_manga','MANGA',240,6,null),   -- Fruits Basket (84)
('shoujo_josei_manga','MANGA',285,7,null),   -- Banana Fish (84)
('shoujo_josei_manga','MANGA',83,8,null),    -- A Silent Voice (87)
('shoujo_josei_manga','MANGA',226,9,null),   -- Kimi ni Todoke (82)
('shoujo_josei_manga','MANGA',292,10,null),  -- Ouran High School Host Club (82)
('shoujo_josei_manga','MANGA',761,11,null),  -- Skip Beat! (82)
('shoujo_josei_manga','MANGA',152,12,null),  -- Blue Box (81)
('shoujo_josei_manga','MANGA',485,13,null),  -- Cardcaptor Sakura (81)
('shoujo_josei_manga','MANGA',1774,14,null), -- Nodame Cantabile (80)
('shoujo_josei_manga','MANGA',506,15,null),  -- Sailor Moon (79)
('shoujo_josei_manga','MANGA',1097,16,null), -- My Love Story!! (79)
('shoujo_josei_manga','MANGA',1423,17,null), -- Honey and Clover (79)
('shoujo_josei_manga','MANGA',277,18,null),  -- Skip and Loafer (86)
('shoujo_josei_manga','MANGA',194,19,null),  -- Given (83)
('shoujo_josei_manga','MANGA',145,20,null)   -- Solanin (80)
on conflict (rail_id, media_type, anilist_id) do update set rank = excluded.rank, note = excluded.note;
commit;
