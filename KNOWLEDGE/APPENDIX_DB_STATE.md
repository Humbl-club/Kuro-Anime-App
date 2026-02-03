APPENDIX Database State (Live Metrics)
======================================

Purpose
- Capture the current, live state of the database (row counts, airing windows, mirroring coverage, list breakdowns) and keep this appendix updated after each import/mirror run.

How to Refresh
- Option A (SQL): Run `scripts/db_state.sql` in Supabase SQL Editor (Project → SQL → New query) and paste the results below.
- Option B (Node): `node scripts/collect_db_metrics.js` to print a ready-to-paste snapshot using the project’s service role key.
- Alternatively, use `psql` or the REST RPC if you expose a read function.

Script location
- scripts/db_state.sql

Last Known Snapshot
- (Pending refresh) — Run the script and paste the output here.
- Prior reported values (from recent runs; verify):
  - Anime titles: ~2000
  - Manga titles: ~3499
  - Airing with `next_airing_at`: ~12 (≈5 within next 24h)
  - Manga `next_chapter_*`: ~0 (AniList generally doesn’t expose schedules)

Paste Latest Output Here
------------------------
-- Example (replace with actual run)
-- table,rows
-- anime,2000
-- manga,3499
-- episodes,XXXXX
-- chapters,XXXXX
-- volumes,XXXXX
-- characters,XXXXX
-- studios,XXXXX
-- authors,XXXXX
-- staff,XXXXX
-- tags,XXXXX
-- anime_characters,XXXXX
-- manga_characters,XXXXX
-- anime_studios,XXXXX
-- manga_authors,XXXXX
-- anime_staff,XXXXX
-- manga_staff,XXXXX
-- anime_tags,XXXXX
-- manga_tags,XXXXX
-- anime_user_lists,XXXXX
-- manga_user_lists,XXXXX
-- anime_comments,XXXXX
-- manga_comments,XXXXX
-- metric,value
-- airing_next_24h,5
-- airing_with_timestamp,12
-- manga_next_chapter_known,0
-- anime_cover_medium_storage,XXXX
-- manga_cover_medium_storage,XXXX
-- characters_image_storage,XXXX
-- staff_image_storage,XXXX
-- anime_cover_medium_remote,XXXX
-- manga_cover_medium_remote,XXXX
-- anime_user_lists_by_type,WATCHING,XXX
-- anime_user_lists_by_type,COMPLETED,XXX
-- ...
-- manga_user_lists_by_type,READING,XXX
-- ...
-- public_tables,NN

Snapshot captured at 2025-11-01T00:58:27.393Z
table,rows
anime,2000
manga,3499
episodes,10554
chapters,46699
volumes,4687
characters,386
studios,75
authors,241
staff,475
tags,264
anime_characters,179
manga_characters,234
anime_studios,175
manga_authors,272
anime_staff,283
manga_staff,300
anime_tags,805
manga_tags,1078
anime_user_lists,0
manga_user_lists,0
anime_comments,0
manga_comments,0
metric,airing_next_24h,5
metric,airing_with_timestamp,12
metric,manga_next_chapter_known,3499
metric,anime_cover_medium_storage,0
metric,manga_cover_medium_storage,0
metric,characters_image_storage,0
metric,staff_image_storage,0
metric,anime_cover_medium_http_like,2000
metric,manga_cover_medium_http_like,3499
metric,anime_user_lists_WATCHING,0
metric,anime_user_lists_COMPLETED,0
metric,anime_user_lists_PLANNING,0
metric,anime_user_lists_DROPPED,0
metric,anime_user_lists_PAUSED,0
metric,manga_user_lists_READING,0
metric,manga_user_lists_COMPLETED,0
metric,manga_user_lists_PLANNING,0
metric,manga_user_lists_DROPPED,0
metric,manga_user_lists_PAUSED,0
coverage,anime,total,2000
coverage,anime,title_english,1918
coverage,anime,cover_image_medium,2000
coverage,anime,banner_image,1926
coverage,anime,description,2000
coverage,anime,genres,2000
coverage,anime,average_score,1991
coverage,anime,episodes,1990
coverage,manga,total,3499
coverage,manga,title_english,2639
coverage,manga,cover_image_medium,3499
coverage,manga,banner_image,2392
coverage,manga,description,3495
coverage,manga,genres,3499
coverage,manga,volumes,1844
coverage,manga,chapters,2288
coverage,characters,total,386
coverage,characters,name_full,386
coverage,characters,image_large,386
coverage,characters,description,367
coverage,staff,total,475
coverage,staff,name_full,475
coverage,staff,image_large,475
coverage,staff,description,344
coverage,authors,total,241
coverage,authors,name_full,241
coverage,authors,image_large,241
coverage,authors,description,162
END

