-- curation_sources_expand_v1
-- Research: docs/superpowers/specs/2026-08-02-curation-sources-research.md
-- Adds Tier-A canon (日本漫画家協会賞, Annecy expansion, Manga Taishō ≥80 nominees,
-- Kono Manga #2/#3) + curation_seasonal_signal (Filmarks / 次にくる / EN desks).
-- Splits opaque Critic Consensus into named desks; renames Annecy Cristal → Annecy.
-- Wires seasonal boost into fetch_realm_hidden_gem (still feature-flagged at 0%).

-- ---------------------------------------------------------------------------
-- 1) Rename Annecy Cristal → Annecy (broader prize categories)
-- ---------------------------------------------------------------------------
update public.canon_seed
set source = 'Annecy'
where source = 'Annecy Cristal';

-- ---------------------------------------------------------------------------
-- 2) Split Critic Consensus into named desks (citeable Tier-B→A soft)
-- ---------------------------------------------------------------------------
-- Paste Magazine
insert into public.canon_seed (media_type, media_id, title, source, source_detail, year, category, blessed)
select media_type, media_id, title, 'Paste Magazine', source_detail, year, category, true
from public.canon_seed
where source = 'Critic Consensus'
  and source_detail ilike '%Paste%'
on conflict (media_type, media_id, source, category) do nothing;

-- Time Out
insert into public.canon_seed (media_type, media_id, title, source, source_detail, year, category, blessed)
select media_type, media_id, title, 'Time Out', source_detail, year, category, true
from public.canon_seed
where source = 'Critic Consensus'
  and source_detail ilike '%Time Out%'
on conflict (media_type, media_id, source, category) do nothing;

-- The A.V. Club
insert into public.canon_seed (media_type, media_id, title, source, source_detail, year, category, blessed)
select media_type, media_id, title, 'The A.V. Club', source_detail, year, category, true
from public.canon_seed
where source = 'Critic Consensus'
  and source_detail ilike '%A.V. Club%'
on conflict (media_type, media_id, source, category) do nothing;

-- Drop opaque Critic Consensus after named-desk split (matview still forces
-- canon from every canon_seed row; blessing alone is not enough).
delete from public.canon_seed
where source = 'Critic Consensus';

-- ---------------------------------------------------------------------------
-- 3) New Tier-A canon rows
-- ---------------------------------------------------------------------------
insert into public.canon_seed
  (media_type, media_id, title, source, source_detail, year, category, blessed)
