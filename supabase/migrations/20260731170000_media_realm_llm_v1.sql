-- Realm Graph Stage 2b — LLM descriptor pass infrastructure.
-- Spec: docs/superpowers/specs/2026-07-31-realm-graph-master-plan.md §6
--
-- The LLM pass is executed BY THE AGENT SWARM (agents are the LLM), not by an
-- external API. This migration is the infrastructure the swarm writes through:
--   scripts/realm_llm_pass_fetch.js  — pulls work items (per-title context
--                                      bundles) from media_realm_llm_pending.
--   scripts/realm_llm_pass_submit.js — validates + submits descriptor JSONL via
--                                      the upsert_media_realm_llm RPC.
--
-- Objects (all new; no existing table/function/view is modified):
--   1) public.media_realm_llm         table — one descriptor row per title.
--   2) public.upsert_media_realm_llm  RPC   — validated, rate-limited bulk upsert.
--   3) public.media_realm_llm_pending view  — the work queue: visible-pool titles
--                                             WITHOUT a media_realm_llm row.
--   4) public.media_realm_profile     view  — consumer read: membership top realm
--                                             + tier + llm descriptor in one row.
--
-- Dependencies (built on the 120000/150000 chain; present in production):
--   - public.realm_meta        (20260731120000) — realm-name validation source.
--   - public.media_realm_tier  (20260731150000) — top realm + tier for
--     media_realm_profile.
--   - public.rate_limit_hit    (20260204221500) — RPC rate limiting.
--
-- Chain note: media_realm_profile has a HARD dependency on the media_realm_tier
-- matview, so 20260731150000 can no longer be re-applied after this migration
-- without `drop view public.media_realm_profile` first (the same class of
-- replay constraint 150000 documents for media_tag_vectors). Production applies
-- migrations once, in order, so this only affects local replays.
--
-- Documented decisions:
--   * Visible pool (spec §6 "score >= 70 pool"): average_score >= 70, not
--     adult, has cover; ancillary ANIME formats excluded exactly like the
--     deck/search default surfaces (format not in SPECIAL/MUSIC/TV_SHORT).
--     Manga has no ancillary-format exclusion (matches browse/search: none
--     exists).
--   * media_realm_llm_pending is an ops queue, not an app surface: anon is
--     revoked explicitly (default privileges would otherwise auto-grant it),
--     authenticated + service_role may read. The spec says "service_role";
--     authenticated is added because the swarm runner (realm_llm_pass_fetch.js)
--     authenticates as the test user (KURO_TEST_JWT), same probationary
--     posture as the rec-edges import window.
--   * tone is 1..3 distinct words of the fixed 24-word vocabulary (spec §6
--     says "3 of"; the validation contract is "max 3" so a writer may commit
--     fewer when a third word would be noise).
--   * realms payload is normalized on write to weight-desc (then realm-asc)
--     order, so "top 3" is structural, not positional-trust.
--   * On upsert conflict the content columns are overwritten and created_at
--     is PRESERVED (first write). There is deliberately no updated_at: the
--     pass is one-shot per title plus a QA rewrite on confidence < 0.7, and
--     the table's single timestamp stays honest to its name.
--   * Rate limit: 60 calls/hour per user (service_role calls share one global
--     bucket, same as upsert_rec_edges). At 100 rows/call that is 6k titles
--     per hour per writer — the 8k pass fits in ~2 windows.

begin;

-- ---------------------------------------------------------------------------
-- 1) TABLE
-- ---------------------------------------------------------------------------

create table if not exists public.media_realm_llm (
  media_type text        not null check (media_type in ('ANIME', 'MANGA')),
  media_id   integer     not null,
  realms     jsonb       not null check (jsonb_typeof(realms) = 'array'), -- [{"realm":"quiet-melancholy","weight":0.8}, ...] top 3, weight-desc
  tone       text[]      not null check (cardinality(tone) between 1 and 3),
  register   text        not null check (register in ('family', 'general', 'seinen-otaku', 'arthouse')),
  pacing     text        not null check (pacing in ('slow-burn', 'steady', 'relentless')),
  confidence real        not null check (confidence between 0 and 1),
  descriptor text        not null check (char_length(descriptor) between 100 and 600), -- 2-3 sentence Kuro-voice description
  model      text        not null, -- writer id, e.g. 'kimi-swarm-2026-08'
  created_at timestamptz not null default now(),
  primary key (media_type, media_id)
);

comment on table public.media_realm_llm is
  'Realm Graph Stage 2b (spec §6): per-title LLM descriptor rows written by the agent swarm via upsert_media_realm_llm. realms = top-3 realm confirmations with 0..1 weights (weight-desc); tone = 1..3 words of the fixed 24-word vocabulary; register/pacing enums; confidence 0..1 (QA pass rewrites rows < 0.7); descriptor = 2-3 sentence Kuro-voice text (100..600 chars); model = writer id. Public read, no direct writes.';

