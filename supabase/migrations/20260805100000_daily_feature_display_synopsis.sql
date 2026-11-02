-- 2026-08-05: The One Thing argument rendered fully lowercase (smoke-test find).
-- Root cause: fetch_daily_feature's p_synopsis fell back to description_normalized —
-- the LOWERCASED search-normalization column — whenever synopsis_enhanced_state was not
-- 'ready'. Display text must fall back to description (display casing). Two-token fix;
-- everything else identical to the live definition (dumped via pg_get_functiondef).

create or replace function public.fetch_daily_feature()
 RETURNS TABLE(media_type text, media_id integer, title text, cover_image_large text, banner_image text, genres text[], score integer, year integer, format text, argument text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  return query
  with pool as (
    select
      b.weight,
      b.label,
      'ANIME'::text as p_media_type,
      a.id as p_media_id,
      coalesce(nullif(a.title_english, ''), a.title_romaji) as p_title,
      a.cover_image_large as p_cover,
      a.banner_image as p_banner,
      a.genres as p_genres,
      a.average_score as p_score,
      coalesce(a.season_year, a.start_date_year) as p_year,
      a.format as p_format,
      case
        when a.synopsis_enhanced_state = 'ready'
         and length(btrim(coalesce(a.synopsis_enhanced, ''))) > 0
          then a.synopsis_enhanced
        else a.description
      end as p_synopsis
    from public.editorial_boosts b
    join public.anime a on a.id = b.media_id
    where b.media_type = 'ANIME'
      and coalesce(a.is_adult, false) = false
      and (a.cover_image_large is not null or a.banner_image is not null)

    union all

    select
      b.weight,
      b.label,
      'MANGA'::text,
      m.id,
      coalesce(nullif(m.title_english, ''), m.title_romaji),
      m.cover_image_large,
      m.banner_image,
      m.genres,
      m.average_score,
      m.start_date_year,
      m.format,
      case
        when m.synopsis_enhanced_state = 'ready'
         and length(btrim(coalesce(m.synopsis_enhanced, ''))) > 0
          then m.synopsis_enhanced
        else m.description
      end
    from public.editorial_boosts b
    join public.manga m on m.id = b.media_id
    where b.media_type = 'MANGA'
      and coalesce(m.is_adult, false) = false
      and (m.cover_image_large is not null or m.banner_image is not null)
  ),
  numbered as (
    select
      p.*,
      row_number() over (order by p.weight desc, p.p_media_type, p.p_media_id) as rn,
      count(*) over () as n
    from pool p
  )
  select
    numbered.p_media_type,
    numbered.p_media_id,
    numbered.p_title,
    numbered.p_cover,
    numbered.p_banner,
    numbered.p_genres,
    numbered.p_score,
    numbered.p_year,
    numbered.p_format,
    case
      -- Substantive editorial label (>= 4 words) wins; tags like "classic" do not.
      when nullif(btrim(numbered.label), '') is not null
       and array_length(regexp_split_to_array(btrim(numbered.label), '\s+'), 1) >= 4
        then btrim(numbered.label)
      else nullif(public._discover_sentence_trim(numbered.p_synopsis, 320), '')
    end as argument
  from numbered
  where numbered.rn = ((extract(doy from now()))::integer - 1) % numbered.n + 1;
end;
$function$
;
