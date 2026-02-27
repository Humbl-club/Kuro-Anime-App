
-- ============================================================
-- Phase 0 Dedup Backfill: Remove cross-rail overlap from
-- premium_picks_anime, premium_picks_manga, short_one_season_anime
-- and replace with unique titles
-- ============================================================

-- 1. Remove premium_picks_anime items that overlap with gateway_anime
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
  AND anilist_id IN (
    SELECT cri.anilist_id
    FROM curated_rail_items cri
    WHERE cri.rail_id = 'premium_picks_anime' AND cri.media_type = 'ANIME'
      AND EXISTS (
        SELECT 1 FROM curated_rail_items g
        WHERE g.anilist_id = cri.anilist_id AND g.media_type = 'ANIME'
          AND g.rail_id = 'gateway_anime'
      )
  );

-- 2. Remove premium_picks_anime items that overlap with classics_anime
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_anime' AND media_type = 'ANIME'
  AND anilist_id IN (
    SELECT cri.anilist_id
    FROM curated_rail_items cri
    WHERE cri.rail_id = 'premium_picks_anime' AND cri.media_type = 'ANIME'
      AND EXISTS (
        SELECT 1 FROM curated_rail_items g
        WHERE g.anilist_id = cri.anilist_id AND g.media_type = 'ANIME'
          AND g.rail_id = 'classics_anime'
      )
  );

-- 3. Remove premium_picks_manga items that overlap with gateway_manga
DELETE FROM curated_rail_items
WHERE rail_id = 'premium_picks_manga' AND media_type = 'MANGA'
  AND anilist_id IN (
    SELECT cri.anilist_id
    FROM curated_rail_items cri
    WHERE cri.rail_id = 'premium_picks_manga' AND cri.media_type = 'MANGA'
      AND EXISTS (
        SELECT 1 FROM curated_rail_items g
        WHERE g.anilist_id = cri.anilist_id AND g.media_type = 'MANGA'
          AND g.rail_id = 'gateway_manga'
      )
  );

-- 4. Remove short_one_season_anime items that overlap with gateway_anime
DELETE FROM curated_rail_items
WHERE rail_id = 'short_one_season_anime' AND media_type = 'ANIME'
  AND anilist_id IN (
    SELECT cri.anilist_id
    FROM curated_rail_items cri
    WHERE cri.rail_id = 'short_one_season_anime' AND cri.media_type = 'ANIME'
      AND EXISTS (
        SELECT 1 FROM curated_rail_items g
        WHERE g.anilist_id = cri.anilist_id AND g.media_type = 'ANIME'
          AND g.rail_id = 'gateway_anime'
      )
  );