values
  ('MANGA', 13, 'SPY x FAMILY', 'Japan Cartoonists Association Award', '第52回（2023）大賞コミック部門 · https://nihonmangakakyokai.or.jp/about/about07', 2023, 'Grand Prize — Comic (2023)', true),
  ('MANGA', 155, 'Golden Kamuy', 'Japan Cartoonists Association Award', '第51回（2022）大賞コミック部門 · https://nihonmangakakyokai.or.jp/about/about07', 2022, 'Grand Prize — Comic (2022)', true),
  ('MANGA', 8, 'Demon Slayer: Kimetsu no Yaiba', 'Japan Cartoonists Association Award', '第50回（2021）大賞コミック部門 · https://nihonmangakakyokai.or.jp/about/about07', 2021, 'Grand Prize — Comic (2021)', true),
  ('MANGA', 30294, 'Areyo Hoshikuzu', 'Japan Cartoonists Association Award', '第48回（2019）大賞コミック部門 · https://nihonmangakakyokai.or.jp/about/about07', 2019, 'Grand Prize — Comic (2019)', true),
  ('MANGA', 2063, 'My Brother''s Husband', 'Japan Cartoonists Association Award', '第47回（2018）優秀賞 · https://nihonmangakakyokai.or.jp/about/about07', 2018, 'Excellence Award (2018)', true),
  ('MANGA', 26569, 'Peleliu: Rakuen no Guernica', 'Japan Cartoonists Association Award', '第46回（2017）優秀賞 · https://nihonmangakakyokai.or.jp/about/about07', 2017, 'Excellence Award (2017)', true),
  ('MANGA', 7, 'One Piece', 'Japan Cartoonists Association Award', '第41回（2012）大賞 · https://nihonmangakakyokai.or.jp/about/about07', 2012, 'Grand Prize (2012)', true),
  ('MANGA', 7827, 'Shinya Shokudou', 'Japan Cartoonists Association Award', '第39回（2010）大賞 · https://nihonmangakakyokai.or.jp/about/about07', 2010, 'Grand Prize (2010)', true),
  ('MANGA', 1265, 'Children of the Sea', 'Japan Cartoonists Association Award', '第38回（2009）優秀賞 · https://nihonmangakakyokai.or.jp/about/about07', 2009, 'Excellence Award (2009)', true),
  ('MANGA', 30, '20th Century Boys', 'Japan Cartoonists Association Award', '第37回（2008）大賞 · https://nihonmangakakyokai.or.jp/about/about07', 2008, 'Grand Prize (2008)', true),
  ('MANGA', 3814, 'Give My Regards to Black Jack', 'Japan Cartoonists Association Award', '第33回（2004）大賞 · https://nihonmangakakyokai.or.jp/about/about07', 2004, 'Grand Prize (2004)', true),
  ('MANGA', 18064, 'Golgo 13', 'Japan Cartoonists Association Award', '第31回（2002）大賞 · https://nihonmangakakyokai.or.jp/about/about07', 2002, 'Grand Prize (2002)', true),
  ('MANGA', 9460, 'Kochira Katsushikaku Kameari Kouenmae Hashutsujo', 'Japan Cartoonists Association Award', '第30回（2001）大賞 · https://nihonmangakakyokai.or.jp/about/about07', 2001, 'Grand Prize (2001)', true),
  ('MANGA', 427, 'Nausicaä of the Valley of the Wind', 'Japan Cartoonists Association Award', '第23回（1994）大賞 · https://nihonmangakakyokai.or.jp/about/about07', 1994, 'Grand Prize (1994)', true),
  ('MANGA', 132, 'Made in Abyss', 'Japan Cartoonists Association Award', '第52回（2023）まんが王国とっとり賞 · https://nihonmangakakyokai.or.jp/about/about07', 2023, 'Tottori Manga Kingdom Award (2023)', true),
  ('MANGA', 301, 'Takopi''s Original Sin', 'Japan Cartoonists Association Award', '第51回（2022）まんが王国とっとり賞 · https://nihonmangakakyokai.or.jp/about/about07', 2022, 'Tottori Manga Kingdom Award (2022)', true),
  ('MANGA', 9410, 'Sensou wa Onna no Kao wo Shiteinai', 'Japan Cartoonists Association Award', '第50回（2021）まんが王国とっとり賞 · https://nihonmangakakyokai.or.jp/about/about07', 2021, 'Tottori Manga Kingdom Award (2021)', true),
  ('MANGA', 11331, 'Chiikawa: Nanka Chiisakute Kawaii Yatsu', 'Japan Cartoonists Association Award', '第53回（2024）大賞萬画部門 · https://nihonmangakakyokai.or.jp/about/about07', 2024, 'Grand Prize — Manga (萬画) (2024)', true),
  ('MANGA', 6697, 'A Witch''s Life in Mongol', 'Japan Cartoonists Association Award', '第55回（2026）大賞コミック部門 · https://nihonmangakakyokai.or.jp/archives/news/20260414', 2026, 'Grand Prize — Comic (2026)', true),
  ('MANGA', 11737, 'Hoshitabi Shounen', 'Japan Cartoonists Association Award', '第54回（2025）大賞萬画部門 · https://nihonmangakakyokai.or.jp/about/about07', 2025, 'Grand Prize — Manga (萬画) (2025)', true),
  ('MANGA', 5134, 'Lupin the 3rd', 'Japan Cartoonists Association Award', '第49回（2020）文部科学大臣賞 · https://nihonmangakakyokai.or.jp/about/about07', 2020, 'Minister of Education Award (2020)', true),
  ('ANIME', 390, 'The Girl Who Leapt Through Time', 'Annecy', 'Annecy 2007 — Special Distinction / Jury · https://www.animenewsnetwork.com/news/2007-06/the-girl-who-leapt-through-time-picks-up-another-award', 2007, 'Jury Award — Feature Film (2007)', true),
  ('ANIME', 1506, 'Colorful ~ The Motion Picture', 'Annecy', 'Annecy 2011 — Special Distinction · https://www.animenewsnetwork.com/news/2011-06-11/keiichi-hara-colorful-anime-film-wins-2-at-annecy-fest', 2011, 'Jury Award — Feature Film (2011)', true),
  ('ANIME', 4105, 'Miss Hokusai', 'Annecy', 'Annecy 2015 — Jury Award · https://en.wikipedia.org/wiki/Annecy_International_Animation_Film_Festival', 2015, 'Jury Award — Feature Film (2015)', true),
  ('ANIME', 1327, 'In This Corner of the World', 'Annecy', 'Annecy 2017 — Jury Award · https://www.animenewsnetwork.com/news/2017-06-18/lu-over-the-wall-in-this-corner-of-the-world-anime-films-win-awards-at-annecy/.117637', 2017, 'Jury Award — Feature Film (2017)', true),
  ('ANIME', 1484, 'Japan Sinks: 2020', 'Annecy', 'Annecy 2021 — Jury Award TV · https://www.animenewsnetwork.com/news/2021-06-20/masaaki-yuasa-science-saru-japan-sinks-2020-tv-anime-wins-jury-award-at-annecy/.174189', 2021, 'Jury Award — TV Series (2021)', true),
  ('ANIME', 8914, 'Dozens of Norths', 'Annecy', 'Annecy 2022 — Contrechamp Award · https://www.cartoonbrew.com/feature-film/annecy-2022-winners-little-nicholas-amok-217839.html', 2022, 'Contrechamp Grand Prix (2022)', true),
  ('ANIME', 7850, 'ChaO', 'Annecy', 'Annecy 2025 — Jury Award · https://www.animenewsnetwork.com/news/2025-06-14/yasuhiro-aoki-studio-4c-chao-anime-wins-annecy-film-festival-jury-prize/.225593', 2025, 'Jury Award — Feature Film (2025)', true),
  ('ANIME', 8654, 'Hanarokushou ga Akeru Hi ni', 'Annecy', 'Annecy 2026 — Contrechamp Jury · https://www.animenewsnetwork.com/news/2026-06-28/a-new-dawn-anime-film-takopi-original-sin-tv-anime-win-at-annecy/.239052', 2026, 'Contrechamp Jury Award (2026)', true),
  ('ANIME', 934, 'Takopi''s Original Sin', 'Annecy', 'Annecy 2026 — Jury Award TV · https://unijapan.org/english/news/awards/annecy_international_animation_film_festival_2026.html', 2026, 'Jury Award — TV Series (2026)', true),
  ('ANIME', 7382, 'Mt. Head', 'Annecy', 'Annecy 2003 — Cristal Short · https://en.wikipedia.org/wiki/Annecy_International_Animation_Film_Festival', 2003, 'Cristal — Short Film (2003)', true),
  ('MANGA', 871, 'Space Brothers', 'Manga Taishō', '2009 runner-up 94 pts · https://en.wikipedia.org/wiki/Manga_Taish%C5%8D', 2009, 'Nominee (≥80 pts) (2009)', true),
  ('MANGA', 871, 'Space Brothers', 'Manga Taishō', '2010 runner-up 89 pts · https://en.wikipedia.org/wiki/Manga_Taish%C5%8D', 2010, 'Nominee (≥80 pts) (2010)', true),
  ('MANGA', 289, 'Erased', 'Manga Taishō', '2014 runner-up 82 pts · https://en.wikipedia.org/wiki/Manga_Taish%C5%8D', 2014, 'Nominee (≥80 pts) (2014)', true),
  ('MANGA', 369, 'Akane-banashi', 'Manga Taishō', '2023 runner-up 100 pts · https://en.wikipedia.org/wiki/Manga_Taish%C5%8D', 2023, 'Nominee (≥80 pts) (2023)', true),
  ('MANGA', 295, 'The Ancient Magus'' Bride', 'Kono Manga ga Sugoi!', '2015 edition · https://www.animenewsnetwork.com/news/2014-12-08/kono-manga-ga-sugoi-2015-series-ranking-for-male-readers/.81892', 2015, '#2 — Male Readers (2015)', true),
  ('MANGA', 10267, 'Kodomo wa Wakatte Agenai', 'Kono Manga ga Sugoi!', '2015 edition · https://www.animenewsnetwork.com/news/2014-12-08/kono-manga-ga-sugoi-2015-series-ranking-for-male-readers/.81892', 2015, '#3 — Male Readers (2015)', true),
  ('MANGA', 3500, 'Tokyo Tarareba Girls', 'Kono Manga ga Sugoi!', '2015 edition · https://www.animenewsnetwork.com/news/2014-12-09/kono-manga-ga-sugoi-2015-series-ranking-for-female-readers/.81948', 2015, '#2 — Female Readers (2015)', true),
  ('MANGA', 1200, 'The Rose of Versailles', 'Kono Manga ga Sugoi!', '2015 edition · https://www.animenewsnetwork.com/news/2014-12-09/kono-manga-ga-sugoi-2015-series-ranking-for-female-readers/.81948', 2015, '#3 — Female Readers (2015)', true),
  ('MANGA', 155, 'Golden Kamuy', 'Kono Manga ga Sugoi!', '2016 edition · https://www.animenewsnetwork.com/news/2015-12-10/kono-manga-ga-sugoi-reveals-2016-series-ranking-for-male-readers/.96294', 2016, '#2 — Male Readers (2016)', true),
  ('MANGA', 541, 'Machida-kun no Sekai', 'Kono Manga ga Sugoi!', '2016 edition · https://www.animenewsnetwork.com/news/2015-12-10/kono-manga-ga-sugoi-reveals-2016-series-ranking-for-female-readers/.96323', 2016, '#3 — Female Readers (2016)', true),
  ('MANGA', 3500, 'Tokyo Tarareba Girls', 'Kono Manga ga Sugoi!', '2016 edition · https://www.animenewsnetwork.com/news/2015-12-10/kono-manga-ga-sugoi-reveals-2016-series-ranking-for-female-readers/.96323', 2016, '#2 — Female Readers (2016)', true),
  ('MANGA', 1926, 'My Boy', 'Kono Manga ga Sugoi!', '2017 edition · https://www.animenewsnetwork.com/news/2016-12-09/kono-manga-ga-sugoi-reveals-2017-series-ranking-for-male-readers/.109675', 2017, '#2 — Male Readers (2017)', true),
  ('MANGA', 78, 'Fire Punch', 'Kono Manga ga Sugoi!', '2017 edition · https://www.animenewsnetwork.com/news/2016-12-09/kono-manga-ga-sugoi-reveals-2017-series-ranking-for-male-readers/.109675', 2017, '#3 — Male Readers (2017)', true),
  ('MANGA', 230, 'My Lesbian Experience With Loneliness', 'Kono Manga ga Sugoi!', '2017 edition · https://www.animenewsnetwork.com/news/2016-12-09/kono-manga-ga-sugoi-reveals-2017-series-ranking-for-female-readers/.109677', 2017, '#3 — Female Readers (2017)', true),
  ('MANGA', 157, 'BEASTARS', 'Kono Manga ga Sugoi!', '2018 edition · https://www.animenewsnetwork.com/news/2017-12-08/kono-manga-ga-sugoi-reveals-2018-series-ranking-for-male-readers/.125015', 2018, '#2 — Male Readers (2018)', true),
  ('MANGA', 154, 'To Your Eternity', 'Kono Manga ga Sugoi!', '2018 edition · https://www.animenewsnetwork.com/news/2017-12-08/kono-manga-ga-sugoi-reveals-2018-series-ranking-for-male-readers/.125015', 2018, '#3 — Male Readers (2018)', true),
  ('MANGA', 1907, 'Don''t Call it Mystery', 'Kono Manga ga Sugoi!', '2019 edition · https://www.animenewsnetwork.com/news/2018-12-10/kono-manga-ga-sugoi-reveals-2019-series-ranking-for-female-readers/.140601', 2019, '#2 — Female Readers (2019)', true),
  ('MANGA', 1230, 'Astra Lost in Space', 'Kono Manga ga Sugoi!', '2019 edition · https://www.animenewsnetwork.com/news/2018-12-10/kono-manga-ga-sugoi-reveals-2019-series-ranking-for-male-readers/.140595', 2019, '#3 — Male Readers (2019)', true),
  ('MANGA', 257, 'The Dangers in My Heart', 'Kono Manga ga Sugoi!', '2020 edition · https://www.animenewsnetwork.com/news/2019-12-11/kono-manga-ga-sugoi-editors-unveil-2020-rankings/.154203', 2020, '#3 — Male Readers (2020)', true),
  ('MANGA', 89, 'Frieren: Beyond Journey’s End', 'Kono Manga ga Sugoi!', '2021 edition · https://www.animenewsnetwork.com/news/2020-12-17/kono-manga-ga-sugoi-editors-unveil-2021-rankings/.167435', 2021, '#2 — Male Readers (2021)', true),
  ('MANGA', 464, 'Kowloon Generic Romance', 'Kono Manga ga Sugoi!', '2021 edition · https://www.animenewsnetwork.com/news/2020-12-17/kono-manga-ga-sugoi-editors-unveil-2021-rankings/.167435', 2021, '#3 — Male Readers (2021)', true),
  ('MANGA', 1447, 'Orb: On the Movements of the Earth', 'Kono Manga ga Sugoi!', '2022 edition · https://www.animenewsnetwork.com/news/2021-12-29/kono-manga-ga-sugoi-editors-unveil-2022-rankings/.181059', 2022, '#2 — Male Readers (2022)', true),
  ('MANGA', 28, 'Kaiju No.8', 'Kono Manga ga Sugoi!', '2022 edition · https://www.animenewsnetwork.com/news/2021-12-29/kono-manga-ga-sugoi-editors-unveil-2022-rankings/.181059', 2022, '#3 — Male Readers (2022)', true),
  ('MANGA', 2087, 'She Loves to Cook, and She Loves to Eat', 'Kono Manga ga Sugoi!', '2022 edition · https://www.animenewsnetwork.com/news/2021-12-29/kono-manga-ga-sugoi-editors-unveil-2022-rankings/.181059', 2022, '#2 — Female Readers (2022)', true),
  ('MANGA', 2024, 'Ōoku: The Inner Chambers', 'Kono Manga ga Sugoi!', '2022 edition · https://www.animenewsnetwork.com/news/2021-12-29/kono-manga-ga-sugoi-editors-unveil-2022-rankings/.181059', 2022, '#3 — Female Readers (2022)', true),
  ('MANGA', 95, 'Goodbye, Eri', 'Kono Manga ga Sugoi!', '2023 edition · https://www.animenewsnetwork.com/news/2022-12-12/kono-manga-ga-sugoi-editors-unveil-2023-rankings/.192823', 2023, '#2 — Male Readers (2023)', true),
  ('MANGA', 301, 'Takopi''s Original Sin', 'Kono Manga ga Sugoi!', '2023 edition · https://www.animenewsnetwork.com/news/2022-12-12/kono-manga-ga-sugoi-editors-unveil-2023-rankings/.192823', 2023, '#3 — Male Readers (2023)', true),
  ('MANGA', 1108, 'Daemons of the Shadow Realm', 'Kono Manga ga Sugoi!', '2024 edition · https://www.animenewsnetwork.com/news/2023-12-11/kono-manga-ga-sugoi-editors-unveil-2024-rankings/.205367', 2024, '#2 — Male Readers (2024)', true),
  ('MANGA', 181, 'The Guy She Was Interested In Wasn''t a Guy at All', 'Kono Manga ga Sugoi!', '2024 edition · https://www.animenewsnetwork.com/news/2023-12-11/kono-manga-ga-sugoi-editors-unveil-2024-rankings/.205367', 2024, '#2 — Female Readers (2024)', true),
  ('MANGA', 3372, 'Girl meets Rock!', 'Kono Manga ga Sugoi!', '2025 edition · https://www.animenewsnetwork.com/news/2024-12-12/kono-manga-ga-sugoi-editors-unveil-full-list-of-top-2025-manga/.218909', 2025, '#2 — Male Readers (2025)', true),
  ('MANGA', 26561, 'Strikeout Pitch', 'Kono Manga ga Sugoi!', '2026 edition · https://www.animenewsnetwork.com/news/2025-12-22/kono-manga-ga-sugoi-editors-unveil-full-list-of-top-2026-manga/.232368', 2026, '#3 — Male Readers (2026)', true)
