-- OWNER_BLESS_REQUIRED — DO NOT APPLY.
-- Draft seed for the future critic_sources registry (table itself ships with the
-- Round 2 migration, only after the owner blesses sites + titles; plan §5).
-- Uncommenting and applying this file IS the blessing act — owner-only.
--
-- Tiers per dossiers in reports/critique-pilot/dossiers/ (2026-08-05 scouting).
-- Weighting downstream: A x1.0, B x0.8, C x0.6 (plan §5 Round 2).

-- insert into public.critic_sources (slug, name, url, lang, covers, tier, lens, robots_posture, blessed_at) values
--   ('ann-review-desk',   'Anime News Network — review desk', 'https://www.animenewsnetwork.com/reviews/', 'en', 'both',  'B', 'named-critic long-form',        'permissive (crawl-delay 2); attributed excerpts permitted', now()),
--   ('wrong-every-time',  'Wrong Every Time (Nick Creamer)',  'https://wrongeverytime.com/',              'en', 'anime', 'B', 'individual critic, craft+theme','permissive + sitemaps',                                      now()),
--   ('manga-bookshelf',   'Manga Bookshelf',                  'https://mangabookshelf.com/',              'en', 'manga', 'C', 'manga-first desk',              'permissive + sitemaps',                                      now()),
--   ('fujitsu-anime-mon', '藤津亮太のアニメの門V',              'https://animeanime.jp/',                   'ja', 'anime', 'B', 'real-name JP critic essays',    'ClaudeBot explicitly permitted (crawl-delay 5)',             now());

-- Alternate (owner call — dormant archive, permissive):
--   ('mangasplaining',    'Mangasplaining',                   'https://www.mangasplaining.com/',          'en', 'manga', 'C', 'manga-first podcast show-notes','permissive (crawl-delay 10); DORMANT since 2025-06',         now());

-- NEVER add without a dossier + explicit robots clearance:
--   Sakuga Blog / THEM / Anime Feminist / マンバ通信 / Filmarks / コミックナタリー — see dossiers/README.md exclusions.
