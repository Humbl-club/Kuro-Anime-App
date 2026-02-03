Supabase Scheduled Imports
==========================

Create daily schedules in the Supabase Dashboard to keep anime/manga (and episodes/chapters/volumes) fresh.

Project: bkdifromsqxkndnllmdj
Functions:
- bulk-import-anime
- bulk-import-manga
- mirror-images

Steps
-----
1) Open Dashboard → Project bkdifromsqxkndnllmdj → Edge Functions → Schedules → New Schedule

Important
---------
- The project DB timezone is UTC (pg_cron schedules are interpreted in UTC).
- For cursor-driven runs, omit `startPage` (or set it to 0) so the function advances using `import_state`.

2) Anime Import (core slice, hourly)
- Function: bulk-import-anime
- Cron: 5 * * * *   (minute 5, every hour)
- Payload:
  {
    "scheduleSafe": true,
    "useCursor": true,
    "lightweight": true,
    "pagesPerBatch": 2,
    "perPage": 25,
    "delayMs": 0,
    "runToEnd": false,
    "maxPagesPerRun": 2,
    "timeBudgetMs": 55000,
    "includeRelations": false,
    "includeEpisodes": false
  }

3) Manga Import (core slice, hourly)
- Function: bulk-import-manga
- Cron: 35 * * * *  (minute 35, every hour)
- Payload:
  {
    "scheduleSafe": true,
    "useCursor": true,
    "lightweight": true,
    "pagesPerBatch": 2,
    "perPage": 25,
    "delayMs": 0,
    "runToEnd": false,
    "maxPagesPerRun": 2,
    "timeBudgetMs": 55000,
    "includeRelations": false,
    "includeChapters": false,
    "includeVolumes": false
  }

Option: Multiple staggered schedules
-----------------------------------
If you want to refresh faster, add additional schedules (same payload) at staggered minutes.
Because `useCursor: true`, you do NOT need different `startPage` values.

This keeps things simple while rotating coverage across imports.

Recommended: Deep refresh (heavy) in small slices
------------------------------------------------
Run a heavier import in tiny slices so you still refresh episodes/relations over time without timing out.

- Anime heavy (hourly)
  - Function: bulk-import-anime
  - Cron: 0 * * * *   (top of every hour)
  - Payload:
    {
      "scheduleSafe": true,
      "useCursor": true,
      "lightweight": false,
      "includeRelations": true,
      "includeEpisodes": true,
      "pagesPerBatch": 1,
      "perPage": 10,
      "delayMs": 0,
      "runToEnd": false,
      "maxPagesPerRun": 1,
      "timeBudgetMs": 55000
    }

- Manga heavy (hourly)
  - Function: bulk-import-manga
  - Cron: 10 * * * *  (10 minutes after the hour)
  - Payload:
    {
      "scheduleSafe": true,
      "useCursor": true,
      "lightweight": false,
      "includeRelations": true,
      "includeChapters": true,
      "includeVolumes": true,
      "pagesPerBatch": 1,
      "perPage": 10,
      "delayMs": 0,
      "runToEnd": false,
      "maxPagesPerRun": 1,
      "timeBudgetMs": 55000
    }

Notes
-----
- Both functions are idempotent per title. They upsert metadata, and delete+insert episodes/chapters/volumes for the specific title to refresh data.
- Increase pagesPerBatch for faster catch-up or run the functions on-demand via the HTTP endpoint.
- Ensure SERVICE_ROLE_KEY is available to the function runtime (Supabase sets it automatically).


Mirror Images to Supabase Storage (CDN)
---------------------------------------
Use the mirror-images function to download cover/banner images from AniList and rewrite DB URLs to your Storage CDN URLs. Run in batches, optionally staggered.

Storage setup (once):
- Create a public bucket named `media` (Dashboard → Storage → New bucket → Public).
- Confirm public access or use signed URLs if preferred.

On-demand invocation example (HTTP payload):
{
  "bucket": "media",
  "mediaTypes": ["ANIME","MANGA","CHARACTER","STAFF"],
  "limit": 500,
  "offset": 0,
  "overwrite": false,
  "skipIfMirrored": true,
  "timeBudgetMs": 55000
}

Recommended schedules (staggered to sweep through records):
- Mirror batch A
  - Function: mirror-images
  - Cron: 0 2 * * *
  - Payload: { "bucket": "media", "mediaTypes": ["ANIME","MANGA"], "limit": 500, "offset": 0,   "overwrite": false, "skipIfMirrored": true, "timeBudgetMs": 55000 }

- Mirror batch B
  - Function: mirror-images
  - Cron: 10 2 * * *
  - Payload: { "bucket": "media", "mediaTypes": ["ANIME","MANGA"], "limit": 500, "offset": 500, "overwrite": false, "skipIfMirrored": true, "timeBudgetMs": 55000 }

- Mirror batch C
  - Function: mirror-images
  - Cron: 20 2 * * *
  - Payload: { "bucket": "media", "mediaTypes": ["ANIME","MANGA"], "limit": 500, "offset": 1000, "overwrite": false, "skipIfMirrored": true, "timeBudgetMs": 55000 }

- Mirror characters
  - Function: mirror-images
  - Cron: 30 2 * * *
  - Payload: { "bucket": "media", "mediaTypes": ["CHARACTER"], "limit": 500, "offset": 0, "overwrite": false, "skipIfMirrored": true, "timeBudgetMs": 55000 }

- Mirror staff
  - Function: mirror-images
  - Cron: 40 2 * * *
  - Payload: { "bucket": "media", "mediaTypes": ["STAFF"], "limit": 500, "offset": 0, "overwrite": false, "skipIfMirrored": true, "timeBudgetMs": 55000 }

Notes:
- The function uploads with upsert=true, so re-running is safe. Set "overwrite": true to re-fetch and replace.
- Updated DB columns: anime.cover_image_large/medium, anime.banner_image; manga.cover_image_large/medium, manga.banner_image.
- The iOS app reads these columns directly; once mirrored, images load from your Storage CDN.
