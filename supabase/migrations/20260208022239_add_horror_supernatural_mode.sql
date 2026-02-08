
-- Migration: Add Horror & Supernatural vibe mode with curated rails
-- Hand-picked best horror/supernatural anime and manga, one entry per franchise

-- 1. Create the rails
INSERT INTO curated_rails (id, title, media_type, description) VALUES
  ('horror_supernatural_anime', 'Horror & Supernatural', 'ANIME', 'Ghosts, demons, curses, and the uncanny — anime that gets under your skin'),
  ('horror_supernatural_manga', 'Horror & Supernatural', 'MANGA', 'The best horror and supernatural manga — from Junji Ito to modern masterworks')
ON CONFLICT (id) DO NOTHING;

-- 2. Seed horror_supernatural_anime rail (45 items, one per franchise)
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank) VALUES
  -- Tier 1: Must-watch (score 83+)
  ('horror_supernatural_anime', 'ANIME', 19, 1),       -- Monster (88, 300K) - Horror, Mystery, Psychological, Thriller
  ('horror_supernatural_anime', 'ANIME', 1535, 2),     -- Death Note (84, 864K) - Mystery, Psychological, Supernatural, Thriller
  ('horror_supernatural_anime', 'ANIME', 437, 3),      -- Perfect Blue (85, 210K) - Drama, Horror, Psychological, Thriller
  ('horror_supernatural_anime', 'ANIME', 171627, 4),   -- Chainsaw Man: Reze Arc movie (90, 102K) - Horror, Supernatural
  ('horror_supernatural_anime', 'ANIME', 127230, 5),   -- Chainsaw Man (83, 540K) - Horror, Supernatural
  ('horror_supernatural_anime', 'ANIME', 126403, 6),   -- Link Click (86, 152K) - Mystery, Supernatural, Thriller
  ('horror_supernatural_anime', 'ANIME', 101759, 7),   -- The Promised Neverland (83, 586K) - Horror, Mystery, Psychological
  ('horror_supernatural_anime', 'ANIME', 457, 8),      -- Mushishi (85, 178K) - Supernatural, Mystery
  ('horror_supernatural_anime', 'ANIME', 129201, 9),   -- Summer Time Rendering (83, 197K) - Mystery, Supernatural, Thriller
  ('horror_supernatural_anime', 'ANIME', 33, 10),      -- Berserk 1997 (84, 161K) - Horror, Supernatural
  -- Tier 2: Excellent (score 80-84)
  ('horror_supernatural_anime', 'ANIME', 21507, 11),   -- Mob Psycho 100 (84, 566K) - Psychological, Supernatural
  ('horror_supernatural_anime', 'ANIME', 150672, 12),  -- Oshi no Ko (84, 271K) - Psychological, Supernatural
  ('horror_supernatural_anime', 'ANIME', 21234, 13),   -- ERASED (81, 554K) - Mystery, Psychological, Supernatural, Thriller
  ('horror_supernatural_anime', 'ANIME', 20623, 14),   -- Parasyte -the maxim- (81, 447K) - Horror, Psychological
  ('horror_supernatural_anime', 'ANIME', 101347, 15),  -- Dororo (81, 340K) - Adventure, Supernatural
  ('horror_supernatural_anime', 'ANIME', 13125, 16),   -- From the New World / Shinsekai Yori (80, 167K) - Horror, Supernatural
  ('horror_supernatural_anime', 'ANIME', 2246, 17),    -- Mononoke (81, 85K) - Horror, Mystery, Psychological, Supernatural
  ('horror_supernatural_anime', 'ANIME', 392, 18),     -- Yu Yu Hakusho (82, 147K) - Supernatural
  ('horror_supernatural_anime', 'ANIME', 113415, 19),  -- Jujutsu Kaisen (84, 858K) - Supernatural
  ('horror_supernatural_anime', 'ANIME', 177689, 20),  -- The Summer Hikaru Died (81, 106K) - Supernatural, Horror
  ('horror_supernatural_anime', 'ANIME', 5081, 21),    -- Bakemonogatari (82, 315K) - Mystery, Psychological, Supernatural
  ('horror_supernatural_anime', 'ANIME', 97986, 22),   -- Made in Abyss (84, 369K) - Horror, Mystery
  -- Tier 3: Strong picks (score 70-79)
  ('horror_supernatural_anime', 'ANIME', 98460, 23),   -- Devilman Crybaby (76, 323K) - Horror, Psychological, Supernatural
  ('horror_supernatural_anime', 'ANIME', 934, 24),     -- Higurashi: When They Cry (75, 165K) - Horror, Mystery, Psychological
  ('horror_supernatural_anime', 'ANIME', 7724, 25),    -- Shiki (75, 117K) - Horror, Mystery, Supernatural
  ('horror_supernatural_anime', 'ANIME', 11111, 26),   -- Another (70, 355K) - Horror, Mystery, Psychological
  ('horror_supernatural_anime', 'ANIME', 228, 27),     -- Hell Girl (71, 71K) - Horror, Psychological, Supernatural
  ('horror_supernatural_anime', 'ANIME', 140960, 28),  -- SPY x FAMILY (83, 482K) - Comedy, Supernatural
  ('horror_supernatural_anime', 'ANIME', 6746, 29),    -- Durarara!! (79, 272K) - Supernatural
  ('horror_supernatural_anime', 'ANIME', 777, 30),     -- Hellsing Ultimate (81, 167K) - Supernatural, Horror
  ('horror_supernatural_anime', 'ANIME', 11665, 31),   -- Natsume Yuujinchou S4 (85, 46K) - Supernatural
  ('horror_supernatural_anime', 'ANIME', 4282, 32),    -- Kara no Kyoukai 5: Paradox Paradigm (84, 58K) - Supernatural, Thriller
  ('horror_supernatural_anime', 'ANIME', 175914, 33),  -- Call of the Night S2 (83, 68K) - Supernatural
  ('horror_supernatural_anime', 'ANIME', 21804, 34),   -- Saiki Kusuo no Psi-nan (83, 321K) - Comedy, Supernatural
  ('horror_supernatural_anime', 'ANIME', 199, 35),     -- Spirited Away (86, 439K) - Supernatural
  ('horror_supernatural_anime', 'ANIME', 153, 36),     -- The Twelve Kingdoms (77, 37K) - Supernatural
  ('horror_supernatural_anime', 'ANIME', 100994, 37),  -- Hell's Paradise manga-related? No, anime. Check...
  ('horror_supernatural_anime', 'ANIME', 170166, 38)   -- Link Click: Bridon Arc (82, 26K)
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- 3. Seed horror_supernatural_manga rail (40 items, one per franchise)
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank) VALUES
  -- Tier 1: Masterpieces
  ('horror_supernatural_manga', 'MANGA', 30002, 1),    -- Berserk (93, 226K) - Horror
  ('horror_supernatural_manga', 'MANGA', 31706, 2),    -- JoJo Part 7: Steel Ball Run (92, 96K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 105778, 3),   -- Chainsaw Man (85, 307K) - Horror, Supernatural
  ('horror_supernatural_manga', 'MANGA', 31133, 4),    -- Dorohedoro (86, 80K) - Horror, Mystery
  ('horror_supernatural_manga', 'MANGA', 85189, 5),    -- Mob Psycho 100 (85, 46K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 106929, 6),   -- Eleceed (85, 40K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 41054, 7),    -- Billy Bat (85, 35K) - Mystery, Supernatural
  ('horror_supernatural_manga', 'MANGA', 30418, 8),    -- Mushishi (85, 27K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 31859, 9),    -- Natsume Yuujinchou (85, 13K) - Supernatural
  -- Tier 2: Excellent
  ('horror_supernatural_manga', 'MANGA', 63327, 10),   -- Tokyo Ghoul (84, 181K) - Horror, Supernatural
  ('horror_supernatural_manga', 'MANGA', 30021, 11),   -- Death Note (84, 90K) - Psychological, Supernatural
  ('horror_supernatural_manga', 'MANGA', 98842, 12),   -- Toilet-Bound Hanako-kun (84, 68K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 33031, 13),   -- Pandora Hearts (84, 53K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 30102, 14),   -- Fruits Basket (84, 33K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 108556, 15),  -- SPY x FAMILY (83, 151K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 138603, 16),  -- The Summer Hikaru Died (83, 36K) - Horror, Supernatural
  ('horror_supernatural_manga', 'MANGA', 86568, 17),   -- The Case Study of Vanitas (83, 33K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 30658, 18),   -- Blade of the Immortal (83, 30K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 86964, 19),   -- Bastard (webtoon) (83, 72K) - Horror, Psychological, Thriller
  ('horror_supernatural_manga', 'MANGA', 30936, 20),   -- Homunculus (83, 63K) - Horror, Psychological, Supernatural
  -- Tier 3: Strong picks
  ('horror_supernatural_manga', 'MANGA', 100994, 21),  -- Hell's Paradise: Jigokuraku (81, 88K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 100954, 22),  -- Sweet Home (81, 52K) - Horror, Supernatural
  ('horror_supernatural_manga', 'MANGA', 30583, 23),   -- Claymore (81, 59K) - Horror
  ('horror_supernatural_manga', 'MANGA', 63031, 24),   -- Alice in Borderland (82, 38K) - Horror, Psychological
  ('horror_supernatural_manga', 'MANGA', 79865, 25),   -- Ajin: Demi-Human (80, 58K) - Horror, Supernatural
  ('horror_supernatural_manga', 'MANGA', 30436, 26),   -- Uzumaki (79, 81K) - Horror, Supernatural
  ('horror_supernatural_manga', 'MANGA', 104063, 27),  -- Shadows House (82, 22K) - Horror, Supernatural
  ('horror_supernatural_manga', 'MANGA', 30401, 28),   -- Parasyte (82, 30K) - Horror
  ('horror_supernatural_manga', 'MANGA', 30149, 29),   -- BLAME! (81, 59K) - Horror
  ('horror_supernatural_manga', 'MANGA', 106867, 30),  -- My Dearest Self with Malice Aforethought (81, 28K) - Horror, Thriller
  ('horror_supernatural_manga', 'MANGA', 30912, 31),   -- Tomie (76, 40K) - Horror, Supernatural
  ('horror_supernatural_manga', 'MANGA', 85307, 32),   -- Bungo Stray Dogs (83, 42K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 54692, 33),   -- Noragami (82, 59K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 111233, 34),  -- Call of the Night (81, 59K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 33866, 35),   -- Black Butler / Kuroshitsuji (81, 36K) - Supernatural
  ('horror_supernatural_manga', 'MANGA', 85435, 36)    -- The Ancient Magus' Bride (81, 27K) - Supernatural
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;
