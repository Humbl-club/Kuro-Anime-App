-- Raise upsert_media_realm_llm hourly budget 60 -> 600 for Groq descriptor drain.
-- Body identical to 20260731170000 except the hit threshold.

begin;

create or replace function public.upsert_media_realm_llm(p_rows jsonb)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  _hits     int;
  _affected int;
  _row      jsonb;
  _realm    jsonb;
begin
  -- Rate limit: 600 calls per hour per user (raised 2026-08-02 for Groq drain). service_role calls carry no uid,
  -- so they share one global bucket. Probationary grant: authenticated callers
  -- are accepted for the swarm pass window; this may be revoked to
  -- service_role-only once the pass completes.
  _hits := public.rate_limit_hit(
    'realm_llm_upsert:' || coalesce(auth.uid()::text, 'service_role'),
    3600
  );
  if _hits > 600 then
    raise exception 'RATE_LIMITED' using errcode = 'P0001';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'INVALID_ROWS: expected a jsonb array' using errcode = 'P0001';
  end if;
  if jsonb_array_length(p_rows) > 100 then
    raise exception 'TOO_MANY_ROWS: max 100 rows per call' using errcode = 'P0001';
  end if;

  for _row in select * from jsonb_array_elements(p_rows)
  loop
    if jsonb_typeof(_row) <> 'object' then
      raise exception 'INVALID_ROW: each row must be an object' using errcode = 'P0001';
    end if;

    -- media_type
    if coalesce(_row->>'media_type', '') not in ('ANIME', 'MANGA') then
      raise exception 'INVALID_MEDIA_TYPE' using errcode = 'P0001';
    end if;

    -- media_id (typeof checked before any cast, so a string id gets the clean
    -- error instead of a cast failure).
    if _row->'media_id' is null
       or jsonb_typeof(_row->'media_id') <> 'number' then
      raise exception 'INVALID_MEDIA_ID: ids must be positive integers' using errcode = 'P0001';
    end if;
    if (_row->>'media_id')::numeric < 1
       or (_row->>'media_id')::numeric <> floor((_row->>'media_id')::numeric)
       or (_row->>'media_id')::numeric > 2147483647 then
      raise exception 'INVALID_MEDIA_ID: ids must be positive integers' using errcode = 'P0001';
    end if;

    -- realms: array of 1..3 distinct {realm, weight} entries; realm must
    -- exist in realm_meta; weight numeric 0..1.
    if _row->'realms' is null
       or jsonb_typeof(_row->'realms') <> 'array'
       or jsonb_array_length(_row->'realms') < 1
       or jsonb_array_length(_row->'realms') > 3 then
      raise exception 'INVALID_REALMS: expected 1..3 realm entries' using errcode = 'P0001';
    end if;
    for _realm in select * from jsonb_array_elements(_row->'realms')
    loop
      if jsonb_typeof(_realm) <> 'object' then
        raise exception 'INVALID_REALM: each entry must be {"realm","weight"}' using errcode = 'P0001';
      end if;
      if coalesce(_realm->>'realm', '') = ''
         or not exists (select 1 from public.realm_meta rm where rm.realm = _realm->>'realm') then
        raise exception 'INVALID_REALM: unknown realm %', coalesce(_realm->>'realm', '<missing>') using errcode = 'P0001';
      end if;
      if _realm->'weight' is null
         or jsonb_typeof(_realm->'weight') <> 'number' then
        raise exception 'INVALID_REALM_WEIGHT: weights must be numbers 0..1' using errcode = 'P0001';
      end if;
      if (_realm->>'weight')::numeric < 0
         or (_realm->>'weight')::numeric > 1 then
        raise exception 'INVALID_REALM_WEIGHT: weights must be numbers 0..1' using errcode = 'P0001';
      end if;
    end loop;
    if (select count(distinct re->>'realm')
        from jsonb_array_elements(_row->'realms') re) <> jsonb_array_length(_row->'realms') then
      raise exception 'INVALID_REALMS: duplicate realm entries' using errcode = 'P0001';
    end if;

    -- tone: 1..3 distinct words of the fixed 24-word vocabulary (spec §6).
    if _row->'tone' is null
       or jsonb_typeof(_row->'tone') <> 'array'
       or jsonb_array_length(_row->'tone') < 1
       or jsonb_array_length(_row->'tone') > 3 then
      raise exception 'INVALID_TONE: expected 1..3 tone words' using errcode = 'P0001';
    end if;
    if exists (
      select 1
      from jsonb_array_elements_text(_row->'tone') w
      where w.value is null
         or w.value <> all (array[
        'whimsical', 'melancholic', 'brutal', 'cozy', 'cerebral', 'kinetic',
        'tender', 'eerie', 'absurd', 'earnest', 'dark', 'warm',
        'bleak', 'playful', 'solemn', 'lush', 'gritty', 'dreamlike',
        'frantic', 'intimate', 'epic', 'quiet', 'hysterical', 'meditative'
      ])
    ) then
      raise exception 'INVALID_TONE_WORD: word outside the 24-word vocabulary' using errcode = 'P0001';
    end if;
    if (select count(distinct w.value)
        from jsonb_array_elements_text(_row->'tone') w) <> jsonb_array_length(_row->'tone') then
      raise exception 'INVALID_TONE: duplicate tone words' using errcode = 'P0001';
    end if;

    -- register / pacing
    if coalesce(_row->>'register', '') not in ('family', 'general', 'seinen-otaku', 'arthouse') then
      raise exception 'INVALID_REGISTER' using errcode = 'P0001';
    end if;
    if coalesce(_row->>'pacing', '') not in ('slow-burn', 'steady', 'relentless') then
      raise exception 'INVALID_PACING' using errcode = 'P0001';
    end if;

    -- confidence (typeof checked before the cast, like media_id).
    if _row->'confidence' is null
       or jsonb_typeof(_row->'confidence') <> 'number' then
      raise exception 'INVALID_CONFIDENCE: must be a number 0..1' using errcode = 'P0001';
    end if;
    if (_row->>'confidence')::numeric < 0
       or (_row->>'confidence')::numeric > 1 then
      raise exception 'INVALID_CONFIDENCE: must be a number 0..1' using errcode = 'P0001';
    end if;

    -- descriptor: 2-3 sentence Kuro-voice text, 100..600 chars.
    if _row->'descriptor' is null
       or jsonb_typeof(_row->'descriptor') <> 'string'
       or char_length(_row->>'descriptor') < 100
       or char_length(_row->>'descriptor') > 600 then
      raise exception 'INVALID_DESCRIPTOR: must be 100..600 chars' using errcode = 'P0001';
    end if;

    -- model: writer id, e.g. 'kimi-swarm-2026-08'.
    if _row->'model' is null
       or jsonb_typeof(_row->'model') <> 'string'
       or char_length(btrim(_row->>'model')) < 1
       or char_length(_row->>'model') > 100 then
      raise exception 'INVALID_MODEL: writer id must be 1..100 chars' using errcode = 'P0001';
    end if;
  end loop;

  -- DISTINCT ON collapses duplicate titles inside one batch, keeping the LAST
  -- occurrence (JSONL append semantics: a later line supersedes an earlier
  -- one). realms normalized to weight-desc/realm-asc so "top 3" is structural.
  insert into public.media_realm_llm (media_type, media_id, realms, tone, register, pacing, confidence, descriptor, model)
  select distinct on (r.media_type, r.media_id)
    r.media_type, r.media_id, r.realms, r.tone, r.register, r.pacing, r.confidence, r.descriptor, r.model
  from (
    select
      _e->>'media_type'                          as media_type,
      (_e->>'media_id')::integer                 as media_id,
      (
        select jsonb_agg(
                 jsonb_build_object('realm', re->>'realm', 'weight', (re->>'weight')::numeric)
                 order by (re->>'weight')::numeric desc, re->>'realm' asc
               )
        from jsonb_array_elements(_e->'realms') re
      )                                          as realms,
      (
        select array_agg(w.value order by w.ord)
        from jsonb_array_elements_text(_e->'tone') with ordinality as w(value, ord)
      )                                          as tone,
      _e->>'register'                            as register,
      _e->>'pacing'                              as pacing,
      (_e->>'confidence')::real                  as confidence,
      _e->>'descriptor'                          as descriptor,
      _e->>'model'                               as model,
      _n                                         as n
    from jsonb_array_elements(p_rows) with ordinality as _e(_e, _n)
  ) r
  order by r.media_type, r.media_id, r.n desc
  on conflict (media_type, media_id) do update set
    realms     = excluded.realms,
    tone       = excluded.tone,
    register   = excluded.register,
    pacing     = excluded.pacing,
    confidence = excluded.confidence,
    descriptor = excluded.descriptor,
    model      = excluded.model;
  -- created_at is preserved on conflict: it records the first write.

  get diagnostics _affected = row_count;
  return _affected;
end;
$$;

revoke all on function public.upsert_media_realm_llm(jsonb) from public;
grant execute on function public.upsert_media_realm_llm(jsonb) to authenticated, service_role;

commit;
