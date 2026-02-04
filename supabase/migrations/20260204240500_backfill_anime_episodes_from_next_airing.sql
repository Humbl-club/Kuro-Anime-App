-- Backfill missing anime episode counts for long-running / airing shows.
-- AniList sometimes returns `episodes = NULL` for RELEASING titles; we already store `next_episode_number`.
-- Use (next_episode_number - 1) as "episodes aired so far" when missing.

begin;

update public.anime
set
  episodes = greatest(coalesce(episodes, 0), greatest(0, coalesce(next_episode_number, 0) - 1)),
  total_duration = case
    when duration is not null then greatest(coalesce(episodes, 0), greatest(0, coalesce(next_episode_number, 0) - 1)) * duration
    else total_duration
  end
where
  (episodes is null or episodes <= 0)
  and next_episode_number is not null
  and next_episode_number > 1;

commit;

