-- Title search rebuild routine.
-- This is intentionally "batch rebuild" for predictable ops at launch.
-- Move to incremental triggers later if needed.

begin;
create or replace function public.rebuild_title_search()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Replace content atomically-ish (truncate inside transaction).
  truncate table public.title_search;

  -- ANIME variants
  insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, lang, popularity)
  select 'ANIME', a.id, 'english', coalesce(a.title_english, ''), public.normalize_title(a.title_english), 'en', a.popularity
  from public.anime a
  where a.title_english is not null and length(a.title_english) > 0;

  insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, lang, popularity)
  select 'ANIME', a.id, 'romaji', coalesce(a.title_romaji, ''), public.normalize_title(a.title_romaji), 'ja-Latn', a.popularity
  from public.anime a
  where a.title_romaji is not null and length(a.title_romaji) > 0;

  insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, lang, popularity)
  select 'ANIME', a.id, 'native', coalesce(a.title_native, ''), public.normalize_title(a.title_native), 'ja', a.popularity
  from public.anime a
  where a.title_native is not null and length(a.title_native) > 0;

  insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, lang, popularity)
  select 'ANIME', a.id, 'synonym', s.synonym, public.normalize_title(s.synonym), null, a.popularity
  from public.anime a
  cross join lateral unnest(coalesce(a.title_synonyms, '{}'::text[])) as s(synonym)
  where s.synonym is not null and length(s.synonym) > 0;

  -- MANGA variants (minimal: english/romaji/native if present)
  insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, lang, popularity)
  select 'MANGA', m.id, 'english', coalesce(m.title_english, ''), public.normalize_title(m.title_english), 'en', m.popularity
  from public.manga m
  where m.title_english is not null and length(m.title_english) > 0;

  insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, lang, popularity)
  select 'MANGA', m.id, 'romaji', coalesce(m.title_romaji, ''), public.normalize_title(m.title_romaji), 'ja-Latn', m.popularity
  from public.manga m
  where m.title_romaji is not null and length(m.title_romaji) > 0;

  insert into public.title_search (media_type, media_id, variant_type, title_raw, title_norm, lang, popularity)
  select 'MANGA', m.id, 'native', coalesce(m.title_native, ''), public.normalize_title(m.title_native), 'ja', m.popularity
  from public.manga m
  where m.title_native is not null and length(m.title_native) > 0;
end;
$$;
revoke all on function public.rebuild_title_search() from public;
commit;