-- ---------------------------------------------------------------------------
-- 2) RLS — public SELECT (editorial data), no direct writes. Writes only via
--    upsert_media_realm_llm() (SECURITY DEFINER): no INSERT/UPDATE/DELETE
--    policies, so RLS default-deny covers direct writes from client roles.
-- ---------------------------------------------------------------------------

alter table public.media_realm_llm enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='media_realm_llm' and policyname='media_realm_llm_select_all'
  ) then
    create policy media_realm_llm_select_all on public.media_realm_llm
      for select using (true);
  end if;
end $$;

grant select on public.media_realm_llm to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) RPC: validated bulk upsert (rate-limited). Validates EVERY row before
--    inserting anything: one bad row rejects the whole batch (the submit
--    script re-validates client-side, so a rejected batch means a generator
--    bug worth fixing, not a partial write worth keeping).
-- ---------------------------------------------------------------------------

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
  -- Rate limit: 60 calls per hour per user. service_role calls carry no uid,
  -- so they share one global bucket. Probationary grant: authenticated callers
  -- are accepted for the swarm pass window; this may be revoked to
  -- service_role-only once the pass completes.
  _hits := public.rate_limit_hit(
    'realm_llm_upsert:' || coalesce(auth.uid()::text, 'service_role'),
    3600
  );
  if _hits > 60 then
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

-- ---------------------------------------------------------------------------
-- 4) media_realm_llm_pending — the work queue: visible-pool titles WITHOUT a
--    media_realm_llm row, ordered by popularity desc. Ops surface only (anon
--    revoked; authenticated + service_role, see header note).
-- ---------------------------------------------------------------------------

drop view if exists public.media_realm_llm_pending;
create view public.media_realm_llm_pending as
select
  'ANIME'::text as media_type,
  a.id as media_id,
  coalesce(nullif(a.title_english, ''), a.title_romaji) as title,
  coalesce(a.popularity, 0) as popularity
from public.anime a
where coalesce(a.is_adult, false) = false
  and coalesce(a.average_score, 0) >= 70
  and a.cover_image_large is not null
  and coalesce(a.format, '') not in ('SPECIAL', 'MUSIC', 'TV_SHORT')
  and not exists (
    select 1 from public.media_realm_llm l
    where l.media_type = 'ANIME' and l.media_id = a.id
  )

union all

select
  'MANGA'::text,
  m.id,
  coalesce(nullif(m.title_english, ''), m.title_romaji),
  coalesce(m.popularity, 0)
from public.manga m
where coalesce(m.is_adult, false) = false
  and coalesce(m.average_score, 0) >= 70
  and m.cover_image_large is not null
  and not exists (
    select 1 from public.media_realm_llm l
    where l.media_type = 'MANGA' and l.media_id = m.id
  )

order by popularity desc, media_type asc, media_id asc;

comment on view public.media_realm_llm_pending is
  'Realm Graph Stage 2b work queue: visible-pool titles (average_score >= 70, not adult, has cover, ancillary anime formats excluded) with no media_realm_llm row yet, popularity desc. Consumed by scripts/realm_llm_pass_fetch.js.';

revoke all on public.media_realm_llm_pending from public, anon, authenticated;
grant select on public.media_realm_llm_pending to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5) media_realm_profile — consumer read view (public): title + its membership
--    top realm + tier + the llm descriptor columns in one row. Titles without
--    an llm row keep their realm/tier with llm_* null (tail titles stay
--    rules-only, spec §6).
-- ---------------------------------------------------------------------------

drop view if exists public.media_realm_profile;
create view public.media_realm_profile as
select
  t.media_type,
  t.media_id,
  case
    when t.media_type = 'ANIME' then coalesce(nullif(a.title_english, ''), a.title_romaji)
    else coalesce(nullif(m.title_english, ''), m.title_romaji)
  end as title,
  t.realm as top_realm,
  t.tier,
  l.realms as llm_realms,
  l.tone as llm_tone,
  l.register as llm_register,
  l.pacing as llm_pacing,
  l.descriptor as llm_descriptor,
  l.confidence as llm_confidence,
  l.model as llm_model,
  l.created_at as llm_at
from public.media_realm_tier t
left join public.anime a
  on t.media_type = 'ANIME' and a.id = t.media_id
left join public.manga m
  on t.media_type = 'MANGA' and m.id = t.media_id
left join public.media_realm_llm l
  on l.media_type = t.media_type and l.media_id = t.media_id;

comment on view public.media_realm_profile is
  'Realm Graph Stage 2b consumer read: one row per tiered title — membership top realm + tier (rules) plus the llm descriptor (realms/tone/register/pacing/descriptor/confidence) when written. Public read.';

revoke all on public.media_realm_profile from public, anon, authenticated;
grant select on public.media_realm_profile to anon, authenticated, service_role;

commit;