Snapshot captured at 2025-11-01T02:17:43.629Z
table,rows
anime,2247
manga,4054
episodes,12849
chapters,69986
volumes,6333
characters,6395
studios,360
authors,241
staff,4754
tags,370
anime_characters,4035
manga_characters,2694
anime_studios,1124
manga_authors,272
anime_staff,4570
manga_staff,1723
anime_tags,4036
manga_tags,6104
anime_user_lists,0
manga_user_lists,0
anime_comments,0
manga_comments,0
import_state,0
metric,airing_next_24h,5
metric,airing_with_timestamp,13
metric,manga_next_chapter_known,4054
metric,anime_cover_medium_storage,0
metric,manga_cover_medium_storage,0
metric,characters_image_storage,0
metric,staff_image_storage,0
metric,anime_cover_medium_http_like,2247
metric,manga_cover_medium_http_like,4054
metric,anime_user_lists_WATCHING,0
metric,anime_user_lists_COMPLETED,0
metric,anime_user_lists_PLANNING,0
metric,anime_user_lists_DROPPED,0
metric,anime_user_lists_PAUSED,0
metric,manga_user_lists_READING,0
metric,manga_user_lists_COMPLETED,0
metric,manga_user_lists_PLANNING,0
metric,manga_user_lists_DROPPED,0
metric,manga_user_lists_PAUSED,0
coverage,anime,total,2247
coverage,anime,title_english,2138
coverage,anime,cover_image_medium,2247
coverage,anime,banner_image,2135
coverage,anime,description,2247
coverage,anime,genres,2247
coverage,anime,average_score,2231
coverage,anime,episodes,2230
coverage,manga,total,4054
coverage,manga,title_english,2969
coverage,manga,cover_image_medium,4054
coverage,manga,banner_image,2672
coverage,manga,description,4046
coverage,manga,genres,4054
coverage,manga,volumes,2121
coverage,manga,chapters,2668
coverage,characters,total,6395
coverage,characters,name_full,6395
coverage,characters,image_large,6395
coverage,characters,description,4628
coverage,staff,total,4754
coverage,staff,name_full,4754
coverage,staff,image_large,4754
coverage,staff,description,3144
coverage,authors,total,241
coverage,authors,name_full,241
coverage,authors,image_large,241
coverage,authors,description,162
END

Snapshot captured at 2025-11-01T00:59:22.076Z
table,rows
anime,2000
manga,3499
episodes,10554
chapters,46699
volumes,4687
characters,386
studios,75
authors,241
staff,475
tags,264
anime_characters,179
manga_characters,234
anime_studios,175
manga_authors,272
anime_staff,283
manga_staff,300
anime_tags,805
manga_tags,1078
anime_user_lists,0
manga_user_lists,0
anime_comments,0
manga_comments,0
import_state,0
metric,airing_next_24h,5
metric,airing_with_timestamp,12
metric,manga_next_chapter_known,3499
metric,anime_cover_medium_storage,0
metric,manga_cover_medium_storage,0
metric,characters_image_storage,0
metric,staff_image_storage,0
metric,anime_cover_medium_http_like,2000
metric,manga_cover_medium_http_like,3499
metric,anime_user_lists_WATCHING,0
metric,anime_user_lists_COMPLETED,0
metric,anime_user_lists_PLANNING,0
metric,anime_user_lists_DROPPED,0
metric,anime_user_lists_PAUSED,0
metric,manga_user_lists_READING,0
metric,manga_user_lists_COMPLETED,0
metric,manga_user_lists_PLANNING,0
metric,manga_user_lists_DROPPED,0
metric,manga_user_lists_PAUSED,0
coverage,anime,total,2000
coverage,anime,title_english,1918
coverage,anime,cover_image_medium,2000
coverage,anime,banner_image,1926
coverage,anime,description,2000
coverage,anime,genres,2000
coverage,anime,average_score,1991
coverage,anime,episodes,1990
coverage,manga,total,3499
coverage,manga,title_english,2639
coverage,manga,cover_image_medium,3499
coverage,manga,banner_image,2392
coverage,manga,description,3495
coverage,manga,genres,3499
coverage,manga,volumes,1844
coverage,manga,chapters,2288
coverage,characters,total,386
coverage,characters,name_full,386
coverage,characters,image_large,386
coverage,characters,description,367
coverage,staff,total,475
coverage,staff,name_full,475
coverage,staff,image_large,475
coverage,staff,description,344
coverage,authors,total,241
coverage,authors,name_full,241
coverage,authors,image_large,241
coverage,authors,description,162
END

At-a-Glance Coverage (from latest snapshot)
-------------------------------------------
- Anime (2000):
  - title_english: 95.9% present (1918); 4.1% missing (82)
  - banner_image: 96.3% present (1926); 3.7% missing (74)
  - average_score: 99.6% present (1991); 0.4% missing (9)
  - episodes: 99.5% present (1990); 0.5% missing (10)
- Manga (3499):
  - title_english: 75.4% present (2639); 24.6% missing (860)
  - banner_image: 68.3% present (2392); 31.7% missing (1107)
  - description: 99.9% present (3495); 0.1% missing (4)
  - volumes (field): 52.7% present (1844); 47.3% missing (1655)
  - chapters (field): 65.4% present (2288); 34.6% missing (1211)
- Characters (386): image_large 100% present; description 95.1% present (367)
- Staff (475): image_large 100% present; description 72.4% present (344)
- Authors (241): image_large 100% present; description 67.2% present (162)
- Mirroring: 0 images mirrored to Storage across anime/manga/characters/staff (all URLs appear remote). Run mirror-images functions to populate.
- Lists/Comments: 0 rows in user lists and comments.

Maintenance Notes
- After scheduled runs (imports/mirror-images), re-run the script and update this section.
- If you add new tables or fields, extend the script accordingly and re-commit.