-- 5. Now add unique replacement titles to premium_picks_anime
--    These are prestige/auteur titles NOT in gateway, classics, or other major rails
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('premium_picks_anime', 'ANIME', 20972,  50, 'Showa Genroku Rakugo Shinju - rakugo performance drama, one of the most adult anime ever made'),
('premium_picks_anime', 'ANIME', 113717, 51, 'Ranking of Kings - deceptive fairy tale that becomes a profound story about strength'),
('premium_picks_anime', 'ANIME', 164212, 52, 'Girls Band Cry - raw music drama with revolutionary CG animation'),
('premium_picks_anime', 'ANIME', 20812,  53, 'SHIROBAKO - love letter to the anime industry, funny and heartfelt'),
('premium_picks_anime', 'ANIME', 10271,  54, 'Kaiji Against All Rules - gambling psychological thriller, second season excellence'),
('premium_picks_anime', 'ANIME', 108465, 55, 'Mushoku Tensei - isekai elevated to literary character study'),
('premium_picks_anime', 'ANIME', 21733,  56, 'Rakugo S2 - continuation of the definitive adult drama anime'),
('premium_picks_anime', 'ANIME', 166216, 57, 'The Dangers in My Heart S2 - tender adolescent romance, masterful character work'),
('premium_picks_anime', 'ANIME', 5,      58, 'Cowboy Bebop: Knockin on Heaven''s Door - standalone film noir in the Bebop universe'),
('premium_picks_anime', 'ANIME', 101903, 59, 'Run with the Wind - Kazetsuyo, university ekiden running, genuine camaraderie')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- 6. Add unique replacement titles to premium_picks_manga
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('premium_picks_manga', 'MANGA', 30756,  50, 'Banana Fish - Yoshida''s crime-action masterpiece, raw and unforgettable'),
('premium_picks_manga', 'MANGA', 30660,  51, 'The Rose of Versailles - Ikeda''s revolutionary shoujo, French Revolution drama'),
('premium_picks_manga', 'MANGA', 74307,  52, 'Blank Canvas - Higashimura''s memoir about her art teacher, moving and honest'),
('premium_picks_manga', 'MANGA', 47051,  53, 'Barakamon - calligrapher on a rural island, gentle comedy with heart'),
('premium_picks_manga', 'MANGA', 55096,  54, 'Silver Spoon - Arakawa''s agricultural school comedy, warm and grounded'),
('premium_picks_manga', 'MANGA', 33082,  55, 'Nichijou manga - absurdist comedy perfected, Arawi''s visual gags'),
('premium_picks_manga', 'MANGA', 149544, 56, 'The Guy She Was Interested In Wasn''t a Guy at All - viral yuri with great chemistry'),
('premium_picks_manga', 'MANGA', 98544,  57, 'Moriarty the Patriot - Conan Doyle reimagined as class warfare thriller'),
('premium_picks_manga', 'MANGA', 87217,  58, 'Innocent Rouge - French Revolution through Sanson''s executioner dynasty, Sakamoto art'),
('premium_picks_manga', 'MANGA', 108251, 59, 'Would You Marry Me Again If You Were Reborn? - elderly couple romance, devastating'),
('premium_picks_manga', 'MANGA', 36812,  60, 'Kyou kara Ore wa!! - delinquent comedy classic, Nishimori at his best'),
('premium_picks_manga', 'MANGA', 132144, 61, 'Return of the Blossoming Blade - Korean martial arts manhwa with gorgeous art'),
('premium_picks_manga', 'MANGA', 48200,  62, 'Classmates (Sotsugyousei) - BL romance with quiet emotional realism'),
('premium_picks_manga', 'MANGA', 58393,  63, 'Sakamichi no Apollon manga - jazz in 1960s Kyushu, Watanabe adapted this'),
('premium_picks_manga', 'MANGA', 36164,  64, 'My Girl - single father raising daughter after lover''s death, gentle tearjerker'),
('premium_picks_manga', 'MANGA', 105747, 65, 'I Had That Same Dream Again - Sumino''s interconnected magical realism'),
('premium_picks_manga', 'MANGA', 67707,  66, 'Your Lie in April manga - the source material, deeply felt musician romance'),
('premium_picks_manga', 'MANGA', 104677, 67, 'Her Tale of Shim Chong - Korean folklore retold as gorgeous historical manhwa')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- 7. Add unique replacement titles to short_one_season_anime
INSERT INTO curated_rail_items (rail_id, media_type, anilist_id, rank, note) VALUES
('short_one_season_anime', 'ANIME', 20972,  50, 'Showa Genroku Rakugo Shinju - 13-episode adult drama'),
('short_one_season_anime', 'ANIME', 113717, 51, 'Ranking of Kings - 23-episode fairy tale with depth'),
('short_one_season_anime', 'ANIME', 164212, 52, 'Girls Band Cry - 13-episode music drama'),
('short_one_season_anime', 'ANIME', 20812,  53, 'SHIROBAKO - 24-episode anime industry drama'),
('short_one_season_anime', 'ANIME', 108465, 54, 'Mushoku Tensei S1 - 11-episode isekai character study'),
('short_one_season_anime', 'ANIME', 166216, 55, 'Dangers in My Heart S2 - 13-episode teen romance'),
('short_one_season_anime', 'ANIME', 101903, 56, 'Run with the Wind - 23-episode running team drama')
ON CONFLICT (rail_id, media_type, anilist_id) DO NOTHING;

-- 8. Re-rank all affected rails
WITH ranked AS (
  SELECT rail_id, media_type, anilist_id,
         ROW_NUMBER() OVER (PARTITION BY rail_id, media_type ORDER BY rank) AS new_rank
  FROM curated_rail_items
  WHERE (rail_id = 'premium_picks_anime' AND media_type = 'ANIME')
     OR (rail_id = 'premium_picks_manga' AND media_type = 'MANGA')
     OR (rail_id = 'short_one_season_anime' AND media_type = 'ANIME')
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
