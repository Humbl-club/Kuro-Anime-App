#!/usr/bin/env node
/**
 * Resolve curation_ingest_candidates.json against the live Kuro catalog and
 * emit:
 *   - reports/curation-ingest/resolved.json
 *   - reports/curation-ingest/unresolved.json
 *   - supabase/migrations/<ts>_curation_sources_expand_v1.sql  (when --write-migration)
 *
 * Usage:
 *   node scripts/compile_curation_ingest.js
 *   node scripts/compile_curation_ingest.js --write-migration
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { getPublicProjectConfig } = require('./lib/project_config');

const ROOT = path.join(__dirname, '..');
const CANDIDATES_PATH = path.join(__dirname, 'data', 'curation_ingest_candidates.json');
const OUT_DIR = path.join(ROOT, 'reports', 'curation-ingest');
const WRITE_MIGRATION = process.argv.includes('--write-migration');

function sqlEscape(s) {
  if (s == null) return 'null';
  return `'${String(s).replace(/'/g, "''")}'`;
}

function normalize(s) {
  return String(s || '')
    .toLowerCase()
    .normalize('NFKC')
    .replace(/[×x✕✖]/g, 'x')
    .replace(/[''`]/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

async function restGet(url, anonKey, tablePath) {
  const r = await fetch(`${url}/rest/v1/${tablePath}`, {
    headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}` },
  });
  if (!r.ok) {
    const body = await r.text();
    throw new Error(`REST ${r.status}: ${body.slice(0, 200)}`);
  }
  return r.json();
}

async function searchCatalog(url, anonKey, mediaType, queries) {
  const table = mediaType === 'ANIME' ? 'anime' : 'manga';
  const seen = new Map();
  for (const q of queries) {
    if (!q || q.length < 2) continue;
    // Prefer short distinctive tokens when titles contain commas/parentheses
    // (commas break PostgREST `or=(...)` trees; we search columns separately).
    const tokens = [q.replace(/"/g, '')];
    if (q.length > 28 || /[,()]/.test(q)) {
      const short = q.split(/[,:(]/)[0].trim();
      if (short.length >= 4) tokens.push(short);
    }
    for (const token of tokens) {
      const pattern = encodeURIComponent(`*${token}*`);
      for (const col of ['title_english', 'title_romaji', 'title_native']) {
        const pathQ =
          `${table}?select=id,title_romaji,title_english,title_native,popularity` +
          `&${col}=ilike.${pattern}` +
          `&order=popularity.desc.nullslast&limit=8`;
        try {
          const rows = await restGet(url, anonKey, pathQ);
          for (const row of rows || []) seen.set(row.id, row);
        } catch {
          // ignore per-column miss
        }
      }
    }
  }
  return [...seen.values()];
}

function pickBest(candidate, rows) {
  if (!rows.length) return null;
  const needles = [candidate.title, ...(candidate.title_alt || [])].map(normalize).filter(Boolean);
  const scoreRow = (row) => {
    const fields = [row.title_english, row.title_romaji, row.title_native].map(normalize);
    let best = 0;
    for (const n of needles) {
      for (const f of fields) {
        if (!f) continue;
        if (f === n) best = Math.max(best, 1000);
        else if (f.startsWith(n) && f.length <= n.length + 4) best = Math.max(best, 800);
        else if (n.startsWith(f) && n.length <= f.length + 4) best = Math.max(best, 700);
        else if (f.includes(n)) best = Math.max(best, 400 - Math.min(200, f.length - n.length));
        else if (n.includes(f) && f.length >= 6) best = Math.max(best, 300);
      }
    }
    // Prefer mainline over side-story when scores tie-ish.
    const blob = fields.join(' ');
    if (/\b(side|b side|gaiden|spin)\b/.test(blob)) best -= 50;
    return best + Math.min(50, Math.log10((row.popularity || 1) + 1) * 10);
  };
  const ranked = [...rows].map((r) => ({ r, s: scoreRow(r) })).sort((a, b) => b.s - a.s);
  if (ranked[0].s < 250) return null;
  return ranked[0].r;
}

async function resolveAll() {
  const { url, anonKey } = getPublicProjectConfig();
  const data = JSON.parse(fs.readFileSync(CANDIDATES_PATH, 'utf8'));
  const all = [...(data.canon || []), ...(data.seasonal || [])];
  const resolved = [];
  const unresolved = [];

  for (const c of all) {
    const queries = [c.title, ...(c.title_alt || [])].filter(Boolean);
    const rows = await searchCatalog(url, anonKey, c.media_type, queries);
    const hit = pickBest(c, rows);
    if (!hit) {
      unresolved.push({ ...c, reason: 'no_catalog_hit' });
      continue;
    }
    resolved.push({
      ...c,
      media_id: hit.id,
      matched_title: hit.title_english || hit.title_romaji,
      matched_romaji: hit.title_romaji,
    });
    // Mild pacing for PostgREST.
    await new Promise((r) => setTimeout(r, 40));
  }

  fs.mkdirSync(OUT_DIR, { recursive: true });
  fs.writeFileSync(path.join(OUT_DIR, 'resolved.json'), JSON.stringify(resolved, null, 2));
  fs.writeFileSync(path.join(OUT_DIR, 'unresolved.json'), JSON.stringify(unresolved, null, 2));
  console.log(`Resolved ${resolved.length} / ${all.length}; unresolved ${unresolved.length}`);
  return { resolved, unresolved };
}

function emitMigration(resolved) {
  const ts = '20260802150000';
  const migPath = path.join(ROOT, 'supabase', 'migrations', `${ts}_curation_sources_expand_v1.sql`);
  const canon = resolved.filter((r) => r.bucket === 'canon');
  const seasonal = resolved.filter((r) => r.bucket === 'seasonal');

  const canonRows = canon.map((r) => {
    const title = r.matched_title || r.title;
    // Unique key is (media_type, media_id, source, category) — stamp year into
    // category when a title can reappear across editions (Kono Manga / Taishō).
    let category = r.category || '';
    if (r.year && !String(category).includes(String(r.year))) {
      category = category ? `${category} (${r.year})` : String(r.year);
    }
    return `  (${sqlEscape(r.media_type)}, ${r.media_id}, ${sqlEscape(title)}, ${sqlEscape(r.source)}, ${sqlEscape(r.source_detail)}, ${r.year ?? 'null'}, ${sqlEscape(category)}, true)`;
  });

  const seasonalRows = seasonal.map((r) => {
    const title = r.matched_title || r.title;
    const score = r.score == null ? 'null' : Number(r.score);
    const rank = r.rank == null ? 'null' : Number(r.rank);
    let category = r.category || 'list';
    if (r.rank != null) category = `${category} #${r.rank}`;
    return `  (${sqlEscape(r.media_type)}, ${r.media_id}, ${sqlEscape(title)}, ${sqlEscape(r.source)}, ${sqlEscape(r.period || String(r.year || ''))}, ${rank}, ${score}, ${sqlEscape(category)}, ${sqlEscape(r.source_detail)}, ${r.year ?? 'null'})`;
  });

  const sql = `-- curation_sources_expand_v1
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
${canonRows.join(',\n')}
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
${seasonalRows.join(',\n')}
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

-- NOTE: media_realm_tier rebuild is intentionally NOT in this migration —
-- the full rebuild is too slow for a migration transaction. As of
-- 20260804120000 media_realm_tier is a TABLE rebuilt nightly by pg_cron
-- ('realm-tier-refresh', 04:50 UTC); or run manually after push:
--   set statement_timeout = '600s'; select public.rebuild_media_realm_tier();
`;

  fs.writeFileSync(migPath, sql);
  console.log(`Wrote migration ${migPath}`);
  console.log(`  canon inserts: ${canon.length}`);
  console.log(`  seasonal inserts: ${seasonal.length}`);
  return migPath;
}

(async () => {
  let resolved;
  let unresolved = [];
  if (process.argv.includes('--from-resolved')) {
    resolved = JSON.parse(fs.readFileSync(path.join(OUT_DIR, 'resolved.json'), 'utf8'));
    console.log(`Loaded ${resolved.length} previously resolved rows`);
  } else {
    ({ resolved, unresolved } = await resolveAll());
    if (unresolved.length) {
      console.log('Unresolved sample:');
      for (const u of unresolved.slice(0, 20)) {
        console.log(`  - [${u.media_type}] ${u.title} (${u.source})`);
      }
    }
  }
  if (WRITE_MIGRATION) {
    if (!resolved.length) throw new Error('No resolved rows; refusing to write empty migration.');
    emitMigration(resolved);
  }
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