on conflict (media_type, media_id, source, category) do nothing;

-- ---------------------------------------------------------------------------
-- 4) Seasonal discovery signals (NOT canon)
-- ---------------------------------------------------------------------------
create table if not exists public.curation_seasonal_signal (
  id bigint generated always as identity primary key,
  media_type text not null check (media_type in ('ANIME','MANGA')),
  media_id integer not null,
  title text not null,
  source text not null,
  period text not null,
  rank integer,
  score numeric,
  category text not null default 'list',
  source_detail text,
  year integer,
  created_at timestamptz not null default now(),
  unique (media_type, media_id, source, period, category)
);

comment on table public.curation_seasonal_signal is
  'Tier-B/C seasonal desks (Filmarks, 次にくるマンガ大賞, EN yearlists). Feeds Hidden Gem / Shelf — never forces media_realm_tier canon.';

alter table public.curation_seasonal_signal enable row level security;

drop policy if exists curation_seasonal_signal_public_read on public.curation_seasonal_signal;
create policy curation_seasonal_signal_public_read
  on public.curation_seasonal_signal
  for select
  using (true);

create index if not exists curation_seasonal_signal_media_idx
  on public.curation_seasonal_signal (media_type, media_id);

create index if not exists curation_seasonal_signal_period_idx
  on public.curation_seasonal_signal (source, period);

