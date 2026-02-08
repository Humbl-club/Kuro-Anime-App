
-- Migration: Add new vibe modes to concierge_config
-- Adds: sports, scifi, horror_supernatural
-- Demographic rails are NOT full vibe modes (no mode entry needed)

UPDATE concierge_config
SET config = jsonb_set(
  config,
  '{modes}',
  (config->'modes') || '[
    {
      "id": "sports",
      "title": "Sports",
      "synonyms": ["sports", "sport", "basketball", "soccer", "football", "volleyball", "boxing", "tennis", "baseball", "cycling", "running", "swimming", "haikyuu", "blue lock", "kuroko", "ippo", "slam dunk", "sportanime", "sportmanga"],
      "required_genres": ["Sports"],
      "min_score": 72,
      "min_popularity": 1500,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
      "rail_id": {"anime": "sports_anime", "manga": "sports_manga"}
    },
    {
      "id": "scifi",
      "title": "Sci-Fi",
      "synonyms": ["sci-fi", "science fiction", "scifi", "cyberpunk", "space", "futuristic", "dystopian", "robots", "space opera", "mecha", "zukunft", "weltraum"],
      "required_genres": ["Sci-Fi"],
      "min_score": 74,
      "min_popularity": 2000,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
      "rail_id": {"anime": "scifi_anime", "manga": "scifi_manga"}
    },
    {
      "id": "horror_supernatural",
      "title": "Horror & Supernatural",
      "synonyms": ["horror", "scary", "creepy", "supernatural", "ghost", "demon", "occult", "vampire", "zombie", "curse", "haunted", "junji ito", "gruselig", "geister", "uebernatuerlich"],
      "required_genres": ["Horror", "Supernatural"],
      "min_score": 70,
      "min_popularity": 1500,
      "exclude_genres": ["Kids"],
      "exclude_formats": ["TV_SHORT", "SPECIAL", "MUSIC"],
      "rail_id": {"anime": "horror_supernatural_anime", "manga": "horror_supernatural_manga"}
    }
  ]'::jsonb
)
WHERE id = true;
