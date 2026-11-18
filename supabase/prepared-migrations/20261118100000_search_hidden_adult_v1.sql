-- PREPARED ONLY (W4): owner approval required to apply.
-- W4 (tracker gaps): additive search_{anime,manga}_page_v2 return {"items": [...v1 rows...],
-- "hidden_adult": n|null}. v1 (the staged bodies of 20261109200000) is NOT touched. Adult =
-- is_adult is true or genres @> {Hentai}. pg_trgm.similarity_threshold stays 0.35 (as v1).
--
-- Import staging (also in this file): a match to an adult catalogue row is staged as unmatched/ADULT_NOT_LISTED;
-- a manual mapping onto one is refused with ADULT_NOT_LISTED (prepare_import_chunk_v2 is restated in full).
-- KNOWN LIMITS (release note, no code change):
--   1. Rows already staged before this migration (a job in `reviewing`) are NOT guarded: the trigger only
--      fires on writes to media_id/disposition, so they keep their existing adult match until written again.
--   2. An import row keeps the catalogue's title name for 18+ titles (title is not scrubbed).
begin;
set local lock_timeout = '3s';
set local search_path = public, extensions;

CREATE FUNCTION public._search_hidden_adult_anime_v1(p_query text, p_trending boolean, p_new_season boolean, p_classics boolean, p_hidden_gems boolean, p_airing_only boolean, p_season text, p_season_year integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- Bounded (100) count of adult titles that pass every OTHER filter of search_anime_page and its
-- text-match predicate (strong stage OR trigram stage). Ecchi is not a condition. Internal only.
declare
  v_count integer;
begin
  execute $count$
select count(*)::int from (
  select 1
  from (
    select
      a.genres,
      a.is_adult,
      lower(coalesce(a.title_english, '')) as title_english_norm,
      lower(coalesce(a.title_romaji, '')) as title_romaji_norm,
      lower(coalesce(a.title_native, '')) as title_native_norm,
      public.catalogue_search_blob_v1(a.title_english,a.title_romaji,a.title_native) as title_blob
    from public.anime a
    where
      (a.is_adult is true or a.genres @> array['Hentai']::text[])
      and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
      and (not coalesce($2, false) or coalesce(a.trending, 0) > 0)
      and (not coalesce($3, false) or coalesce(a.season_year, a.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($4, false) or coalesce(a.season_year, a.start_date_year, 9999) < 2010)
      and (not coalesce($5, false) or (coalesce(a.average_score, 0) >= 85 and coalesce(a.season_year, a.start_date_year, 9999) < 2015))
      and (not coalesce($6, false) or a.status = 'RELEASING')
      and ($7 is null or a.season = $7)
      and ($8 is null or a.season_year = $8)
  ) b
  where
      (
        nullif(lower(trim(coalesce($1, ''))), '') is not null
        and (
          title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
          or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
          or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
          or title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
          or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
          or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
          or title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
          or (
            (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
          )
          or (
            length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
          )
        )
      )
  limit 100
) s
$count$ into v_count using p_query, p_trending, p_new_season, p_classics, p_hidden_gems, p_airing_only, p_season, p_season_year;
  return coalesce(v_count, 0);
end;
$function$;

CREATE FUNCTION public._search_hidden_adult_manga_v1(p_query text, p_trending boolean, p_new_season boolean, p_classics boolean, p_hidden_gems boolean)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- Bounded (100) count of adult titles that pass every OTHER filter of search_manga_page and its
-- text-match predicate (strong stage OR trigram stage). Ecchi is not a condition. Internal only.
declare
  v_count integer;
begin
  execute $count$
select count(*)::int from (
  select 1
  from (
    select
      m.genres,
      m.is_adult,
      lower(coalesce(m.title_english, '')) as title_english_norm,
      lower(coalesce(m.title_romaji, '')) as title_romaji_norm,
      lower(coalesce(m.title_native, '')) as title_native_norm,
      public.catalogue_search_blob_v1(m.title_english,m.title_romaji,m.title_native) as title_blob
    from public.manga m
    where
      (m.is_adult is true or m.genres @> array['Hentai']::text[])
      and (not coalesce($2, false) or coalesce(m.trending, 0) > 0)
      and (not coalesce($3, false) or coalesce(m.start_date_year, 0) >= (extract(year from now())::int - 1))
      and (not coalesce($4, false) or coalesce(m.start_date_year, 9999) < 2010)
      and (not coalesce($5, false) or (coalesce(m.average_score, 0) >= 85 and coalesce(m.start_date_year, 9999) < 2015))
  ) b
  where
      (
        nullif(lower(trim(coalesce($1, ''))), '') is not null
        and (
          title_english_norm = nullif(lower(trim(coalesce($1, ''))), '')
          or title_romaji_norm = nullif(lower(trim(coalesce($1, ''))), '')
          or title_native_norm = nullif(lower(trim(coalesce($1, ''))), '')
          or title_english_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
          or title_romaji_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
          or title_native_norm like (nullif(lower(trim(coalesce($1, ''))), '') || '%')
          or title_blob like ('%' || nullif(lower(trim(coalesce($1, ''))), '') || '%')
          or (
            (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end) is not null
            and to_tsvector('simple', title_blob) @@ (case when nullif(trim(coalesce($1, '')), '') is not null and length(nullif(trim(coalesce($1, '')), ''))>=3 then websearch_to_tsquery('simple',nullif(trim(coalesce($1, '')), '')) else null end)
          )
          or (
            length(nullif(lower(trim(coalesce($1, ''))), ''))::int >= 5
            and ((title_english_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_romaji_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_native_norm operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '') or title_blob operator(extensions.%) nullif(lower(trim(coalesce($1, ''))), '')) and greatest(
              extensions.similarity(title_english_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_romaji_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_native_norm, nullif(lower(trim(coalesce($1, ''))), '')),
              extensions.similarity(title_blob, nullif(lower(trim(coalesce($1, ''))), ''))
            ) >= 0.35)
          )
        )
      )
  limit 100
) s
$count$ into v_count using p_query, p_trending, p_new_season, p_classics, p_hidden_gems;
  return coalesce(v_count, 0);
end;
$function$;

CREATE FUNCTION public.search_anime_page_v2(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false, p_airing_only boolean DEFAULT false, p_season text DEFAULT NULL::text, p_season_year integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- {"items": <search_anime_page rows in v1 order>, "hidden_adult": <0..100> | null}. v1 does all
-- ranking, filtering and paging; hidden_adult is only computed for page 1 of a >= 2 character query.
declare
  v_items jsonb;
  v_hidden integer := null;
begin
  select coalesce(jsonb_agg(to_jsonb(r) - 'ordinality' order by r.ordinality), '[]'::jsonb)
    into v_items
    from public.search_anime_page(p_query, p_limit, p_cursor_rank, p_cursor_popularity, p_cursor_id, p_trending, p_new_season, p_classics, p_hidden_gems, p_airing_only, p_season, p_season_year) with ordinality r;
  if p_cursor_id is null and length(btrim(coalesce(p_query, ''))) >= 2 then
    v_hidden := public._search_hidden_adult_anime_v1(p_query, p_trending, p_new_season, p_classics, p_hidden_gems, p_airing_only, p_season, p_season_year);
  end if;
  return jsonb_build_object('items', v_items, 'hidden_adult', v_hidden);
end;
$function$;

CREATE FUNCTION public.search_manga_page_v2(p_query text, p_limit integer DEFAULT 30, p_cursor_rank double precision DEFAULT NULL::double precision, p_cursor_popularity integer DEFAULT NULL::integer, p_cursor_id integer DEFAULT NULL::integer, p_trending boolean DEFAULT false, p_new_season boolean DEFAULT false, p_classics boolean DEFAULT false, p_hidden_gems boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
 SET jit TO 'off'
 SET pg_trgm.similarity_threshold TO '0.35'
AS $function$
-- {"items": <search_manga_page rows in v1 order>, "hidden_adult": <0..100> | null}. v1 does all
-- ranking, filtering and paging; hidden_adult is only computed for page 1 of a >= 2 character query.
declare
  v_items jsonb;
  v_hidden integer := null;
begin
  select coalesce(jsonb_agg(to_jsonb(r) - 'ordinality' order by r.ordinality), '[]'::jsonb)
    into v_items
    from public.search_manga_page(p_query, p_limit, p_cursor_rank, p_cursor_popularity, p_cursor_id, p_trending, p_new_season, p_classics, p_hidden_gems) with ordinality r;
  if p_cursor_id is null and length(btrim(coalesce(p_query, ''))) >= 2 then
    v_hidden := public._search_hidden_adult_manga_v1(p_query, p_trending, p_new_season, p_classics, p_hidden_gems);
  end if;
  return jsonb_build_object('items', v_items, 'hidden_adult', v_hidden);
end;
$function$;

revoke all on function public._search_hidden_adult_anime_v1(text,boolean,boolean,boolean,boolean,boolean,text,integer), public._search_hidden_adult_manga_v1(text,boolean,boolean,boolean,boolean) from public, anon, authenticated;
revoke all on function public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer), public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean) from public;
grant execute on function public.search_anime_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean,boolean,text,integer), public.search_manga_page_v2(text,integer,double precision,integer,integer,boolean,boolean,boolean,boolean) to anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Import staging: a match to an adult catalogue row becomes 'unmatched' with the stable detail
-- code ADULT_NOT_LISTED (no new disposition value: TestFlight 25 decodes a closed enum).
-- The trigger covers every staging path (prepare_import_chunk_v2 insert and its ON CONFLICT
-- update, manual mapping, re-review). Rows already applied/undone ('added','updated','unchanged',
-- 'pending','conflict', ...) are outside the WHEN clause and are never touched.
-- Legacy apply_import_chunk_v1 (series_foundation_v1 off) is out of scope.
create function public._import_item_adult_guard_v1() returns trigger
 language plpgsql
 set search_path to 'public', 'extensions'
as $function$
declare
  v_adult boolean;
begin
  if new.medium = 'anime' then
    select (a.is_adult is true or a.genres @> array['Hentai']::text[]) into v_adult from public.anime a where a.id = new.media_id;
  else
    select (m.is_adult is true or m.genres @> array['Hentai']::text[]) into v_adult from public.manga m where m.id = new.media_id;
  end if;
  if coalesce(v_adult, false) then
    -- A manual mapping (insert, including the ON CONFLICT DO UPDATE form) onto an 18+ row is refused with a
    -- stable code instead of being resolved to the adult title. Automatic matches and re-staging
    -- (BEFORE UPDATE) still degrade to unmatched/ADULT_NOT_LISTED below.
    if tg_op = 'INSERT' and new.manual_resolved then
      raise exception 'ADULT_NOT_LISTED';
    end if;
    new.disposition := 'unmatched';
    new.detail := 'ADULT_NOT_LISTED: 18+ title, not listed in Kuro';
    new.media_id := null;
    new.identity_resolved := false;
    new.manual_resolved := false;
    new.current_values := null;
    new.changed_fields := '[]'::jsonb;
    new.expected_revision := null;
    new.expected_lifecycle := null;
    new.baseline_tombstones := '[]'::jsonb;
  end if;
  return new;
end;
$function$;
revoke all on function public._import_item_adult_guard_v1() from public, anon, authenticated;

drop trigger if exists library_import_items_adult_guard_v1 on public.library_import_items;
create trigger library_import_items_adult_guard_v1
  before insert or update of media_id, disposition on public.library_import_items
  for each row
  when (new.media_id is not null and new.disposition in ('new', 'existing', 'changes'))
  execute function public._import_item_adult_guard_v1();

-- Same keys and filters as before, plus adult_not_listed.
create or replace function public._import_v2_counts(p_job uuid) returns jsonb
 language plpgsql
 stable
 set search_path to 'public', 'extensions'
as $function$
begin
  return (
    select jsonb_build_object(
      'added', count(*) filter (where disposition = 'added'),
      'updated', count(*) filter (where disposition = 'updated'),
      'unchanged', count(*) filter (where disposition = 'unchanged'),
      'conflict', count(*) filter (where disposition in ('conflict', 'source_changed')),
      'unmatched', count(*) filter (where disposition = 'unmatched'),
      'invalid', count(*) filter (where disposition = 'invalid'),
      'pending', count(*) filter (where not terminal and disposition in ('new', 'existing', 'changes', 'pending')),
      'adult_not_listed', count(*) filter (where disposition = 'unmatched' and detail like 'ADULT\_NOT\_LISTED:%')
    )
    from public.library_import_items where job_id = p_job
  );
end;
$function$;

-- Effective body of 20261008110000 (the only definition) restated in full with ONE change: an automatic
-- catalogue match onto an 18+ row no longer counts as `resolved` for the MAPPING_ALREADY_RESOLVED test.
create or replace function public.prepare_import_chunk_v2(p_job_id uuid,p_items jsonb,p_exhausted_media jsonb default '{}')returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
#variable_conflict use_variable
declare uid uuid:=auth.uid(); j public.library_import_jobs%rowtype; old public.library_import_items%rowtype;
 it jsonb; inc jsonb; cur jsonb; fields jsonb; medium text; external text; title text; med integer; found_ref boolean; resolved boolean;
 manual integer; disposition text; detail text; h text; m text; complete boolean; merged jsonb;
begin
 if uid is null then raise exception 'UNAUTHENTICATED'; end if;
 perform pg_advisory_xact_lock(hashtextextended('kuro.library.account:'||uid::text,0));
 select * into j from public.library_import_jobs where id=p_job_id and user_id=uid for update;
 if not found then raise exception 'NOT_AUTHORIZED'; end if;
 if j.contract_version<>2 then raise exception 'CONTRACT_VERSION_MISMATCH'; end if;
 if j.phase not in('preparing','reviewing')then raise exception 'JOB_NOT_PREPARING'; end if;
 if jsonb_typeof(p_items)is distinct from 'array' or jsonb_array_length(p_items)>100
  or jsonb_typeof(p_exhausted_media)is distinct from 'object' then raise exception 'INVALID_PAYLOAD'; end if;
 if exists(select 1 from jsonb_each(p_exhausted_media)e where not(j.selection->'media'?e.key)or jsonb_typeof(e.value)<>'boolean')then raise exception 'INVALID_COVERAGE'; end if;
 for it in select value from jsonb_array_elements(p_items)loop
  medium:=lower(it->>'medium'); external:=it->>'external_id'; manual:=null;
  if jsonb_typeof(it)<>'object'or medium is null or not(j.selection->'media'?medium)or external is null or length(external)>100 then raise exception 'INVALID_ITEM'; end if;
  if it->>'resolved_media_id' is not null then
   if jsonb_typeof(it->'resolved_media_id')<>'number'or(it->>'resolved_media_id')!~'^[1-9][0-9]{0,9}$'or(it->>'resolved_media_id')::numeric>2147483647 then raise exception 'INVALID_MAPPING'; end if;
   manual:=(it->>'resolved_media_id')::integer;
  end if;
  title:=left(coalesce(nullif(it->>'title',''),case medium when 'anime'then 'Anime 'else 'Manga 'end||external),500);
  med:=null;cur:=null;resolved:=false;found_ref:=false;detail:=null;fields:='[]';disposition:=null;
  begin
   if jsonb_typeof(it->'external_id')<>'string'or external!~'^[0-9]{1,10}$'or external::numeric>2147483647 or external::numeric<1 then raise exception 'INVALID_EXTERNAL_ID'; end if;
   inc:=public._import_v2_values(it->'values',medium);
   if not(inc?'status')then raise exception 'MISSING_STATUS'; end if;
  exception when others then
   disposition:='invalid';detail:=case sqlerrm when 'INVALID_EXTERNAL_ID'then 'Invalid provider ID'when 'INVALID_STATUS'then 'Unsupported status'else 'Invalid source values'end;
   inc:=jsonb_build_object('unavailable_fields','[]'::jsonb);
  end;
  h:=encode(digest(inc::text,'sha256'),'hex');
  select * into old from public.library_import_items where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external for update;
  if found then
   if old.terminal or old.decision_hash is not null then
    if old.request_hash<>h or manual is not null then raise exception 'SOURCE_ALREADY_DECIDED'; end if;
    continue;
   end if;
   if exists(select 1 from jsonb_each(old.incoming-'custom_lists'-'unavailable_fields')x where inc?x.key and (inc->x.key)is distinct from x.value)then
    update public.library_import_items set disposition='source_changed',detail='Contradictory values across source appearances',changed_fields='[]'where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
   if old.disposition='source_changed'then continue; end if;
   -- Missing/unavailable fields are not contradictory values. Merge available
   -- evidence; do not let an unavailable marker suppress a supplied valid value.
   inc:=old.incoming||inc;
   select coalesce(jsonb_agg(x order by x),'[]')into merged from(
    select distinct value x from jsonb_array_elements_text(coalesce(old.incoming->'unavailable_fields','[]')||coalesce(inc->'unavailable_fields','[]'))
    where not(inc?value))q;
   inc:=inc||jsonb_build_object('unavailable_fields',merged);
   if old.incoming?'custom_lists'or inc?'custom_lists'then
    select coalesce(jsonb_agg(x order by x),'[]')into merged from(select distinct value x from jsonb_array_elements_text(coalesce(old.incoming->'custom_lists','[]')||coalesce(inc->'custom_lists','[]')))q;
    inc:=inc||jsonb_build_object('custom_lists',merged);
   end if;
   h:=encode(digest(inc::text,'sha256'),'hex');
   -- After coverage closes, effective source evidence is immutable. A new
   -- field cannot expand a previously reviewed semantic approval group.
   if j.phase='reviewing'and inc is distinct from old.incoming then
    update public.library_import_items set disposition='source_changed',detail='Source values changed after review became ready',changed_fields='[]'where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
   -- Compatible duplicate evidence must pass the same precise-unit policy
   -- as first staging before either duplicate fast path can return.
   if old.media_id is not null and(manual is null or(old.manual_resolved and manual=old.media_id))and inc->>'unit_id'is not null
    and not exists(select 1 from public.catalogue_units u where u.id=(inc->>'unit_id')::uuid and u.medium=medium
     and(case medium when 'anime'then u.anime_id else u.manga_id end)=old.media_id
     and(not(inc?'progress_label')or u.label=inc->>'progress_label'))then
    update public.library_import_items set incoming=inc,request_hash=h,disposition='invalid',detail='Source unit does not belong to the matched title or label',changed_fields='[]'where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
   -- Repeating the same match must not launder a later edit/tombstone into
   -- the original review baseline. Deliberate target changes get fresh review.
   if manual is not null and old.manual_resolved and old.media_id=manual then
    update public.library_import_items set incoming=inc,request_hash=h,changed_fields=case when old.current_values is null then old.changed_fields else public._import_v2_changed(old.current_values,inc,medium)end where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
   if manual is null then
    update public.library_import_items set incoming=inc,request_hash=h,
     changed_fields=case when current_values is not null then public._import_v2_changed(current_values,inc,medium)else changed_fields end,
     disposition=case when current_values is not null then case when jsonb_array_length(public._import_v2_changed(current_values,inc,medium))=0 then 'existing'else 'changes'end else library_import_items.disposition end
     where job_id=j.id and provider=j.provider and library_import_items.medium=medium and external_id=external;
    continue;
   end if;
  elsif coalesce((j.exhausted_media->>medium)::boolean,false)then raise exception 'SOURCE_ALREADY_EXHAUSTED'; end if;
  if disposition is null then
   select case when unresolved then null when medium='anime'then anime_id else manga_id end,not unresolved into med,resolved from public.provider_entry_refs
    where provider=j.provider and provider_entry_refs.medium=medium and external_id=external;
   found_ref:=found;
   if not found_ref then
    if medium='anime'then
     if j.provider='anilist'then select min(id)into med from public.anime where anilist_id=external::integer having count(*)=1;
     else select min(id)into med from public.anime where mal_id=external::integer having count(*)=1;end if;
    else
     if j.provider='anilist'then select min(id)into med from public.manga where anilist_id=external::integer having count(*)=1;
     else select min(id)into med from public.manga where mal_id=external::integer having count(*)=1;end if;
    end if;
    resolved:=med is not null;
   end if;
   -- W4: an automatic match onto an 18+ row is not a resolution (the guard trigger turns that row into
   -- unmatched/ADULT_NOT_LISTED), so a later manual match must not be refused as MAPPING_ALREADY_RESOLVED.
   if resolved and med is not null and(
     (medium='anime'and exists(select 1 from public.anime a where a.id=med and(a.is_adult is true or a.genres @> array['Hentai']::text[])))
     or(medium='manga'and exists(select 1 from public.manga g where g.id=med and(g.is_adult is true or g.genres @> array['Hentai']::text[]))))then
    resolved:=false;
   end if;
   if manual is not null then
    if resolved or old.identity_resolved then raise exception 'MAPPING_ALREADY_RESOLVED'; end if;
    if (medium='anime'and not exists(select 1 from public.anime where id=manual))or(medium='manga'and not exists(select 1 from public.manga where id=manual))then raise exception 'INVALID_MAPPING';end if;
    med:=manual;
   end if;
   if med is null then disposition:='unmatched';detail:='Catalogue identity requires review';
   else
    if inc->>'unit_id'is not null and not exists(select 1 from public.catalogue_units u where u.id=(inc->>'unit_id')::uuid and u.medium=medium and(case medium when 'anime'then u.anime_id else u.manga_id end)=med and(not(inc?'progress_label')or u.label=inc->>'progress_label'))then
     disposition:='invalid';detail:='Source unit does not belong to the matched title';
    else
     cur:=public._import_v2_row(uid::text,medium,med);
     fields:=case when cur is null then '[]'::jsonb else public._import_v2_changed(cur,inc,medium)end;
     disposition:=case when cur is null then 'new'when jsonb_array_length(fields)=0 then 'existing'else 'changes'end;
     if medium='anime'then select left(coalesce(title_english,title_romaji,title_native,title),500)into title from public.anime where id=med;
     else select left(coalesce(title_english,title_romaji,title_native,title),500)into title from public.manga where id=med;end if;
    end if;
   end if;
  elsif manual is not null then raise exception 'INVALID_MAPPING'; end if;
  insert into public.library_import_items(job_id,provider,external_id,medium,disposition,request_hash,detail,media_id,title,incoming,current_values,changed_fields,expected_revision,expected_lifecycle,identity_resolved,manual_resolved,baseline_tombstones)
  values(j.id,j.provider,external,medium,disposition,h,detail,med,title,inc,cur,fields,(cur->>'server_revision')::bigint,(cur->>'lifecycle_id')::uuid,resolved,manual is not null,public._import_v2_tombstones(uid::text,medium,med))
  on conflict on constraint library_import_items_pkey do update set disposition=excluded.disposition,request_hash=excluded.request_hash,detail=excluded.detail,media_id=excluded.media_id,title=excluded.title,incoming=excluded.incoming,
   current_values=excluded.current_values,changed_fields=excluded.changed_fields,expected_revision=excluded.expected_revision,expected_lifecycle=excluded.expected_lifecycle,identity_resolved=excluded.identity_resolved,manual_resolved=excluded.manual_resolved,baseline_tombstones=excluded.baseline_tombstones;
 end loop;
 foreach m in array array['anime','manga']loop
  if coalesce((p_exhausted_media->>m)::boolean,false)then j.exhausted_media:=j.exhausted_media||jsonb_build_object(m,true);end if;
 end loop;
 complete:=not exists(select 1 from jsonb_array_elements_text(j.selection->'media')s(medium)where not coalesce((j.exhausted_media->>s.medium)::boolean,false));
 update public.library_import_jobs set exhausted_media=j.exhausted_media,counters=public._import_v2_counts(j.id),phase=case when complete then 'reviewing'else 'preparing'end,updated_at=clock_timestamp()where id=j.id;
 return public._import_v2_outcome(j.id);
end;$$;

revoke all on function public.prepare_import_chunk_v2(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.prepare_import_chunk_v2(uuid,jsonb,jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