insert into public.curation_seasonal_signal
  (media_type, media_id, title, source, period, rank, score, category, source_detail, year)
values
  ('ANIME', 2445, 'STEEL BALL RUN JoJo''s Bizarre Adventure 1st STAGE', 'Filmarks', '2026-H1', 1, 4.45, 'list #1', 'Filmarks 2026上半期アニメランキング #1 · https://prtimes.jp/main/html/rd/p/000000771.000008641.html', 2026),
  ('ANIME', 3934, 'Dorohedoro Season 2', 'Filmarks', '2026-H1', 2, 4.33, 'list #2', 'Filmarks 2026上半期 #2', 2026),
  ('ANIME', 1165, 'Frieren: Beyond Journey’s End Season 2', 'Filmarks', '2026-H1', 3, 4.29, 'list #3', 'Filmarks 2026上半期 #3', 2026),
  ('ANIME', 18588, 'NIPPON SANGOKU: The Three Nations of the Crimson Sun', 'Filmarks', '2026-H1', 4, 4.27, 'list #4', 'Filmarks 2026上半期 #4', 2026),
  ('ANIME', 4562, 'You and I Are Polar Opposites', 'Filmarks', '2026-H1', 5, 4.26, 'list #5', 'Filmarks 2026上半期 #5', 2026),
  ('ANIME', 5816, 'Journal with Witch', 'Filmarks', '2026-H1', 6, 4.25, 'list #6', 'Filmarks 2026上半期 #6', 2026),
  ('ANIME', 2745, 'Black Butler: Emerald Witch Arc', 'Filmarks', '2025-H1', 1, 4.46, 'list #1', 'Filmarks 2025上半期 #1 · https://eeo.today/media/2025/07/16/243179/', 2025),
  ('ANIME', 2454, 'Umamusume: Cinderella Gray', 'Filmarks', '2025-H1', 2, 4.38, 'list #2', 'Filmarks 2025上半期 #2', 2025),
  ('ANIME', 465, 'The Apothecary Diaries Season 2', 'Filmarks', '2025-H1', 5, 4.27, 'list #5', 'Filmarks 2025上半期 #5', 2025),
  ('ANIME', 2428, 'Medalist', 'Filmarks', '2025-H1', 6, 4.26, 'list #6', 'Filmarks 2025上半期 #6', 2025),
  ('MANGA', 497, 'Ichi the Witch', 'Tsugi ni Kuru Manga Award', '2025', 1, null, 'list #1', '次にくるマンガ大賞2025 コミックス部門1位 · https://www.hmv.co.jp/news/article/250620120/', 2025),
  ('MANGA', 4167, 'Cosmos', 'Tsugi ni Kuru Manga Award', '2025', 2, null, 'list #2', '次にくるマンガ大賞2025 コミックス部門2位', 2025),
  ('MANGA', 134, 'Kagurabachi', 'Tsugi ni Kuru Manga Award', '2024', 1, null, 'list #1', '次にくるマンガ大賞2024 コミックス部門1位 · https://manga.watch.impress.co.jp/docs/news/1619545.html', 2024),
  ('MANGA', 3372, 'Girl meets Rock!', 'Tsugi ni Kuru Manga Award', '2024', 1, null, 'Web Manga #1', '次にくるマンガ大賞2024 Webマンガ部門1位', 2024),
  ('MANGA', 26561, 'Strikeout Pitch', 'Tsugi ni Kuru Manga Award', '2025', 1, null, 'Web Manga #1', '次にくるマンガ大賞2025 Webマンガ部門1位', 2025),
  ('ANIME', 145, 'Frieren: Beyond Journey’s End', 'IndieWire', '2024', 1, null, 'list #1', 'IndieWire / EN year-end critic desk (seasonal) — seed exemplar', 2024),
  ('ANIME', 337, 'Delicious in Dungeon', 'Polygon', '2024', 2, null, 'list #2', 'Polygon year-end anime list exemplar (seasonal)', 2024),
  ('MANGA', 225, 'The Summer Hikaru Died', 'Comics Beat', '2024', 3, null, 'list #3', 'Comics Beat manga year-list exemplar (seasonal)', 2024)
on conflict (media_type, media_id, source, period, category) do nothing;

-- ---------------------------------------------------------------------------
-- 5) Hidden Gem: prefer seasonal-signal titles when in tonight's realm pool
-- ---------------------------------------------------------------------------
create or replace function public.fetch_realm_hidden_gem()
returns table (
  realm text,
  display_name text,
  blurb text,
  media_type text,
  media_id integer,
  title text,
  cover_image_large text,
  banner_image text,
  genres text[],
  score integer,
  year integer,
  format text,
  argument text
)
language plpgsql
stable
security invoker
set search_path = public, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_realm text;
  v_display text;
  v_blurb text;
  v_week int;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  v_realm := public._tonight_realm(v_uid);
  if v_realm is null then
    return;
  end if;

  select rm.display_name, rm.blurb into v_display, v_blurb
  from public.realm_meta rm where rm.realm = v_realm;

  v_week := (extract(epoch from date_trunc('week', now() at time zone 'utc')) / 86400)::int;

  return query
  with pool as (
    select
      t.media_type,
      t.media_id,
      t.tier
    from public.media_realm_tier t
    join public.media_realm_membership_effective m
      on m.media_type = t.media_type
     and m.media_id = t.media_id
     and m.realm = t.realm
    where t.realm = v_realm
      and t.tier in ('canon', 'acclaimed')
      and m.weight >= 0.35
  ),
  scored as (
    select
      p.media_type,
      p.media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
      a.cover_image_large,
      a.banner_image,
      a.genres,
      a.average_score as score,
      coalesce(a.season_year, a.start_date_year) as year,
      a.format,
      coalesce(a.popularity, 0) as popularity,
      left(coalesce(
        case when a.synopsis_enhanced_state = 'ready' then a.synopsis_enhanced end,
        a.description_normalized, ''
      ), 280) as argument,
      exists (
        select 1 from public.curation_seasonal_signal css
        where css.media_type = p.media_type and css.media_id = p.media_id
      ) as has_seasonal
    from pool p
    join public.anime a on p.media_type = 'ANIME' and a.id = p.media_id
    where coalesce(a.is_adult, false) = false
      and a.cover_image_large is not null
      and coalesce(a.average_score, 0) >= 75
      and coalesce(a.popularity, 0) > 0
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text and ul.media_type = 'anime' and ul.media_id = a.id
      )

    union all

    select
      p.media_type,
      p.media_id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.banner_image,
      m.genres,
      m.average_score,
      m.start_date_year,
      m.format,
      coalesce(m.popularity, 0),
      left(coalesce(
        case when m.synopsis_enhanced_state = 'ready' then m.synopsis_enhanced end,
        m.description_normalized, ''
      ), 280),
      exists (
        select 1 from public.curation_seasonal_signal css
        where css.media_type = p.media_type and css.media_id = p.media_id
      )
    from pool p
    join public.manga m on p.media_type = 'MANGA' and m.id = p.media_id
    where coalesce(m.is_adult, false) = false
      and m.cover_image_large is not null
      and coalesce(m.average_score, 0) >= 75
      and coalesce(m.popularity, 0) > 0
      and not exists (
        select 1 from public.user_lists ul
        where ul.user_id = v_uid::text and ul.media_type = 'manga' and ul.media_id = m.id
      )
  ),
  cut as (
    select s.*,
           percent_rank() over (order by s.popularity asc) as pop_pct,
           row_number() over (
             order by
               (case when s.has_seasonal then 0 else 1 end),
               (hashtext(s.media_type || ':' || s.media_id::text || ':' || v_week::text))
           ) as rn
    from scored s
  )
  select
    v_realm,
    v_display,
    v_blurb,
    c.media_type,
    c.media_id,
    c.title,
    c.cover_image_large,
    c.banner_image,
    c.genres,
    c.score,
    c.year,
    c.format,
    public._discover_sentence_trim(
      coalesce(nullif(c.argument, ''), v_blurb),
      280
    )
  from cut c
  where c.pop_pct <= 0.55 or c.has_seasonal
  order by c.rn
  limit 1;
end;
$$;

revoke all on function public.fetch_realm_hidden_gem() from public;
grant execute on function public.fetch_realm_hidden_gem() to authenticated, service_role;


-- NOTE: media_realm_tier refresh is intentionally NOT in this migration —
-- a full refresh times out inside the migration transaction. Existing
-- pg_cron job refreshes the matview; or run manually after push:
--   refresh materialized view concurrently public.media_realm_tier;
